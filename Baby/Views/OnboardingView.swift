import SwiftUI

/// One setup screen with two ways in: start a new log (optional name and
/// birth date), or join a log someone else started. Then straight into logging.
struct BabyOnboardingView: View {
    enum Path: String {
        case start
        case join
    }

    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var events: EventStore
    /// Owned by the root, which swaps this screen out while an invitation is
    /// accepted: a failed join comes back to the Join path with its message.
    @ObservedObject var joinModel: JoinLogModel
    @State private var path: Path

    init(joinModel: JoinLogModel) {
        self.joinModel = joinModel
        let failed = if case .failed = joinModel.phase { true } else { false }
        _path = State(initialValue: failed ? .join : .start)
    }
    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var feeding: FeedingStyle?
    @State private var showSaveError = false
    @FocusState private var isEditingName: Bool

    var body: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    welcomeHeader
                    pathChoice
                    if path == .start {
                        babyDetails
                        Text("All optional. Invite your partner or anyone else helping from Settings once you're in.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        JoinLogForm(model: joinModel)
                    }
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
                if path == .start {
                    Button("Start tracking") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboarding.primary")
                } else {
                    JoinButton(model: joinModel)
                }
                Link("Privacy Policy", destination: BabyLinks.privacyPolicy)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .frame(minHeight: 44)
            }
        }
        .padding(AppTheme.margin)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        // Back from waiting on a baby that never came: a fresh start.
        .onAppear { if joinModel.phase == .joined { joinModel.reset() } }
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

    private var pathChoice: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            pathOption(.start, title: "Start a new log", detail: "You're the first to log for this baby.", symbol: "plus")
            pathOption(.join, title: "Join a shared log", detail: "Your partner or someone else already started. Scan their code.", symbol: "person.2.fill")
        }
        .accessibilityElement(children: .contain)
    }

    private func pathOption(_ option: Path, title: String, detail: String, symbol: String) -> some View {
        let isSelected = path == option
        return Button {
            Haptics.selected()
            path = option
        } label: {
            HStack(alignment: .center, spacing: AppTheme.spacing) {
                Image(systemName: symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.buttonInk : AppTheme.accent)
                    .frame(width: AppTheme.iconSize, height: AppTheme.iconSize)
                    .background(isSelected ? AppTheme.actionFill : AppTheme.cardElevated, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.ink3)
                    .accessibilityHidden(true)
            }
            .padding(AppTheme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: AppTheme.cardShape)
            .overlay(AppTheme.cardShape.strokeBorder(isSelected ? AppTheme.accent : AppTheme.edge, lineWidth: isSelected ? AppTheme.outlineWidth : AppTheme.hairlineWidth))
            .contentShape(AppTheme.cardShape)
        }
        .pressableCard()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.path.\(option.rawValue)")
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
            if feeding != .expecting {
                Divider()
                Toggle("Add birth date", isOn: $hasBirthDate)
                if hasBirthDate {
                    LabeledContent("Birth date") {
                        DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                            .themedDatePicker()
                    }
                }
            }
            Divider()
            feedingChoice
        }
        .card()
    }

    /// One optional question. It sets the reminder gap offered after the
    /// first feed, and nothing else.
    private var feedingChoice: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text("How is the baby fed?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach([[FeedingStyle.breast, .bottle, .both], [.pumped, .expecting]], id: \.self) { row in
                HStack(spacing: AppTheme.tightSpacing) {
                    ForEach(row) { style in
                        feedingChip(style)
                    }
                }
            }
        }
    }

    private func feedingChip(_ style: FeedingStyle) -> some View {
        let isOn = feeding == style
        return Button {
            Haptics.selected()
            feeding = isOn ? nil : style
            if feeding == .expecting { hasBirthDate = false }
        } label: {
            Text(style.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? AppTheme.feed : AppTheme.card, in: AppTheme.buttonShape)
                .overlay(AppTheme.buttonShape.strokeBorder(isOn ? AppTheme.feed : AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
                .contentShape(AppTheme.buttonShape)
        }
        .pressableCard()
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("onboarding.feeding.\(style.rawValue)")
    }

    private func finish() {
        isEditingName = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = hasBirthDate ? birthDate : nil
        guard events.finishSetup(name: trimmed.isEmpty ? nil : trimmed, birthDate: date) else {
            showSaveError = true
            return
        }
        Reminders.feedingStyle = feeding
        StoreService.shared.recordSetupStage(expecting: feeding == .expecting)
        settings.hasCompletedSetup = true
    }
}
