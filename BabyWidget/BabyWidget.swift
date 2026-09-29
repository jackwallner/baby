import AppIntents
import CoreData
import SwiftUI
import WidgetKit

/// Both widgets read the shared store directly, so a tap in the widget shows
/// up in the widget the same second, whether or not the app has run since.
struct BabyEntry: TimelineEntry {
    let date: Date
    let summary: NowSummary
    /// Set for the few seconds after a tap, when the one-button tiles offer Undo.
    var undo: WidgetUndo?
}

struct BabyProvider: TimelineProvider {
    private static let placeholder: BabyEntry = {
        var summary = NowSummary()
        summary.childName = "Nora"
        summary.dayOfLife = 3
        summary.lastFeedAt = Date.now.addingTimeInterval(-2 * 3600 - 14 * 60)
        summary.lastFeedSide = .left
        summary.lastDiaperAt = Date.now.addingTimeInterval(-48 * 60)
        summary.lastDiaperKind = .wet
        summary.todayFeeds = 7
        summary.todayWet = 3
        summary.todayDirty = 2
        return BabyEntry(date: .now, summary: summary)
    }()

    func placeholder(in context: Context) -> BabyEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BabyEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? Self.placeholder : BabyEntry(date: .now, summary: Self.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BabyEntry>) -> Void) {
        Task { @MainActor in
            let summary = Self.load()
            let now = Date.now
            // Just after a tap: Undo first, then the tile's normal face.
            let undo = WidgetUndo.showing(at: now)
            let resume = undo?.hidesAt ?? now
            // Relative times ("2h 14m ago") are rendered per entry, so a fresh
            // entry every five minutes keeps them honest without live text.
            let entries = (undo.map { [BabyEntry(date: now, summary: summary, undo: $0)] } ?? [])
                + (0..<12).map { BabyEntry(date: resume.addingTimeInterval(Double($0) * 300), summary: summary) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    @MainActor
    static func load() -> NowSummary {
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context) else { return NowSummary.load() }
        return NowSummary.make(child: child, events: persistence.events(for: child, in: context, limit: 200))
    }
}

// MARK: - Now widget (glance)

struct BabyNowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BabyEntry

    private var s: NowSummary { entry.summary }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(s.leadLine(now: entry.date)).font(.headline).lineLimit(1)
                ForEach(Array(s.supportingLines(now: entry.date).prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).lineLimit(1)
                }
                if s.supportingLines(now: entry.date).count < 2, !s.todayLine.isEmpty {
                    Text(s.todayLine).font(.caption2).lineLimit(1)
                }
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: s.leadKind.symbolName).font(.caption2)
                Text(s.leadElapsed(now: entry.date)).font(.headline.bold()).minimumScaleFactor(0.7)
                if let detail = s.leadShortDetail { Text(detail).font(.caption2) }
            }
        case .accessoryInline:
            Label(s.leadLine(now: entry.date), systemImage: s.leadKind.symbolName)
        case .systemMedium:
            HStack(alignment: .top, spacing: AppTheme.spacing) {
                glance
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: AppTheme.hairSpacing) {
                    if let day = s.dayOfLife {
                        Text("Day \(day)").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink2)
                    }
                    ForEach(s.tracked.buttons.filter { $0 != .sleep }, id: \.self) { kind in
                        count(kind)
                    }
                }
                .monospacedDigit()
            }
        default:
            glance
        }
    }

    private func count(_ kind: EventKind) -> Text {
        let value = switch kind {
        case .feed: s.todayFeeds
        case .wet: s.todayWet
        default: s.todayDirty
        }
        let unit = kind == .feed ? (value == 1 ? "feed" : "feeds") : kind.label.lowercased()
        return Text("\(value)").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.color(for: kind))
            + Text(" \(unit)").font(.caption).foregroundStyle(AppTheme.ink2)
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            HStack(spacing: AppTheme.hairSpacing) {
                Image(systemName: s.leadKind.symbolName).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.color(for: s.leadKind))
                Text(s.childName).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink2).lineLimit(1)
            }
            Text(s.leadLine(now: entry.date))
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if s.leadKind == .feed, s.tracked.tracksDiapers {
                Text(s.diaperLine(now: entry.date))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(2)
            }
            if s.leadKind != .sleep, s.tracked.contains(.sleep), let sleep = s.sleepLine(now: entry.date) {
                Text(sleep).font(.caption).foregroundStyle(AppTheme.sleep).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct BabyNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.now, provider: BabyProvider()) { entry in
            BabyNowWidgetView(entry: entry)
                .containerBackground(AppTheme.card, for: .widget)
        }
        .configurationDisplayName("Last feed and diaper")
        .description("When the baby last ate, which side, and the last diaper.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Log widget (buttons)

struct BabyLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BabyEntry

    private var s: NowSummary { entry.summary }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: AppTheme.hairSpacing) {
                ForEach(rowKinds, id: \.self) { kind in
                    logButton(kind)
                }
            }
        case .systemMedium:
            HStack(spacing: AppTheme.spacing) {
                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    Text(s.leadLine(now: entry.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let line = s.supportingLines(now: entry.date).first {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink2)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                grid
                    .frame(width: 150)
            }
        default:
            grid
        }
    }

    /// The Lock Screen row: the one-tap kinds, or Sleep if that is all.
    private var rowKinds: [EventKind] {
        let taps = s.tracked.buttons.filter { $0 != .sleep }
        return taps.isEmpty ? [.sleep] : taps
    }

    /// The tracked buttons two to a row, in their usual order.
    private var grid: some View {
        let kinds = s.tracked.buttons
        return VStack(spacing: AppTheme.tightSpacing) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: 2)), id: \.self) { start in
                HStack(spacing: AppTheme.tightSpacing) {
                    ForEach(kinds[start..<min(start + 2, kinds.count)], id: \.self) { kind in
                        logButton(kind)
                    }
                }
            }
        }
    }

    private func logButton(_ kind: EventKind) -> some View {
        let label = kind == .sleep ? (s.isSleeping ? "Wake" : "Sleep") : kind.label
        let choice: LogChoice = switch kind {
        case .feed: .feed
        case .wet: .wet
        case .dirty: .dirty
        default: .sleep
        }
        return Button(intent: LogEventIntent(what: choice)) {
            VStack(spacing: 0) {
                Image(systemName: kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: kind))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
        }
        .buttonStyle(.plain)
    }
}

struct BabyLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.log, provider: BabyProvider()) { entry in
            BabyLogWidgetView(entry: entry)
                .containerBackground(AppTheme.card, for: .widget)
        }
        .configurationDisplayName("One-tap log")
        .description("Log with one tap, without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct BabyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BabyNowWidget()
        BabyLogWidget()
        QuickFeedWidget()
        QuickWetWidget()
        QuickDirtyWidget()
        BabyLiveActivity()
        if #available(iOS 18.0, *) {
            FeedControl()
            WetControl()
            DirtyControl()
        }
    }
}
