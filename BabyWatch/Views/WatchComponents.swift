import SwiftUI
import WatchKit

/// Every wrist button: a kind-tinted pill that dips when pressed.
struct WatchTapStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The log controls, in the phone's order: feed sides, the diaper pair, sleep.
/// `at` logs in the past (Log earlier); nil logs now. The side to offer next
/// is filled stronger and, on watchOS 11, answers the double-tap gesture.
struct WatchLogGrid: View {
    @EnvironmentObject private var store: WatchStore
    let now: Date
    var at: Date? = nil
    var onLog: () -> Void = {}

    private var summary: NowSummary { store.summary }
    private var tracked: TrackedKinds { summary.tracked }

    var body: some View {
        VStack(spacing: AppTheme.hairSpacing) {
            if tracked.contains(.feed) {
                HStack(spacing: AppTheme.hairSpacing) {
                    ForEach(FeedSide.allCases, id: \.self) { side in
                        feedButton(side)
                    }
                }
            }
            if tracked.tracksDiapers {
                HStack(spacing: AppTheme.hairSpacing) {
                    ForEach([EventKind.wet, .dirty].filter(tracked.contains), id: \.self) { kind in
                        button(kind.label, symbol: kind.symbolName, kind: kind) { store.log(kind, at: at ?? .now) }
                    }
                }
            }
            if tracked.contains(.sleep) {
                sleepButton
            }
        }
    }

    private func feedButton(_ side: FeedSide) -> some View {
        // The other breast after a breastfeed, the bottle again after a bottle.
        let next = at == nil && !summary.feedSides.isEmpty && side == summary.suggestedSide
        return button(side.label, symbol: nil, kind: .feed, emphasized: next) {
            store.log(.feed, side: side, at: at ?? .now)
        }
        .accessibilityLabel(next ? "Feed, \(side.label), next" : "Feed, \(side.label)")
        .primaryGesture(at == nil && side == summary.suggestedSide)
    }

    private var sleepButton: some View {
        let asleep = summary.runningSleepStart
        let title = asleep.map { "Wake · \(WatchGlance.elapsed(since: $0, now: now))" } ?? "Sleep"
        return button(title, symbol: asleep == nil ? EventKind.sleep.symbolName : "sun.max.fill", kind: .sleep,
                      emphasized: asleep != nil, height: AppTheme.watchCompactButtonHeight) {
            store.toggleSleep(at: at ?? .now)
        }
        .accessibilityLabel(asleep == nil ? "Start sleep" : "Wake, asleep \(Format.compactDuration(now.timeIntervalSince(asleep ?? now)))")
    }

    private func button(
        _ title: String,
        symbol: String?,
        kind: EventKind,
        emphasized: Bool = false,
        height: CGFloat = AppTheme.watchButtonHeight,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            onLog()
        } label: {
            HStack(spacing: AppTheme.hairSpacing) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.color(for: kind))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, AppTheme.hairSpacing)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(AppTheme.buttonShape)
        }
        .buttonStyle(WatchTapStyle(fill: emphasized ? AppTheme.strongFill(for: kind) : AppTheme.fill(for: kind)))
        .accessibilityValue(at.map { "\(Format.compactDuration(now.timeIntervalSince($0))) ago" } ?? "")
    }
}

private extension View {
    /// The watchOS 11 double tap (thumb and finger) logs the next side, for a
    /// parent with a baby in the other arm.
    @ViewBuilder
    func primaryGesture(_ enabled: Bool) -> some View {
        if enabled, #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

/// "Fed · Left" over "2h 14m": one column of the glance.
struct WatchGlanceColumn: View {
    let label: String
    let symbol: String
    let kind: EventKind
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(label, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.color(for: kind))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The answer to "when did she last eat, and which side", and the last
/// diaper beside it. Sleep shows on its own button while it runs.
struct WatchGlance: View {
    let summary: NowSummary
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.tightSpacing) {
            if summary.tracked.contains(.feed) { feed }
            if summary.tracked.tracksDiapers { diaper }
            if !summary.tracked.contains(.feed), !summary.tracked.tracksDiapers { sleep }
        }
    }

    private var feed: some View {
        let running = summary.runningFeedStart
        let since = running ?? summary.lastFeedAt
        let sides = FeedSide.label(for: running != nil ? summary.runningSides : summary.feedSides)
        let verb = running != nil ? "Feeding" : "Fed"
        return WatchGlanceColumn(
            label: sides.map { "\(verb) · \($0)" } ?? verb,
            symbol: EventKind.feed.symbolName,
            kind: .feed,
            value: since.map { Self.elapsed(since: $0, now: now) } ?? "Not yet"
        )
    }

    private var diaper: some View {
        let kind = summary.lastDiaperKind ?? .wet
        return WatchGlanceColumn(
            label: summary.lastDiaperKind?.label ?? "Diaper",
            symbol: kind.symbolName,
            kind: kind,
            value: summary.lastDiaperAt.map { Self.elapsed(since: $0, now: now) } ?? "Not yet"
        )
    }

    private var sleep: some View {
        let asleep = summary.runningSleepStart
        return WatchGlanceColumn(
            label: asleep != nil ? "Asleep" : "Awake",
            symbol: asleep != nil ? EventKind.sleep.symbolName : "sun.max.fill",
            kind: .sleep,
            value: (asleep ?? summary.lastWokeAt).map { Self.elapsed(since: $0, now: now) } ?? "Not yet"
        )
    }

    /// "just now", "12m", "2h 14m".
    static func elapsed(since date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "just now" : Format.compactDuration(seconds)
    }
}

/// The tap just made, with Undo while it can still be taken back.
struct WatchConfirmationBanner: View {
    @EnvironmentObject private var store: WatchStore
    let confirmation: WatchStore.Confirmation

    var body: some View {
        HStack(spacing: AppTheme.tightSpacing) {
            Image(systemName: confirmation.canUndo ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(confirmation.canUndo ? AppTheme.color(for: confirmation.kind) : AppTheme.ink2)
                .accessibilityHidden(true)
            Text(confirmation.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if confirmation.canUndo {
                Button {
                    store.undo()
                } label: {
                    Text("Undo")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.buttonInk)
                        .fixedSize()
                        .padding(.horizontal, AppTheme.spacing)
                        .frame(minHeight: AppTheme.watchCompactButtonHeight)
                        .contentShape(AppTheme.buttonShape)
                }
                .buttonStyle(WatchTapStyle(fill: AppTheme.actionFill))
                .accessibilityHint("Removes this entry")
                    .accessibilityHint("Removes this entry")
            }
        }
        .padding(.leading, AppTheme.spacing)
        .padding(.trailing, confirmation.canUndo ? AppTheme.hairSpacing : AppTheme.spacing)
        .padding(.vertical, AppTheme.hairSpacing)
        .frame(minHeight: AppTheme.watchButtonHeight)
        .background(AppTheme.cardElevated, in: AppTheme.buttonShape)
        .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
        .onTapGesture { if !confirmation.canUndo { store.dismissConfirmation() } }
    }
}
