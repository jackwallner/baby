import SwiftUI

/// The four buttons. They never move, never rename, and never gain a fifth:
/// a stable layout is the feature. A tap logs now; a long press opens the
/// editor with that kind pre-filled.
struct LogButtons: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @ScaledMetric(relativeTo: .title3) private var buttonHeight = AppTheme.logButtonHeight
    let onEdit: (EventKind, FeedSide?) -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            feedRow
            HStack(spacing: AppTheme.spacing) {
                kindButton(.wet, label: "Wet") { events.log(.wet) }
                kindButton(.dirty, label: "Dirty") { events.log(.dirty) }
            }
            kindButton(.sleep, label: events.runningSleep == nil ? "Sleep" : "Wake", symbol: events.runningSleep == nil ? "moon.fill" : "sun.max.fill") {
                events.toggleSleep()
            }
        }
    }

    /// Feed is one card with three zones so "which side" is answered by the
    /// tap itself, not by a second sheet.
    private var feedRow: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
            ForEach(Array(FeedSide.allCases.enumerated()), id: \.element) { index, side in
                Button {
                    Haptics.logged()
                    events.log(.feed, side: side)
                } label: {
                    VStack(spacing: AppTheme.hairSpacing) {
                        Text(side.label)
                            .font(.title3.weight(.semibold))
                        Text("Feed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: buttonHeight)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(AppTheme.ink)
                .pressableCard()
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    Haptics.selected()
                    onEdit(.feed, side)
                })
                .accessibilityLabel("Feed, \(side.label)")
                .accessibilityIdentifier("log.feed.\(side.rawValue)")
                .accessibilityHint("Logs a feed now. Hold to change the time or add details.")
                .accessibilityAction(named: "Add details") { onEdit(.feed, side) }
                if index < FeedSide.allCases.count - 1 {
                    if dynamicTypeSize.isAccessibilitySize {
                        Divider().padding(.horizontal, AppTheme.looseSpacing)
                    } else {
                        Rectangle()
                            .fill(AppTheme.feed.opacity(0.35))
                            .frame(width: 1, height: AppTheme.logButtonHeight - AppTheme.looseSpacing)
                    }
                }
            }
        }
        .background(AppTheme.fill(for: .feed), in: AppTheme.buttonShape)
    }

    private func kindButton(_ kind: EventKind, label: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.logged()
            action()
        } label: {
            HStack(spacing: AppTheme.tightSpacing) {
                Image(systemName: symbol ?? kind.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: kind))
                VStack(spacing: AppTheme.hairSpacing) {
                    Text(label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    if kind == .sleep, let start = events.summary.runningSleepStart {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("Asleep \(Format.compactDuration(context.date.timeIntervalSince(start)))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: buttonHeight)
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .contentShape(AppTheme.buttonShape)
        }
        .pressableCard()
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            Haptics.selected()
            onEdit(kind, nil)
        })
        .accessibilityLabel(label)
        .accessibilityIdentifier("log.\(kind.rawValue)")
        .accessibilityHint(kind == .sleep ? "Starts or ends sleep. Hold to log an earlier sleep." : "Logs a diaper now. Hold to add details.")
        .accessibilityAction(named: "Add details") { onEdit(kind, nil) }
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.summary.isSleeping)
    }
}
