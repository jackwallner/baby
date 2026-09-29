import CoreData
import SwiftUI

/// The log buttons. They never move: a stable layout is the feature. Feed,
/// then the diaper pair, then Sleep; a family can turn any of them off in
/// Settings and the rest keep their order. The diaper pair reads Pee and
/// Poop, or Wet and Dirty. A tap logs at the log clock's time (now, unless
/// the parent wound it back); a long press opens the editor with that kind
/// pre-filled.
struct LogButtons: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    @ObservedObject var clock: LogClock
    @State private var showSaveError = false
    /// The feed the side chips edit: the one Feed just logged.
    @State private var sideTarget: NSManagedObjectID?
    @State private var sideTimeout: Task<Void, Never>?
    @ScaledMetric(relativeTo: .title3) private var buttonHeight = AppTheme.logButtonHeight
    var minimumHeight: CGFloat = AppTheme.logButtonHeight
    let onEdit: (EventKind) -> Void

    /// How long the side chips stay after the last tap on them or on Feed.
    static let sideWindow: TimeInterval = 90

    /// The rows the tracked buttons make: Feed, the diaper pair (or the one
    /// diaper button left), Sleep.
    static func rows(for tracked: TrackedKinds) -> [[EventKind]] {
        [[.feed], [.wet, .dirty], [.sleep]]
            .map { $0.filter(tracked.contains) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ForEach(Self.rows(for: settings.tracked), id: \.self) { row in
                if row == [.feed] {
                    feedCard
                } else {
                    (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: AppTheme.spacing)) : AnyLayout(HStackLayout(spacing: AppTheme.spacing))) {
                        ForEach(row, id: \.self) { kind in
                            button(for: kind)
                        }
                    }
                }
            }
        }
        .alert("Couldn't save this entry", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was logged. Please try again.")
        }
    }

    @ViewBuilder
    private func button(for kind: EventKind) -> some View {
        switch kind {
        case .sleep:
            kindButton(.sleep, label: events.runningSleep == nil ? "Sleep" : "Wake") { at in
                if events.runningSleep != nil {
                    return events.stopRunning(.sleep, at: at)
                }
                return events.startTimed(.sleep, at: at) != nil
            }
        default:
            kindButton(kind, label: kind.label) { events.log(kind, at: $0) != nil }
        }
    }

    /// Every tap changes the card, the totals and the toast together: one
    /// transaction, so nothing on the screen moves on its own schedule.
    private func animate<T>(_ change: () -> T) -> T {
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation, change)
    }

    // MARK: - Feed

    /// One tap logs a feed. The side is a second, optional step that opens
    /// under the button once the feed is safely logged, so the quick path
    /// never waits on a choice.
    private var feedCard: some View {
        VStack(spacing: 0) {
            Button(action: logFeed) {
                HStack(spacing: AppTheme.tightSpacing) {
                    CareGraphic(kind: .feed)
                    Text("Feed")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.tightSpacing)
                .frame(minHeight: max(buttonHeight, minimumHeight))
                .contentShape(Rectangle())
            }
            .pressableCard()
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                Haptics.selected()
                onEdit(.feed)
            })
            .accessibilityLabel("Feed")
            .accessibilityIdentifier("log.feed")
            .accessibilityHint("Logs a feed. You can add a side after. Hold to change the time or add details.")
            .accessibilityAction(named: "Add details") { onEdit(.feed) }

            if let target = targetFeed {
                VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                    Rectangle()
                        .fill(AppTheme.feed.opacity(0.35))
                        .frame(height: AppTheme.hairlineWidth)
                    Text("Add a side (optional)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink2)
                        .padding(.top, AppTheme.hairSpacing)
                    FeedSideChips(selection: sidesBinding(for: target))
                }
                .padding([.horizontal, .bottom], AppTheme.spacing)
                // The card grows and the row fades up into the new space; on
                // the way out it fades first, so chips never slide over Feed.
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -AppTheme.tightSpacing)),
                    removal: .opacity
                ))
            }
        }
        .background(AppTheme.fill(for: .feed), in: AppTheme.buttonShape)
        .clipShape(AppTheme.buttonShape)
        .graphicBorder()
    }

    private var targetFeed: LogEvent? {
        guard let sideTarget else { return nil }
        return events.events.first { $0.objectID == sideTarget }
    }

    private func logFeed() {
        let at = clock.time()
        let event = animate {
            let event = events.log(.feed, at: at)
            if let event { sideTarget = event.objectID }
            return event
        }
        reportSave(event != nil)
        if event != nil { holdSides() }
    }

    private func sidesBinding(for event: LogEvent) -> Binding<[FeedSide]> {
        Binding(
            get: { event.feedSides },
            set: { sides in
                let saved = animate {
                    event.feedSides = sides
                    return events.save()
                }
                if !saved { showSaveError = true }
                holdSides()
            }
        )
    }

    private func holdSides() {
        sideTimeout?.cancel()
        sideTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.sideWindow))
            guard !Task.isCancelled else { return }
            animate { sideTarget = nil }
        }
    }

    // MARK: - Diapers and sleep

    private func reportSave(_ saved: Bool) {
        if saved {
            Haptics.logged()
            clock.touched()
        } else {
            showSaveError = true
        }
    }

    private func kindButton(_ kind: EventKind, label: String, action: @escaping (Date) -> Bool) -> some View {
        Button {
            // The side row stays: a diaper change mid-feed must not cost the side.
            let at = clock.time()
            reportSave(animate { action(at) })
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
            onEdit(kind)
        })
        .accessibilityLabel(label)
        .accessibilityIdentifier("log.\(kind.rawValue)")
        .accessibilityHint(kind == .sleep ? "Starts or ends sleep. Hold to log an earlier sleep." : "Logs a diaper. Hold to add details.")
        .accessibilityAction(named: "Add details") { onEdit(kind) }
    }
}

/// Left, Right, Bottle: any, all or none, in the order tapped (that order is
/// the feed's order, "right then left"). Shared by Now and the editor.
struct FeedSideChips: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: [FeedSide]

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: AppTheme.tightSpacing)) : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
            ForEach(FeedSide.allCases, id: \.self) { side in
                chip(side)
            }
        }
    }

    private func chip(_ side: FeedSide) -> some View {
        let isOn = selection.contains(side)
        return Button {
            Haptics.selected()
            if isOn {
                selection.removeAll { $0 == side }
            } else {
                selection.append(side)
            }
        } label: {
            HStack(spacing: AppTheme.hairSpacing) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(side.label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isOn ? AppTheme.feed : AppTheme.card, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(isOn ? AppTheme.feed : AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
            .contentShape(AppTheme.buttonShape)
        }
        .pressableCard()
        .accessibilityLabel(side.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("feedSide.\(side.rawValue)")
    }
}
