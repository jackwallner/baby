import Foundation

/// The last entry a widget, a control or Siri logged, offered back on the
/// one-button widgets for a few seconds. There is no confirm before a log:
/// the tap logs, and the tile turns into Undo. Undo removes exactly this
/// entry by its id, so a late tap can never take a different one.
struct WidgetUndo: Codable, Equatable, Sendable {
    var eventID: UUID
    var kind: EventKind
    var loggedAt: Date
    /// Feed timers this log ended, reopened by Undo.
    var closedIDs: [UUID] = []

    /// How long the tile shows Undo.
    static let showFor: TimeInterval = 10
    /// How long a tap on Undo still counts. Longer than it shows, because
    /// WidgetKit can redraw the tile a little late; never so long that an
    /// Undo left on screen by a missed redraw removes an old entry.
    static let acceptFor: TimeInterval = 60

    var hidesAt: Date { loggedAt.addingTimeInterval(Self.showFor) }

    func isShowing(at now: Date) -> Bool {
        now >= loggedAt.addingTimeInterval(-1) && now < hidesAt
    }

    func isAcceptable(at now: Date) -> Bool {
        now >= loggedAt.addingTimeInterval(-5) && now < loggedAt.addingTimeInterval(Self.acceptFor)
    }

    /// The Undo to show right now, if any.
    static func showing(at now: Date = .now) -> WidgetUndo? {
        guard let undo = load(), undo.isShowing(at: now) else { return nil }
        return undo
    }

    static func load() -> WidgetUndo? {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.widgetUndo) else { return nil }
        return try? JSONDecoder().decode(WidgetUndo.self, from: data)
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: AppGroup.Key.widgetUndo)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetUndo)
    }
}
