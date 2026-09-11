import SwiftData
import SwiftUI
import WidgetKit

struct CaffeineWidgetEntry: TimelineEntry {
    let date: Date
    let consumed: Double
    let remaining: Double
    let bedtimeRemaining: Double
    let bedtime: Date
}

struct CaffeineWidgetProvider: TimelineProvider {
    private static let placeholder = CaffeineWidgetEntry(
        date: .now,
        consumed: 220,
        remaining: 148,
        bedtimeRemaining: 42,
        bedtime: Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: .now) ?? .now
    )

    func placeholder(in context: Context) -> CaffeineWidgetEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CaffeineWidgetEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? Self.placeholder : loadEntry(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CaffeineWidgetEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = (0...6).map { loadEntry(at: now.addingTimeInterval(Double($0) * 30 * 60)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
        }
    }

    @MainActor
    private func loadEntry(at date: Date) -> CaffeineWidgetEntry {
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
        let minutes = defaults.object(forKey: caffeineBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        let halfLife = defaults.object(forKey: caffeineHalfLifeKey) as? Double ?? 5
        let start = Calendar.current.startOfDay(for: date)
        var bedtime = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? date
        if bedtime <= date {
            bedtime = Calendar.current.date(byAdding: .day, value: 1, to: bedtime) ?? bedtime
        }
        let selection = CaffeineSourceSelection()
        return CaffeineWidgetEntry(
            date: date,
            consumed: CaffeineClearance.consumedToday(samples: samples, selection: selection, now: date),
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
            ),
            bedtime: bedtime
        )
    }
}

struct CaffeineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaffeineWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 18) {
                remaining
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("At bedtime", systemImage: "moon.stars.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.cyan)
                    Text(CaffeineFormat.milligrams(entry.bedtimeRemaining))
                        .font(.title2.bold())
                    Text(CaffeineFormat.time(entry.bedtime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(CaffeineFormat.milligrams(entry.consumed)) today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("CAFFEINE NOW").font(.caption2)
                Text(CaffeineFormat.milligrams(entry.remaining)).font(.headline.bold())
                Text("\(CaffeineFormat.compactMilligrams(entry.bedtimeRemaining)) at bedtime").font(.caption)
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "waveform.path.ecg").font(.caption2)
                Text("\(Int(entry.remaining.rounded()))").font(.headline.bold())
                Text("mg").font(.caption2)
            }
        default:
            remaining
        }
    }

    private var remaining: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(Theme.violet)
            Text(CaffeineFormat.milligrams(entry.remaining))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            Text("estimated remaining")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct CaffeineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaffeineWidget", provider: CaffeineWidgetProvider()) { entry in
            CaffeineWidgetView(entry: entry)
                .containerBackground(Theme.surface, for: .widget)
        }
        .configurationDisplayName("Caffeine forecast")
        .description("See estimated caffeine remaining now and at bedtime.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
