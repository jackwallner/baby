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

    private var sinceLead: String { s.leadElapsed(now: entry.date) }

    private var cornerLabel: String {
        switch s.leadKind {
        case .feed: FeedSide.label(for: s.feedSides) ?? "fed"
        case .sleep: s.isSleeping ? "asleep" : "awake"
        default: "diaper"
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: s.leadKind.symbolName).font(.caption2)
                Text(sinceLead).font(.headline.bold()).minimumScaleFactor(0.6)
                if let detail = s.leadShortDetail { Text(detail).font(.caption2) }
            }
            .foregroundStyle(AppTheme.color(for: s.leadKind))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(s.leadLine(now: entry.date)).font(.headline).lineLimit(1)
                ForEach(Array(s.supportingLines(now: entry.date).prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2).lineLimit(1)
                }
                if s.supportingLines(now: entry.date).count < 2, !s.todayLine.isEmpty {
                    Text(s.todayLine).font(.caption2).lineLimit(1)
                }
            }
        case .accessoryInline:
            Label(s.leadLine(now: entry.date), systemImage: s.leadKind.symbolName)
        case .accessoryCorner:
            Text(sinceLead)
                .font(.headline.bold())
                .widgetLabel { Text(cornerLabel) }
        default:
            Text(sinceLead)
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
