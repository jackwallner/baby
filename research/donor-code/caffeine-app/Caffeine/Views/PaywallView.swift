import RevenueCat
import StoreKit
import SwiftUI

/// The Caffeine+ purchase surface.
///
/// Rendered inline as the Upgrade tab (no close button, the tab bar stays
/// reachable) and as a sheet from the locked rows elsewhere. Apple 3.1.2
/// requires the price, the billing period, the renewal behaviour, a restore
/// action, and links to the Privacy Policy and the Apple Standard EULA to be
/// present at the point of purchase, so `legalFooter` and `disclosure` render in
/// every state including loading and failure.
struct CaffeinePaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    var displayCloseButton: Bool = true
    var paywallImpressionID: String = "caffeine_paywall"
    /// The locked feature the user reached for, so the hero can lead with it
    /// instead of a generic pitch.
    var focus: PlusFeature?

    @State private var selected: Package?
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.background.ignoresSafeArea()

            // A subscriber is checked first. They need no plan list, so gating
            // this screen on products would show them "Couldn't load plans"
            // whenever the offering was slow or the device offline, on a tab
            // that is titled Caffeine+ and is the only place to reach Manage
            // subscription.
            if store.isPro {
                subscriberContent
            } else if store.packages.isEmpty && store.isLoadingProducts {
                loadingState
            } else if store.packages.isEmpty {
                emptyState
            } else {
                content
            }

            if displayCloseButton {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.elevated, in: Circle())
                        .padding(14)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .task {
            store.trackPaywallImpression(id: paywallImpressionID, oncePerSession: !displayCloseButton)
            if store.packages.isEmpty { store.start(forceRefresh: false) }
            selectDefaultIfNeeded()
        }
        .onChange(of: store.packages.count) { _, _ in selectDefaultIfNeeded() }
        .onChange(of: store.isPro) { _, isPro in
            if isPro && displayCloseButton { dismiss() }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(Theme.cyan)
            Text("Loading plans")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            legalFooter
        }
        .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38))
                .foregroundStyle(Theme.textSecondary)
            Text("Couldn't load plans")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(store.errorMessage ?? "Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { store.start(forceRefresh: true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
            Spacer()
            legalFooter
        }
        .padding(24)
    }

    /// One viewport: hero, three reasons, plans, the billed amount, the CTA, the
    /// 3.1.2 disclosure, and the footer, with nothing below the fold.
    ///
    /// This used to end with an "everything in Caffeine+" card repeating all six
    /// features at full detail under the buy button. It read as a spec sheet,
    /// pushed the decision into a second screenful, and duplicated three bullets
    /// the user had already passed. The fleet's better-converting paywalls carry
    /// three reasons and a price; that is what this is now. `PlusFeature` still
    /// drives the copy, and the subscriber state still lists everything, which is
    /// where a complete list is actually useful.
    private var content: some View {
        ScrollView {
            VStack(spacing: 11) {
                hero
                headlineBenefits
                plans
                checkout
                legalFooter
            }
            .padding(.horizontal, 22)
            .padding(.top, displayCloseButton ? 48 : 6)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Keeps the footer clear of the floating tab bar when the paywall
            // is the Upgrade tab rather than a sheet.
            Color.clear.frame(height: displayCloseButton ? 0 : 84)
        }
    }

    /// What an existing subscriber sees on the same tab. Apple expects a
    /// purchased user to be able to find and manage what they bought.
    private var subscriberContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.forecastGradient)
                Text("Caffeine+ is active")
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Your body insights, full history, custom drinks, and the bedtime reminder are unlocked on every device signed in to this Apple ID.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                // Above the feature list, not below it. Managing the
                // subscription is the one action this screen exists to offer,
                // and six features at full detail is enough to push it off the
                // first screenful.
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Text("Manage subscription")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaywallCTAStyle())

                VStack(spacing: 10) {
                    ForEach(PlusFeature.allCases) { feature in
                        benefitRow(feature, unlocked: true)
                    }
                }
                .padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                legalFooter
            }
            .padding(.horizontal, 22)
            .padding(.top, displayCloseButton ? 52 : 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: displayCloseButton ? 0 : 60)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: focus?.symbolName ?? "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.forecastGradient)
            }
            Text(headline)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(subhead)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    /// Three lines above the plan cards. The reasons to buy, without the spec
    /// sheet pushing the price off the first screen.
    private var headlineBenefits: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.headlineFeatures) { feature in
                HStack(spacing: 10) {
                    Image(systemName: feature.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 22)
                    Text(feature.pitchLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let headlineFeatures: [PlusFeature] = [
        .bodyComparisons, .tunedHalfLife, .fullHistory,
    ]

    private var headline: String {
        if let focus { return focus.pitchHeadline }
        return "See how caffeine lands\non your own body"
    }

    private var subhead: String {
        "What sits under your cutoff: caffeine next to the sleep and heart data already in Apple Health. The cutoff itself, logging and both estimates stay free."
    }

    private func benefitRow(_ feature: PlusFeature, unlocked: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : feature.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(unlocked ? Theme.mint : Theme.cyan)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var plans: some View {
        VStack(spacing: 8) {
            ForEach(store.packages, id: \.identifier) { package in
                PlanCard(
                    package: package,
                    isSelected: selected?.identifier == package.identifier,
                    trialLabel: store.eligibleIntroLabel(for: package),
                    perMonthLabel: perMonthLabel(for: package),
                    savingsPercent: savingsPercent(for: package)
                ) {
                    selected = package
                }
            }
        }
    }

    private var checkout: some View {
        VStack(spacing: 8) {
            if let selected {
                // Apple 3.1.2(c): the amount actually billed is the largest
                // pricing element on the screen, above the neutral CTA.
                VStack(spacing: 2) {
                    Text(ConversionCopy.billedAmount(priceLabel: selected.caffeinePriceLabel))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text(ConversionCopy.billedNote(
                        trialLabel: selected.caffeineIntroOfferLabel,
                        eligibleForTrial: store.isEligibleForIntroOffer(selected)
                    ))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            Button {
                guard let selected else { return }
                restoreMessage = nil
                Task {
                    // `.pending` is Ask to Buy or a bank confirmation: nothing
                    // failed, so it gets its own copy rather than the error slot.
                    if await store.purchase(selected) == .pending {
                        restoreMessage = ConversionCopy.purchasePendingMessage
                    }
                }
            } label: {
                if store.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(ConversionCopy.ctaLabel(
                        trialLabel: selected?.caffeineIntroOfferLabel,
                        priceLabel: selected?.caffeinePriceLabel ?? "",
                        eligibleForTrial: selected.map { store.isEligibleForIntroOffer($0) } ?? false
                    ))
                }
            }
            .buttonStyle(PaywallCTAStyle())
            .disabled(selected == nil || store.isLoading)

            Text(disclosureText)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = store.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The 3.1.2 billing disclosure, with the Guideline 1.4.1 hedge on the end.
    /// The hedge used to be its own caption under the feature bullets; folding
    /// it in here keeps it on the buy screen without a fourth block of small
    /// print, and this text already sits directly under the CTA.
    private var disclosureText: String {
        guard let selected else {
            return "Prices are shown in your local currency before you buy. Subscriptions renew automatically until cancelled. \(Self.wellnessHedge)"
        }
        if selected.caffeinePackageKind == .lifetime {
            return "\(selected.caffeinePriceLabel). One-time purchase, no subscription and nothing renews. \(Self.wellnessHedge)"
        }
        let billing = ConversionCopy.disclosure(
            trialLabel: selected.caffeineIntroOfferLabel,
            priceLabel: selected.caffeinePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
        return "\(billing) \(Self.wellnessHedge)"
    }

    private static let wellnessHedge = "Insights are observations, not medical advice."

    /// Restore plus the two links Apple requires at the point of purchase.
    /// Rendered in every state, including the ones where no product loaded.
    private var legalFooter: some View {
        VStack(spacing: 6) {
            Button {
                restoreMessage = nil
                isRestoring = true
                Task {
                    await store.restore()
                    isRestoring = false
                    if !store.isPro {
                        restoreMessage = "No active Caffeine+ purchase was found for this Apple ID."
                    }
                }
            } label: {
                Text(isRestoring ? "Restoring…" : "Restore purchases")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || store.isLoading)

            HStack(spacing: 6) {
                Link("Terms of Use", destination: CaffeineLinks.standardEULA)
                Text("·")
                Link("Privacy Policy", destination: CaffeineLinks.privacyPolicy)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private func selectDefaultIfNeeded() {
        guard selected == nil, !store.packages.isEmpty else { return }
        selected = store.yearlyPackage ?? store.packages.first
    }

    /// Per-month anchor on the annual card. StoreKit gives a per-week figure
    /// directly; per-month is the comparison people actually make against the
    /// monthly plan sitting next to it.
    private func perMonthLabel(for package: Package) -> String? {
        guard package.caffeinePackageKind == .yearly else { return nil }
        let yearly = package.storeProduct.price as Decimal
        guard yearly > 0 else { return nil }
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let monthly = (yearly as NSDecimalNumber).dividing(by: 12, withBehavior: handler)
        let formatter = package.storeProduct.priceFormatter ?? {
            let value = NumberFormatter()
            value.numberStyle = .currency
            return value
        }()
        guard let text = formatter.string(from: monthly) else { return nil }
        return "\(text) / mo"
    }

    private func savingsPercent(for package: Package) -> Int? {
        guard package.caffeinePackageKind == .yearly,
              let monthly = store.packages.first(where: { $0.caffeinePackageKind == .monthly }) else {
            return nil
        }
        let yearlyPrice = package.storeProduct.price as Decimal
        let monthlyPrice = monthly.storeProduct.price as Decimal
        guard monthlyPrice > 0, yearlyPrice > 0 else { return nil }
        let atMonthlyRate = monthlyPrice * 12
        guard atMonthlyRate > yearlyPrice else { return nil }
        let saved = (atMonthlyRate - yearlyPrice) / atMonthlyRate
        return Int((saved as NSDecimalNumber).doubleValue * 100)
    }
}

/// The Caffeine+ feature list, driven off one enum so the paywall bullets and
/// the locked rows in the app cannot drift apart.
enum PlusFeature: String, CaseIterable, Identifiable {
    case bodyComparisons
    case tunedHalfLife
    case fullHistory
    case customDrinks
    case reminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyComparisons: "Caffeine against sleep, heart rate and HRV"
        case .tunedHalfLife: "A half-life starting point for your body"
        case .fullHistory: "Full history and trends"
        case .customDrinks: "Custom quick-log drinks"
        case .reminder: "Bedtime estimate reminder"
        }
    }

    var detail: String {
        switch self {
        case .bodyComparisons:
            "Higher-caffeine days next to lower ones for time asleep, resting heart rate, HRV, breathing, blood oxygen and activity."
        case .tunedHalfLife:
            "A suggested half-life from your age band, plus your intake per kilogram of body mass."
        case .fullHistory:
            "Ninety days of intake and bedtime estimates instead of the last seven."
        case .customDrinks:
            "Set your own three quick-log drinks and milligram amounts."
        case .reminder:
            "A note two hours before bedtime with the evening's estimate."
        }
    }

    var symbolName: String {
        switch self {
        case .bodyComparisons: "heart.text.square.fill"
        case .tunedHalfLife: "figure.stand"
        case .fullHistory: "chart.bar.fill"
        case .customDrinks: "cup.and.saucer.fill"
        case .reminder: "bell.badge.fill"
        }
    }

    /// One compressed line for the paywall's three-reason list. `detail` is the
    /// full sentence for the subscriber list and the locked rows; a paywall that
    /// leads with three of those reads as a spec sheet.
    var pitchLine: String {
        switch self {
        case .bodyComparisons: "Caffeine next to your sleep, heart rate and HRV"
        case .tunedHalfLife: "A half-life starting point for your body"
        case .fullHistory: "90 days of history instead of 7"
        case .customDrinks: "Your own quick-log drinks"
        case .reminder: "Tonight's estimate before bed"
        }
    }

    var pitchHeadline: String {
        switch self {
        case .bodyComparisons: "See caffeine next to\nyour sleep and heart data"
        case .tunedHalfLife: "Start from a half-life\nthat fits your age band"
        case .fullHistory: "See every day,\nnot just this week"
        case .customDrinks: "Log the drinks\nyou actually order"
        case .reminder: "Get tonight's estimate\nbefore bed"
        }
    }
}

private struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let trialLabel: String?
    let perMonthLabel: String?
    let savingsPercent: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.cyan : Theme.textSecondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Theme.cyan).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.caffeineDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let savingsPercent {
                            badge("SAVE \(savingsPercent)%")
                        } else if package.caffeinePackageKind == .lifetime {
                            badge("PAY ONCE")
                        }
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Text(package.caffeinePriceLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.cyan : Theme.textSecondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var secondary: String? {
        var parts: [String] = []
        if let trialLabel { parts.append(trialLabel) }
        if let perMonthLabel { parts.append(perMonthLabel) }
        if parts.isEmpty, package.caffeinePackageKind == .lifetime {
            return "One-time purchase, never renews"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.violet, in: Capsule())
    }
}

struct PaywallCTAStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.forecastGradient, in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
