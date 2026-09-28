import CoreData
import SwiftUI

/// The four buttons. They never move and never gain a fifth: a stable layout
/// is the feature. The diaper pair reads Pee and Poop, or Wet and Dirty when
/// the parent picks those words in More. A tap logs at the log clock's time
/// (now, unless the parent wound it back); a long press opens the editor with
/// that kind pre-filled.
struct LogButtons: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
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

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            feedCard
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: AppTheme.spacing)) : AnyLayout(HStackLayout(spacing: AppTheme.spacing))) {
                kindButton(.wet, label: EventKind.wet.label) { events.log(.wet, at: $0) != nil }
                kindButton(.dirty, label: EventKind.dirty.label) { events.log(.dirty, at: $0) != nil }
            }
            kindButton(.sleep, label: events.runningSleep == nil ? "Sleep" : "Wake") { at in
                if events.runningSleep != nil {
                    return events.stopRunning(.sleep, at: at)
                }
                return events.startTimed(.sleep, at: at) != nil
            }
        }
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: sideTarget)
        .alert("Couldn't save this entry", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was logged. Please try again.")
        }
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
                Rectangle()
                    .fill(AppTheme.feed.opacity(0.35))
                    .frame(height: AppTheme.hairlineWidth)
                    .padding(.horizontal, AppTheme.spacing)
                VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                    Text("Add a side (optional)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink2)
                    FeedSideChips(selection: sidesBinding(for: target))
                }
                .padding(AppTheme.spacing)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.fill(for: .feed), in: AppTheme.buttonShape)
        .graphicBorder()
    }

    private var targetFeed: LogEvent? {
        guard let sideTarget else { return nil }
        return events.events.first { $0.objectID == sideTarget }
    }

    private func logFeed() {
        let event = events.log(.feed, at: clock.time())
        reportSave(event != nil)
        guard let event else { return }
        sideTarget = event.objectID
        holdSides()
    }

    private func sidesBinding(for event: LogEvent) -> Binding<[FeedSide]> {
        Binding(
            get: { event.feedSides },
            set: { sides in
                event.feedSides = sides
                if !events.save() { showSaveError = true }
                holdSides()
            }
        )
    }

    private func holdSides() {
        sideTimeout?.cancel()
        sideTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.sideWindow))
            guard !Task.isCancelled else { return }
            sideTarget = nil
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
            reportSave(action(clock.time()))
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
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.summary.isSleeping)
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
