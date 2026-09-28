import SwiftUI

/// The whole everyday app: the last feed, four log controls and today's totals.
/// History is one tap away. Everything else lives in More.
struct NowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var events: EventStore
    @State private var editor: EditorRequest?
    @State private var showSettings = false
    @State private var now = Date.now
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
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.spacing) {
                            NowStatusCard(now: now, clock: logClock)
                            LoggingControls(height: min(AppTheme.maxLogButtonHeight, max(AppTheme.logButtonHeight, (geometry.size.height - AppTheme.homeSummaryAllowance) / 3)), clock: logClock, editor: $editor)
                            Spacer(minLength: 0)
                            TodayTotalsView(now: now)
                            OlderEntryLink(editor: $editor)
                        }
                        .frame(minHeight: max(0, geometry.size.height - AppTheme.looseSpacing * 2), alignment: .top)
                    }
                }
                .frame(maxWidth: AppTheme.contentWidth)
                .padding(.horizontal, AppTheme.margin)
                .padding(.vertical, AppTheme.looseSpacing)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { HistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("History")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("more")
            }
        }
        .sheet(item: $editor) { request in
            EventEditorView(request: request)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
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

}

private struct LoggingControls: View {
    let height: CGFloat
    @ObservedObject var clock: LogClock
    @Binding var editor: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            LogTimeRow(clock: clock)
            LogButtons(clock: clock, minimumHeight: height) { kind in
                editor = EditorRequest(kind: kind, at: clock.chosen)
            }
            LogHint(clock: clock)
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
                        selection: Binding(get: { clock.time(now: context.date) }, set: { clock.set($0) }),
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
            .padding(.horizontal, AppTheme.spacing)
            .background(clock.isAdjusted ? AppTheme.actionFill.opacity(0.35) : .clear, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(clock.isAdjusted ? AppTheme.accent : .clear, lineWidth: AppTheme.hairlineWidth))
        }
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: clock.chosen)
    }

    @ViewBuilder
    private var status: some View {
        if clock.isAdjusted {
            Button {
                Haptics.selected()
                clock.reset()
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
            action()
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

/// Under the buttons: how to use them, or, while the time is wound back,
/// which time a tap logs at and when it returns to now.
private struct LogHint: View {
    @ObservedObject var clock: LogClock

    var body: some View {
        Group {
            if let chosen = clock.chosen, let returnsAt = clock.returnsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Taps log at \(LogClock.label(for: chosen, now: context.date)). Back to now in \(Self.countdown(returnsAt.timeIntervalSince(context.date))).")
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                }
            } else {
                Text("Tap to log now. Hold to add details.")
                    .foregroundStyle(AppTheme.ink2)
            }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("logHint")
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

private struct NowStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @State private var showSaveError = false
    let now: Date
    @ObservedObject var clock: LogClock

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing))
                : AnyLayout(HStackLayout())) {
                Label(events.summary.isFeeding ? "Feeding now" : "Last feed", systemImage: EventKind.feed.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.feed)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppTheme.tightSpacing) }
                if let day = events.summary.dayOfLife {
                    Text("Day \(day)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink2)
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(feedTime)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .fixedSize(horizontal: false, vertical: true)
                Text(feedDetail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(events.summary.feedLine(now: now))
            if events.summary.isFeeding {
                Button("Finish feed") { showSaveError = !events.stopRunning(.feed, at: clock.time()) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("finishFeed")
            }
            Divider().overlay(AppTheme.cardElevated)
            HStack(spacing: AppTheme.tightSpacing) {
                Image(systemName: (events.summary.lastDiaperKind ?? .wet).symbolName)
                    .foregroundStyle(AppTheme.color(for: events.summary.lastDiaperKind ?? .wet))
                    .accessibilityHidden(true)
                Text(events.summary.diaperLine(now: now))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.summary)
        .accessibilityIdentifier("nowCard")
        .alert("Couldn't finish this feed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The timer is still running. Please try again.")
        }
    }

    private var feedTime: String {
        if let start = events.summary.runningFeedStart { return Format.compactDuration(now.timeIntervalSince(start)) }
        guard let date = events.summary.lastFeedAt else { return "A fresh start" }
        return Format.ago(date, now: now)
    }

    private var feedDetail: String {
        let summary = events.summary
        guard let date = summary.runningFeedStart ?? summary.lastFeedAt else {
            return "Log a first feed below. We’ll remember the time and side."
        }
        let sides = summary.isFeeding ? summary.runningSides : summary.feedSides
        let label: String? = switch sides.count {
        case 1: sides[0] == .bottle ? "Bottle" : "\(sides[0].label) breast"
        default: FeedSide.label(for: sides)
        }
        return [label, Format.time(date)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The day so far, counted from the hour the parent chose in More (or over
/// the last 24 hours), with an hour-by-hour strip beneath: one row per
/// button, one square per hour.
private struct TodayTotalsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    let now: Date

    var body: some View {
        let totals = WindowTotals.make(events: events.events, window: settings.totalsWindow, now: now)
        let title = settings.totalsWindow.title()
        VStack(spacing: AppTheme.tightSpacing) {
            VStack(spacing: AppTheme.hairSpacing) {
                SectionLabel(text: title)
                Text(totals.line)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(totals.line)")
            .accessibilityIdentifier("todayTotals")
            HourStrip(totals: totals)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: totals)
    }
}

/// A contribution-graph for one day: four rows (the four buttons), 24 hourly
/// squares. Darker is more; sleep fills by how much of the hour was asleep.
/// Hours still to come stay faint.
private struct HourStrip: View {
    let totals: WindowTotals

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.cellGap) {
            ForEach(WindowTotals.kinds, id: \.self) { kind in
                HStack(spacing: AppTheme.cellGap) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: AppTheme.cellHeight - 1, weight: .bold))
                        .foregroundStyle(AppTheme.color(for: kind))
                        .frame(width: AppTheme.stripIconWidth, height: AppTheme.cellHeight)
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
        WindowTotals.kinds.compactMap { kind -> String? in
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
                .foregroundStyle(AppTheme.accent)
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
