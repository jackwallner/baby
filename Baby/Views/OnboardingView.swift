import RevenueCat
import SwiftUI

/// First run: what the app does, who the baby is, and one Baby+ step that can
/// purchase in place. Every step routes through one `page(...)` builder so the
/// primary button sits in a pixel-identical frame the whole way through, with
/// a fixed legal slot reserved under it on every step.
struct BabyOnboardingView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var events: EventStore

    var startAtBabyStep = false

    @State private var step = Self.initialStep
    @State private var name = ""
    @State private var isBorn = true
    @State private var birthDate = Date.now
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showPaywallFallback = false

    private static let totalSteps = 3

    private static var initialStep: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OnboardingStep"),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]) else { return 0 }
        return min(max(value, 0), totalSteps - 1)
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .tint(AppTheme.accent)
                    .padding(.horizontal, AppTheme.margin)
                    .padding(.top, AppTheme.spacing)
                Group {
                    switch step {
                    case 0: welcomePage
                    case 1: babyPage
                    default: plusPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if startAtBabyStep { step = 1 }
        }
        // Prefetch so the Baby+ step has a real localized price the moment it
        // appears and never renders a placeholder one (Apple 3.1.2).
        .task {
            if store.packages.isEmpty { store.start(forceRefresh: false) }
        }
        .fullScreenCover(isPresented: $showPaywallFallback, onDismiss: finish) {
            BabyPaywallView(paywallImpressionID: "baby_onboarding_fallback")
                .environmentObject(store)
        }
    }

    // MARK: - Shared page chrome

    private func page<Above: View, Content: View>(
        icon: String,
        title: String,
        @ViewBuilder body: () -> Content,
        @ViewBuilder aboveButton: () -> Above = { EmptyView() },
        primaryLabel: String,
        busy: Bool = false,
        showLegalFooter: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    Image(systemName: icon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    body()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.tightSpacing)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: AppTheme.spacing) {
                aboveButton()

                Button(action: action) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryLabel)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("onboarding.primary")

                // Reserved on every step, so the button-to-bottom distance is
                // identical whether or not a purchase is on screen.
                legalFooter
                    .opacity(showLegalFooter ? 1 : 0)
                    .allowsHitTesting(showLegalFooter)
                    .accessibilityHidden(!showLegalFooter)
            }
        }
        .padding(AppTheme.margin)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(AppTheme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalFooter: some View {
        HStack(spacing: AppTheme.tightSpacing) {
            Link("Terms of Use", destination: BabyLinks.standardEULA)
            Text("·").foregroundStyle(AppTheme.ink2)
            Link("Privacy Policy", destination: BabyLinks.privacyPolicy)
            Text("·").foregroundStyle(AppTheme.ink2)
            Button("Restore") { Task { await store.restore() } }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.ink2)
        .frame(minHeight: AppTheme.looseSpacing)
    }

    private func softExit(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink2)
            .frame(minHeight: 44)
            .disabled(isPurchasing)
    }

    // MARK: - Steps

    private var welcomePage: some View {
        page(
            icon: "hand.tap.fill",
            title: "One tap. Then sleep.",
            body: {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    detail("Four buttons that never move: Feed, Wet, Dirty, Sleep. One tap logs now. Long-press to fix the time.")
                    bullet("clock.fill", "\"Fed 2h 14m ago, Left\" on the Now screen, the lock screen and your wrist")
                    bullet("checklist", "The first-weeks tally sheet, with typical ranges by day of life")
                    bullet("person.2.fill", "Share with your partner through iCloud. No accounts, no ads.")
                    Text(Guidance.disclaimer)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            primaryLabel: "Get started",
            action: { advance(to: 1) }
        )
    }

    private var babyPage: some View {
        page(
            icon: "figure.child",
            title: "Who are we tracking?",
            body: {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    detail("The birth date sets the day of life, which is what the typical diaper ranges are counted against. Both can be changed later.")
                    TextField("Name (optional)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("onboarding.name")
                    Toggle("Already born", isOn: $isBorn)
                        .tint(AppTheme.accent)
                    if isBorn {
                        DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    } else {
                        detail("No problem. Add the birth date in Settings when the day comes; logging works either way.")
                    }
                }
            },
            primaryLabel: "Continue",
            action: {
                saveBaby()
                advance(to: 2)
            }
        )
    }

    private var plusPage: some View {
        page(
            icon: "doc.text.fill",
            title: "Walk into the pediatrician with a clean summary",
            body: {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    detail("Logging, the first-weeks tally, widgets, the Watch app and partner sharing are free forever. Baby+ is the reporting on top.")
                    ForEach(Self.pitchFeatures) { feature in
                        bullet(feature.symbolName, feature.pitchLine)
                    }
                }
            },
            aboveButton: { plusAboveButton },
            primaryLabel: purchaseLabel,
            busy: isPurchasing,
            showLegalFooter: true,
            action: startPurchase
        )
        .onAppear {
            store.trackPaywallImpression(id: "baby_onboarding_plus", oncePerSession: true)
        }
    }

    private static let pitchFeatures: [PlusFeature] = [.pediatricianSummary, .trends, .export]

    @ViewBuilder
    private var plusAboveButton: some View {
        VStack(spacing: AppTheme.spacing) {
            softExit("Get Started") { finish() }
                .accessibilityIdentifier("onboarding.softExit")

            if let package = onboardingPackage {
                Text(ConversionCopy.billedAmount(priceLabel: package.babyPriceLabel))
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(ConversionCopy.disclosure(
                    trialLabel: package.babyIntroOfferLabel,
                    priceLabel: package.babyPriceLabel,
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                ))
                .font(.caption2)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let purchaseError {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.notice)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var onboardingPackage: Package? {
        store.yearlyPackage ?? store.packages.first
    }

    private var purchaseLabel: String {
        guard let package = onboardingPackage else { return "See Baby+ plans" }
        return ConversionCopy.ctaLabel(
            trialLabel: package.babyIntroOfferLabel,
            priceLabel: package.babyPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    // MARK: - Actions

    private func advance(to next: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func saveBaby() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date: Date? = isBorn ? birthDate : nil
        if let child = events.child {
            events.update(child: child, name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        } else {
            events.createChild(name: trimmed.isEmpty ? nil : trimmed, birthDate: date)
        }
    }

    private func startPurchase() {
        guard let package = onboardingPackage else {
            showPaywallFallback = true
            return
        }
        purchaseError = nil
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            switch await store.purchase(package) {
            case .purchased, .pending:
                Haptics.purchased()
                finish()
            case .cancelled:
                purchaseError = nil
            case .none:
                purchaseError = store.errorMessage ?? "Couldn't reach the App Store. Please try again."
            }
        }
    }

    private func finish() {
        if events.child == nil { saveBaby() }
        settings.hasCompletedSetup = true
    }
}
