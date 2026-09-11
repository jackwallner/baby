import Foundation

/// The hospital tally sheet, as numbers: how many wet and dirty diapers and
/// feeds are typical on each day of life, and the lines that mean "call".
///
/// Everything here is general guidance for healthy full-term newborns, drawn
/// from the American Academy of Pediatrics' parent guidance on
/// healthychildren.org and the discharge sheets hospitals hand out. It is
/// worded as a typical range and a reason to call, never as normal or abnormal,
/// and never as a judgement about a particular baby (App Review 1.4.1).
enum Guidance {
    struct DayRange: Equatable, Sendable {
        let day: Int
        /// Typical minimum wet diapers in 24 hours.
        let wetMin: Int
        /// Typical minimum dirty diapers in 24 hours.
        let dirtyMin: Int
        /// What stools usually look like on this day.
        let stoolNote: String
        let feedsMin: Int
        let feedsMax: Int

        var wetText: String { "\(wetMin)+ wet" }
        var dirtyText: String { "\(dirtyMin)+ dirty" }
        var feedsText: String { "\(feedsMin) to \(feedsMax) feeds" }
        var summary: String { "\(wetText) · \(dirtyText) · \(feedsText)" }
    }

    static let sourceLine = "General guidance from the American Academy of Pediatrics (healthychildren.org) for healthy full-term newborns. Your pediatrician's advice comes first."

    static let disclaimer = "Baby Tracker is a log, not medical advice. It does not diagnose, treat or assess your baby. Typical ranges are general guidance; call your pediatrician with any concern."

    /// The typical range for a day of life. Days past the first week share the
    /// day-six figures, which hold through the early weeks.
    static func range(forDayOfLife day: Int) -> DayRange {
        let d = max(1, day)
        switch d {
        case 1: return DayRange(day: 1, wetMin: 1, dirtyMin: 1, stoolNote: "black and tarry (meconium)", feedsMin: 8, feedsMax: 12)
        case 2: return DayRange(day: 2, wetMin: 2, dirtyMin: 2, stoolNote: "black to dark green", feedsMin: 8, feedsMax: 12)
        case 3: return DayRange(day: 3, wetMin: 3, dirtyMin: 3, stoolNote: "green, turning yellow", feedsMin: 8, feedsMax: 12)
        case 4: return DayRange(day: 4, wetMin: 4, dirtyMin: 3, stoolNote: "yellow and seedy", feedsMin: 8, feedsMax: 12)
        case 5: return DayRange(day: 5, wetMin: 5, dirtyMin: 3, stoolNote: "yellow and seedy", feedsMin: 8, feedsMax: 12)
        default: return DayRange(day: d, wetMin: 6, dirtyMin: 3, stoolNote: "yellow; formula-fed babies often pass fewer, firmer stools", feedsMin: 8, feedsMax: 12)
        }
    }

    /// Days shown on the first-weeks tally.
    static let tallyDays = 14

    /// Reasons to call, as the discharge sheet words them.
    static let callIf: [String] = [
        "Fewer wet diapers than the day of life in the first five days, or fewer than 6 a day after day five.",
        "No dirty diaper in 24 hours during the first week.",
        "Fewer than 8 feeds in 24 hours, or a baby too sleepy to wake for feeds.",
        "Brick-dust or reddish stains in the diaper after day four.",
        "A temperature of 100.4°F (38°C) or higher: call right away.",
    ]

    /// One neutral line comparing today's count with the typical range.
    /// Deliberately never says "low", "abnormal" or "dehydrated".
    static func comparison(wet: Int, dirty: Int, day: Int, dayComplete: Bool) -> String? {
        let range = range(forDayOfLife: day)
        guard dayComplete else { return nil }
        var below: [String] = []
        if wet < range.wetMin { below.append("wet") }
        if dirty < range.dirtyMin { below.append("dirty") }
        guard !below.isEmpty else { return nil }
        let which = below.joined(separator: " and ")
        return "Below the typical \(which) range for day \(day). Call your pediatrician if you are concerned."
    }
}
