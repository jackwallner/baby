import SwiftUI

/// The four buttons. They never move and never gain a fifth: a stable layout
/// is the feature. The diaper pair reads Pee and Poop, or Wet and Dirty when
/// the parent picks those words in More. A tap logs now; a long press opens the
/// editor with that kind pre-filled.
struct LogButtons: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @State private var showSaveError = false
    @ScaledMetric(relativeTo: .title3) private var buttonHeight = AppTheme.logButtonHeight
    var minimumHeight: CGFloat = AppTheme.logButtonHeight
    let onEdit: (EventKind, FeedSide?) -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            feedRow
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: AppTheme.spacing)) : AnyLayout(HStackLayout(spacing: AppTheme.spacing))) {
                kindButton(.wet, label: EventKind.wet.label) { events.log(.wet) != nil }
                kindButton(.dirty, label: EventKind.dirty.label) { events.log(.dirty) != nil }
            }
            kindButton(.sleep, label: events.runningSleep == nil ? "Sleep" : "Wake", symbol: events.runningSleep == nil ? "moon.fill" : "sun.max.fill") {
                if events.runningSleep != nil {
                    return events.stopRunning(.sleep)
                }
                return events.startTimed(.sleep) != nil
            }
        }
        .alert("Couldn't save this entry", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was logged. Please try again.")
        }
    }

    /// Feed is one card with three zones so "which side" is answered by the
    /// tap itself, not by a second sheet.
    private var feedRow: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
            ForEach(Array(FeedSide.allCases.enumerated()), id: \.element) { index, side in
                Button {
                    reportSave(events.log(.feed, side: side) != nil)
                } label: {
                    VStack(spacing: AppTheme.hairSpacing) {
                        CareGraphic(kind: .feed, side: side)
                        Text(side.label)
                            .font(.title3.weight(.semibold))
                        Text("Feed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.tightSpacing)
                    .frame(minHeight: max(buttonHeight, minimumHeight))
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
        .graphicBorder()
    }

    private func reportSave(_ saved: Bool) {
        if saved {
            Haptics.logged()
        } else {
            showSaveError = true
        }
    }

    private func kindButton(_ kind: EventKind, label: String, symbol: String? = nil, action: @escaping () -> Bool) -> some View {
        Button {
            reportSave(action())
        } label: {
            HStack(spacing: AppTheme.tightSpacing) {
                if kind == .sleep, events.runningSleep != nil {
                    Image(systemName: "sun.max.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.sleep)
                        .frame(width: AppTheme.graphicSize, height: AppTheme.graphicSize)
                        .accessibilityHidden(true)
                } else {
                    CareGraphic(kind: kind)
                }
                VStack(spacing: AppTheme.hairSpacing) {
                    Text(label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    if kind == .sleep, let start = events.summary.runningSleepStart {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(Format.asleep(context.date.timeIntervalSince(start)))
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.tightSpacing)
            .frame(minHeight: max(buttonHeight, minimumHeight))
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .graphicBorder()
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
