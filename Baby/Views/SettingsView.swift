import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        Form {
            Group {
                toolsSection
                babySection
                babiesSection
                sharingSection
                appearanceSection
                diaperWordsSection
                plusSection
                aboutSection
            }
            .themedRow()
        }
        .foregroundStyle(AppTheme.ink)
        .scrollContentBackground(.hidden)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
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
        .onAppear { loadChild() }
        .onChange(of: events.child?.objectID) { _, _ in loadChild() }
        .onChange(of: name) { _, _ in saveChild() }
        .onChange(of: hasBirthDate) { _, _ in saveChild() }
        .onChange(of: birthDate) { _, _ in saveChild() }
    }

    private var toolsSection: some View {
        Section("When you need them") {
            NavigationLink { FirstWeeksView() } label: {
                Label("First Weeks", systemImage: "checklist")
            }
            NavigationLink { SummaryView() } label: {
                Label("Pediatrician summary", systemImage: "doc.text")
            }
            Button { showStainHelper = true } label: {
                Label("Stain helper", systemImage: "tshirt")
            }
        }
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
            Button("Add a baby") { addBaby() }
            .foregroundStyle(AppTheme.accent)
        } header: {
            Text("Babies")
        } footer: {
            Text("Each baby keeps its own log, its own first-weeks tally and its own summary.")
        }
    }

    private func addBaby() {
        guard events.createChild(name: nil, birthDate: nil) else {
            showSaveError = true
            return
        }
        name = ""
        hasBirthDate = false
        birthDate = .now
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
                Label("Join someone else's log", systemImage: "camera.viewfinder")
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("settings.partner.join")
        } header: {
            Text("Log together")
        } footer: {
            Text("Parents, grandparents and nannies each log from their own iPhone into the same baby's log, privately through iCloud.")
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
        Section("Diaper buttons") {
            Picker("Diaper buttons", selection: $settings.diaperWords) {
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
            Button("Restore purchases") { Task { await store.restore() } }
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
            Link("Rate Baby Tracker", destination: AppStoreReviewLinks.writeReviewURL)
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

/// The review funnel: enjoying it? Then rate; otherwise tell us. Only after
/// several days of real logging, never in screenshot mode.
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @StateObject private var reviews = ReviewPromptService.shared
    @State private var step: Step = .enjoyment

    enum Step {
        case enjoyment
        case rate
        case feedback
    }

    var body: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            Image(systemName: step == .feedback ? "envelope.fill" : "heart.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
            VStack(spacing: AppTheme.tightSpacing) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(PrimaryButtonStyle())
                Button(secondaryTitle) {
                    switch step {
                    case .enjoyment: step = .feedback
                    case .rate, .feedback:
                        reviews.markDeferred()
                        dismiss()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .frame(minHeight: 44)
            }
        }
        .padding(AppTheme.margin)
        .presentationDetents([.height(360)])
        .background(AppTheme.paper)
    }

    private var title: String {
        switch step {
        case .enjoyment: "Is Baby Tracker helping?"
        case .rate: "Glad to hear it"
        case .feedback: "Tell us what's missing"
        }
    }

    private var detail: String {
        switch step {
        case .enjoyment: "You've been logging for a few days now. How is it going?"
        case .rate: "A rating on the App Store helps other parents find it."
        case .feedback: "Send a note instead. Every message is read, and it shapes what gets built next."
        }
    }

    private var primaryTitle: String {
        switch step {
        case .enjoyment: "Yes, it helps"
        case .rate: "Rate on the App Store"
        case .feedback: "Send feedback"
        }
    }

    private var secondaryTitle: String {
        switch step {
        case .enjoyment: "Not really"
        case .rate, .feedback: "Not now"
        }
    }

    private func primaryAction() {
        switch step {
        case .enjoyment:
            step = .rate
        case .rate:
            reviews.markRated()
            requestReview()
            dismiss()
        case .feedback:
            reviews.markDeferred()
            openURL(BabyLinks.support)
            dismiss()
        }
    }
}
