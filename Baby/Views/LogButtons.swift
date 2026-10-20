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
    @ObservedObject var sides: FeedSidePrompt
    @State private var showSaveError = false
    @ScaledMetric(relativeTo: .title3) private var buttonHeight = AppTheme.logButtonHeight
    /// Each button's height, fitted to the screen; nil uses the scaled default.
    var height: CGFloat? = nil
    var spacing = AppTheme.spacing
    let onEdit: (EventKind) -> Void

    /// A fitted button can get as short as its graphic allows.
    private var labelPadding: CGFloat {
        height == nil ? AppTheme.tightSpacing : AppTheme.hairSpacing
    }

    /// The rows the tracked buttons make: Feed, the diaper pair (or the one
    /// diaper button left), Sleep.
    static func rows(for tracked: TrackedKinds) -> [[EventKind]] {
        [[.feed], [.wet, .dirty], [.sleep]]
            .map { $0.filter(tracked.contains) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Self.rows(for: settings.tracked), id: \.self) { row in
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))) {
                    ForEach(row, id: \.self) { kind in
                        button(for: kind)
                    }
                }
            }
        }
        .alert("Couldn't save this entry", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was logged. Please try again.")
        }
        .sheet(isPresented: $sides.showReminderOffer) {
            FeedReminderOfferView()
        }
    }

    @ViewBuilder
    private func button(for kind: EventKind) -> some View {
        switch kind {
        case .feed:
            // One tap logs a feed. The side is a second, optional step that
            // opens above the buttons once the feed is safely logged, so the
            // quick path never waits on a choice.
            kindButton(.feed, label: "Feed") { at in
                guard let event = events.log(.feed, at: at) else { return false }
                sides.open(event.objectID)
                return true
            }
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

    private func hint(for kind: EventKind) -> String {
        switch kind {
        case .feed: "Logs a feed. You can add a side after. Hold to change the time or add details."
        case .sleep: "Starts or ends sleep. Hold to log an earlier sleep."
        default: "Logs a diaper. Hold to add details."
        }
    }

    /// Every tap changes the card, the totals and the toast together: one
    /// transaction, so nothing on the screen moves on its own schedule.
    private func animate<T>(_ change: () -> T) -> T {
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation, change)
    }

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
            .padding(.vertical, labelPadding)
            .frame(minHeight: height ?? buttonHeight)
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
        .accessibilityHint(hint(for: kind))
        .accessibilityAction(named: "Add details") { onEdit(kind) }
    }
}

/// What follows a Feed tap: the feed the side chips edit, how long they stay,
/// and the one-time reminder offer, which waits for the parent to finish.
@MainActor
final class FeedSidePrompt: ObservableObject {
    /// How long the side chips stay after the last tap on them or on Feed.
    static let window: TimeInterval = 90
    /// The reminder offer waits this long after the last Feed or side tap, so
    /// it never lands on a parent mid-choice.
    static let reminderOfferDelay: TimeInterval = 6

    @Published private(set) var target: NSManagedObjectID?
    @Published var showReminderOffer = false
    private var timeout: Task<Void, Never>?
    private var reminderOffer: Task<Void, Never>?

    /// The feed the chips edit, while it still exists (Undo removes it).
    func event(in events: [LogEvent]) -> LogEvent? {
        guard let target else { return nil }
        return events.first { $0.objectID == target }
    }

    /// Feed just logged: offer its side.
    func open(_ id: NSManagedObjectID) {
        target = id
        hold()
        queueReminderOffer()
    }

    /// A side tap: another full window, and the offer waits again.
    func touched() {
        hold()
        if reminderOffer != nil { queueReminderOffer() }
    }

    func close() {
        timeout?.cancel()
        target = nil
    }

    private func hold() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.window))
            guard !Task.isCancelled else { return }
            withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : AppTheme.feedbackAnimation) {
                self?.target = nil
            }
        }
    }

    /// Once per install, a few seconds after a feed: the next feed's reminder.
    private func queueReminderOffer() {
        guard ReminderOfferGate.isEnabled, !Reminders.hasOfferedFeedReminder else { return }
        reminderOffer?.cancel()
        reminderOffer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.reminderOfferDelay))
            guard !Task.isCancelled, !Reminders.hasOfferedFeedReminder else { return }
            self?.showReminderOffer = true
        }
    }
}

/// After a Feed tap, in the log-time row's place and at its height: which
/// side that feed was. Nothing else on the screen moves when it opens.
struct FeedSideRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @ObservedObject var prompt: FeedSidePrompt
    let event: LogEvent
    @State private var showSaveError = false

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing))
            : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
            Text("Side")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink2)
                .fixedSize()
                .accessibilityLabel("Add a side, optional")
            FeedSideChips(selection: selection)
            Button("Done") {
                Haptics.selected()
                animate { prompt.close() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize()
            .accessibilityLabel("Done adding a side")
            .accessibilityIdentifier("feedSide.done")
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.vertical, AppTheme.hairSpacing)
        .background(AppTheme.fill(for: .feed), in: AppTheme.buttonShape)
        .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
        .alert("Couldn't save this side", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The feed is logged. Please try the side again.")
        }
    }

    private func animate<T>(_ change: () -> T) -> T {
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation, change)
    }

    private var selection: Binding<[FeedSide]> {
        Binding(
            get: { event.feedSides },
            set: { sides in
                let saved = animate {
                    event.feedSides = sides
                    return events.save()
                }
                if !saved { showSaveError = true }
                prompt.touched()
            }
        )
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
