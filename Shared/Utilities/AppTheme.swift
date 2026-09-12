import SwiftUI
#if !os(watchOS)
import UIKit
#endif

/// The one place a number or a colour is decided. `scripts/design-audit.py`
/// fails any view that types its own spacing, radius or colour, so changing the
/// app's rhythm is one edit here.
///
/// What the app is trying to look like: a calm surface a tired parent can read
/// in a dark room with one hand, that never looks assembled. System font only,
/// a four-point spacing scale, one radius with a continuous curve, and colour
/// that means one thing: which of the four kinds an entry is.
enum AppTheme {
    // MARK: Spacing (multiples of four)

    static let hairSpacing: CGFloat = 4
    static let tightSpacing: CGFloat = 8
    static let spacing: CGFloat = 12
    static let looseSpacing: CGFloat = 20
    /// The `.insetGrouped` inset on iPhone, so cards and Settings share an edge.
    static let margin: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 20
    /// The four log buttons: tall enough to hit while holding a baby.
    static let logButtonHeight: CGFloat = 72
    static let ctaHeight: CGFloat = 52
    static let iconSize: CGFloat = 36
    static let welcomeIconSize: CGFloat = 72

    static let feedbackAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
    }

    // MARK: Colour

    #if os(watchOS)
    static let paper = Color.black
    static let card = Color(white: 0.12)
    static let cardElevated = Color(white: 0.18)
    static let ink = Color.white
    static let ink2 = Color(white: 0.72)
    static let ink3 = Color(white: 0.5)
    static let feed = Color(red: 0.95, green: 0.68, blue: 0.30)
    static let wet = Color(red: 0.45, green: 0.68, blue: 0.95)
    static let dirty = Color(red: 0.72, green: 0.58, blue: 0.40)
    static let sleep = Color(red: 0.62, green: 0.60, blue: 0.95)
    static let accent = Color(red: 0.95, green: 0.55, blue: 0.42)
    static let notice = Color(red: 0.95, green: 0.68, blue: 0.30)
    #else
    /// Warm off-white by day, near-black at night.
    static let paper = Color(light: .init(0.97, 0.96, 0.94), dark: .init(0.07, 0.065, 0.06))
    static let card = Color(light: .init(1, 1, 1), dark: .init(0.12, 0.115, 0.105))
    static let cardElevated = Color(light: .init(0.94, 0.93, 0.91), dark: .init(0.18, 0.17, 0.16))
    static let ink = Color(light: .init(0.11, 0.10, 0.09), dark: .init(0.95, 0.94, 0.92))
    static let ink2 = Color(light: .init(0.42, 0.40, 0.38), dark: .init(0.68, 0.66, 0.63))
    static let ink3 = Color(light: .init(0.62, 0.60, 0.58), dark: .init(0.48, 0.46, 0.44))
    /// Kind colours. Amber, blue, brown, indigo: distinct at a glance and at 3am.
    static let feed = Color(light: .init(0.58, 0.35, 0.10), dark: .init(0.95, 0.68, 0.30))
    static let wet = Color(light: .init(0.20, 0.47, 0.82), dark: .init(0.45, 0.68, 0.95))
    static let dirty = Color(light: .init(0.52, 0.38, 0.22), dark: .init(0.72, 0.58, 0.40))
    static let sleep = Color(light: .init(0.36, 0.34, 0.78), dark: .init(0.62, 0.60, 0.95))
    /// Primary actions that are not one of the four kinds: onboarding, paywall.
    static let accent = Color(light: .init(0.78, 0.36, 0.25), dark: .init(0.95, 0.55, 0.42))
    static let notice = Color(light: .init(0.72, 0.45, 0.08), dark: .init(0.95, 0.68, 0.30))
    #endif

    static func color(for kind: EventKind) -> Color {
        switch kind {
        case .feed: feed
        case .wet: wet
        case .dirty: dirty
        case .sleep: sleep
        case .weight: ink2
        }
    }

    /// The soft fill behind a kind's button: the kind colour at low opacity so
    /// the label stays ink-on-paper and the buttons read as one family.
    static func fill(for kind: EventKind) -> Color {
        color(for: kind).opacity(0.16)
    }
}

#if !os(watchOS)
extension Color {
    struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    init(light: RGB, dark: RGB) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}

/// Four haptics, named after what happened. Nothing fires for navigation.
enum Haptics {
    @MainActor static func logged() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    @MainActor static func selected() { UISelectionFeedbackGenerator().selectionChanged() }
    @MainActor static func purchased() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func failed() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
#endif
