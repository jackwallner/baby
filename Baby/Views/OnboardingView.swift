import SwiftUI

/// One optional setup screen, then straight into logging.
struct BabyOnboardingView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var events: EventStore
    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var showSaveError = false
    @FocusState private var isEditingName: Bool

    var body: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    welcomeHeader
                    partnerExplainer
                    babyDetails
                    Text("Both are optional. You can change them anytime in More.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                    Text(Guidance.disclaimer)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                        .accessibilityIdentifier("onboarding.disclaimer")
                }
                .frame(maxWidth: AppTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: AppTheme.tightSpacing) {
                Button("Start tracking") { finish() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.primary")
                Link("Privacy Policy", destination: BabyLinks.privacyPolicy)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .frame(minHeight: 44)
            }
        }
        .padding(AppTheme.margin)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        .alert("Couldn't save setup", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your details are still here. Please try again.")
        }
    }

    private var welcomeHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppTheme.looseSpacing) {
                carePreview
                welcomeCopy
            }
            VStack(alignment: .leading, spacing: AppTheme.spacing) {
                carePreview
                welcomeCopy
            }
        }
    }

    private var carePreview: some View {
        HStack(spacing: AppTheme.tightSpacing) {
            CareGraphic(kind: .feed, side: .left)
            CareGraphic(kind: .wet)
            CareGraphic(kind: .sleep)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feed, diaper, and sleep tracking")
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text("Hello, little one.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Feeds, diapers and sleep. A little less to remember.")
                .font(.body)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var partnerExplainer: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SharedLogGraphic()
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                Text("Keep one shared log")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("You can both add feeds, diapers and sleep to this same log.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Invite your partner anytime in More", systemImage: "person.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(elevated: true)
        .accessibilityIdentifier("onboarding.partner")
    }

    private var babyDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            TextField("Baby's name (optional)", text: $name)
                .font(.body)
                .textInputAutocapitalization(.words)
                .focused($isEditingName)
                .submitLabel(.done)
                .onSubmit { isEditingName = false }
                .frame(minHeight: 44)
                .accessibilityIdentifier("onboarding.name")
            Divider()
            Toggle("Add birth date", isOn: $hasBirthDate)
            if hasBirthDate {
                DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
            }
        }
        .card()
    }

    private func finish() {
        isEditingName = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = hasBirthDate ? birthDate : nil
        let saved: Bool
        if let child = events.child {
            saved = events.update(child: child, name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        } else {
            saved = events.createChild(name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        }
        guard saved else {
            showSaveError = true
            return
        }
        settings.hasCompletedSetup = true
    }
}
