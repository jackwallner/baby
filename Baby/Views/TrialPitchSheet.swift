import RevenueCat
import SwiftUI
import UIKit

/// When the passive Baby+ sheet may appear: after a log has stood (its Undo
/// window ran out), once the baby has a few entries, never for a subscriber,
/// and at most once every 14 days. Modeled on Recharge's Root trial sheet.
///
/// Without it two thirds of new users never saw an offer: Baby has no trial
/// page in onboarding, and the paywall only opens from Upgrade, Reports or
/// Settings (2026-11-24 read, 48 of 141 new customers). Onboarding itself stays
/// free of purchase screens.
enum TrialPitch {
    static let cooldownDays = 14
    /// Enough to have seen the log work, early enough to reach the many
    /// families who only use the app on the first day.
    static let minimumEntries = 3
    static let impressionID = "baby_trial_sheet"

    private static let lastShownKey = "trialPitch.lastShown"

    static func shouldShow(entries: Int, isPro: Bool, canPitch: Bool, lastShown: Date?, now: Date = .now) -> Bool {
        guard !isPro, canPitch, entries >= minimumEntries else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= TimeInterval(cooldownDays) * 86_400
    }

    static func lastShown(_ defaults: UserDefaults = AppGroup.defaults) -> Date? {
        #if DEBUG
        if let days = launchShownDaysAgo { return Date(timeIntervalSinceNow: -Double(days) * 86_400) }
        #endif
        return defaults.object(forKey: lastShownKey) as? Date
    }

    static func markShown(_ defaults: UserDefaults = AppGroup.defaults, now: Date = .now) {
        #if DEBUG
        launchShownDaysAgo = nil
        #endif
        defaults.set(now, forKey: lastShownKey)
    }

    /// Off in captures, probe runs and UI tests (`-NoCloudKit`, as
    /// `ReminderOfferGate`), which drive the app and must not be covered by a
    /// sheet. `-TrialPitchTest` turns it back on for `TrialPitchUITests`.
    static var isEnabled: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-TrialPitchTest") { return true }
        return !ScreenshotConfig.isEnabled && !RevenueCatProbe.isEnabled
            && !args.contains("-DuoStop") && !args.contains("-NoCloudKit")
        #else
        return true
        #endif
    }

    #if DEBUG
    /// `-TrialPitchShownDaysAgo N` stands in for the stored date, so a test
    /// can sit inside or outside the cooldown.
    nonisolated(unsafe) private static var launchShownDaysAgo: Int? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-TrialPitchShownDaysAgo"), index + 1 < args.count else { return nil }
        return Int(args[index + 1])
    }()
    #endif

    /// A sheet, alert or share sheet already up anywhere in the window.
    @MainActor
    static var isSomethingPresented: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }
}

/// The passive half sheet: one plan, the billed amount, one decision. Yearly
/// with its free week, like the paywall's default; the full plan list stays on
/// Upgrade.
struct TrialPitchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: StoreService
    @State private var isRestoring = false
    @State private var message: String?

    static let detentHeight: CGFloat = 560

    private var package: Package? { store.yearlyPackage }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                pitch
                    .padding(.top, AppTheme.looseSpacing)
                    .padding(.bottom, AppTheme.spacing)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .padding(.horizontal, AppTheme.margin)
        .background(AppTheme.paper.ignoresSafeArea())
        .tint(AppTheme.accent)
        .task { store.trackPaywallImpression(id: TrialPitch.impressionID) }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private var pitch: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            VStack(spacing: AppTheme.tightSpacing) {
                SectionLabel(text: String(localized: "Baby+"))
                Text("Reports for the pediatrician")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: AppTheme.spacing) {
                ForEach(PlusFeature.allCases) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing) {
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
            .card()
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            if let package {
                // The billed amount is the largest pricing text here (3.1.2(c)).
                VStack(spacing: AppTheme.hairSpacing) {
                    Text(package.babyBilledAmount)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("trialPitch.billedAmount")
                    Text(ConversionCopy.billedNote(
                        trial: package.babyIntroOffer,
                        eligibleForTrial: store.isEligibleForIntroOffer(package)
                    ))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                }
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Button {
                guard let package else { return }
                message = nil
                Task {
                    switch await store.purchase(package) {
                    case .purchased: dismiss()
                    case .pending: message = ConversionCopy.purchasePendingMessage
                    default: break
                    }
                }
            } label: {
                if store.isLoading {
                    ProgressView().tint(AppTheme.buttonInk)
                } else {
                    Text(store.shortConversionCTALabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(package == nil || store.isLoading)
            .accessibilityIdentifier("trialPitch.cta")

            Button("Not now") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("trialPitch.decline")

            if let note = message ?? store.errorMessage {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let package {
                Text(ConversionCopy.sheetDisclosure(
                    trial: package.babyIntroOffer,
                    priceLabel: package.babyPriceLabel,
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                ))
                .font(.caption2)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            legalRow
        }
        .padding(.bottom, AppTheme.tightSpacing)
    }

    private var legalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.tightSpacing) { legalItems }
            VStack(spacing: 0) { legalItems }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.ink2)
    }

    @ViewBuilder
    private var legalItems: some View {
        Button {
            message = nil
            isRestoring = true
            Task {
                await store.restore()
                isRestoring = false
                if !store.isPro, store.errorMessage == nil {
                    message = String(localized: "No active Baby+ purchase was found for this Apple ID.")
                }
            }
        } label: {
            Text(isRestoring ? String(localized: "Restoring…") : String(localized: "Restore purchases"))
                .frame(minHeight: 44)
        }
        .disabled(isRestoring || store.isLoading)
        Link(destination: BabyLinks.standardEULA) { Text("Terms of Use").frame(minHeight: 44) }
        Link(destination: BabyLinks.privacyPolicy) { Text("Privacy Policy").frame(minHeight: 44) }
    }
}
