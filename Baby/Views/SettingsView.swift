import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var sharing: SharingService
    @State private var showPaywall = false
    @State private var showSharing = false
    @State private var showJoin = false
    @State private var showStainHelper = false
    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var showSaveError = false
    @State private var showAddBaby = false
    @State private var newBabyName = ""
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Group {
                babySection
                buttonsSection
                if settings.tracked.tracksDiapers { diaperWordsSection }
                totalsSection
                RemindersSection()
                appearanceSection
                sharingSection
                babiesSection
                guidesSection
                plusSection
                aboutSection
            }
            .themedRow()
        }
        .foregroundStyle(AppTheme.ink)
        .scrollContentBackground(.hidden)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            BabyPaywallView(paywallImpressionID: "baby_settings")
        }
        .sheet(isPresented: $showSharing) {
            if let child = events.child { SharingSheet(child: child) }
        }
        .sheet(isPresented: $showJoin) { JoinSharedLogView() }
        .sheet(isPresented: $showStainHelper) { StainHelperView() }
        .alert("Couldn't save changes", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your baby's details were not changed. Please try again.")
        }
        .alert("Restore purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .alert("Add a baby", isPresented: $showAddBaby) {
            TextField("Name (optional)", text: $newBabyName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addBaby() }
        } message: {
            Text("Logging switches to the new baby. Switch back any time under Babies.")
        }
        .onAppear { loadChild() }
        .onChange(of: events.child?.objectID) { _, _ in loadChild() }
        .onChange(of: name) { _, _ in saveChild() }
        .onChange(of: hasBirthDate) { _, _ in saveChild() }
        .onChange(of: birthDate) { _, _ in saveChild() }
    }

    private var guidesSection: some View {
        Section("Guides") {
            NavigationLink { FirstWeeksView().reservesNavigationCapsule() } label: {
                Label("First Weeks", systemImage: "checklist")
            }
            Button { showStainHelper = true } label: {
                Label("Stain helper", systemImage: "tshirt")
            }
        }
    }

    /// Which buttons this family uses. The last one left cannot be turned
    /// off, so the home screen is never empty.
    private var buttonsSection: some View {
        Section {
            ForEach(TrackedKinds.buttons, id: \.self) { kind in
                Toggle(isOn: trackingBinding(kind)) {
                    HStack(spacing: AppTheme.tightSpacing) {
                        KindDot(kind: kind, size: AppTheme.legendDotSize)
                        Text(kind.label)
                    }
                }
                .disabled(settings.tracked.buttons == [kind])
                .accessibilityIdentifier("track.\(kind.rawValue)")
            }
        } header: {
            Text("Buttons")
        } footer: {
            Text("A button that is off leaves the home screen, widgets, Watch, History and reports. What was logged with it is kept, and comes back if you turn it on again.")
        }
    }

    private func trackingBinding(_ kind: EventKind) -> Binding<Bool> {
        Binding(
            get: { settings.tracked.contains(kind) },
            set: { isOn in
                var hidden = settings.tracked.hidden
                if isOn { hidden.remove(kind) } else { hidden.insert(kind) }
                settings.tracked = TrackedKinds(hidden: hidden)
            }
        )
    }

    private func loadChild() {
        name = events.child?.name ?? ""
        hasBirthDate = events.child?.birthDate != nil
        birthDate = events.child?.birthDate ?? .now
    }

    private func saveChild() {
        guard let child = events.child else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !events.update(child: child, name: trimmed.isEmpty ? nil : trimmed, birthDate: hasBirthDate ? birthDate : nil) {
            showSaveError = true
        }
    }

    private var babySection: some View {
        Section("Baby") {
            TextField("Name", text: $name)
            Toggle("Born", isOn: $hasBirthDate)
            if hasBirthDate {
                LabeledContent("Birth date") {
                    DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                        .themedDatePicker()
                }
            }
            if let day = events.child?.dayOfLife() {
                LabeledContent("Day of life", value: "\(day)")
            }
        }
    }

    /// Twins, or the next one. Free: a second baby is a fact about the
    /// family, not a reporting feature, so it never sits behind Baby+.
    private var babiesSection: some View {
        Section {
            if events.children.count > 1 {
                ForEach(events.children, id: \.objectID) { child in
                    Button {
                        events.setActive(child)
                    } label: {
                        HStack {
                            Text(child.displayName)
                                .foregroundStyle(AppTheme.ink)
                            if sharing.isSharedChild(child) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.ink2)
                            }
                            Spacer()
                            if child.objectID == events.child?.objectID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            Button("Add a baby") {
                newBabyName = ""
                showAddBaby = true
            }
            .foregroundStyle(AppTheme.accent)
        } header: {
            Text("Babies")
        } footer: {
            Text("Each baby keeps its own log, its own first-weeks tally and its own summary.")
        }
    }

    private func addBaby() {
        let trimmed = newBabyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard events.createChild(name: trimmed.isEmpty ? nil : trimmed, birthDate: nil) else {
            showSaveError = true
            return
        }
        loadChild()
    }

    private var sharingSection: some View {
        Section {
            if sharing.share != nil, !sharing.isOwner {
                LabeledContent("Started by", value: sharing.ownerName ?? "Someone else")
                Button {
                    showSharing = true
                } label: {
                    Label(sharing.inviteURL == nil ? "People and leaving" : "Invite someone or leave", systemImage: "person.2.fill")
                }
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("settings.partner.share")
            } else {
                if sharing.share != nil {
                    let names = sharing.participantNames
                    LabeledContent("Logging with", value: names.isEmpty ? "No one yet" : names.joined(separator: ", "))
                }
                Button {
                    showSharing = true
                } label: {
                    Label("Invite someone", systemImage: "qrcode")
                }
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("settings.partner.share")
            }
            Button {
                showJoin = true
            } label: {
                Label("Join a shared log", systemImage: "camera.viewfinder")
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("settings.partner.join")
        } header: {
            Text("Log together")
        } footer: {
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                Text("Parents, grandparents and nannies each log from their own iPhone into the same baby's log, privately through iCloud.")
                if !ScreenshotConfig.isEnabled {
                    SyncStatusLine(sync: events.sync, mirrors: events.persistence.cloudKitEnabled)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.label)
                        .foregroundStyle(AppTheme.ink)
                        .tag(appearance)
                        .accessibilityIdentifier("appearance.\(appearance.rawValue)")
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Appearance")
        } footer: {
            Text("Night light uses dim, warm colors that are easier on the eyes during feeds in a dark room.")
        }
    }

    private var diaperWordsSection: some View {
        Section("Diaper words") {
            Picker("Diaper words", selection: $settings.diaperWords) {
                ForEach(DiaperWords.allCases, id: \.rawValue) { words in
                    Text(words.label)
                        .foregroundStyle(AppTheme.ink)
                        .tag(words)
                        .accessibilityIdentifier("diaperWords.\(words.rawValue)")
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// When the totals under the buttons start: a day from a chosen hour
    /// (for the parent whose day starts with the 6am feed), or a rolling
    /// 24 hours.
    private var totalsSection: some View {
        Section {
            Picker("Count", selection: Binding(
                get: { settings.totalsWindow == .last24Hours },
                set: { settings.totalsWindow = $0 ? .last24Hours : .midnight }
            )) {
                Text("By day").tag(false)
                Text("Last 24 hours").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("totals.mode")
            if case .day(let hour) = settings.totalsWindow {
                Picker("Day starts at", selection: Binding(
                    get: { hour },
                    set: { settings.totalsWindow = .day(startHour: $0) }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(TotalsWindow.hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("totals.dayStart")
            }
        } header: {
            Text("Daily totals")
        } footer: {
            Text("For the totals and hour chart under the buttons. History and reports always use calendar days.")
        }
    }

    private var plusSection: some View {
        Section("Baby+") {
            LabeledContent("Status", value: store.isPro ? "Active" : "Free")
            if store.isPro {
                Link("Manage subscription", destination: BabyLinks.manageSubscriptions)
                .foregroundStyle(AppTheme.accent)
            } else {
                Button("See Baby+") { showPaywall = true }
                .foregroundStyle(AppTheme.accent)
            }
            Button("Restore purchases") {
                Task {
                    await store.restore()
                    restoreMessage = store.isPro ? "Baby+ is active on this Apple ID." : (store.errorMessage ?? "No active Baby+ purchase was found for this Apple ID.")
                }
            }
            .foregroundStyle(AppTheme.accent)
            #if DEBUG
            Toggle("Local Pro override (debug)", isOn: Binding(
                get: { store.isPro },
                set: { store.setLocalOverride(isPro: $0) }
            ))
            #endif
        }
    }

    private var aboutSection: some View {
        Section("About") {
            // Separate rating and feedback rows, with no question in front of
            // either (App Review 5.6.1).
            Link("Rate Baby Tracker", destination: AppStoreReviewLinks.writeReviewURL)
                .foregroundStyle(AppTheme.accent)
            Link("Send Feedback", destination: BabyLinks.feedback)
                .foregroundStyle(AppTheme.accent)
            Link("Support", destination: BabyLinks.support)
                .foregroundStyle(AppTheme.accent)
            Link("Privacy policy", destination: BabyLinks.privacyPolicy)
                .foregroundStyle(AppTheme.accent)
            Link("Terms of use", destination: BabyLinks.standardEULA)
                .foregroundStyle(AppTheme.accent)
            LabeledContent("Version", value: Bundle.main.appVersionLabel)
            Text(Guidance.disclaimer)
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
        }
    }
}

/// When this phone last synced with iCloud, or what is stopping it. Watches
/// the sync state itself, so only this line redraws as CloudKit works.
private struct SyncStatusLine: View {
    @ObservedObject var sync: CloudSyncState
    let mirrors: Bool

    var body: some View {
        if let problem = sync.problem {
            Text(problem.message)
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("settings.sync.problem")
        } else if mirrors, let synced = sync.lastSynced {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Synced with iCloud \(SettingsView.syncedPhrase(synced, now: context.date)).")
            }
            .accessibilityIdentifier("settings.sync.last")
        }
    }
}

extension SettingsView {
    /// "just now" for the last minute, where "in 0 seconds" or "5 seconds ago"
    /// would read as noise.
    static func syncedPhrase(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
