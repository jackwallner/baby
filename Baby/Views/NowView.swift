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

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= AppTheme.wideLayout && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: AppTheme.looseSpacing) {
                            VStack(spacing: AppTheme.looseSpacing) {
                                NowStatusCard(now: now)
                                TodayTotalsView()
                            }
                            LoggingControls(height: AppTheme.maxLogButtonHeight, editor: $editor)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                            NowStatusCard(now: now)
                            LoggingControls(height: min(AppTheme.maxLogButtonHeight, max(AppTheme.logButtonHeight, (geometry.size.height - AppTheme.homeSummaryAllowance) / 3)), editor: $editor)
                            Spacer(minLength: 0)
                            TodayTotalsView()
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
            if !Calendar.current.isDate(now, inSameDayAs: date) { events.reload() }
            now = date
        }
        .onChange(of: events.events.count) { _, _ in
            now = .now
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from a long nap: the elapsed time must be right on first sight.
            if phase == .active { now = .now }
        }
    }

    private var title: String {
        guard let child = events.child else { return "Now" }
        return child.displayName
    }

}

private struct LoggingControls: View {
    let height: CGFloat
    @Binding var editor: EditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            LogButtons(minimumHeight: height) { kind, side in
                editor = EditorRequest(kind: kind, side: side)
            }
            Text("Tap to log now. Hold to add details.")
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct NowStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @State private var showSaveError = false
    let now: Date

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
                Button("Finish feed") { showSaveError = !events.stopRunning(.feed) }
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
        let side = summary.runningFeedSide ?? summary.lastFeedSide
        let label = side.map { $0 == .bottle ? "Bottle" : "\($0.label) breast" }
        return [label, Format.time(date)].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct TodayTotalsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var events: EventStore

    var body: some View {
        VStack(spacing: AppTheme.hairSpacing) {
            SectionLabel(text: "Today")
            Text(events.summary.todayLine)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: \(events.summary.todayLine)")
        .accessibilityIdentifier("todayTotals")
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.summary.todayLine)
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var kind: EventKind
    var side: FeedSide?
    var existing: LogEvent?
}
