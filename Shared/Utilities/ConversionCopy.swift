import Foundation

/// Pure copy helpers for Baby+ conversion CTAs. StoreKit always purchases
/// the same package. Trial vs paid is eligibility, not a different product.
/// These helpers keep every pitch surface honest when the user has already used
/// their free trial.
/// A free trial's length. Sentences take these raw parts, not the plan card's
/// label, so each one carries its own trial wording in its own grammar.
struct TrialOffer: Equatable, Sendable {
    enum Unit: Sendable {
        case day
        case month
        case year
    }

    let count: Int
    let unit: Unit

    /// The standalone label on a plan card: "7-day free trial".
    var label: String {
        switch unit {
        case .day: String(localized: "\(count)-day free trial")
        case .month: String(localized: "\(count)-month free trial")
        case .year: String(localized: "\(count)-year free trial")
        }
    }
}

enum ConversionCopy {
    /// Primary button. Deliberately carries no pricing words at all: not the
    /// trial, not the price. Apple 3.1.2(c) weighs pricing elements against each
    /// other, and a bold button reading "Start 7-day free trial" would outshout
    /// the calm price line above it. With a neutral button, the billed amount in
    /// `BilledAmountBlock` is the leading pricing text on the surface.
    ///
    /// The parameters are retained so callers keep passing the real offer, and
    /// so re-introducing price wording stays a one-line change that is obviously
    /// coupled to the block's sizing.
    static func ctaLabel(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        String(localized: "Continue with Baby+")
    }

    /// Short capsule CTA on locked rows. These sit far from any price and only
    /// route to a purchase surface, so they stay neutral for the same reason.
    static func shortCTALabel(eligibleForTrial: Bool) -> String {
        String(localized: "Continue with Baby+")
    }

    /// Subordinate line under the billed amount. The trial stays a visible
    /// conversion hook, but the price always leads and gets the stronger type.
    static func billedNote(trial: TrialOffer?, eligibleForTrial: Bool) -> String {
        guard eligibleForTrial, let trial else { return String(localized: "Billed automatically · Cancel anytime") }
        switch trial.unit {
        case .day: return String(localized: "\(trial.count)-day free trial included · Cancel anytime")
        case .month: return String(localized: "\(trial.count)-month free trial included · Cancel anytime")
        case .year: return String(localized: "\(trial.count)-year free trial included · Cancel anytime")
        }
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    static func disclosure(trial: TrialOffer?, priceLabel: String, eligibleForTrial: Bool) -> String {
        guard eligibleForTrial, let trial else {
            return String(localized: "\(priceLabel). Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.")
        }
        switch trial.unit {
        case .day: return String(localized: "\(priceLabel) after the \(trial.count)-day free trial. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.")
        case .month: return String(localized: "\(priceLabel) after the \(trial.count)-month free trial. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.")
        case .year: return String(localized: "\(priceLabel) after the \(trial.count)-year free trial. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.")
        }
    }

    /// Compact disclosure for the trial offer sheet footer.
    static func sheetDisclosure(trial: TrialOffer?, priceLabel: String, eligibleForTrial: Bool) -> String {
        guard eligibleForTrial, let trial else {
            return String(localized: "\(priceLabel). Auto-renews unless cancelled 24h before the period ends.")
        }
        switch trial.unit {
        case .day: return String(localized: "\(priceLabel) after the \(trial.count)-day free trial. Auto-renews unless cancelled at least 24 hours before the trial ends.")
        case .month: return String(localized: "\(priceLabel) after the \(trial.count)-month free trial. Auto-renews unless cancelled at least 24 hours before the trial ends.")
        case .year: return String(localized: "\(priceLabel) after the \(trial.count)-year free trial. Auto-renews unless cancelled at least 24 hours before the trial ends.")
        }
    }

    /// Cancel / failure copy never blames a "trial" the user wasn't eligible for.
    static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Trial wasn't started. Tap again to continue.")
            : String(localized: "Purchase wasn't completed. Tap again to continue.")
    }

    static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Couldn't start your trial. Please try again.")
            : String(localized: "Couldn't complete the purchase. Please try again.")
    }

    /// StoreKit `.pending`: Ask to Buy, or a bank confirmation. Nothing has
    /// failed and nothing has completed, so the copy must not imply either. It
    /// says the wait is expected and that Baby+ turns itself on.
    static let purchasePendingMessage = String(localized: "Waiting on Apple to confirm this purchase. Baby+ turns on by itself as soon as it goes through, so there is nothing to tap again.")
}
