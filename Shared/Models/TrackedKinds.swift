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

    static let all = TrackedKinds(hidden: [])

    static var current: TrackedKinds {
        let raw = AppGroup.defaults.stringArray(forKey: AppGroup.Key.hiddenKinds) ?? []
        return TrackedKinds(hidden: Set(raw.compactMap(EventKind.init(rawValue:))))
    }

    init(hidden: Set<EventKind>) {
        // At least one button always stays, and weight is never hidden.
        let valid = hidden.intersection(Self.buttons)
        self.hidden = valid.count >= Self.buttons.count ? [] : valid
    }

    func contains(_ kind: EventKind) -> Bool { !hidden.contains(kind) }

    /// The buttons still shown, in order.
    var buttons: [EventKind] { Self.buttons.filter(contains) }

    var tracksDiapers: Bool { contains(.wet) || contains(.dirty) }

    /// The kinds in sentence form, for headings: "Feeds, diapers and sleep".
    var headline: String {
        var parts: [String] = []
        if contains(.feed) { parts.append("feeds") }
        if tracksDiapers { parts.append("diapers") }
        if contains(.sleep) { parts.append("sleep") }
        let joined = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "") : parts.joined()
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    func store() {
        AppGroup.defaults.set(hidden.map(\.rawValue).sorted(), forKey: AppGroup.Key.hiddenKinds)
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
