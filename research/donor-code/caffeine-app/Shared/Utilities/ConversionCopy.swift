import Foundation

/// Pure copy helpers for Caffeine+ conversion CTAs. StoreKit always purchases
/// the same package. Trial vs paid is eligibility, not a different product.
/// These helpers keep every pitch surface honest when the user has already used
/// their free trial.
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
        "Continue with Caffeine+"
    }

    /// Short capsule CTA on locked rows. These sit far from any price and only
    /// route to a purchase surface, so they stay neutral for the same reason.
    static func shortCTALabel(eligibleForTrial: Bool) -> String {
        "Continue with Caffeine+"
    }

    /// Apple 3.1.2(c): the amount the user will actually be billed, phrased as a
    /// commitment rather than a rate ("$14.99 / year" -> "$14.99 per year").
    /// Every purchase surface renders this as its largest pricing element.
    static func billedAmount(priceLabel: String) -> String {
        priceLabel.replacingOccurrences(of: " / ", with: " per ")
    }

    /// Subordinate line under the billed amount. The trial stays a visible
    /// conversion hook, but the price always leads and gets the stronger type.
    static func billedNote(trialLabel: String?, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(trialLabel.lowercased()) included · Cancel anytime"
        }
        return "Billed automatically · Cancel anytime"
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    static func disclosure(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool,
        renewClause: String = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(priceLabel) after the \(trialLabel.lowercased()). \(renewClause)"
        }
        return "\(priceLabel). \(renewClause)"
    }

    /// Compact disclosure for the trial offer sheet footer.
    static func sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(priceLabel) after the \(trialLabel.lowercased()). Auto-renews unless cancelled at least 24 hours before the trial ends."
        }
        return "\(priceLabel). Auto-renews unless cancelled 24h before the period ends."
    }

    /// Cancel / failure copy never blames a "trial" the user wasn't eligible for.
    static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Trial wasn't started. Tap again to continue."
            : "Purchase wasn't completed. Tap again to continue."
    }

    static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Couldn't start your trial. Please try again."
            : "Couldn't complete the purchase. Please try again."
    }

    /// StoreKit `.pending`: Ask to Buy, or a bank confirmation. Nothing has
    /// failed and nothing has completed, so the copy must not imply either. It
    /// says the wait is expected and that Caffeine+ turns itself on.
    static let purchasePendingMessage =
        "Waiting on Apple to confirm this purchase. Caffeine+ turns on by itself as soon as it goes through, so there is nothing to tap again."
}
