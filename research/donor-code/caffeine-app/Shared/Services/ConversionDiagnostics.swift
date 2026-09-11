import Foundation
import os

/// On-device record of how someone met Caffeine+ before they bought it: which
/// surfaces they saw, how many times, how early they were asked, and how long it
/// took.
///
/// RevenueCat can say a trial started; it cannot say what was on screen when it
/// did, or how many pitches came before it. `StoreService` mirrors these counters
/// onto the RevenueCat customer as subscriber attributes, where they are readable
/// per customer without a device in hand.
///
/// Deliberately NOT sent as extra custom paywall impressions: RevenueCat counts
/// every impression id as a paywall encounter, so pushing funnel steps through
/// that channel would inflate the encounter rate and ruin the one server-side
/// number that already works.
///
/// The attribute keys and their formats are fleet-wide. Keep them identical in
/// every app so one query reads the whole portfolio; anything app-specific
/// belongs in a separate attribute, not in a renamed version of these.
///
/// Nothing here may carry health data, free text, or anything the user typed.
/// Counts, dates, and short surface names only.
enum ConversionDiagnostics {
    private static let logger = Logger(subsystem: "com.jackwallner.caffeine", category: "Conversion")

    /// Spelled out rather than taken from the data layer, so this file can join
    /// the unit-test bundle without dragging the app's storage stack in behind it.
    static let suiteName = "group.com.jackwallner.caffeine"


    /// Impression ids carry an app prefix that says nothing once the attributes
    /// are already grouped under this app's customer record.
    private static let impressionPrefix = "caffeine_"

    /// Overridable so tests get their own suite instead of stamping on the real
    /// counters in the shared container.
    nonisolated(unsafe) static var defaultsOverride: UserDefaults?

    private static var defaults: UserDefaults {
        defaultsOverride ?? UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let totalViews = "conv.pitchViews.total"
        static let firstSeen = "conv.pitchFirstSeen"
        static let lastSurface = "conv.pitchLastSurface"
        static func views(_ surface: String) -> String { "conv.pitchViews.\(surface)" }

        static let installedAt = "conv.installedAt"
        static let appOpens = "conv.appOpens"
        static let opensBeforeFirstPitch = "conv.opensBeforeFirstPitch"
        static let daysSinceInstallAtFirstPitch = "conv.daysToFirstPitch"

        static let convertedOn = "conv.convertedOn"
        static let convertedAt = "conv.convertedAt"
        static let viewsAtConvert = "conv.viewsAtConvert"
        static let daysToConvert = "conv.daysToConvert"
        static let convertedPlan = "conv.convertedPlan"
        static let convertedWithTrial = "conv.convertedWithTrial"
        static let convertedOffering = "conv.convertedOffering"
    }

    static func surface(fromImpressionID id: String) -> String {
        id.hasPrefix(impressionPrefix) ? String(id.dropFirst(impressionPrefix.count)) : id
    }

    // MARK: - Recording

    /// One app launch. Stamps the install date on the very first call, which is
    /// the closest thing to an install timestamp available without a server.
    ///
    /// An install that predates this code has no stamp, so its first launch
    /// after updating becomes day zero. That undercounts age for existing users
    /// and cannot be helped; `days_since_install` is only trustworthy for
    /// installs that started on a build containing this file.
    static func recordAppOpen() {
        let d = defaults
        if d.object(forKey: Key.installedAt) == nil {
            d.set(Date.now.timeIntervalSince1970, forKey: Key.installedAt)
        }
        d.set(d.integer(forKey: Key.appOpens) + 1, forKey: Key.appOpens)
    }

    /// One pitch was put in front of the user. Called from
    /// `StoreService.trackPaywallImpression` so every surface is covered without
    /// each call site remembering to.
    ///
    /// The "how early were they asked" pair is frozen on the first pitch only. A
    /// customer who sees a paywall on day 30 has not retroactively been asked on
    /// day 30 if the first ask was on day one.
    static func recordPitchView(impressionID: String) {
        let surface = surface(fromImpressionID: impressionID)
        let d = defaults
        d.set(d.integer(forKey: Key.totalViews) + 1, forKey: Key.totalViews)
        d.set(d.integer(forKey: Key.views(surface)) + 1, forKey: Key.views(surface))
        d.set(surface, forKey: Key.lastSurface)
        if d.object(forKey: Key.firstSeen) == nil {
            d.set(Date.now.timeIntervalSince1970, forKey: Key.firstSeen)
            d.set(d.integer(forKey: Key.appOpens), forKey: Key.opensBeforeFirstPitch)
            if let installed = installDate {
                let days = Calendar.current.dateComponents([.day], from: installed, to: .now).day ?? 0
                d.set(max(0, days), forKey: Key.daysSinceInstallAtFirstPitch)
            }
        }
        logger.info("Pitch view: \(surface, privacy: .public) (total \(d.integer(forKey: Key.totalViews)))")
    }

    /// A purchase went through. Freezes what the funnel looked like at that
    /// moment, so later views cannot rewrite the story of how they converted.
    ///
    /// Only the *first* conversion is recorded: a renewal or a plan change is
    /// not a new answer to "what sold this person".
    static func recordConversion(
        plan: String,
        startedTrial: Bool,
        offeringID: String? = nil
    ) {
        let d = defaults
        guard d.string(forKey: Key.convertedOn) == nil else { return }
        d.set(d.string(forKey: Key.lastSurface) ?? "unknown", forKey: Key.convertedOn)
        d.set(d.integer(forKey: Key.totalViews), forKey: Key.viewsAtConvert)
        d.set(plan, forKey: Key.convertedPlan)
        d.set(startedTrial, forKey: Key.convertedWithTrial)
        if let offeringID { d.set(offeringID, forKey: Key.convertedOffering) }
        d.set(Date.now.timeIntervalSince1970, forKey: Key.convertedAt)
        if let first = firstSeenDate {
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            d.set(max(0, days), forKey: Key.daysToConvert)
        }
        logger.info("Conversion on \(d.string(forKey: Key.convertedOn) ?? "?", privacy: .public) after \(d.integer(forKey: Key.viewsAtConvert)) pitches")
    }

    // MARK: - Reading

    static var totalPitchViews: Int { defaults.integer(forKey: Key.totalViews) }
    static var lastSurface: String? { defaults.string(forKey: Key.lastSurface) }
    static var appOpens: Int { defaults.integer(forKey: Key.appOpens) }

    static var firstSeenDate: Date? {
        let stamp = defaults.double(forKey: Key.firstSeen)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static var installDate: Date? {
        let stamp = defaults.double(forKey: Key.installedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Every per-surface count that is non-zero, keyed by surface.
    static var viewsBySurface: [String: Int] {
        var result: [String: Int] = [:]
        let prefix = "conv.pitchViews."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let surface = String(key.dropFirst(prefix.count))
            guard surface != "total", let count = value as? Int, count > 0 else { continue }
            result[surface] = count
        }
        return result
    }

    /// The whole record as RevenueCat subscriber attributes. Keys stay under
    /// RevenueCat's 40-character limit and values are plain strings, which is
    /// all that API accepts.
    ///
    /// Empty until the first pitch: a customer who has never been shown a
    /// paywall has nothing to say about paywalls, and sending zeros would make
    /// them indistinguishable from someone the funnel genuinely failed.
    static var subscriberAttributes: [String: String] {
        var attributes: [String: String] = [:]
        let d = defaults

        let total = totalPitchViews
        guard total > 0 else { return attributes }
        attributes["pitch_views_total"] = String(total)
        for (surface, count) in viewsBySurface {
            let key = "pitch_views_\(surface)"
            attributes[String(key.prefix(40))] = String(count)
        }
        if let last = lastSurface { attributes["pitch_last"] = last }
        if let first = firstSeenDate {
            attributes["pitch_first_seen"] = ISO8601DateFormatter().string(from: first)
            let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
            attributes["days_since_first_pitch"] = String(max(0, days))
        }
        // Absent on installs that predate this file, which is the honest answer:
        // their real install date is unknown, not zero.
        if d.object(forKey: Key.daysSinceInstallAtFirstPitch) != nil {
            attributes["days_since_install"] = String(d.integer(forKey: Key.daysSinceInstallAtFirstPitch))
        }
        if d.object(forKey: Key.opensBeforeFirstPitch) != nil {
            attributes["opens_before_first_pitch"] = String(d.integer(forKey: Key.opensBeforeFirstPitch))
        }
        if let convertedOn = d.string(forKey: Key.convertedOn) {
            attributes["converted_surface"] = convertedOn
            let stamp = d.double(forKey: Key.convertedAt)
            if stamp > 0 {
                attributes["converted_at"] = ISO8601DateFormatter()
                    .string(from: Date(timeIntervalSince1970: stamp))
            }
            attributes["pitch_views_at_convert"] = String(d.integer(forKey: Key.viewsAtConvert))
            attributes["days_to_convert"] = String(d.integer(forKey: Key.daysToConvert))
            attributes["converted_plan"] = d.string(forKey: Key.convertedPlan) ?? "unknown"
            attributes["converted_with_trial"] = d.bool(forKey: Key.convertedWithTrial) ? "true" : "false"
            if let offering = d.string(forKey: Key.convertedOffering) {
                attributes["converted_offering"] = offering
            }
        }
        return attributes
    }

    #if DEBUG
    /// Test seam. The counters outlive a launch.
    static func reset() {
        let d = defaults
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("conv.") {
            d.removeObject(forKey: key)
        }
    }
    #endif
}
