import SwiftData
import SwiftUI
import WidgetKit

struct WatchBabyEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let bedtimeRemaining: Double
}

struct WatchBabyProvider: TimelineProvider {
    private static let placeholder = WatchBabyEntry(date: .now, remaining: 148, bedtimeRemaining: 42)

    func placeholder(in context: Context) -> WatchBabyEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchBabyEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? Self.placeholder : load(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchBabyEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = (0...4).map { load(at: now.addingTimeInterval(Double($0) * 30 * 60)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
        }
    }

    @MainActor
    private func load(at date: Date) -> WatchBabyEntry {
        let context = DataService.sharedModelContainer.mainContext
        let cached = (try? context.fetch(FetchDescriptor<CachedBabyDose>())) ?? []
        let samples = cached.map {
            BabySample(
                id: $0.id,
                sourceBundleID: $0.sourceBundleID,
                sourceName: $0.sourceName,
                milligrams: $0.milligrams,
                endDate: $0.date,
                isOurs: $0.isOurs
            )
        }
        let defaults = UserDefaults(suiteName: babyAppGroupID) ?? .standard
        let halfLife = defaults.object(forKey: babyHalfLifeKey) as? Double ?? 5
        let minutes = defaults.object(forKey: babyBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        let start = Calendar.current.startOfDay(for: date)
        var bedtime = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? date
        if bedtime <= date {
            bedtime = Calendar.current.date(byAdding: .day, value: 1, to: bedtime) ?? bedtime
        }
        let selection = BabySourceSelection()
        return WatchBabyEntry(
            date: date,
            remaining: BabyClearance.remaining(
                samples: samples,
                at: date,
                selection: selection,
                halfLifeHours: halfLife
            ),
            bedtimeRemaining: BabyClearance.remaining(
                samples: samples,
                at: bedtime,
                selection: selection,
                halfLifeHours: halfLife
            )
        )
    }
}

struct WatchBabyComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchBabyEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "waveform.path.ecg").font(.caption2)
                Text("\(Int(entry.remaining.rounded()))").font(.headline.bold())
                Text("mg").font(.caption2)
            }
            .foregroundStyle(Theme.cyan)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("BABY").font(.caption2)
                Text("\(BabyFormat.compactMilligrams(entry.remaining)) now").font(.headline.bold())
                Text("\(BabyFormat.compactMilligrams(entry.bedtimeRemaining)) at bedtime").font(.caption)
            }
        case .accessoryInline:
            Label(
                "\(BabyFormat.compactMilligrams(entry.remaining)) baby now",
                systemImage: "waveform.path.ecg"
            )
        case .accessoryCorner:
            Text("\(Int(entry.remaining.rounded()))")
                .font(.headline.bold())
                .widgetLabel { Text("mg") }
        default:
            Text(BabyFormat.compactMilligrams(entry.remaining))
        }
    }
}

@main
struct BabyWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyWatchWidget", provider: WatchBabyProvider()) { entry in
            WatchBabyComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baby forecast")
        .description("Estimated baby remaining now and at bedtime.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
