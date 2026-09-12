import SwiftUI

/// The home screen: the answer to "when did she last eat, and which side",
/// the four buttons, today's tally against the typical range, and (until it is
/// done) the partner invite. Nothing here is more than one tap deep.
struct NowView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var settings: BabySettings
    @StateObject private var reviews = ReviewPromptService.shared
    @State private var editor: EditorRequest?
    @State private var showSettings = false
    @State private var showSharing = false
    @State private var stainStain: StainGuide.Stain?
    @State private var now = Date.now

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                nowCard
                LogButtons { kind, side in editor = EditorRequest(kind: kind, side: side) }
                todayCard
                stainRow
                if sharing.share == nil, !settings.hasDismissedShareCard {
                    shareCard
                }
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.vertical, AppTheme.spacing)
        }
        .background(AppTheme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .overlay(alignment: .bottom) {
            if let logged = events.lastLogged {
                UndoToast(logged: logged, undo: { events.undoLast() }, stainHelp: { stainStain = .blowout })
                    .padding(.horizontal, AppTheme.margin)
                    .padding(.bottom, AppTheme.tightSpacing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: events.lastLogged)
        .sheet(item: $editor) { request in
            EventEditorView(request: request)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(item: $stainStain) { stain in
            StainHelperView(initialStain: stain)
        }
        .sheet(isPresented: $showSharing) {
            if let child = events.child {
                SharingSheet(child: child)
            }
        }
        .sheet(isPresented: $reviews.isPresented) {
            ReviewPromptSheet()
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: events.events.count) { _, _ in
            reviews.recordLoggingDay()
            now = .now
        }
    }

    private var title: String {
        guard let child = events.child else { return "Now" }
        if let day = child.dayOfLife(on: now) { return "\(child.displayName) · Day \(day)" }
        return child.displayName
    }

    // MARK: - Cards

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            line(events.summary.feedLine(now: now), kind: .feed, prominent: true)
            line(events.summary.diaperLine(now: now), kind: events.summary.lastDiaperKind ?? .wet)
            if let sleep = events.summary.sleepLine(now: now) {
                HStack(spacing: AppTheme.spacing) {
                    line(sleep, kind: .sleep)
                    Spacer(minLength: 0)
                    Button("Wake") { events.toggleSleep() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            if events.summary.isFeeding {
                Button("Stop feed") { events.stopRunning(.feed) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .card()
        .accessibilityIdentifier("nowCard")
    }

    private func line(_ text: String, kind: EventKind, prominent: Bool = false) -> some View {
        HStack(spacing: AppTheme.spacing) {
            KindDot(kind: kind)
            Text(text)
                .font(prominent ? .title3.weight(.semibold) : .body)
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private var todayCard: some View {
        NavigationLink {
            FirstWeeksView()
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                HStack {
                    SectionLabel(text: todayLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink3)
                }
                HStack(spacing: AppTheme.looseSpacing) {
                    stat(events.summary.todayWet, "wet", kind: .wet)
                    stat(events.summary.todayDirty, "dirty", kind: .dirty)
                    stat(events.summary.todayFeeds, "feeds", kind: .feed)
                    Spacer(minLength: 0)
                }
                if let day = events.summary.dayOfLife {
                    let range = Guidance.range(forDayOfLife: day)
                    Text("Typical by day \(min(day, 6)): \(range.summary)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Add a birth date in Settings to see typical ranges by day of life.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
        .pressableCard()
        .accessibilityIdentifier("todayCard")
    }

    private var todayLabel: String {
        if let day = events.summary.dayOfLife { return "Today · Day \(day)" }
        return "Today"
    }

    private func stat(_ value: Int, _ label: String, kind: EventKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.hairSpacing) {
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppTheme.color(for: kind))
        }
    }

    /// The stain helper lives here and in the undo toast, never in the four
    /// buttons.
    private var stainRow: some View {
        Button {
            stainStain = .blowout
        } label: {
            HStack(spacing: AppTheme.tightSpacing) {
                Image(systemName: "tshirt.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                Text("Blowout on your clothes? Stain helper")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.ink3)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .pressableCard()
        .accessibilityIdentifier("stainRow")
    }

    private var shareCard: some View {
        Button {
            showSharing = true
        } label: {
            HStack(spacing: AppTheme.spacing) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    Text("Share with your partner")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Both of you log and see the same list, through iCloud. No accounts.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink3)
            }
            .card()
        }
        .pressableCard()
        .accessibilityIdentifier("shareCard")
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var kind: EventKind
    var side: FeedSide?
    var existing: LogEvent?
}
