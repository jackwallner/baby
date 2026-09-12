import SwiftUI

/// One optional setup screen, then straight into logging.
struct BabyOnboardingView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var events: EventStore
    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @FocusState private var isEditingName: Bool

    var body: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    Image(systemName: "figure.child")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.welcomeIconSize, height: AppTheme.welcomeIconSize)
                        .background(AppTheme.accent.opacity(0.10), in: AppTheme.cardShape)
                        .accessibilityHidden(true)
                    Text("Hello, little one.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Feeds, diapers and sleep. A little less to remember.")
                        .font(.body)
                        .foregroundStyle(AppTheme.ink2)
                    babyDetails
                    Text("Both are optional. You can change them anytime in More.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                    Text(Guidance.disclaimer)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                }
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
        if let child = events.child {
            events.update(child: child, name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        } else {
            events.createChild(name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        }
        settings.hasCompletedSetup = true
    }
}
