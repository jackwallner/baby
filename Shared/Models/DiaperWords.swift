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
        case .peePoop: String(localized: "Pee and Poop")
        case .wetDirty: String(localized: "Wet and Dirty")
        }
    }
}

extension EventKind {
    /// The on-screen name, in the parent's chosen diaper words.
    var label: String { label(words: .current) }

    func label(words: DiaperWords) -> String {
        switch self {
        case .feed: String(localized: "Feed")
        case .wet: words == .peePoop ? String(localized: "Pee") : String(localized: "Wet")
        case .dirty: words == .peePoop ? String(localized: "Poop") : String(localized: "Dirty")
        case .sleep: String(localized: "Sleep")
        case .weight: String(localized: "Weight")
        }
    }

    /// The lowercase word used in compact sentences, independently localized.
    var lowercaseLabel: String { lowercaseLabel(words: .current) }

    func lowercaseLabel(words: DiaperWords) -> String {
        switch self {
        case .feed: String(localized: "feed")
        case .wet: words == .peePoop ? String(localized: "pee") : String(localized: "wet")
        case .dirty: words == .peePoop ? String(localized: "poop") : String(localized: "dirty")
        case .sleep: String(localized: "sleep")
        case .weight: String(localized: "weight")
        }
    }

    /// Said when a shortcut asks for a button the family turned off.
    var turnedOffMessage: String {
        switch self {
        case .feed: String(localized: "Feed is turned off in Baby Tracker's Settings, so nothing was logged.")
        case .wet: DiaperWords.current == .peePoop
            ? String(localized: "Pee is turned off in Baby Tracker's Settings, so nothing was logged.")
            : String(localized: "Wet is turned off in Baby Tracker's Settings, so nothing was logged.")
        case .dirty: DiaperWords.current == .peePoop
            ? String(localized: "Poop is turned off in Baby Tracker's Settings, so nothing was logged.")
            : String(localized: "Dirty is turned off in Baby Tracker's Settings, so nothing was logged.")
        case .sleep: String(localized: "Sleep is turned off in Baby Tracker's Settings, so nothing was logged.")
        case .weight: String(localized: "Weight is turned off in Baby Tracker's Settings, so nothing was logged.")
        }
    }

    /// The spoken reply for a logged diaper.
    var loggedDiaperDialog: String {
        switch self {
        case .wet: DiaperWords.current == .peePoop ? String(localized: "Logged a pee diaper.") : String(localized: "Logged a wet diaper.")
        case .dirty: DiaperWords.current == .peePoop ? String(localized: "Logged a poop diaper.") : String(localized: "Logged a dirty diaper.")
        default: String(localized: "Logged a feed.")
        }
    }

    var logLabel: String {
        switch self {
        case .feed: String(localized: "Log feed")
        case .wet: DiaperWords.current == .peePoop ? String(localized: "Log pee") : String(localized: "Log wet")
        case .dirty: DiaperWords.current == .peePoop ? String(localized: "Log poop") : String(localized: "Log dirty")
        case .sleep: String(localized: "Log sleep")
        case .weight: String(localized: "Log weight")
        }
    }

    var undoLabel: String {
        switch self {
        case .feed: String(localized: "Undo feed")
        case .wet: DiaperWords.current == .peePoop ? String(localized: "Undo pee") : String(localized: "Undo wet")
        case .dirty: DiaperWords.current == .peePoop ? String(localized: "Undo poop") : String(localized: "Undo dirty")
        case .sleep: String(localized: "Undo sleep")
        case .weight: String(localized: "Undo weight")
        }
    }

    var diaperNoun: String {
        switch self {
        case .feed: String(localized: "feed")
        case .wet: DiaperWords.current == .peePoop ? String(localized: "pee diaper") : String(localized: "wet diaper")
        case .dirty: DiaperWords.current == .peePoop ? String(localized: "poop diaper") : String(localized: "dirty diaper")
        case .sleep: String(localized: "sleep")
        case .weight: String(localized: "weight")
        }
    }
}
