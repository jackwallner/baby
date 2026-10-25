import SwiftUI
import UIKit

/// The small vocabulary every screen is built from, so no view invents its own
/// card, button or press state.

struct CardBackground: ViewModifier {
    var elevated = false
    var padding = AppTheme.looseSpacing
    /// Nil: the same as the sides.
    var verticalPadding: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, verticalPadding ?? padding)
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
        let isDark = colorScheme == .dark
        content
            .background(AppTheme.card, in: AppTheme.cardShape)
            .overlay(
                CardEdge(width: isDark ? AppTheme.hairlineWidth : AppTheme.outlineWidth,
                         offset: isDark ? 0 : AppTheme.shadowOffset)
                    .fill(AppTheme.edge)
            )
    }
}

/// Outline and offset shadow as one path drawn over the card. A stroke laid
/// over a continuous-corner fill is not concentric with it, so the fill pokes
/// past the stroke at the corners and a light seam shows against the shadow.
private struct CardEdge: Shape {
    var width: CGFloat
    var offset: CGFloat

    func path(in rect: CGRect) -> Path {
        let outer = AppTheme.cardShape.path(in: rect)
        // Stroking the outline itself keeps the width even through the
        // corners, which an inset continuous corner does not.
        let band = outer.strokedPath(StrokeStyle(lineWidth: width * 2)).normalized(eoFill: false)
        let ring = outer.subtracting(outer.subtracting(band))
        guard offset != 0 else { return ring }
        return ring.union(outer.offsetBy(dx: offset, dy: offset).subtracting(outer))
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

    func card(elevated: Bool = false, padding: CGFloat = AppTheme.looseSpacing, verticalPadding: CGFloat? = nil) -> some View {
        modifier(CardBackground(elevated: elevated, padding: padding, verticalPadding: verticalPadding))
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

/// Spoken confirmations. A tap's toast sits at the top of the screen, far
/// from where VoiceOver's focus is, so what changed is also said aloud.
enum VoiceOver {
    static var isRunning: Bool { UIAccessibility.isVoiceOverRunning }

    static func say(_ text: String) {
        guard isRunning else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

extension View {
    /// Undo stays above the controls. Applied once around all tabs so History
    /// deletion can be undone too. Where a screen has bar buttons (back, add
    /// entry) it insets to clear them; Log has none, so it uses the margins.
    func undoToast(clearsBarButtons: Bool) -> some View { modifier(UndoToastOverlay(clearsBarButtons: clearsBarButtons)) }
}

private struct UndoToastOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var events: EventStore
    let clearsBarButtons: Bool
    @State private var showUndoError = false

    /// One transaction for everything Undo changes: the toast folds away
    /// while the card, the buttons and the totals settle back together.
    private func undo() {
        Haptics.selected()
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation) {
            showUndoError = !events.undoLast()
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // The animation belongs to the toast alone. On the whole stack
                // it springs every list change made in the same transaction,
                // which fought the row's own swipe-to-delete animation.
                ZStack(alignment: .top) {
                    if let logged = events.lastLogged {
                        UndoToast(logged: logged, undo: undo)
                            .frame(maxWidth: AppTheme.toastWidth)
                            .padding(.leading, clearsBarButtons ? AppTheme.toastLeadingInset : AppTheme.margin)
                            .padding(.trailing, clearsBarButtons ? AppTheme.toastTrailingInset : AppTheme.margin)
                            .gesture(DragGesture(minimumDistance: AppTheme.tightSpacing).onEnded { value in
                                if value.translation.height < 0 { events.dismissUndo() }
                            })
                            // In from the top; out by shrinking in place, so a
                            // toast leaving never slides under the status bar.
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                    }
                }
                .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: events.lastLogged)
            }
            .onChange(of: events.lastLogged) { _, logged in
                guard let logged else { return }
                VoiceOver.say("\(UndoToast(logged: logged, undo: {}).title). Undo is at the top of the screen.")
            }
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
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, AppTheme.spacing)
        .padding(.trailing, AppTheme.spacing)
        .background(AppTheme.cardElevated, in: AppTheme.cardShape)
        .graphicBorder()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
    }

    /// A whole sleep added from the editor, not one just begun.
    private var isFinishedSleep: Bool {
        logged.kind == .sleep && !logged.reopensTimer && logged.detail != nil && logged.detail != "Asleep"
    }

    /// Short, in the buttons' own words: the toast can sit between two bar buttons.
    var title: String {
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
        if !logged.alsoLogged.isEmpty {
            return "Logged feed, \(EventKind.wet.label.lowercased()) and \(EventKind.dirty.label.lowercased())" + backdated
        }
        let base: String = switch logged.kind {
        case .feed: "Logged feed"
        case .wet, .dirty: "Logged \(logged.kind.label.lowercased())"
        case .sleep: logged.reopensTimer ? "Sleep ended" : (isFinishedSleep ? "Logged sleep" : "Sleep started")
        case .weight: "Logged weight"
        }
        if logged.kind == .sleep, isFinishedSleep, let detail = logged.detail { return "\(base) · \(detail)" + backdated }
        if logged.kind == .sleep { return base + backdated }
        // A finished feed ended the running feed timer. Say so, so the timer
        // vanishing from Now is explained and Undo is known to bring it back.
        if logged.kind == .feed, !logged.closedTimers.isEmpty { return "\(base), timer ended" }
        if let detail = logged.detail, !detail.isEmpty { return "\(base) · \(detail)" + backdated }
        return base + backdated
    }

    /// " · 7:15 AM" when the tap logged at a wound-back time, so the parent
    /// sees the entry landed where they meant it to.
    private var backdated: String {
        guard let eventAt = logged.eventAt, logged.at.timeIntervalSince(eventAt) > 90 else { return "" }
        return " · \(LogClock.label(for: eventAt, now: logged.at))"
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
    var size: CGFloat = AppTheme.spacing

    var body: some View {
        Circle()
            .fill(AppTheme.color(for: kind))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
