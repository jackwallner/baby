import RevenueCat
import SwiftUI

/// First-run setup.
///
/// Every step routes through one `page(...)` builder so the primary button
/// lands in a pixel-identical frame the whole way through. Anything that varies
/// per step (a soft exit, a price disclosure, an error) is passed as
/// `aboveButton` and absorbed by the scrolling region above it, and a
/// fixed-height legal slot is reserved under the button on every step, real
/// links only where a purchase is on screen. The thumb never has to move.
///
/// The flow also does two jobs the old three-page version did not: it asks for
/// the optional body-data permission while the reason for it is on screen, and
/// it pitches Caffeine+ once, in context, instead of leaving the first mention
/// of it to a lock icon in the tab bar.
struct CaffeineOnboardingView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @EnvironmentObject private var store: StoreService

    @State private var step = Self.initialStep
    @State private var bedtime = Calendar.current.date(
        bySettingHour: 22,
        minute: 30,
        second: 0,
        of: .now
    ) ?? .now
    @State private var isWorking = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showPaywallFallback = false

    private static let totalSteps = 5

    /// Lets a headless run land directly on a step, which is the only way to
    /// check that the primary button occupies the same frame on all five.
    private static var initialStep: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OnboardingStep"),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]) else {
            return 0
        }
        return min(max(value, 0), totalSteps - 1)
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .tint(Theme.cyan)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Group {
                    switch step {
                    case 0: welcomePage
                    case 1: bedtimePage
                    case 2: healthPage
                    case 3: bodyPage
                    default: plusPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Prefetch the offering while the user is still on step 0, so the
        // Caffeine+ step has a real localized price the moment it appears and
        // never renders a placeholder one (Apple 3.1.2).
        .task {
            if store.packages.isEmpty { store.start(forceRefresh: false) }
        }
        .fullScreenCover(isPresented: $showPaywallFallback, onDismiss: finish) {
            CaffeinePaywallView(paywallImpressionID: "caffeine_onboarding_fallback")
                .environmentObject(store)
                .environmentObject(settings)
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
        VStack(alignment: .leading, spacing: 20) {
            // Scrolls rather than truncates. A plain VStack hands its flexible
            // Text children whatever height is left, which on a short container
            // clips every paragraph mid-word.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: icon)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Theme.forecastGradient)
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    body()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                aboveButton()

                Button(action: action) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryLabel)
                    }
                }
                .buttonStyle(ForecastButtonStyle())
                .disabled(busy)

                // Reserved on every step, so the button-to-bottom distance is
                // identical whether or not a purchase is on screen.
                legalFooter
                    .opacity(showLegalFooter ? 1 : 0)
                    .allowsHitTesting(showLegalFooter)
                    .accessibilityHidden(!showLegalFooter)
            }
        }
        .padding(24)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalFooter: some View {
        HStack(spacing: 10) {
            Link("Terms of Use", destination: CaffeineLinks.standardEULA)
            Text("·").foregroundStyle(Theme.textSecondary)
            Link("Privacy Policy", destination: CaffeineLinks.privacyPolicy)
            Text("·").foregroundStyle(Theme.textSecondary)
            Button("Restore") { Task { await store.restore() } }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
    }

    private func softExit(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .disabled(isWorking || isPurchasing)
    }

    // MARK: - Steps

    private var welcomePage: some View {
        page(
            icon: "waveform.path.ecg",
            title: "See what may still be active",
            body: {
                VStack(alignment: .leading, spacing: 16) {
                    detail("Log a drink in one tap. Caffeine estimates what may remain now and at bedtime with a half-life model.")
                    bullet("cup.and.saucer.fill", "One tap to log, one tap to undo")
                    bullet("moon.stars.fill", "Preview a drink before you log it and watch the bedtime number move")
                    bullet("heart.text.square.fill", "Stays in Apple Health, so the log works alongside your other apps")
                    Text("Estimates are informational and vary by person. Caffeine does not diagnose, treat, or prescribe.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            primaryLabel: "Get started",
            action: { advance(to: 1) }
        )
    }

    private var bedtimePage: some View {
        page(
            icon: "bed.double.fill",
            title: "When do you usually go to bed?",
            body: {
                VStack(alignment: .leading, spacing: 16) {
                    detail("Every forecast in the app is quoted at this time. You can change it later in Settings.")
                    DatePicker("Usual bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                }
            },
            primaryLabel: "Continue",
            action: {
                saveBedtime()
                advance(to: 2)
            }
        )
    }

    private var healthPage: some View {
        page(
            icon: "heart.text.square.fill",
            title: "Keep one caffeine timeline",
            body: {
                VStack(alignment: .leading, spacing: 16) {
                    detail("Next, iOS will ask whether Caffeine can read and write dietary caffeine in Apple Health. That keeps one record across your apps and devices instead of a second private list here.")
                    bullet("arrow.triangle.2.circlepath", "Anything another app already recorded shows up in your estimate right away")
                    bullet("slider.horizontal.3", "You choose which of those sources count, in Settings")
                    bullet("lock.fill", "Sleep and heart data stay off until the next step")
                }
            },
            aboveButton: { softExit("Not now") { advance(to: 3) } },
            primaryLabel: "Connect Apple Health",
            busy: isWorking,
            action: { Task { await connectHealth() } }
        )
    }

    private var bodyPage: some View {
        page(
            icon: "bed.double.circle.fill",
            title: "Find the number your own nights react to",
            body: {
                VStack(alignment: .leading, spacing: 16) {
                    detail("With sleep and heart data, Caffeine can stop quoting an average and start reporting your own record: the bedtime estimate above which your sleep actually ran shorter.")
                    bullet("moon.stars.fill", "Your personal cutoff, worked out from your own nights")
                    bullet("waveform.path.ecg", "Higher-caffeine days next to lower ones across \(BodyMetric.allCases.count) measurements")
                    bullet("heart.fill", "What your heart rate did in the 90 minutes after each dose")
                    detail("This is a separate Apple Health permission, it is read-only, and nothing leaves your device. Declining it changes nothing about logging or the bedtime forecast.")
                }
            },
            aboveButton: { softExit("Skip for now") { advance(to: 4) } },
            primaryLabel: "Turn on body insights",
            busy: isWorking,
            action: { Task { await connectBodyInsights() } }
        )
    }

    private var plusPage: some View {
        page(
            icon: "sparkles",
            title: "Get the answers, not just the averages",
            body: {
                VStack(alignment: .leading, spacing: 14) {
                    detail("Logging, both estimates, the drink preview, widgets, and a week of history are free forever. Caffeine+ is the part that reads your own body back to you.")
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
            store.trackPaywallImpression(id: "caffeine_onboarding_plus", oncePerSession: true)
        }
    }

    private static let pitchFeatures: [PlusFeature] = [
        .bodyComparisons, .tunedHalfLife, .fullHistory,
    ]

    @ViewBuilder
    private var plusAboveButton: some View {
        VStack(spacing: 12) {
            softExit("Continue with the free app") { finish() }

            if let package = onboardingPackage {
                // Apple 3.1.2(c): the billed amount is the largest pricing
                // element on the step, above a neutral CTA.
                Text(ConversionCopy.billedAmount(priceLabel: package.caffeinePriceLabel))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(ConversionCopy.disclosure(
                    trialLabel: package.caffeineIntroOfferLabel,
                    priceLabel: package.caffeinePriceLabel,
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                ))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let purchaseError {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var onboardingPackage: Package? {
        store.yearlyPackage ?? store.packages.first
    }

    private var purchaseLabel: String {
        guard let package = onboardingPackage else { return "See Caffeine+ plans" }
        return ConversionCopy.ctaLabel(
            trialLabel: package.caffeineIntroOfferLabel,
            priceLabel: package.caffeinePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(package)
        )
    }

    // MARK: - Actions

    private func advance(to next: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func saveBedtime() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
    }

    /// Declining Apple Health is a supported path, not a dead end: the log falls
    /// back to this device and retries on every foreground, so the step always
    /// moves on whichever way the system sheet is answered.
    private func connectHealth() async {
        isWorking = true
        try? await HealthKitService.shared.requestAuthorization()
        await HealthKitService.shared.refreshCache()
        isWorking = false
        advance(to: 3)
    }

    private func connectBodyInsights() async {
        isWorking = true
        let granted = await HealthInsightsService.shared.requestAuthorization()
        settings.bodyInsightsEnabled = granted
        isWorking = false
        advance(to: 4)
    }

    /// One-tap conversion on the last step. No loaded product means the full
    /// paywall opens instead of a dead button; either way onboarding finishes.
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
                finish()
            case .cancelled:
                // Dismissing Apple's sheet is a choice, not a failure. A red
                // error there makes a working screen look broken.
                purchaseError = nil
            case .none:
                purchaseError = store.errorMessage ?? "Couldn't reach the App Store. Please try again."
            }
        }
    }

    private func finish() {
        saveBedtime()
        settings.hasCompletedSetup = true
    }
}
