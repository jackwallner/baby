import SwiftUI

/// The second page: today's counts, then every entry in the phone's totals
/// window, newest first. Turn the crown down from Now to reach it.
struct WatchTodayView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let summary = store.summary.current(now: context.date)
            let entries = summary.recentInWindow(now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                    Text(heading(summary))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.ink2)
                    counts(summary)
                    if summary.tracked.contains(.sleep), summary.runningSleepStart != nil || summary.lastWokeAt != nil {
                        Label(summary.awakeLine(now: context.date), systemImage: summary.isSleeping ? EventKind.sleep.symbolName : "sun.max.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.sleep)
                    }
                    if entries.isEmpty {
                        Text("Nothing logged yet")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink2)
                            .padding(.top, AppTheme.hairSpacing)
                    } else {
                        ForEach(entries) { entry in
                            row(entry, now: context.date)
                        }
                    }
                }
            }
            .navigationTitle(summary.childName)
        }
    }

    /// "Today · Day 3" in the first weeks, "Since 6 AM" with a custom day.
    private func heading(_ summary: NowSummary) -> String {
        guard let day = summary.dayOfLife, day <= 28 else { return summary.window.title() }
        return "\(summary.window.title()) · Day \(day)"
    }

    private func counts(_ summary: NowSummary) -> some View {
        let kinds: [EventKind] = [.feed, .wet, .dirty].filter(summary.tracked.contains)
        return HStack(spacing: AppTheme.hairSpacing) {
            ForEach(kinds, id: \.self) { kind in
                let count = switch kind {
                case .feed: summary.todayFeeds
                case .wet: summary.todayWet
                default: summary.todayDirty
                }
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                    Text(kind == .feed ? (count == 1 ? "feed" : "feeds") : kind.label.lowercased())
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.hairSpacing)
                .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ entry: RecentEntry, now: Date) -> some View {
        HStack(spacing: AppTheme.tightSpacing) {
            Image(systemName: entry.kind.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.color(for: entry.kind))
                .frame(width: AppTheme.stripIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title(now: now))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Format.time(entry.at))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer(minLength: 0)
            Text(WatchGlance.elapsed(since: entry.at, now: now))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(.vertical, AppTheme.hairSpacing)
        .accessibilityElement(children: .combine)
    }
}
