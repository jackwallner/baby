import AppIntents
import CoreData
import SwiftUI
import WidgetKit

/// Both widgets read the shared store directly, so a tap in the widget shows
/// up in the widget the same second, whether or not the app has run since.
struct BabyEntry: TimelineEntry {
    let date: Date
    let summary: NowSummary
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
            // Relative times ("2h 14m ago") are rendered per entry, so a fresh
            // entry every five minutes keeps them honest without live text.
            let entries = (0..<12).map { BabyEntry(date: now.addingTimeInterval(Double($0) * 300), summary: summary) }
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
                Text(s.feedLine(now: entry.date)).font(.headline).lineLimit(1)
                Text(s.diaperLine(now: entry.date)).font(.caption).lineLimit(1)
                if let sleep = s.sleepLine(now: entry.date) {
                    Text(sleep).font(.caption).lineLimit(1)
                } else {
                    Text(s.todayLine).font(.caption2).lineLimit(1)
                }
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: EventKind.feed.symbolName).font(.caption2)
                Text(sinceFeed).font(.headline.bold()).minimumScaleFactor(0.7)
                if let side = s.lastFeedSide { Text(side.shortLabel).font(.caption2) }
            }
        case .accessoryInline:
            Label(s.feedLine(now: entry.date), systemImage: EventKind.feed.symbolName)
        case .systemMedium:
            HStack(alignment: .top, spacing: AppTheme.spacing) {
                glance
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: AppTheme.hairSpacing) {
                    if let day = s.dayOfLife {
                        Text("Day \(day)").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink2)
                    }
                    Text("\(s.todayWet)").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.wet) + Text(" wet").font(.caption).foregroundStyle(AppTheme.ink2)
                    Text("\(s.todayDirty)").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.dirty) + Text(" dirty").font(.caption).foregroundStyle(AppTheme.ink2)
                    Text("\(s.todayFeeds)").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.feed) + Text(" feeds").font(.caption).foregroundStyle(AppTheme.ink2)
                }
                .monospacedDigit()
            }
        default:
            glance
        }
    }

    private var sinceFeed: String {
        if let start = s.runningFeedStart { return Format.compactDuration(entry.date.timeIntervalSince(start)) }
        guard let last = s.lastFeedAt else { return "–" }
        return Format.compactDuration(entry.date.timeIntervalSince(last))
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            HStack(spacing: AppTheme.hairSpacing) {
                Image(systemName: EventKind.feed.symbolName).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.feed)
                Text(s.childName).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink2).lineLimit(1)
            }
            Text(s.feedLine(now: entry.date))
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(s.diaperLine(now: entry.date))
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .lineLimit(2)
            if let sleep = s.sleepLine(now: entry.date) {
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
        .description("When she last ate, which side, and the last diaper.")
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
                logButton("Feed", kind: .feed, choice: .feed)
                logButton("Wet", kind: .wet, choice: .wet)
                logButton("Dirty", kind: .dirty, choice: .dirty)
            }
        case .systemMedium:
            HStack(spacing: AppTheme.spacing) {
                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    Text(s.feedLine(now: entry.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(s.diaperLine(now: entry.date))
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                grid
                    .frame(width: 150)
            }
        default:
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            HStack(spacing: AppTheme.tightSpacing) {
                logButton("Feed \(s.suggestedSide.shortLabel)", kind: .feed, choice: .feed)
                logButton("Wet", kind: .wet, choice: .wet)
            }
            HStack(spacing: AppTheme.tightSpacing) {
                logButton("Dirty", kind: .dirty, choice: .dirty)
                logButton(s.isSleeping ? "Wake" : "Sleep", kind: .sleep, choice: .sleep)
            }
        }
    }

    private func logButton(_ label: String, kind: EventKind, choice: LogChoice) -> some View {
        Button(intent: LogEventIntent(what: choice)) {
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
        .description("Log a feed, a wet or dirty diaper, or sleep without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct BabyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BabyNowWidget()
        BabyLogWidget()
        BabyLiveActivity()
    }
}
