import SwiftData
import SwiftUI
import WidgetKit

struct WatchCaffeineEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let bedtimeRemaining: Double
}

struct WatchCaffeineProvider: TimelineProvider {
    private static let placeholder = WatchCaffeineEntry(date: .now, remaining: 148, bedtimeRemaining: 42)

    func placeholder(in context: Context) -> WatchCaffeineEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchCaffeineEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? Self.placeholder : load(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchCaffeineEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = (0...4).map { load(at: now.addingTimeInterval(Double($0) * 30 * 60)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
        }
    }

    @MainActor
    private func load(at date: Date) -> WatchCaffeineEntry {
        let context = DataService.sharedModelContainer.mainContext
        let cached = (try? context.fetch(FetchDescriptor<CachedCaffeineDose>())) ?? []
        let samples = cached.map {
            CaffeineSample(
                id: $0.id,
                sourceBundleID: $0.sourceBundleID,
                sourceName: $0.sourceName,
                milligrams: $0.milligrams,
                endDate: $0.date,
                isOurs: $0.isOurs
            )
        }
        let defaults = UserDefaults(suiteName: caffeineAppGroupID) ?? .standard
        let halfLife = defaults.object(forKey: caffeineHalfLifeKey) as? Double ?? 5
        let minutes = defaults.object(forKey: caffeineBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        let start = Calendar.current.startOfDay(for: date)
        var bedtime = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? date
        if bedtime <= date {
            bedtime = Calendar.current.date(byAdding: .day, value: 1, to: bedtime) ?? bedtime
        }
        let selection = CaffeineSourceSelection()
        return WatchCaffeineEntry(
            date: date,
            remaining: CaffeineClearance.remaining(
                samples: samples,
                at: date,
                selection: selection,
                halfLifeHours: halfLife
            ),
            bedtimeRemaining: CaffeineClearance.remaining(
                samples: samples,
                at: bedtime,
                selection: selection,
                halfLifeHours: halfLife
            )
        )
    }
}

struct WatchCaffeineComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchCaffeineEntry

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
                Text("CAFFEINE").font(.caption2)
                Text("\(CaffeineFormat.compactMilligrams(entry.remaining)) now").font(.headline.bold())
                Text("\(CaffeineFormat.compactMilligrams(entry.bedtimeRemaining)) at bedtime").font(.caption)
            }
        case .accessoryInline:
            Label(
                "\(CaffeineFormat.compactMilligrams(entry.remaining)) caffeine now",
                systemImage: "waveform.path.ecg"
            )
        case .accessoryCorner:
            Text("\(Int(entry.remaining.rounded()))")
                .font(.headline.bold())
                .widgetLabel { Text("mg") }
        default:
            Text(CaffeineFormat.compactMilligrams(entry.remaining))
        }
    }
}

@main
struct CaffeineWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaffeineWatchWidget", provider: WatchCaffeineProvider()) { entry in
            WatchCaffeineComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Caffeine forecast")
        .description("Estimated caffeine remaining now and at bedtime.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
