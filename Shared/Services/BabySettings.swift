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

    /// The Now-screen invite card can be put away; Settings keeps the entry.
    @Published var hasDismissedShareCard: Bool {
        didSet { defaults.set(hasDismissedShareCard, forKey: "hasDismissedShareCard") }
    }

    private init() {
        hasCompletedSetup = defaults.bool(forKey: AppGroup.Key.hasCompletedSetup)
        appearance = AppAppearance(rawValue: defaults.string(forKey: AppGroup.Key.appearance) ?? "") ?? .system
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
