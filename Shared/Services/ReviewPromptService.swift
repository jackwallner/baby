import Foundation
import SwiftUI

/// The fleet review funnel: wait for a genuinely positive moment, ask whether
/// the person is enjoying the app, and only call Apple's native prompt after
/// they say yes. Someone who says no is routed to support instead.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Logging days before the app is allowed to ask anything.
    static let minimumLoggingDays = 5
    /// Days to wait before asking again after a dismissal.
    static let cooldownDays = 90

    @Published var isPresented = false

    private let defaults = AppGroup.defaults
    private static let loggingDaysKey = "reviewLoggingDayKeys"
    private static let lastAskedKey = "reviewLastAskedAt"
    private static let hasRatedKey = "reviewHasRated"
    private var askedThisSession = false

    private init() {}

    var loggingDayCount: Int { loggedDayKeys.count }

    private var loggedDayKeys: [String] {
        defaults.stringArray(forKey: Self.loggingDaysKey) ?? []
    }

    /// Called after every successful log.
    func recordLoggingDay(_ date: Date = .now) {
        let key = DateHelpers.dayKey(for: date)
        var keys = loggedDayKeys
        guard !keys.contains(key) else { return }
        keys.append(key)
        defaults.set(keys.suffix(60).map { $0 }, forKey: Self.loggingDaysKey)
    }

    /// The positive moment: a day that finished inside the typical range.
    func considerAfterDayInRange() {
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

    func markRated() {
        defaults.set(true, forKey: Self.hasRatedKey)
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }

    func markDeferred() {
        defaults.set(Date.now, forKey: Self.lastAskedKey)
        isPresented = false
    }
}
