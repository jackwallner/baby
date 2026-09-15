import Foundation

/// What the two diaper kinds are called on screen. Pee and Poop by default;
/// Wet and Dirty for parents who prefer them. Stored in the App Group so the
/// widgets read it, and carried to the Watch with the summary. Reports for a
/// doctor keep the clinical words whatever this says.
enum DiaperWords: String, CaseIterable, Sendable {
    case peePoop
    case wetDirty

    static var current: DiaperWords {
        DiaperWords(rawValue: AppGroup.defaults.string(forKey: AppGroup.Key.diaperWords) ?? "") ?? .peePoop
    }

    var label: String {
        switch self {
        case .peePoop: "Pee and Poop"
        case .wetDirty: "Wet and Dirty"
        }
    }
}

extension EventKind {
    /// The on-screen name, in the parent's chosen diaper words.
    var label: String { label(words: .current) }

    func label(words: DiaperWords) -> String {
        switch self {
        case .feed: "Feed"
        case .wet: words == .peePoop ? "Pee" : "Wet"
        case .dirty: words == .peePoop ? "Poop" : "Dirty"
        case .sleep: "Sleep"
        case .weight: "Weight"
        }
    }
}
