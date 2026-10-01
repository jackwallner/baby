import SwiftUI
import WidgetKit

struct WatchBabyEntry: TimelineEntry {
    let date: Date
    let summary: NowSummary
}

/// One entry a minute for three hours, then every five minutes to twelve,
/// so "2h 14m" on the face is never more than a minute behind the app.
struct WatchBabyProvider: TimelineProvider {
    static let minuteEntries = 180
    static let fiveMinuteEntries = 108

    static var placeholder: WatchBabyEntry {
        var summary = NowSummary()
        let now = Date.now
        summary.childName = "Baby"
        summary.lastFeedAt = now.addingTimeInterval(-2 * 3600 - 14 * 60)
        summary.setLastFeedSides([.left])
        summary.lastDiaperAt = now.addingTimeInterval(-48 * 60)
        summary.lastDiaperKind = .wet
        summary.lastWokeAt = now.addingTimeInterval(-70 * 60)
        summary.todayFeeds = 7
        summary.todayWet = 5
        summary.todayDirty = 2
        return WatchBabyEntry(date: now, summary: summary)
    }

    func placeholder(in context: Context) -> WatchBabyEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchBabyEntry) -> Void) {
        completion(context.isPreview ? Self.placeholder : WatchBabyEntry(date: .now, summary: NowSummary.load().current()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchBabyEntry>) -> Void) {
        let summary = NowSummary.load()
        completion(Timeline(entries: Self.entries(for: summary, from: .now), policy: .atEnd))
    }

    static func entries(for summary: NowSummary, from now: Date) -> [WatchBabyEntry] {
        let minutes = (0..<minuteEntries).map { now.addingTimeInterval(Double($0) * 60) }
        let tail = (1...fiveMinuteEntries).map { now.addingTimeInterval(Double(minuteEntries - 1) * 60 + Double($0) * 300) }
        // Today's counts reset at the phone's day start even with no new push.
        return (minutes + tail).map { WatchBabyEntry(date: $0, summary: summary.current(now: $0)) }
    }
}

/// "just now", "12m", "2h 14m", or a dash before anything is logged.
private func elapsed(_ since: Date?, _ now: Date) -> String {
    guard let since else { return "–" }
    let seconds = now.timeIntervalSince(since)
    return seconds < 60 ? "now" : Format.compactDuration(seconds)
}

/// The circular face every complication shares: a symbol, a big value, a caption.
private struct CircularFace: View {
    let symbol: String
    let value: String
    let caption: String?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .widgetAccentable()
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, AppTheme.hairSpacing)
        }
    }
}

// MARK: - Last feed

struct LastFeedView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set only by the DEBUG gallery in the Watch app, which has no widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    let entry: WatchBabyEntry

    private var s: NowSummary { entry.summary }
    private var running: Bool { s.runningFeedStart != nil }
    private var since: Date? { s.runningFeedStart ?? s.lastFeedAt }
    private var sides: [FeedSide] { running ? s.runningSides : s.feedSides }
    private var value: String { elapsed(since, entry.date) }

    var body: some View {
        if !s.tracked.contains(.feed) {
            OffFace(kind: .feed, family: family)
        } else {
            switch family {
            case .accessoryCircular:
                CircularFace(symbol: EventKind.feed.symbolName, value: value, caption: FeedSide.shortLabel(for: sides) ?? (running ? "feeding" : "fed"))
            case .accessoryCorner:
                Image(systemName: EventKind.feed.symbolName)
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
                    .widgetLabel { Text([value, FeedSide.shortLabel(for: sides)].compactMap { $0 }.joined(separator: " ")) }
            case .accessoryInline:
                Label(s.feedLine(now: entry.date), systemImage: EventKind.feed.symbolName)
            default:
                rectangular
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(running ? "Feeding" : "Last feed", systemImage: EventKind.feed.symbolName)
                .font(.headline)
                .foregroundStyle(AppTheme.feed)
                .widgetAccentable()
            Text(since == nil ? "Nothing yet" : [value == "now" ? "Just now" : running ? value : "\(value) ago", FeedSide.label(for: sides)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(footer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The last diaper, or a sleep that is running, or today's feeds.
    private var footer: String {
        if s.tracked.contains(.sleep), let sleep = s.sleepLine(now: entry.date) { return sleep }
        if s.tracked.tracksDiapers, let at = s.lastDiaperAt {
            return ["Diaper \(elapsed(at, entry.date))", s.lastDiaperKind?.label].compactMap { $0 }.joined(separator: " · ")
        }
        return "Today \(Format.count(s.todayFeeds, "feed"))"
    }
}

// MARK: - Last diaper

struct LastDiaperView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set only by the DEBUG gallery in the Watch app, which has no widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    let entry: WatchBabyEntry

    private var s: NowSummary { entry.summary }
    private var kind: EventKind { s.lastDiaperKind ?? (s.tracked.contains(.wet) ? .wet : .dirty) }
    private var value: String { elapsed(s.lastDiaperAt, entry.date) }

    var body: some View {
        if !s.tracked.tracksDiapers {
            OffFace(kind: .wet, family: family)
        } else {
            switch family {
            case .accessoryCircular:
                CircularFace(symbol: kind.symbolName, value: value, caption: s.lastDiaperKind?.label.lowercased() ?? "diaper")
            case .accessoryCorner:
                Image(systemName: kind.symbolName)
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
                    .widgetLabel { Text([value, s.lastDiaperKind?.label].compactMap { $0 }.joined(separator: " ")) }
            case .accessoryInline:
                Label(s.diaperLine(now: entry.date), systemImage: kind.symbolName)
            default:
                rectangular
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Last diaper", systemImage: kind.symbolName)
                .font(.headline)
                .foregroundStyle(AppTheme.color(for: kind))
                .widgetAccentable()
            Text(s.lastDiaperAt == nil ? "Nothing yet" : [value == "now" ? "Just now" : "\(value) ago", s.lastDiaperKind?.label].compactMap { $0 }.joined(separator: " · "))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(today)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Today 5 pee · 2 poop", only the kinds this family tracks.
    private var today: String {
        var parts: [String] = []
        if s.tracked.contains(.wet) { parts.append("\(s.todayWet) \(EventKind.wet.label.lowercased())") }
        if s.tracked.contains(.dirty) { parts.append("\(s.todayDirty) \(EventKind.dirty.label.lowercased())") }
        return "\(s.window.title()) " + parts.joined(separator: " · ")
    }
}

// MARK: - One-tap logging

/// Pee or Poop on the face: a tap opens the Watch app, which logs it and
/// shows Undo. An off button says so and just opens the app.
struct LogDiaperView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set only by the DEBUG gallery in the Watch app, which has no widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    let entry: WatchBabyEntry
    let kind: EventKind

    var body: some View {
        if !entry.summary.tracked.contains(kind) {
            OffFace(kind: kind, family: family)
        } else {
            face.widgetURL(AppGroup.WatchLink.log(kind))
        }
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: kind.symbolName)
                .font(.title3.weight(.semibold))
                .widgetAccentable()
                .widgetLabel { Text("Log \(kind.label.lowercased())") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: kind.symbolName)
                        .font(.title3.weight(.semibold))
                        .widgetAccentable()
                    Text(kind.label)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityLabel("Log \(kind.label)")
        }
    }
}

/// Sleep or Wake on the face, with how long she has been asleep.
struct SleepToggleView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    /// Set only by the DEBUG gallery in the Watch app, which has no widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    let entry: WatchBabyEntry

    private var s: NowSummary { entry.summary }
    private var asleep: Date? { s.runningSleepStart }

    var body: some View {
        if !s.tracked.contains(.sleep) {
            OffFace(kind: .sleep, family: family)
        } else {
            face.widgetURL(AppGroup.WatchLink.log(.sleep))
        }
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: asleep == nil ? EventKind.sleep.symbolName : "sun.max.fill")
                .font(.title3.weight(.semibold))
                .widgetAccentable()
                .widgetLabel { Text(asleep.map { "Wake · \(elapsed($0, entry.date))" } ?? "Sleep") }
        default:
            if let asleep {
                CircularFace(symbol: "sun.max.fill", value: elapsed(asleep, entry.date), caption: "Wake")
                    .accessibilityLabel("Wake. Asleep \(elapsed(asleep, entry.date))")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: EventKind.sleep.symbolName)
                            .font(.title3.weight(.semibold))
                            .widgetAccentable()
                        Text("Sleep")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .accessibilityLabel("Start sleep")
            }
        }
    }
}

/// A button turned off on the phone: say so, and never log.
private struct OffFace: View {
    let kind: EventKind
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: kind.symbolName)
                .widgetLabel { Text("Off") }
        case .accessoryInline:
            Text("\(kind.isDiaper ? "Diapers" : kind.label) off in Settings")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(kind.isDiaper ? "Diapers" : kind.label, systemImage: kind.symbolName).font(.headline)
                Text("Off in Settings on iPhone").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: kind.symbolName).font(.caption2)
                    Text("Off").font(.caption2.weight(.semibold))
                }
            }
        }
    }
}
