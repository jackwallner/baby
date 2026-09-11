import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
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
        hasDismissedShareCard = defaults.bool(forKey: "hasDismissedShareCard")
    }
}
