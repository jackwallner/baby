import SwiftData
import SwiftUI
import WidgetKit

struct BabyWidgetEntry: TimelineEntry {
    let date: Date
    let consumed: Double
    let remaining: Double
    let bedtimeRemaining: Double
    let bedtime: Date
}

struct BabyWidgetProvider: TimelineProvider {
    private static let placeholder = BabyWidgetEntry(
        date: .now,
        consumed: 220,
        remaining: 148,
        bedtimeRemaining: 42,
        bedtime: Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: .now) ?? .now
    )

    func placeholder(in context: Context) -> BabyWidgetEntry { Self.placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BabyWidgetEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? Self.placeholder : loadEntry(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BabyWidgetEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = (0...6).map { loadEntry(at: now.addingTimeInterval(Double($0) * 30 * 60)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
        }
    }

    @MainActor
    private func loadEntry(at date: Date) -> BabyWidgetEntry {
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
        let minutes = defaults.object(forKey: babyBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        let halfLife = defaults.object(forKey: babyHalfLifeKey) as? Double ?? 5
        let start = Calendar.current.startOfDay(for: date)
        var bedtime = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? date
        if bedtime <= date {
            bedtime = Calendar.current.date(byAdding: .day, value: 1, to: bedtime) ?? bedtime
        }
        let selection = BabySourceSelection()
        return BabyWidgetEntry(
            date: date,
            consumed: BabyClearance.consumedToday(samples: samples, selection: selection, now: date),
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
            ),
            bedtime: bedtime
        )
    }
}

struct BabyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BabyWidgetEntry

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
                    Text(BabyFormat.milligrams(entry.bedtimeRemaining))
                        .font(.title2.bold())
                    Text(BabyFormat.time(entry.bedtime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(BabyFormat.milligrams(entry.consumed)) today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("BABY NOW").font(.caption2)
                Text(BabyFormat.milligrams(entry.remaining)).font(.headline.bold())
                Text("\(BabyFormat.compactMilligrams(entry.bedtimeRemaining)) at bedtime").font(.caption)
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
            Text(BabyFormat.milligrams(entry.remaining))
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
struct BabyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyWidget", provider: BabyWidgetProvider()) { entry in
            BabyWidgetView(entry: entry)
                .containerBackground(Theme.surface, for: .widget)
        }
        .configurationDisplayName("Baby forecast")
        .description("See estimated baby remaining now and at bedtime.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
