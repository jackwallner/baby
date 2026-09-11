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
    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now

    var body: some View {
        Form {
            babySection
            sharingSection
            plusSection
            aboutSection
        }
        .navigationTitle("Settings")
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
        .onAppear {
            name = events.child?.name ?? ""
            hasBirthDate = events.child?.birthDate != nil
            birthDate = events.child?.birthDate ?? .now
        }
        .onChange(of: name) { _, _ in saveChild() }
        .onChange(of: hasBirthDate) { _, _ in saveChild() }
        .onChange(of: birthDate) { _, _ in saveChild() }
    }

    private func saveChild() {
        guard let child = events.child else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        events.update(child: child, name: trimmed.isEmpty ? nil : trimmed, birthDate: hasBirthDate ? birthDate : nil)
    }

    private var babySection: some View {
        Section("Baby") {
            TextField("Name", text: $name)
            Toggle("Born", isOn: $hasBirthDate)
            if hasBirthDate {
                DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
            }
            if let day = events.child?.dayOfLife() {
                LabeledContent("Day of life", value: "\(day)")
            }
        }
    }

    private var sharingSection: some View {
        Section {
            if let share = sharing.share {
                let names = sharing.participantNames
                LabeledContent("Shared with", value: names.isEmpty ? "Invite pending" : names.joined(separator: ", "))
                Button(sharing.isOwner ? "Manage sharing" : "Leave") { showSharing = true }
                let _ = share
            } else {
                Button("Share with your partner") { showSharing = true }
            }
        } header: {
            Text("Partner")
        } footer: {
            Text("Sharing goes through iCloud, from your Apple ID to theirs. Both of you log to the same list. There are no accounts and nothing is stored on our servers.")
        }
    }

    private var plusSection: some View {
        Section("Baby+") {
            LabeledContent("Status", value: store.isPro ? "Active" : "Free")
            if store.isPro {
                Link("Manage subscription", destination: BabyLinks.manageSubscriptions)
            } else {
                Button("See Baby+") { showPaywall = true }
            }
            Button("Restore purchases") { Task { await store.restore() } }
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
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            Link("Rate Baby Tracker", destination: AppStoreReviewLinks.writeReviewURL)
            Link("Support", destination: BabyLinks.support)
            Link("Privacy policy", destination: BabyLinks.privacyPolicy)
            Link("Terms of use", destination: BabyLinks.standardEULA)
            LabeledContent("Version", value: Bundle.main.appVersionLabel)
            Text(Guidance.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
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
