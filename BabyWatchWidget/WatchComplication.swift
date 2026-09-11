import SwiftUI
import WidgetKit

struct WatchBabyEntry: TimelineEntry {
    let date: Date
    let summary: NowSummary
}

struct WatchBabyProvider: TimelineProvider {
    private static var placeholder: WatchBabyEntry {
        var summary = NowSummary()
        summary.lastFeedAt = Date.now.addingTimeInterval(-2 * 3600 - 14 * 60)
        summary.lastFeedSide = .left
        summary.lastDiaperAt = Date.now.addingTimeInterval(-48 * 60)
        summary.lastDiaperKind = .wet
        return WatchBabyEntry(date: .now, summary: summary)
    }

    func placeholder(in context: Context) -> WatchBabyEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchBabyEntry) -> Void) {
        completion(context.isPreview ? Self.placeholder : WatchBabyEntry(date: .now, summary: NowSummary.load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchBabyEntry>) -> Void) {
        let summary = NowSummary.load()
        let now = Date.now
        let entries = (0..<12).map { WatchBabyEntry(date: now.addingTimeInterval(Double($0) * 300), summary: summary) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WatchBabyComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchBabyEntry

    private var s: NowSummary { entry.summary }

    private var sinceFeed: String {
        if let start = s.runningFeedStart { return Format.compactDuration(entry.date.timeIntervalSince(start)) }
        guard let last = s.lastFeedAt else { return "–" }
        return Format.compactDuration(entry.date.timeIntervalSince(last))
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: EventKind.feed.symbolName).font(.caption2)
                Text(sinceFeed).font(.headline.bold()).minimumScaleFactor(0.6)
                if let side = s.lastFeedSide { Text(side.shortLabel).font(.caption2) }
            }
            .foregroundStyle(AppTheme.feed)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(s.feedLine(now: entry.date)).font(.headline).lineLimit(1)
                Text(s.diaperLine(now: entry.date)).font(.caption2).lineLimit(1)
                Text(s.sleepLine(now: entry.date) ?? s.todayLine).font(.caption2).lineLimit(1)
            }
        case .accessoryInline:
            Label(s.feedLine(now: entry.date), systemImage: EventKind.feed.symbolName)
        case .accessoryCorner:
            Text(sinceFeed)
                .font(.headline.bold())
                .widgetLabel { Text(s.lastFeedSide?.label ?? "fed") }
        default:
            Text(sinceFeed)
        }
    }
}

@main
struct BabyWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.complication, provider: WatchBabyProvider()) { entry in
            WatchBabyComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last feed")
        .description("How long since the last feed, and which side.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
