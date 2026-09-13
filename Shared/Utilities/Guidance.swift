import Foundation

/// The hospital tally sheet, as numbers: how many wet and dirty diapers and
/// feeds are typical on each day of life, and the lines that mean "call".
///
/// The diaper reference is the NHS Healthier Together breastfeeding guide.
/// It is educational context for the first two weeks, not a personalized
/// target or assessment. Fever advice comes from the AAP.
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

    static let sourceLine = "Diaper reference: NHS Healthier Together breastfeeding guidance. Fever and newborn care: American Academy of Pediatrics. Your pediatrician's advice comes first."
    static let referenceScope = "A breastfeeding reference for the first two weeks, not a target for every baby. Formula or mixed feeding can have different patterns. Follow your pediatrician's feeding plan. Counts include only what you log."
    static let diaperSource = URL(string: "https://www.swlondon-healthiertogether.nhs.uk/new-baby/keeping-your-child-safe-2-1/breastfeeding-your-baby")!
    static let feverSource = URL(string: "https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/Fever-and-Your-Baby.aspx")!
    static let feedingSource = URL(string: "https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/how-often-and-how-much-should-your-baby-eat.aspx")!

    static let disclaimer = "Baby Tracker is a log, not medical advice. It does not diagnose, treat or assess your baby. Typical ranges are general guidance; call your pediatrician with any concern."

    /// The typical range for a day of life. Days past the first week share the
    /// day-six figures, which hold through the early weeks.
    static func range(forDayOfLife day: Int) -> DayRange {
        let d = max(1, day)
        switch d {
        case 1: return DayRange(day: 1, wetMin: 1, dirtyMin: 1, stoolNote: "black and tarry (meconium)", feedsMin: 8, feedsMax: 12)
        case 2: return DayRange(day: 2, wetMin: 2, dirtyMin: 1, stoolNote: "black to dark green", feedsMin: 8, feedsMax: 12)
        case 3: return DayRange(day: 3, wetMin: 3, dirtyMin: 2, stoolNote: "brown, green or yellow", feedsMin: 8, feedsMax: 12)
        case 4: return DayRange(day: 4, wetMin: 4, dirtyMin: 2, stoolNote: "brown, green or yellow", feedsMin: 8, feedsMax: 12)
        case 5: return DayRange(day: 5, wetMin: 5, dirtyMin: 2, stoolNote: "yellow and loose", feedsMin: 8, feedsMax: 12)
        default: return DayRange(day: d, wetMin: 6, dirtyMin: 2, stoolNote: "yellow and loose", feedsMin: 8, feedsMax: 12)
        }
    }

    /// Days shown on the first-weeks tally.
    static let tallyDays = 14

    /// Reasons to call, as the discharge sheet words them.
    static let callIf: [String] = [
        "Your baby has fewer wet diapers than usual, feeds poorly, or you are worried about feeding or weight gain.",
        "Your newborn has not passed the first dark stool within 48 hours of birth.",
        "Your baby is difficult to wake for feeds: seek medical advice right away.",
        "Pink or brick-red diaper staining continues, or you notice blood in the urine or stool.",
        "At 3 months or younger, a rectal temperature of 100.4°F (38°C) or higher needs an immediate call, even if your baby seems well.",
    ]

}
