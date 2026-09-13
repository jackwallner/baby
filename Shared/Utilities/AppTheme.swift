import SwiftUI
#if !os(watchOS)
import UIKit
#endif

/// The one place a number or a colour is decided. `scripts/design-audit.py`
/// fails any view that types its own spacing, radius or colour, so changing the
/// app's rhythm is one edit here.
///
/// Warm paper, outlined care graphics and clear labels for a tired parent.
/// Three palettes: light (firm outlines and an offset ink shadow), dark (the
/// shadow is dropped, because a shadow lighter than the page reads as a glow,
/// and surfaces separate by tone behind a hairline), and Night light (dark's
/// shape with dim, warm, low-blue colours for feeds in a dark room).
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
    static let logButtonHeight: CGFloat = 88
    static let maxLogButtonHeight: CGFloat = 124
    static let outlineWidth: CGFloat = 2
    /// Card edges in dark themes: tone does the separating, the line only hints.
    static let hairlineWidth: CGFloat = 1
    static let shadowOffset: CGFloat = 3
    static let graphicSize: CGFloat = 44
    static let wideLayout: CGFloat = 700
    static let contentWidth: CGFloat = 1000
    static let homeSummaryAllowance: CGFloat = 360
    static let ctaHeight: CGFloat = 52
    static let iconSize: CGFloat = 36
    static let welcomeIconSize: CGFloat = 72
    static let inviteCodeSize: CGFloat = 200

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
    static let ink3 = Color(white: 0.60)
    static let feed = Color(red: 0.95, green: 0.68, blue: 0.30)
    static let wet = Color(red: 0.45, green: 0.68, blue: 0.95)
    static let dirty = Color(red: 0.72, green: 0.58, blue: 0.40)
    static let sleep = Color(red: 0.62, green: 0.60, blue: 0.95)
    static let accent = Color(red: 0.95, green: 0.55, blue: 0.42)
    static let notice = Color(red: 0.95, green: 0.68, blue: 0.30)
    static let outline = Color(white: 0.62)
    static let edge = Color(white: 0.30)
    static let shadow = Color.clear
    static let actionFill = Color(red: 0.95, green: 0.68, blue: 0.57)
    static let buttonInk = Color(white: 0.10)
    #else
    /// Warm off-white by day, near-black at night, dim umber for Night light.
    static let paper = Color(light: .init(0.97, 0.96, 0.94), dark: .init(0.07, 0.065, 0.06), night: .init(0.045, 0.032, 0.022))
    static let card = Color(light: .init(1, 1, 1), dark: .init(0.125, 0.12, 0.11), night: .init(0.095, 0.068, 0.048))
    static let cardElevated = Color(light: .init(0.94, 0.93, 0.91), dark: .init(0.17, 0.162, 0.15), night: .init(0.13, 0.095, 0.068))
    static let inkUIColor = UIColor(light: .init(0.11, 0.10, 0.09), dark: .init(0.95, 0.94, 0.92), night: .init(0.86, 0.68, 0.52))
    static let ink = Color(uiColor: inkUIColor)
    static let ink2 = Color(light: .init(0.42, 0.40, 0.38), dark: .init(0.68, 0.66, 0.63), night: .init(0.64, 0.49, 0.37))
    static let ink3 = Color(light: .init(0.43, 0.41, 0.39), dark: .init(0.62, 0.60, 0.58), night: .init(0.56, 0.43, 0.33))
    /// Kind colours. Amber, blue, brown, indigo: distinct at a glance and at 3am.
    /// Night light swaps blue and indigo for warm-shifted slate and mauve.
    static let feed = Color(light: .init(0.58, 0.35, 0.10), dark: .init(0.95, 0.68, 0.30), night: .init(0.84, 0.56, 0.26))
    static let wet = Color(light: .init(0.18, 0.43, 0.76), dark: .init(0.45, 0.68, 0.95), night: .init(0.46, 0.60, 0.58))
    static let dirty = Color(light: .init(0.52, 0.38, 0.22), dark: .init(0.72, 0.58, 0.40), night: .init(0.62, 0.56, 0.36))
    static let sleep = Color(light: .init(0.36, 0.34, 0.78), dark: .init(0.62, 0.60, 0.95), night: .init(0.64, 0.50, 0.58))
    /// Primary actions that are not one of the four kinds: onboarding, paywall.
    static let accent = Color(light: .init(0.70, 0.30, 0.20), dark: .init(0.95, 0.55, 0.42), night: .init(0.84, 0.48, 0.34))
    static let notice = Color(light: .init(0.60, 0.36, 0.06), dark: .init(0.95, 0.68, 0.30), night: .init(0.84, 0.56, 0.26))
    /// Strokes inside care graphics and icon rings.
    static let outline = Color(light: .init(0.14, 0.12, 0.11), dark: .init(0.56, 0.53, 0.50), night: .init(0.52, 0.40, 0.30))
    /// The border around cards and buttons. Ink by day, a quiet hairline at night.
    static let edge = Color(light: .init(0.14, 0.12, 0.11), dark: .init(0.25, 0.235, 0.22), night: .init(0.20, 0.145, 0.10))
    /// The offset "physical edge" shadow. Only light has one.
    static let shadow = Color(light: .init(0.14, 0.12, 0.11), dark: nil, night: nil)
    static let actionFill = Color(light: .init(1, 0.72, 0.60), dark: .init(0.92, 0.63, 0.51), night: .init(0.70, 0.43, 0.30))
    static let buttonInk = Color(light: .init(0.10, 0.10, 0.10), dark: .init(0.10, 0.10, 0.10), night: .init(0.07, 0.045, 0.03))
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
        color(for: kind).opacity(0.20)
    }
}

/// Small, flat care illustrations. Labels carry meaning alongside the artwork.
struct CareGraphic: View {
    let kind: EventKind
    var side: FeedSide? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.card)
                .overlay(Circle().strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
            if kind == .feed, side != .bottle {
                Image(systemName: "heart.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.feed)
            } else {
                CareGlyph(kind: kind)
                    .fill(AppTheme.fill(for: kind))
                    .overlay(CareGlyph(kind: kind).stroke(AppTheme.outline, style: StrokeStyle(lineWidth: AppTheme.outlineWidth, lineCap: .round, lineJoin: .round)))
                    .padding(AppTheme.tightSpacing)
            }
        }
        .frame(width: AppTheme.graphicSize, height: AppTheme.graphicSize)
        .accessibilityHidden(true)
    }
}

private struct CareGlyph: Shape {
    let kind: EventKind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        switch kind {
        case .feed:
            p.move(to: point(0.39, 0.20))
            p.addLine(to: point(0.39, 0.10))
            p.addQuadCurve(to: point(0.61, 0.10), control: point(0.50, -0.04))
            p.addLine(to: point(0.61, 0.20))
            p.addLine(to: point(0.72, 0.28))
            p.addLine(to: point(0.72, 0.85))
            p.addQuadCurve(to: point(0.28, 0.85), control: point(0.50, 1.02))
            p.addLine(to: point(0.28, 0.28))
            p.closeSubpath()
            p.move(to: point(0.28, 0.35)); p.addLine(to: point(0.72, 0.35))
            p.move(to: point(0.29, 0.55)); p.addLine(to: point(0.47, 0.55))
            p.move(to: point(0.29, 0.70)); p.addLine(to: point(0.43, 0.70))
        case .wet:
            p.move(to: point(0.50, 0.04))
            p.addCurve(to: point(0.50, 0.95), control1: point(0.28, 0.38), control2: point(-0.13, 0.85))
            p.addCurve(to: point(0.50, 0.04), control1: point(1.13, 0.85), control2: point(0.72, 0.38))
            p.closeSubpath()
        case .dirty:
            p.move(to: point(0.08, 0.23))
            p.addLine(to: point(0.92, 0.23))
            p.addQuadCurve(to: point(0.70, 0.86), control: point(0.92, 0.62))
            p.addLine(to: point(0.30, 0.86))
            p.addQuadCurve(to: point(0.08, 0.23), control: point(0.08, 0.62))
            p.closeSubpath()
            p.move(to: point(0.09, 0.40)); p.addLine(to: point(0.91, 0.40))
            p.move(to: point(0.12, 0.56)); p.addQuadCurve(to: point(0.34, 0.85), control: point(0.37, 0.56))
            p.move(to: point(0.88, 0.56)); p.addQuadCurve(to: point(0.66, 0.85), control: point(0.63, 0.56))
        case .sleep:
            p.move(to: point(0.67, 0.07))
            p.addCurve(to: point(0.87, 0.78), control1: point(-0.22, -0.06), control2: point(0.04, 1.31))
            p.addCurve(to: point(0.67, 0.07), control1: point(0.30, 0.91), control2: point(0.23, 0.26))
            p.closeSubpath()
        case .weight:
            p.addRoundedRect(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.15), cornerSize: CGSize(width: rect.width * 0.15, height: rect.height * 0.15))
            p.move(to: point(0.50, 0.48)); p.addLine(to: point(0.65, 0.30))
        }
        return p
    }
}

#if !os(watchOS)
/// Night light rides the trait system, so a dynamic colour re-resolves the
/// moment it flips, in SwiftUI and in the UIKit bars and sheets alike.
struct NightLightTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
}

struct NightLightKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = false

    static func read(from traitCollection: UITraitCollection) -> Bool {
        traitCollection[NightLightTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) {
        mutableTraits[NightLightTrait.self] = value
    }
}

extension EnvironmentValues {
    var nightLight: Bool {
        get { self[NightLightKey.self] }
        set { self[NightLightKey.self] = newValue }
    }
}

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

    /// A nil value is transparent. Night falls back to dark when not given.
    init(light: RGB, dark: RGB?, night: RGB? = nil) {
        self.init(uiColor: UIColor(light: light, dark: dark, night: night))
    }
}

extension UIColor {
    convenience init(light: Color.RGB, dark: Color.RGB?, night: Color.RGB? = nil) {
        self.init { traits in
            let value: Color.RGB?
            if traits.userInterfaceStyle != .dark {
                value = light
            } else if traits[NightLightTrait.self] {
                value = night ?? dark
            } else {
                value = dark
            }
            guard let value else { return .clear }
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        }
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
