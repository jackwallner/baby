import SwiftUI
import WidgetKit

struct SimpleGLPWidgetEntry: TimelineEntry {
    let date: Date
    let lastShotDate: Date?
    let recentShots: [RecentShot]
    let showConfirmation: Bool
}

struct SimpleGLPWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleGLPWidgetEntry {
        SimpleGLPWidgetEntry(date: .now, lastShotDate: nil, recentShots: [], showConfirmation: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleGLPWidgetEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleGLPWidgetEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(at: now)
        var entries = [entry]
        if entry.showConfirmation {
            // Flip out of confirmation a couple seconds later.
            let revert = now.addingTimeInterval(3)
            entries.append(SimpleGLPWidgetEntry(
                date: revert,
                lastShotDate: entry.lastShotDate,
                recentShots: entry.recentShots,
                showConfirmation: false
            ))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func makeEntry(at date: Date) -> SimpleGLPWidgetEntry {
        let defaults = GLPAppGroup.userDefaults
        let last = defaults.object(forKey: GLPStorageKey.widgetLastLoggedAt.rawValue) as? Date
        let shots = RecentShotsStore.load()
        let recentlyLogged = last.map { date.timeIntervalSince($0) < 3 } ?? false
        return SimpleGLPWidgetEntry(date: date, lastShotDate: last, recentShots: shots, showConfirmation: recentlyLogged)
    }
}

struct SimpleGLPWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SimpleGLPWidgetProvider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        default:
            mediumBody
        }
    }

    private var smallBody: some View {
        Button(intent: LogShotIntent()) {
            VStack(spacing: 8) {
                Image(systemName: entry.showConfirmation ? "checkmark.circle.fill" : "syringe.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(entry.showConfirmation ? "Logged" : "I took my shot")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let last = entry.lastShotDate, !entry.showConfirmation {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            (entry.showConfirmation ? AppTheme.brandPressed : AppTheme.brand)
        }
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(intent: LogShotIntent()) {
                VStack(spacing: 6) {
                    Image(systemName: entry.showConfirmation ? "checkmark.circle.fill" : "syringe.fill")
                        .font(.system(size: 28, weight: .bold))
                    Text(entry.showConfirmation ? "Logged" : "I took my shot")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .background(
                    (entry.showConfirmation ? AppTheme.brandPressed : AppTheme.brand),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("Last few shots")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                if entry.recentShots.isEmpty {
                    Text("Nothing yet")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    ForEach(entry.recentShots.prefix(3)) { shot in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.brand)
                            Text(shot.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(AppTheme.text)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .containerBackground(AppTheme.bg, for: .widget)
    }
}

@main
struct SimpleGLPWidget: Widget {
    let kind: String = "SimpleGLPWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleGLPWidgetProvider()) { entry in
            SimpleGLPWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Simple GLP")
        .description("One tap to log your shot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
