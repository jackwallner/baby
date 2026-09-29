import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
    /// Dark's layout with dim, warm, low-blue colours for night feeds.
    case night

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .night: "Night light"
        }
    }

    var isNightLight: Bool { self == .night }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .night: .dark
        }
    }
}

/// Small preferences that are not part of the log. Stored in the App Group so
/// widgets read the same values.
@MainActor
final class BabySettings: ObservableObject {
    static let shared = BabySettings()

    private let defaults = AppGroup.defaults

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: AppGroup.Key.hasCompletedSetup) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: AppGroup.Key.appearance) }
    }

    /// Pee and Poop, or Wet and Dirty. Every surface re-reads it on change.
    @Published var diaperWords: DiaperWords {
        didSet {
            guard diaperWords != oldValue else { return }
            defaults.set(diaperWords.rawValue, forKey: AppGroup.Key.diaperWords)
            EventStore.shared.republishLabels()
        }
    }

    /// The buttons this family uses. Turning one off rebuilds the log and the
    /// summary, so Now, History, the reports, widgets and Watch all follow.
    @Published var tracked: TrackedKinds {
        didSet {
            guard tracked != oldValue else { return }
            tracked.store()
            EventStore.shared.reload()
        }
    }

    /// When the totals under the log buttons start counting. The summary the
    /// widgets and the Watch read is rebuilt with it.
    @Published var totalsWindow: TotalsWindow {
        didSet {
            guard totalsWindow != oldValue else { return }
            defaults.set(totalsWindow.storedValue, forKey: AppGroup.Key.totalsWindow)
            EventStore.shared.reload()
        }
    }

    /// The Now-screen invite card can be put away; Settings keeps the entry.
    @Published var hasDismissedShareCard: Bool {
        didSet { defaults.set(hasDismissedShareCard, forKey: "hasDismissedShareCard") }
    }

    private init() {
        hasCompletedSetup = defaults.bool(forKey: AppGroup.Key.hasCompletedSetup)
        appearance = AppAppearance(rawValue: defaults.string(forKey: AppGroup.Key.appearance) ?? "") ?? .system
        diaperWords = .current
        #if DEBUG
        // Seeded runs start with every button, whatever a previous run left.
        if ProcessInfo.processInfo.arguments.contains("-SeedScreenshotData") {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        }
        #endif
        tracked = .current
        totalsWindow = .current
        #if DEBUG
        // `-Appearance night` pins a palette for captures and UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-Appearance"), index + 1 < arguments.count,
           let pinned = AppAppearance(rawValue: arguments[index + 1]) {
            appearance = pinned
        }
        #endif
        hasDismissedShareCard = defaults.bool(forKey: "hasDismissedShareCard")
    }
}
