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
            .graphicBorder()
    }
}

/// The physical card edge. Light gets an ink outline and a hard offset shadow.
/// Dark themes drop the shadow (a shadow lighter than the page reads as a
/// glow) and keep a hairline, so surfaces separate by tone.
struct GraphicBorder: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                AppTheme.cardShape
                    .fill(AppTheme.card)
                    .shadow(color: AppTheme.shadow, radius: 0, x: AppTheme.shadowOffset, y: AppTheme.shadowOffset)
            }
            .overlay(AppTheme.cardShape.strokeBorder(AppTheme.edge, lineWidth: colorScheme == .dark ? AppTheme.hairlineWidth : AppTheme.outlineWidth))
    }
}

extension View {
    func graphicBorder() -> some View {
        modifier(GraphicBorder())
    }

    /// A list or form row on the theme: card fill and a warm separator.
    func themedRow() -> some View {
        listRowBackground(AppTheme.card)
            .listRowSeparatorTint(AppTheme.separator)
    }

    /// The compact date picker draws a cool grey capsule with white text that
    /// no UIKit appearance reaches. Night light multiplies it into warm ink.
    func themedDatePicker() -> some View {
        modifier(NightLightMultiply())
    }

    func card(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }

    /// A card or row that answers back under the finger.
    func pressableCard() -> some View {
        buttonStyle(PressableCardStyle())
    }
}

private struct NightLightMultiply: ViewModifier {
    @Environment(\.nightLight) private var nightLight

    func body(content: Content) -> some View {
        content.colorMultiply(nightLight ? AppTheme.ink : .white)
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
            .foregroundStyle(AppTheme.buttonInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing)
            .frame(minHeight: AppTheme.ctaHeight)
            .background(AppTheme.actionFill, in: AppTheme.buttonShape)
            .graphicBorder()
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: configuration.isPressed)
    }
}

/// A second action beside a primary one: card fill, accent label, same edge.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing)
            .frame(minHeight: AppTheme.ctaHeight)
            .background(AppTheme.card, in: AppTheme.buttonShape)
            .graphicBorder()
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

extension View {
    /// The Undo toast pinned to the top, in the navigation bar between History
    /// and More, so it covers only the title: never the log controls and never
    /// the bar buttons. Applied once around the navigation stack.
    func undoToast() -> some View { modifier(UndoToastOverlay()) }
}

private struct UndoToastOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var events: EventStore
    @State private var showUndoError = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let logged = events.lastLogged {
                    UndoToast(logged: logged, undo: { showUndoError = !events.undoLast() })
                        .frame(maxWidth: AppTheme.toastWidth)
                        .padding(.horizontal, AppTheme.toastSideInset)
                        .gesture(DragGesture(minimumDistance: AppTheme.tightSpacing).onEnded { value in
                            if value.translation.height < 0 { events.dismissUndo() }
                        })
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.lastLogged)
            .alert("Couldn't undo this entry", isPresented: $showUndoError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The entry is unchanged. Please try again or edit it in History.")
            }
    }
}

/// The top toast after a tap or a delete: what happened, and Undo.
struct UndoToast: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let logged: EventStore.LoggedEvent
    let undo: () -> Void

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.hairSpacing)) : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.color(for: logged.kind))
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
        }
        .padding(.leading, AppTheme.spacing)
        .padding(.trailing, AppTheme.spacing)
        .background(AppTheme.cardElevated, in: AppTheme.cardShape)
        .graphicBorder()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
    }

    /// Short, in the buttons' own words: the toast sits between two bar buttons.
    private var title: String {
        if logged.deleted != nil {
            let base: String = switch logged.kind {
            case .feed: "Deleted feed"
            case .wet, .dirty: "Deleted \(logged.kind.label.lowercased())"
            case .sleep: "Deleted sleep"
            case .weight: "Deleted weight"
            }
            guard let detail = logged.detail, !detail.isEmpty else { return base }
            return "\(base) · \(detail)"
        }
        let base: String = switch logged.kind {
        case .feed: "Logged feed"
        case .wet, .dirty: "Logged \(logged.kind.label.lowercased())"
        case .sleep: logged.reopensTimer ? "Sleep ended" : "Sleep started"
        case .weight: "Logged weight"
        }
        if logged.kind == .sleep { return base }
        // A finished feed ended the running feed timer. Say so, so the timer
        // vanishing from Now is explained and Undo is known to bring it back.
        if logged.kind == .feed, !logged.closedTimers.isEmpty { return "\(base), timer ended" }
        if let detail = logged.detail, !detail.isEmpty { return "\(base) · \(detail)" }
        return base
    }
}

/// A quiet icon tile shared by summaries, history and onboarding.
struct KindIcon: View {
    let kind: EventKind

    var body: some View {
        CareGraphic(kind: kind)
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
