import AppIntents
import SwiftUI
import WidgetKit

// MARK: - One-button widgets

/// One kind, one tap: a Lock Screen circle or a Home Screen tile that logs a
/// feed, a pee or a poop the moment it is touched. Three separate widgets
/// rather than one configurable one, so each shows up ready to place in the
/// gallery with nothing to set up.
struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let kind: EventKind
    let entry: BabyEntry

    private var s: NowSummary { entry.summary }

    /// This tile's own tap, for the few seconds Undo is offered.
    private var undo: WidgetUndo? {
        guard let undo = entry.undo, undo.kind == kind, undo.isShowing(at: entry.date) else { return nil }
        return undo
    }

    var body: some View {
        if !s.tracked.contains(kind) {
            offFace
        } else if let undo {
            Button(intent: UndoWidgetLogIntent(eventID: undo.eventID)) {
                undoFace.contentShape(Rectangle()).invalidatableContent()
            }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo \(kind.label.lowercased())")
                .accessibilityValue("Logged just now")
        } else {
            logButton
        }
    }

    /// The button was turned off in the app. The tile stays put, quietly,
    /// rather than logging something no screen shows; a tap opens the app.
    @ViewBuilder
    private var offFace: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: kind.symbolName)
                    .font(.title3.weight(.semibold))
                    .opacity(0.4)
            }
            .accessibilityLabel("\(kind.label) is turned off in Settings")
        default:
            VStack(spacing: AppTheme.tightSpacing) {
                CareGraphic(kind: kind)
                    .opacity(0.5)
                Text(kind.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                Text("Off in Settings")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.cardElevated, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kind.label) is turned off in Settings")
        }
    }

    /// After a tap: the tile says it logged, and a second tap takes it back.
    @ViewBuilder
    private var undoFace: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                    Text("Undo")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .widgetAccentable()
        default:
            VStack(spacing: AppTheme.tightSpacing) {
                CareGraphic(kind: kind)
                Label("Logged", systemImage: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
        }
    }

    private var logButton: some View {
        Button(intent: WidgetLogEventIntent(what: kind.logChoice, childID: s.childID)) {
            logFace.contentShape(Rectangle()).invalidatableContent()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.label.lowercased())")
        .accessibilityValue(detail)
    }

    @ViewBuilder
    private var logFace: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: kind.symbolName)
                        .font(.title3.weight(.semibold))
                    Text(kind.label)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .widgetAccentable()
        default:
            VStack(spacing: AppTheme.tightSpacing) {
                CareGraphic(kind: kind)
                Text(kind.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
        }
    }

    /// Under the tile's label: what the tap will change.
    private var detail: String {
        switch kind {
        case .feed:
            if s.isFeeding { return "Feeding now" }
            guard let last = s.lastFeedAt else { return "Tap to log" }
            return "Last \(Format.ago(last, now: entry.date))"
        case .wet: return "\(s.todayWet) \(period)"
        case .dirty: return "\(s.todayDirty) \(period)"
        default: return ""
        }
    }

    /// "today", "since 6 AM", "in 24 hours": the phone's totals window.
    private var period: String {
        switch s.window {
        case .last24Hours: "in 24 hours"
        case .day(0): "today"
        case .day(let hour): "since \(TotalsWindow.hourLabel(hour))"
        }
    }
}

@MainActor
private func quickLogConfiguration(kind: EventKind, widgetKind: String, name: String) -> some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: BabyProvider()) { entry in
        QuickLogWidgetView(kind: kind, entry: entry)
            .containerBackground(AppTheme.card, for: .widget)
    }
    .configurationDisplayName(name)
    .description("One tap logs it, from the Lock Screen or the Home Screen, without opening the app.")
    .supportedFamilies([.accessoryCircular, .systemSmall])
}

struct QuickFeedWidget: Widget {
    var body: some WidgetConfiguration {
        quickLogConfiguration(kind: .feed, widgetKind: AppGroup.WidgetKind.quickFeed, name: "Feed button")
    }
}

struct QuickWetWidget: Widget {
    var body: some WidgetConfiguration {
        quickLogConfiguration(kind: .wet, widgetKind: AppGroup.WidgetKind.quickWet, name: "\(EventKind.wet.label) button")
    }
}

struct QuickDirtyWidget: Widget {
    var body: some WidgetConfiguration {
        quickLogConfiguration(kind: .dirty, widgetKind: AppGroup.WidgetKind.quickDirty, name: "\(EventKind.dirty.label) button")
    }
}

// MARK: - Controls

/// Lock Screen and Control Center buttons (iOS 18): put Feed, Pee or Poop in
/// place of the flashlight or camera, or on the Action button.
@available(iOS 18.0, *)
struct FeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppGroup.WidgetKind.feedControl, provider: LogControlProvider(kind: .feed)) { result in
            ControlWidgetButton(action: LogEventIntent(what: .feed)) {
                Label("Log feed", systemImage: EventKind.feed.symbolName)
            } actionLabel: { isActive in
                ControlConfirmation(kind: .feed, isActive: isActive, result: result)
            }
        }
        .displayName("Log feed")
        .description("Logs a feed with one tap.")
    }
}

@available(iOS 18.0, *)
struct WetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppGroup.WidgetKind.wetControl, provider: LogControlProvider(kind: .wet)) { result in
            ControlWidgetButton(action: LogEventIntent(what: .wet)) {
                Label("Log \(EventKind.wet.label.lowercased())", systemImage: EventKind.wet.symbolName)
            } actionLabel: { isActive in
                ControlConfirmation(kind: .wet, isActive: isActive, result: result)
            }
        }
        .displayName("Log pee diaper")
        .description("Logs a pee (wet) diaper with one tap.")
    }
}

@available(iOS 18.0, *)
struct DirtyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AppGroup.WidgetKind.dirtyControl, provider: LogControlProvider(kind: .dirty)) { result in
            ControlWidgetButton(action: LogEventIntent(what: .dirty)) {
                Label("Log \(EventKind.dirty.label.lowercased())", systemImage: EventKind.dirty.symbolName)
            } actionLabel: { isActive in
                ControlConfirmation(kind: .dirty, isActive: isActive, result: result)
            }
        }
        .displayName("Log poop diaper")
        .description("Logs a poop (dirty) diaper with one tap.")
    }
}

/// What a control shows in the system overlay once pressed, so a tap on a
/// locked phone visibly lands.
@available(iOS 18.0, *)
private struct ControlConfirmation: View {
    let kind: EventKind
    let isActive: Bool
    let result: WidgetLogResult?

    private var noun: String { kind == .feed ? "feed" : "\(kind.label.lowercased()) diaper" }

    var body: some View {
        if !TrackedKinds.current.contains(kind) {
            Label("\(kind.label) is off in Settings", systemImage: kind.symbolName)
        } else if isActive {
            Label("Logging \(noun)", systemImage: kind.symbolName)
        } else if let result {
            Label(result.succeeded ? "Logged \(noun)" : "Not logged. Open Baby Tracker.",
                  systemImage: result.succeeded ? "checkmark" : "exclamationmark.circle")
        } else {
            Label("Log \(noun)", systemImage: kind.symbolName)
        }
    }
}

@available(iOS 18.0, *)
private struct LogControlProvider: ControlValueProvider {
    let kind: EventKind
    var previewValue: WidgetLogResult? { nil }
    func currentValue() async throws -> WidgetLogResult? { WidgetLogResult.load(for: kind) }
}

private extension EventKind {
    var logChoice: LogChoice {
        switch self {
        case .feed: .feed
        case .wet: .wet
        case .dirty: .dirty
        default: .sleep
        }
    }
}
