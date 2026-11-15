import Foundation

/// Which of the four buttons this family uses. A kind that is turned off
/// leaves Now, the widgets, the Watch, History and the reports; its entries
/// stay in the log and come back when it is turned on again. Weight is not a
/// button and is always kept. Stored in the App Group so the widgets read it,
/// and carried to the Watch with the summary.
struct TrackedKinds: Equatable, Sendable {
    /// The four buttons, in their fixed order.
    static let buttons: [EventKind] = [.feed, .wet, .dirty, .sleep]

    var hidden: Set<EventKind>
    /// The built-in Pump button, off until turned on.
    var pump: Bool
    /// The parent's own buttons, by name, in the order added.
    var custom: [String]

    /// Pump and custom buttons together, so the home screen keeps its fit.
    static let maxExtras = 4

    static let all = TrackedKinds(hidden: [])

    static var current: TrackedKinds {
        let defaults = AppGroup.defaults
        let raw = defaults.stringArray(forKey: AppGroup.Key.hiddenKinds) ?? []
        return TrackedKinds(
            hidden: Set(raw.compactMap(EventKind.init(rawValue:))),
            pump: defaults.bool(forKey: AppGroup.Key.showsPump),
            custom: defaults.stringArray(forKey: AppGroup.Key.customButtons) ?? []
        )
    }

    init(hidden: Set<EventKind>, pump: Bool = false, custom: [String] = []) {
        // At least one button always stays, and weight is never hidden.
        let valid = hidden.intersection(Self.buttons)
        self.hidden = valid.count >= Self.buttons.count ? [] : valid
        self.pump = pump
        var names: [String] = []
        for name in custom.map(Self.clean) where !name.isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        self.custom = Array(names.prefix(Self.maxExtras - (pump ? 1 : 0)))
    }

    /// Custom entries always stay in the log: a button that was removed
    /// still leaves what was logged with it in History.
    func contains(_ kind: EventKind) -> Bool {
        switch kind {
        case .pump: pump
        case .custom: true
        default: !hidden.contains(kind)
        }
    }

    /// The extra buttons below the four, in order: Pump first, then the
    /// parent's own.
    var extras: [ExtraButton] {
        (pump ? [ExtraButton.pump] : []) + custom.map(ExtraButton.custom)
    }

    var canAddExtra: Bool { extras.count < Self.maxExtras }

    static let maxNameLength = 24

    static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// The buttons still shown, in order.
    var buttons: [EventKind] { Self.buttons.filter(contains) }

    var tracksDiapers: Bool { contains(.wet) || contains(.dirty) }

    /// The kinds in sentence form, for headings: "Feeds, diapers and sleep".
    var headline: String {
        switch (contains(.feed), tracksDiapers, contains(.sleep)) {
        case (true, true, true): String(localized: "Feeds, diapers and sleep")
        case (true, true, false): String(localized: "Feeds and diapers")
        case (true, false, true): String(localized: "Feeds and sleep")
        case (false, true, true): String(localized: "Diapers and sleep")
        case (true, false, false): String(localized: "Feeds")
        case (false, true, false): String(localized: "Diapers")
        case (false, false, true): String(localized: "Sleep")
        case (false, false, false): ""
        }
    }

    var metadataHeadline: String {
        switch (contains(.feed), tracksDiapers, contains(.sleep)) {
        case (true, true, true): String(localized: "feeds, diapers and sleep")
        case (true, true, false): String(localized: "feeds and diapers")
        case (true, false, true): String(localized: "feeds and sleep")
        case (false, true, true): String(localized: "diapers and sleep")
        case (true, false, false): String(localized: "feeds")
        case (false, true, false): String(localized: "diapers")
        case (false, false, true): String(localized: "sleep")
        case (false, false, false): ""
        }
    }

    func store() {
        let defaults = AppGroup.defaults
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: AppGroup.Key.hiddenKinds)
        defaults.set(pump, forKey: AppGroup.Key.showsPump)
        defaults.set(custom, forKey: AppGroup.Key.customButtons)
    }
}

/// One button below the four: Pump, or one the parent named.
enum ExtraButton: Hashable, Sendable {
    case pump
    case custom(String)

    var kind: EventKind {
        switch self {
        case .pump: .pump
        case .custom: .custom
        }
    }

    var name: String? {
        if case let .custom(name) = self { return name }
        return nil
    }

    var label: String { name ?? kind.label }

    var id: String {
        switch self {
        case .pump: "pump"
        case let .custom(name): "custom.\(name)"
        }
    }
}

/// Which feeds this family gives: breast (Left and Right), bottle, or both.
/// With only one, the Feed button needs no side question: a bottle-only
/// family's tap is a bottle. Stored in the App Group for the widgets, and
/// carried to the Watch with the summary.
struct FeedTypes: Equatable, Sendable {
    var breast: Bool
    var bottle: Bool

    static let all = FeedTypes(breast: true, bottle: true)

    static var current: FeedTypes {
        let raw = AppGroup.defaults.stringArray(forKey: AppGroup.Key.hiddenFeedTypes) ?? []
        return FeedTypes(hidden: Set(raw.compactMap(FeedSide.init(rawValue:))))
    }

    init(breast: Bool, bottle: Bool) {
        // At least one type always stays.
        self.breast = breast || !bottle
        self.bottle = bottle
    }

    init(hidden: Set<FeedSide>) {
        self.init(breast: !hidden.contains(.left), bottle: !hidden.contains(.bottle))
    }

    /// The side choices shown, in order.
    var sides: [FeedSide] { (breast ? [.left, .right] : []) + (bottle ? [.bottle] : []) }

    /// The side a bare Feed tap logs: Bottle for a bottle-only family, else
    /// none (which breast is the parent's answer, after the tap).
    var tapSide: FeedSide? { breast ? nil : .bottle }

    var hidden: [FeedSide] { FeedSide.allCases.filter { !sides.contains($0) } }

    func store() {
        AppGroup.defaults.set(hidden.map(\.rawValue), forKey: AppGroup.Key.hiddenFeedTypes)
    }
}
