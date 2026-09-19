import RevenueCat
import StoreKit
import SwiftUI

/// The Baby+ purchase surface. Apple 3.1.2 requires the price, the billing
/// period, the renewal behaviour, a restore action, and links to the Privacy
/// Policy and the Apple Standard EULA at the point of purchase, so
/// `legalFooter` and `disclosure` render in every state including loading
/// and failure.
struct BabyPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    var displayCloseButton: Bool = true
    var paywallImpressionID: String = "baby_paywall"
    var focus: PlusFeature?

    @State private var selected: Package?
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.paper.ignoresSafeArea()

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
                        .foregroundStyle(AppTheme.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .padding(AppTheme.tightSpacing)
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
        VStack(spacing: AppTheme.spacing) {
            Spacer()
            ProgressView().tint(AppTheme.accent)
            Text("Loading plans")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
            Spacer()
            legalFooter
        }
        .padding(AppTheme.margin)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.ink2)
            Text("Couldn't load plans")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(store.errorMessage ?? "Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
            Button("Try again") { store.start(forceRefresh: true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
            Spacer()
            legalFooter
        }
        .padding(AppTheme.margin)
    }

    /// One viewport: hero, three reasons, plans, the billed amount, the CTA,
    /// the disclosure, and the footer.
    private var content: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing) {
                hero
                headlineBenefits
                plans
                checkout
                legalFooter
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.top, displayCloseButton ? 44 : AppTheme.tightSpacing)
            .padding(.bottom, AppTheme.tightSpacing)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var subscriberContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.looseSpacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.accent)
                Text("Baby+ is active")
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("The pediatrician summary, trends and export are unlocked on every device signed in to this Apple ID.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
                Link(destination: BabyLinks.manageSubscriptions) {
                    Text("Manage subscription").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                VStack(spacing: AppTheme.spacing) {
                    ForEach(PlusFeature.allCases) { feature in
                        benefitRow(feature, unlocked: true)
                    }
                }
                .card()
                legalFooter
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.top, displayCloseButton ? 44 : AppTheme.looseSpacing)
            .padding(.bottom, AppTheme.looseSpacing)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            Image(systemName: focus?.symbolName ?? "doc.text.fill")
                .font(.title)
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.welcomeIconSize, height: AppTheme.welcomeIconSize)
                .background(AppTheme.card, in: AppTheme.cardShape)
                .graphicBorder()
                .accessibilityHidden(true)
            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subhead)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headlineBenefits: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            ForEach(Self.headlineFeatures) { feature in
                HStack(spacing: AppTheme.spacing) {
                    Image(systemName: feature.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 24)
                    Text(feature.pitchLine)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let headlineFeatures: [PlusFeature] = [.pediatricianSummary, .trends, .export]

    private var headline: String {
        if let focus { return focus.pitchHeadline }
        return "Walk into the pediatrician\nwith a clean summary"
    }

    private var subhead: String {
        "Logging, the first-weeks tally, widgets, the Watch app and logging together stay free. Baby+ is the reporting on top."
    }

    private func benefitRow(_ feature: PlusFeature, unlocked: Bool) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : feature.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var plans: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            ForEach(store.packages, id: \.identifier) { package in
                PlanCard(
                    package: package,
                    isSelected: selected?.identifier == package.identifier,
                    trialLabel: store.eligibleIntroLabel(for: package),
                    perMonthLabel: perMonthLabel(for: package),
                    savingsPercent: savingsPercent(for: package)
                ) {
                    Haptics.selected()
                    selected = package
                }
            }
        }
    }

    private var checkout: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            if let selected {
                VStack(spacing: AppTheme.hairSpacing) {
                    Text(ConversionCopy.billedAmount(priceLabel: selected.babyPriceLabel))
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("paywall.billedAmount")
                    Text(ConversionCopy.billedNote(
                        trialLabel: selected.babyIntroOfferLabel,
                        eligibleForTrial: store.isEligibleForIntroOffer(selected)
                    ))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                }
            }

            Button {
                guard let selected else { return }
                restoreMessage = nil
                Task {
                    if await store.purchase(selected) == .pending {
                        restoreMessage = ConversionCopy.purchasePendingMessage
                    }
                }
            } label: {
                if store.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(ConversionCopy.ctaLabel(
                        trialLabel: selected?.babyIntroOfferLabel,
                        priceLabel: selected?.babyPriceLabel ?? "",
                        eligibleForTrial: selected.map { store.isEligibleForIntroOffer($0) } ?? false
                    ))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected == nil || store.isLoading)

            Text(disclosureText)
                .font(.caption2)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = store.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.notice)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var disclosureText: String {
        guard let selected else {
            return "Prices are shown in your local currency before you buy. Subscriptions renew automatically until cancelled. \(Self.hedge)"
        }
        if selected.babyPackageKind == .lifetime {
            return "\(selected.babyPriceLabel). One-time purchase, no subscription and nothing renews. \(Self.hedge)"
        }
        let billing = ConversionCopy.disclosure(
            trialLabel: selected.babyIntroOfferLabel,
            priceLabel: selected.babyPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
        return "\(billing) \(Self.hedge)"
    }

    private static let hedge = "Baby Tracker is a log, not medical advice."

    private var legalFooter: some View {
        VStack(spacing: AppTheme.hairSpacing) {
            Button {
                restoreMessage = nil
                isRestoring = true
                Task {
                    await store.restore()
                    isRestoring = false
                    if !store.isPro {
                        restoreMessage = store.errorMessage ?? "No active Baby+ purchase was found for this Apple ID."
                    }
                }
            } label: {
                Text(isRestoring ? "Restoring…" : "Restore purchases")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                    .frame(minHeight: 44)
            }
            .disabled(isRestoring || store.isLoading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.tightSpacing) {
                    Link("Terms of Use", destination: BabyLinks.standardEULA)
                    Text("·").accessibilityHidden(true)
                    Link("Privacy Policy", destination: BabyLinks.privacyPolicy)
                }
                VStack(spacing: AppTheme.hairSpacing) {
                    Link("Terms of Use", destination: BabyLinks.standardEULA)
                    Link("Privacy Policy", destination: BabyLinks.privacyPolicy)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink2)
        }
    }

    // MARK: - Helpers

    private func selectDefaultIfNeeded() {
        guard selected == nil, !store.packages.isEmpty else { return }
        if let requested = Self.requestedPlan, let match = store.packages.first(where: { $0.babyPackageKind == requested }) {
            selected = match
            return
        }
        selected = store.yearlyPackage ?? store.packages.first
    }

    /// `-PaywallSnapshot monthly|yearly|lifetime` picks the plan for a review
    /// screenshot, so each product's render shows its own billed amount.
    private static var requestedPlan: BabyPackageKind? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PaywallSnapshot"), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "monthly": return .monthly
        case "yearly": return .yearly
        case "lifetime": return .lifetime
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private func perMonthLabel(for package: Package) -> String? {
        guard package.babyPackageKind == .yearly else { return nil }
        let yearly = package.storeProduct.price as Decimal
        guard yearly > 0 else { return nil }
        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
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
        guard package.babyPackageKind == .yearly,
              let monthly = store.packages.first(where: { $0.babyPackageKind == .monthly }) else { return nil }
        let yearlyPrice = package.storeProduct.price as Decimal
        let monthlyPrice = monthly.storeProduct.price as Decimal
        guard monthlyPrice > 0, yearlyPrice > 0 else { return nil }
        let atMonthlyRate = monthlyPrice * 12
        guard atMonthlyRate > yearlyPrice else { return nil }
        let saved = (atMonthlyRate - yearlyPrice) / atMonthlyRate
        return Int((saved as NSDecimalNumber).doubleValue * 100)
    }
}

/// The Baby+ feature list: reporting to share with a doctor, nothing else.
/// Driven off one enum so the paywall bullets and the
/// locked rows in the app cannot drift apart. Nothing here may be something
/// that ships free.
enum PlusFeature: String, CaseIterable, Identifiable {
    case pediatricianSummary
    case trends
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pediatricianSummary: "Pediatrician summary"
        case .trends: "Trends"
        case .export: "CSV export"
        }
    }

    var detail: String {
        switch self {
        case .pediatricianSummary: "A one-page PDF since the last visit: feeds and the longest gap between them, wet and dirty counts, sleep, weights. Hand it over or AirDrop it in the exam room."
        case .trends: "Feeds per day, longest sleep stretch and diaper counts over the weeks."
        case .export: "Every entry as a spreadsheet, for your records or a specialist."
        }
    }

    var symbolName: String {
        switch self {
        case .pediatricianSummary: "doc.text.fill"
        case .trends: "chart.bar.fill"
        case .export: "square.and.arrow.up.fill"
        }
    }

    var pitchLine: String {
        switch self {
        case .pediatricianSummary: "A one-page summary since the last visit"
        case .trends: "Feeds, sleep and diapers over the weeks"
        case .export: "Export every entry as a spreadsheet"
        }
    }

    var pitchHeadline: String {
        switch self {
        case .pediatricianSummary: "Walk into the pediatrician\nwith a clean summary"
        case .trends: "See the weeks,\nnot just today"
        case .export: "Take the whole log\nwith you"
        }
    }
}

private struct PlanCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let package: Package
    let isSelected: Bool
    let trialLabel: String?
    let perMonthLabel: String?
    let savingsPercent: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing)) : AnyLayout(HStackLayout(spacing: AppTheme.spacing))) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppTheme.accent : AppTheme.ink3, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(AppTheme.accent).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    HStack(spacing: AppTheme.tightSpacing) {
                        Text(package.babyDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let savingsPercent {
                            badge("SAVE \(savingsPercent)%")
                        } else if package.babyPackageKind == .lifetime {
                            badge("PAY ONCE")
                        }
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.ink2)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppTheme.tightSpacing) }

                Text(package.babyPriceLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.vertical, AppTheme.tightSpacing)
            .frame(minHeight: 56)
            .background(isSelected ? AppTheme.actionFill.opacity(0.20) : AppTheme.card, in: AppTheme.cardShape)
            .graphicBorder()
        }
        .pressableCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var secondary: String? {
        var parts: [String] = []
        if let trialLabel { parts.append(trialLabel) }
        if let perMonthLabel { parts.append(perMonthLabel) }
        if parts.isEmpty, package.babyPackageKind == .lifetime {
            return "One-time purchase, never renews"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.buttonInk)
            .padding(.horizontal, AppTheme.hairSpacing)
            .background(AppTheme.actionFill, in: Capsule())
    }
}
