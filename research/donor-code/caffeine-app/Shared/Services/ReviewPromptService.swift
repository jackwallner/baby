import Foundation
import SwiftUI

/// The fleet review funnel: wait for a genuinely positive moment, ask whether
/// the person is enjoying the app, and only call Apple's native prompt after
/// they say yes. Someone who says no is routed to support instead, which is the
/// whole point of the gate.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Logging days before the app is allowed to ask anything. Four days means
    /// the person has a real forecast behind them, not a first-run impression.
    static let minimumLoggingDays = 4
    /// Days to wait before asking again after a dismissal.
    static let cooldownDays = 90

    @Published var isPresented = false

    private let defaults = UserDefaults(suiteName: caffeineAppGroupID) ?? .standard
    private static let loggingDaysKey = "reviewLoggingDayKeys"
    private static let lastAskedKey = "reviewLastAskedAt"
    private static let hasRatedKey = "reviewHasRated"
    /// One ask per launch, however many good moments occur.
    private var askedThisSession = false

    private init() {}

    var loggingDayCount: Int { loggedDayKeys.count }

    private var loggedDayKeys: [String] {
        defaults.stringArray(forKey: Self.loggingDaysKey) ?? []
    }

    /// Called after every successful log. Records the day so the funnel knows
    /// how much real use is behind the ask.
    func recordLoggingDay(_ date: Date = .now) {
        let key = DateHelpers.dayKey(for: date)
        var keys = loggedDayKeys
        guard !keys.contains(key) else { return }
        keys.append(key)
        defaults.set(keys.suffix(60).map { $0 }, forKey: Self.loggingDaysKey)
    }

    /// A positive moment: the person just logged a drink and their bedtime
    /// estimate still sits under the preference they set. Asking here means the
    /// app has visibly just done its job.
    func considerAfterGoodForecast(estimatedAtBedtime: Double, threshold: Double) {
        guard estimatedAtBedtime <= threshold else { return }
        considerAsking()
    }

    func considerAsking() {
        guard isEligible else { return }
        askedThisSession = true
        isPresented = true
    }

    var isEligible: Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        guard !askedThisSession else { return false }
        guard !defaults.bool(forKey: Self.hasRatedKey) else { return false }
        guard loggingDayCount >= Self.minimumLoggingDays else { return false }
        if let last = defaults.object(forKey: Self.lastAskedKey) as? Date {
            let elapsed = Date.now.timeIntervalSince(last) / 86_400
            guard elapsed >= Double(Self.cooldownDays) else { return false }
        }
        return true
    }

    /// The person said they are enjoying it and agreed to rate. Apple decides
    /// whether the native sheet actually appears, so this also marks the funnel
    /// finished either way.
    func markRated() {
        defaults.set(true, forKey: Self.hasRatedKey)
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }

    /// Dismissed, or routed to feedback. Starts the cooldown without closing the
    /// funnel permanently.
    func markDeferred() {
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }
}
