import SwiftUI

/// The small vocabulary every screen is built from, so no view invents its own
/// card, button or press state.

struct CardBackground: ViewModifier {
    var elevated = false

    func body(content: Content) -> some View {
        content
            .padding(AppTheme.looseSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elevated ? AppTheme.cardElevated : AppTheme.card, in: AppTheme.cardShape)
    }
}

extension View {
    func card(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }

    /// A card or row that answers back under the finger.
    func pressableCard() -> some View {
        buttonStyle(PressableCardStyle())
    }
}

struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: configuration.isPressed)
    }
}

/// Onboarding and paywall primary action. One height everywhere, so the
/// thumb never has to move between steps.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing)
            .frame(minHeight: AppTheme.ctaHeight)
            .background(AppTheme.accent, in: AppTheme.buttonShape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: configuration.isPressed)
    }
}

/// Section label above a card: small caps, secondary ink.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink2)
            .kerning(0.6)
    }
}

/// The bottom toast after a tap: what was logged, and Undo.
struct UndoToast: View {
    let logged: EventStore.LoggedEvent
    let undo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.spacing) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.color(for: logged.kind))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppTheme.tightSpacing)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, AppTheme.looseSpacing)
        .padding(.vertical, AppTheme.hairSpacing)
        .background(AppTheme.cardElevated, in: AppTheme.cardShape)
        .shadow(color: .black.opacity(0.12), radius: AppTheme.spacing, y: AppTheme.hairSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
    }

    private var title: String {
        let base: String = switch logged.kind {
        case .feed: "Logged feed"
        case .wet: "Logged wet diaper"
        case .dirty: "Logged dirty diaper"
        case .sleep: "Sleep"
        case .weight: "Logged weight"
        }
        if let detail = logged.detail, !detail.isEmpty { return "\(base) · \(detail)" }
        return base
    }
}

/// A quiet icon tile shared by summaries, history and onboarding.
struct KindIcon: View {
    let kind: EventKind

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.color(for: kind))
            .frame(width: AppTheme.iconSize, height: AppTheme.iconSize)
            .background(AppTheme.fill(for: kind), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A kind dot with a label, for the history rows and the tally.
struct KindDot: View {
    let kind: EventKind

    var body: some View {
        Circle()
            .fill(AppTheme.color(for: kind))
            .frame(width: AppTheme.spacing, height: AppTheme.spacing)
    }
}
