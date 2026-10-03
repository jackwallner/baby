import SwiftUI

/// The everyday log: the last feed, the log controls and today's totals.
struct NowView: View {
    var isVisible = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    @State private var editor: EditorRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date.now
    @State private var fit = NowFit()
    @State private var hourStripHeight: CGFloat = 0
    @StateObject private var logClock = LogClock()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= AppTheme.wideLayout && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: AppTheme.looseSpacing) {
                            VStack(spacing: AppTheme.looseSpacing) {
                                NowStatusCard(now: now, clock: logClock)
                                TodayTotalsView(now: now)
                                OlderEntryLink(editor: $editor)
                            }
                            LoggingControls(height: AppTheme.maxLogButtonHeight, clock: logClock, editor: $editor)
                        }
                        .padding(.vertical, AppTheme.looseSpacing)
                    } else if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: AppTheme.spacing) {
                            NowStatusCard(now: now, clock: logClock)
                            LoggingControls(height: nil, clock: logClock, editor: $editor)
                            TodayTotalsView(now: now)
                            OlderEntryLink(editor: $editor)
                        }
                        .padding(.vertical, AppTheme.looseSpacing)
                    } else {
                        // TabView draws under its floating inset, so reserve the capsule before fitting Now.
                        fitted(
                            available: geometry.size.height
                                - geometry.safeAreaInsets.bottom
                                - AppTheme.bottomNavigationReservedHeight
                                - AppTheme.tightSpacing * 2
                        )
                            .padding(.vertical, AppTheme.tightSpacing)
                    }
                }
                .frame(maxWidth: AppTheme.contentWidth)
                .padding(.horizontal, AppTheme.margin)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { request in
            EventEditorView(request: request)
        }
        .onChange(of: isVisible) { _, visible in
            guard visible else { return }
            now = .now
            logClock.expireIfDue()
        }
        .onReceive(clock) { date in
            // A new totals day: rebuild the summary the widgets and Watch read.
            let window = TotalsWindow.current
            if window != .last24Hours, window.interval(at: now).start != window.interval(at: date).start { events.reload() }
            now = date
            logClock.expireIfDue()
        }
        .onChange(of: events.events.count) { _, _ in
            now = .now
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from a long nap: the elapsed time must be right on first sight.
            if phase == .active {
                now = .now
                logClock.expireIfDue()
            }
        }
    }

    private var title: String {
        guard let child = events.child else { return "Now" }
        return child.displayName
    }

    /// A phone: everything on one screen. The buttons take whatever height
    /// the rest leaves (within a floor and a cap), so they grow on a Pro Max,
    /// shrink on a small phone, and give way when the side chips open. The
    /// shortest screen (an SE) drops the hour strip. Past the floor (large
    /// text), the page scrolls rather than clipping.
    private func fitted(available: CGFloat) -> some View {
        let showsHourStrip = available >= AppTheme.hourStripMinHeight && fit.showsHourStrip
        // Sections sit 12 apart; the time row and the buttons, one control,
        // sit 8 apart.
        return VStack(alignment: .leading, spacing: AppTheme.spacing) {
            NowStatusCard(now: now, clock: logClock, compact: true)
            LoggingControls(height: fit.buttonHeight, spacing: AppTheme.tightSpacing, clock: logClock, editor: $editor)
                .padding(.bottom, fit.slack)
            TodayTotalsView(now: now, compact: true, showsHourStrip: showsHourStrip) { height in
                hourStripHeight = height
            }
            OlderEntryLink(editor: $editor)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // The page as drawn, less the part the last fit decided, is the
            // part that does not stretch.
            let fixed = height - fit.slack - fit.buttonHeight * rows
            refit(fixed: fixed, available: available, showsHourStrip: showsHourStrip, animated: fit.fixed != nil)
        }
        .onChange(of: available) { _, available in
            if let fixed = fit.fixed { refit(fixed: fixed, available: available, showsHourStrip: fit.showsHourStrip, animated: false) }
        }
        .onChange(of: hourStripHeight) { _, _ in
            if let fixed = fit.fixed { refit(fixed: fixed, available: available, showsHourStrip: fit.showsHourStrip, animated: false) }
        }
        .frame(minHeight: max(0, available), alignment: .top)
    }

    private var rows: CGFloat {
        CGFloat(max(1, LogButtons.rows(for: settings.tracked).count))
    }

    /// The buttons split what the rest leaves. Slack past the cap goes above
    /// the totals, so they sit at the bottom of the screen.
    private func refit(fixed: CGFloat, available: CGFloat, showsHourStrip: Bool, animated: Bool) {
        let withoutStrip = fixed - (showsHourStrip ? hourStripHeight : 0)
        let keepsStrip = available >= AppTheme.hourStripMinHeight
            && withoutStrip + hourStripHeight + AppTheme.minLogButtonHeight * rows <= available
        let fittedFixed = withoutStrip + (keepsStrip ? hourStripHeight : 0)
        let share = ((available - fittedFixed) / rows).rounded(.down)
        let height = min(AppTheme.maxLogButtonHeight, max(AppTheme.minLogButtonHeight, share))
        let next = NowFit(fixed: fittedFixed, buttonHeight: height, slack: max(0, available - fittedFixed - height * rows), showsHourStrip: keepsStrip)
        guard next.showsHourStrip != fit.showsHourStrip || abs(next.buttonHeight - fit.buttonHeight) >= 1 || abs(next.slack - fit.slack) >= 1 else {
            fit.fixed = fittedFixed
            return
        }
        // The first fit lands before anything draws; later ones (the side
        // chips opening) ride the same spring as the tap that caused them.
        withAnimation(animated && !reduceMotion ? AppTheme.feedbackAnimation : nil) {
            fit = next
        }
    }
}

/// The phone layout's last fit: the height that does not stretch (nil until
/// measured), each button's height, and the slack above the totals.
private struct NowFit: Equatable {
    var fixed: CGFloat?
    var buttonHeight: CGFloat = AppTheme.logButtonHeight
    var slack: CGFloat = 0
    var showsHourStrip = true
}

private struct LoggingControls: View {
    /// Nil: the scaled default, for accessibility text sizes.
    let height: CGFloat?
    var spacing = AppTheme.spacing
    @ObservedObject var clock: LogClock
    @Binding var editor: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            LogTimeRow(clock: clock)
            LogButtons(clock: clock, height: height, spacing: spacing) { kind in
                editor = EditorRequest(kind: kind, at: clock.chosen)
            }
            if clock.isAdjusted {
                LogHint(clock: clock)
            }
        }
    }
}

/// The time the buttons log at, right above them: the current time, or the
/// time a parent wound it back to. Minus and plus step five minutes on the
/// five-minute grid (7:26, 7:25, 7:20, 7:15); the time itself opens a wheel
/// for a bigger jump. "Now" puts it back, and it goes back on its own.
private struct LogTimeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var clock: LogClock

    var body: some View {
        TimelineView(.everyMinute) { context in
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing))
                : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
                status
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: AppTheme.tightSpacing) {
                    nudge("minus", label: "5 minutes earlier", id: "logTime.earlier") { clock.nudge(earlier: true) }
                    DatePicker(
                        "Log time",
                        selection: Binding(get: { clock.time(now: context.date) }, set: { date in animate { clock.set(date) } }),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .themedDatePicker()
                    .accessibilityIdentifier("logTime")
                    nudge("plus", label: "5 minutes later", id: "logTime.later") { clock.nudge(earlier: false) }
                        .disabled(!clock.isAdjusted)
                        .opacity(clock.isAdjusted ? 1 : 0.35)
                }
            }
            // Inset inside the wound-back outline, so the round buttons never
            // sit on its edge.
            .padding(.horizontal, AppTheme.spacing)
            .padding(.vertical, AppTheme.hairSpacing)
            .background(clock.isAdjusted ? AppTheme.actionFill.opacity(0.35) : .clear, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(clock.isAdjusted ? AppTheme.accent : .clear, lineWidth: AppTheme.hairlineWidth))
        }
    }

    /// The row and the hint under the buttons change together, in one
    /// transaction, so nothing between them jumps.
    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation, change)
    }

    @ViewBuilder
    private var status: some View {
        if clock.isAdjusted {
            Button {
                Haptics.selected()
                animate { clock.reset() }
            } label: {
                Label("Now", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Back to now")
            .accessibilityIdentifier("logTime.now")
        } else {
            Label("Logging at", systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink2)
                .frame(minHeight: 44)
        }
    }

    private func nudge(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selected()
            animate(action)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(AppTheme.card, in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
                .contentShape(Circle())
        }
        .pressableCard()
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Under the buttons while the time is wound back: which time a tap logs at
/// and when it returns to now.
private struct LogHint: View {
    @ObservedObject var clock: LogClock

    var body: some View {
        if let chosen = clock.chosen, let returnsAt = clock.returnsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Taps log at \(LogClock.label(for: chosen, now: context.date)). Back to now in \(Self.countdown(returnsAt.timeIntervalSince(context.date))).")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("logHint")
            }
        }
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The time the log buttons log at. Live by default. A parent can wind it
/// back to when it really happened; it comes back to live by itself a minute
/// after the last adjustment or tap, so a wound-back time never lingers into
/// the next feed.
@MainActor
final class LogClock: ObservableObject {
    static let hold: TimeInterval = 60
    static let step: TimeInterval = 5 * 60

    /// Nil while live.
    @Published private(set) var chosen: Date?
    @Published private(set) var returnsAt: Date?
    private var expiry: Task<Void, Never>?

    var isAdjusted: Bool { chosen != nil }

    func time(now: Date = .now) -> Date { chosen ?? now }

    /// From the wheel. A time-only wheel can land later today, which can only
    /// mean yesterday; within a minute of now is simply now.
    func set(_ date: Date, now: Date = .now, calendar: Calendar = .current) {
        var date = date
        if date > now.addingTimeInterval(60) {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        adopt(date, now: now)
    }

    /// Five minutes earlier or later, landing on the five-minute grid.
    func nudge(earlier: Bool, now: Date = .now) {
        let base = time(now: now).timeIntervalSinceReferenceDate
        var slot = earlier ? (floor((base - 1) / Self.step)) * Self.step : (floor(base / Self.step) + 1) * Self.step
        // Just past a mark (8:30:10), the mark itself is still "now": step on.
        if earlier, slot > now.timeIntervalSinceReferenceDate - 60 { slot -= Self.step }
        adopt(Date(timeIntervalSinceReferenceDate: slot), now: now)
    }

    /// A tap logged at the chosen time: give the parent another minute.
    func touched(now: Date = .now) {
        guard chosen != nil else { return }
        extend(now: now)
    }

    func reset() {
        chosen = nil
        returnsAt = nil
        expiry?.cancel()
    }

    /// The app slept through the expiry task: catch up on wake.
    func expireIfDue(now: Date = .now) {
        if let returnsAt, returnsAt <= now { reset() }
    }

    /// "7:15 AM", or "11:50 PM yesterday".
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return Format.time(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(Format.time(date)) yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func adopt(_ date: Date, now: Date) {
        guard date < now.addingTimeInterval(-30) else {
            reset()
            return
        }
        chosen = date
        extend(now: now)
    }

    private func extend(now: Date) {
        returnsAt = now.addingTimeInterval(Self.hold)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hold))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }
}


/// The answer to the 3am question. It leads with the last feed; a family that
/// does not track feeds sees the last diaper instead, and one that tracks
/// only sleep sees how long the baby has been asleep or awake.
private struct NowStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    @State private var showSaveError = false
    let now: Date
    @ObservedObject var clock: LogClock
    /// A phone fitting one screen: a tighter card.
    var compact = false

    private enum Lead { case feed, diaper, sleep }

    private var lead: Lead {
        if settings.tracked.contains(.feed) { return .feed }
        return settings.tracked.tracksDiapers ? .diaper : .sleep
    }

    private var summary: NowSummary { events.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? AppTheme.tightSpacing : AppTheme.spacing) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing))
                : AnyLayout(HStackLayout())) {
                Label(heading, systemImage: headingKind.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.color(for: headingKind))
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppTheme.tightSpacing) }
                if let day = summary.dayOfLife {
                    Text("Day \(day)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink2)
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(leadTime)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()
                    // A crossfade: "just now" to "2h 15m ago" is not a number
                    // rolling over, and the numeric roll smeared the letters.
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .fixedSize(horizontal: false, vertical: true)
                Text(leadDetail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLine)
            if lead == .feed, summary.isFeeding {
                Button("Finish feed") {
                    withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation) {
                        showSaveError = !events.stopRunning(.feed, at: clock.time())
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("finishFeed")
            }
            if lead == .feed, settings.tracked.tracksDiapers {
                Divider().overlay(AppTheme.cardElevated)
                HStack(spacing: AppTheme.tightSpacing) {
                    Image(systemName: diaperKind.symbolName)
                        .foregroundStyle(AppTheme.color(for: diaperKind))
                        .accessibilityHidden(true)
                    Text(summary.diaperLine(now: now))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink2)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(padding: compact ? AppTheme.compactCardPadding : AppTheme.looseSpacing)
        .accessibilityIdentifier("nowCard")
        .alert("Couldn't finish this feed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The timer is still running. Please try again.")
        }
    }

    /// The diaper kind to draw: the last one logged, else the first tracked.
    private var diaperKind: EventKind {
        summary.lastDiaperKind ?? (settings.tracked.contains(.wet) ? .wet : .dirty)
    }

    private var headingKind: EventKind {
        switch lead {
        case .feed: .feed
        case .diaper: diaperKind
        case .sleep: .sleep
        }
    }

    private var heading: String {
        switch lead {
        case .feed: summary.isFeeding ? "Feeding now" : "Last feed"
        case .diaper: "Last diaper"
        case .sleep: summary.isSleeping ? "Asleep" : "Awake"
        }
    }

    private var leadTime: String {
        switch lead {
        case .feed:
            if let start = summary.runningFeedStart { return Format.compactDuration(now.timeIntervalSince(start)) }
            guard let date = summary.lastFeedAt else { return "A fresh start" }
            return Format.ago(date, now: now)
        case .diaper:
            guard let date = summary.lastDiaperAt else { return "A fresh start" }
            return Format.ago(date, now: now)
        case .sleep:
            if let start = summary.runningSleepStart { return Format.compactDuration(now.timeIntervalSince(start)) }
            guard let woke = summary.lastWokeAt else { return "A fresh start" }
            return Format.compactDuration(now.timeIntervalSince(woke))
        }
    }

    private var leadDetail: String {
        switch lead {
        case .feed:
            guard let date = summary.runningFeedStart ?? summary.lastFeedAt else {
                return "Log a first feed below. We’ll remember the time and side."
            }
            let sides = summary.isFeeding ? summary.runningSides : summary.feedSides
            let label: String? = switch sides.count {
            case 1: sides[0] == .bottle ? "Bottle" : "\(sides[0].label) breast"
            default: FeedSide.label(for: sides)
            }
            return [label, Format.time(date)].compactMap { $0 }.joined(separator: " · ")
        case .diaper:
            guard let date = summary.lastDiaperAt else { return "Log a first diaper below." }
            return [summary.lastDiaperKind?.label, Format.time(date)].compactMap { $0 }.joined(separator: " · ")
        case .sleep:
            if let start = summary.runningSleepStart { return "Since \(Format.time(start))" }
            guard let woke = summary.lastWokeAt else { return "Tap Sleep when the baby falls asleep." }
            return "Woke at \(Format.time(woke))"
        }
    }

    private var accessibilityLine: String {
        switch lead {
        case .feed: summary.feedLine(now: now)
        case .diaper: summary.diaperLine(now: now)
        case .sleep: summary.awakeLine(now: now)
        }
    }
}

/// The day so far, counted from the hour the parent chose in Settings (or
/// over the last 24 hours): one figure per button, then an hour-by-hour
/// strip beneath with one row per button.
private struct TodayTotalsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    let now: Date
    var compact = false
    var showsHourStrip = true
    var onHourStripHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        let totals = WindowTotals.make(events: events.events, window: settings.totalsWindow, now: now)
        let title = settings.totalsWindow.title()
        let kinds = settings.tracked.buttons
        VStack(alignment: .leading, spacing: compact ? AppTheme.tightSpacing : AppTheme.spacing) {
            SectionLabel(text: title)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing))
                : AnyLayout(HStackLayout(alignment: .top, spacing: AppTheme.tightSpacing))) {
                ForEach(kinds, id: \.self) { kind in
                    stat(kind, totals: totals)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(totals.line(settings.tracked))")
            .accessibilityIdentifier("todayTotals")
            if showsHourStrip {
                HourStrip(totals: totals, kinds: kinds)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height + (compact ? AppTheme.tightSpacing : AppTheme.spacing)
                    } action: { height in
                        onHourStripHeightChange?(height)
                    }
            }
        }
        .card(padding: compact ? AppTheme.compactCardPadding : AppTheme.looseSpacing)
    }

    private func stat(_ kind: EventKind, totals: WindowTotals) -> some View {
        let value = kind == .sleep ? Format.compactDuration(totals.sleepSeconds) : "\(totals.count(kind))"
        return VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: AppTheme.hairSpacing) {
                KindDot(kind: kind, size: AppTheme.legendDotSize)
                Text(unit(kind, count: totals.count(kind)))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func unit(_ kind: EventKind, count: Int) -> String {
        switch kind {
        case .feed: count == 1 ? "feed" : "feeds"
        case .sleep: "sleep"
        default: kind.label.lowercased()
        }
    }
}

/// A contribution graph for the day: one row per button, 24 hourly squares.
/// Darker is more; sleep fills by how much of the hour was asleep. Hours still
/// to come stay faint.
private struct HourStrip: View {
    let totals: WindowTotals
    let kinds: [EventKind]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.cellGap) {
            ForEach(kinds, id: \.self) { kind in
                HStack(spacing: AppTheme.cellGap) {
                    KindDot(kind: kind, size: AppTheme.legendDotSize)
                        .frame(width: AppTheme.stripIconWidth, height: AppTheme.cellHeight, alignment: .leading)
                    ForEach(0..<WindowTotals.columns, id: \.self) { hour in
                        AppTheme.cellShape
                            .fill(fill(kind: kind, hour: hour))
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.cellHeight)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: WindowTotals.columns, by: 6)), id: \.self) { hour in
                    Text(totals.gridStart.addingTimeInterval(Double(hour) * 3600).formatted(.dateTime.hour()))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, AppTheme.stripIconWidth + AppTheme.cellGap)
            .padding(.top, AppTheme.hairSpacing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hour by hour")
        .accessibilityValue(spokenSummary)
        .accessibilityIdentifier("hourStrip")
    }

    private func fill(kind: EventKind, hour: Int) -> Color {
        let value = totals.hours[kind]?[hour] ?? 0
        guard value > 0 else {
            return hour >= totals.futureFrom ? AppTheme.separator.opacity(0.4) : AppTheme.separator
        }
        let strength = kind == .sleep ? 0.3 + 0.7 * min(1, value) : min(1, 0.3 + 0.35 * value)
        return AppTheme.color(for: kind).opacity(strength)
    }

    /// "Feed: 2 AM, 5 AM. Pee: 3 AM." Hours with at least one entry.
    private var spokenSummary: String {
        kinds.compactMap { kind -> String? in
            let hours = (totals.hours[kind] ?? []).enumerated().filter { $0.element > 0 }.map {
                totals.gridStart.addingTimeInterval(Double($0.offset) * 3600).formatted(.dateTime.hour())
            }
            return hours.isEmpty ? nil : "\(kind.label): \(hours.joined(separator: ", "))"
        }
        .joined(separator: ". ")
    }
}

/// Backfilling: the feed from before the app was installed, or the diaper
/// nobody logged overnight. Quiet, and last, so it never competes with a tap.
private struct OlderEntryLink: View {
    @Binding var editor: EditorRequest?

    var body: some View {
        Menu {
            NewEntryMenuItems(editor: $editor)
        } label: {
            Label("Add an older entry", systemImage: "clock.badge.plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink2)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("addOlderEntry")
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var kind: EventKind
    /// The time a new entry starts at: the log clock's, when wound back.
    var at: Date?
    var existing: LogEvent?
}
