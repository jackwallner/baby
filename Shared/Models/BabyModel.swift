import CoreData
import Foundation

/// What a tap logs. The raw values are stored in Core Data and in every
/// payload between processes, so they never change.
enum EventKind: String, CaseIterable, Codable, Sendable {
    case feed
    case wet
    case dirty
    case sleep
    /// Reporting-only kinds. Logged from the editor, never from the four buttons.
    case weight

    var label: String {
        switch self {
        case .feed: "Feed"
        case .wet: "Wet"
        case .dirty: "Dirty"
        case .sleep: "Sleep"
        case .weight: "Weight"
        }
    }

    var symbolName: String {
        switch self {
        case .feed: "fork.knife"
        case .wet: "drop.fill"
        case .dirty: "drop.triangle.fill"
        case .sleep: "moon.fill"
        case .weight: "scalemass.fill"
        }
    }

    var isDiaper: Bool { self == .wet || self == .dirty }

    /// Kinds that can be running (started, not yet ended).
    var canRun: Bool { self == .feed || self == .sleep }
}

enum FeedSide: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case bottle

    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .bottle: "Bottle"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: "L"
        case .right: "R"
        case .bottle: "Bottle"
        }
    }

    /// The side a parent is most likely to offer next: the other breast after
    /// a breastfeed, the bottle again after a bottle.
    var next: FeedSide {
        switch self {
        case .left: .right
        case .right: .left
        case .bottle: .bottle
        }
    }
}

enum StoolColor: String, CaseIterable, Codable, Sendable {
    case black
    case green
    case yellow
    case brown
    case other

    var label: String {
        switch self {
        case .black: "Black"
        case .green: "Green"
        case .yellow: "Yellow"
        case .brown: "Brown"
        case .other: "Other"
        }
    }
}

/// The Core Data model, built in code so the whole schema is readable in one
/// place and reviewed in diffs. Every attribute is optional or defaulted and
/// every relationship has an inverse, which is what CloudKit mirroring needs.
enum BabyModel {
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        let child = NSEntityDescription()
        child.name = "Child"
        child.managedObjectClassName = "Child"

        let event = NSEntityDescription()
        event.name = "LogEvent"
        event.managedObjectClassName = "LogEvent"

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            return a
        }

        let childEvents = NSRelationshipDescription()
        childEvents.name = "events"
        childEvents.destinationEntity = event
        childEvents.minCount = 0
        childEvents.maxCount = 0
        childEvents.deleteRule = .cascadeDeleteRule
        childEvents.isOptional = true

        let eventChild = NSRelationshipDescription()
        eventChild.name = "child"
        eventChild.destinationEntity = child
        eventChild.minCount = 0
        eventChild.maxCount = 1
        eventChild.deleteRule = .nullifyDeleteRule
        eventChild.isOptional = true

        childEvents.inverseRelationship = eventChild
        eventChild.inverseRelationship = childEvents

        child.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("birthDate", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("lastVisitAt", .dateAttributeType),
            childEvents,
        ]
        event.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("side", .stringAttributeType),
            attribute("amount", .doubleAttributeType, optional: false, defaultValue: 0),
            attribute("stoolColor", .stringAttributeType),
            attribute("note", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            eventChild,
        ]

        let model = NSManagedObjectModel()
        model.entities = [child, event]
        return model
    }()
}

@objc(Child)
final class Child: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var birthDate: Date?
    @NSManaged var createdAt: Date?
    /// The last pediatrician visit, which is what the summary counts from.
    @NSManaged var lastVisitAt: Date?
    @NSManaged var events: NSSet?

    /// Never empty: the Now screen, the widgets and the PDF all need a word.
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Baby" : trimmed
    }

    var eventCount: Int { events?.count ?? 0 }

    /// Day 1 is the calendar day of birth. `nil` before birth or with no date.
    func dayOfLife(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        return DateHelpers.dayOfLife(birthDate: birthDate, on: date, calendar: calendar)
    }

    @discardableResult
    static func make(in context: NSManagedObjectContext, name: String?, birthDate: Date?) -> Child {
        let child = Child(context: context)
        child.id = UUID()
        child.name = name
        child.birthDate = birthDate
        child.createdAt = .now
        return child
    }
}

@objc(LogEvent)
final class LogEvent: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var kind: String?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var side: String?
    /// Millilitres for a bottle, grams for a weight. Zero means "not entered".
    @NSManaged var amount: Double
    @NSManaged var stoolColor: String?
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var child: Child?

    var eventKind: EventKind {
        get { EventKind(rawValue: kind ?? "") ?? .feed }
        set { kind = newValue.rawValue }
    }

    var feedSide: FeedSide? {
        get { side.flatMap(FeedSide.init(rawValue:)) }
        set { side = newValue?.rawValue }
    }

    var stool: StoolColor? {
        get { stoolColor.flatMap(StoolColor.init(rawValue:)) }
        set { stoolColor = newValue?.rawValue }
    }

    var start: Date { startedAt ?? createdAt ?? .distantPast }

    /// Started and not ended: a feed or sleep still in progress. An instant
    /// feed is stored with `endedAt == startedAt`, so "no end" always means
    /// running for the kinds that can run.
    var isRunning: Bool { eventKind.canRun && endedAt == nil }

    var duration: TimeInterval? {
        guard let endedAt, let startedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// A short second line for lists and the undo toast: "Left", "Bottle 60 ml",
    /// "Yellow", "1h 05m".
    var detailText: String? {
        switch eventKind {
        case .feed:
            var parts: [String] = []
            if let feedSide { parts.append(feedSide.label) }
            if feedSide == .bottle, amount > 0 { parts.append(Format.millilitres(amount)) }
            if let duration, duration >= 60 { parts.append(Format.compactDuration(duration)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .dirty:
            return stool?.label
        case .sleep:
            if isRunning { return "Asleep" }
            if let duration { return Format.duration(duration) }
            return nil
        case .wet:
            return nil
        case .weight:
            return amount > 0 ? Format.grams(amount) : nil
        }
    }

    static func make(in context: NSManagedObjectContext, child: Child, kind: EventKind, at date: Date) -> LogEvent {
        let event = LogEvent(context: context)
        event.id = UUID()
        event.eventKind = kind
        event.startedAt = date
        event.createdAt = .now
        event.updatedAt = .now
        event.child = child
        return event
    }
}

/// One wrist action on its way to the phone.
struct WatchLogPayload: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case log
        case startSleep
        case stopSleep
    }

    var id: UUID
    var action: Action
    var kind: EventKind
    var side: FeedSide?
    var at: Date

    static let key = "watchLog"

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    init(id: UUID = UUID(), action: Action, kind: EventKind, side: FeedSide? = nil, at: Date = .now) {
        self.id = id
        self.action = action
        self.kind = kind
        self.side = side
        self.at = at
    }

    init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.key] as? Data,
              let payload = try? JSONDecoder().decode(WatchLogPayload.self, from: data) else { return nil }
        self = payload
    }
}
