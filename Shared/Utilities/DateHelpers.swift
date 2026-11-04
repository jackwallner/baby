import Foundation

enum DateHelpers {
    /// "2026-09-11" style key used to bucket events by local day.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Day 1 is the calendar day of birth; nil before birth.
    static func dayOfLife(birthDate: Date, on date: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: birthDate)
        let today = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: start, to: today).day, days >= 0 else { return nil }
        return days + 1
    }

    /// The calendar day for a given day of life, 1-based.
    static func date(forDayOfLife day: Int, birthDate: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: birthDate)
        return calendar.date(byAdding: .day, value: day - 1, to: start) ?? start
    }

    static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}

/// Every string that shows a time, a duration or an amount goes through here,
/// so the phone, the widgets and the Watch say the same thing.
enum Format {
    enum PluralForm {
        case one
        case other
    }

    static func pluralForm(_ count: Int) -> PluralForm {
        let token = String(localized: "\(count) plural category")
        return token.hasPrefix("one ") ? .one : .other
    }

    /// "just now", "12m ago", "2h 14m ago", "1d 3h ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return String(localized: "just now") }
        return String(localized: "\(compactDuration(seconds)) ago")
    }

    /// "12m", "2h 14m", "1d 3h". Minutes only under an hour, no seconds.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = .current
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(seconds, 0)) ?? String(localized: "0m")
    }

    /// Same as `compactDuration` but "0m" reads as "under a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? String(localized: "under a minute") : compactDuration(seconds)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Asleep 1h 5m", or "Asleep just now" in the first minute rather than "0m".
    static func asleep(_ seconds: TimeInterval) -> String {
        seconds < 60 ? String(localized: "Asleep just now") : String(localized: "Asleep \(compactDuration(seconds))")
    }

    /// Amounts are stored metric and shown the way the parent's pediatrician
    /// talks: ounces and pounds in the US, millilitres and kilograms elsewhere.
    static var usesImperial: Bool { Locale.current.measurementSystem == .us }

    static let millilitresPerOunce = 29.5735
    static let gramsPerOunce = 28.3495
    private static let millilitresUnit = UnitVolume(symbol: "ml", converter: UnitConverterLinear(coefficient: 0.001))
    private static let fluidOuncesUnit = UnitVolume(symbol: "oz", converter: UnitConverterLinear(coefficient: millilitresPerOunce / 1000))
    private static let poundsUnit = UnitMass(symbol: "lb", converter: UnitConverterLinear(coefficient: 453.59237))
    private static let ouncesUnit = UnitMass(symbol: "oz", converter: UnitConverterLinear(coefficient: gramsPerOunce))

    static func millilitres(_ value: Double, imperial: Bool = usesImperial) -> String {
        guard imperial else { return measurement(Double(Int(value.rounded())), unit: millilitresUnit, fractionDigits: 0...0) }
        let ounces = (value / millilitresPerOunce * 2).rounded() / 2
        return measurement(ounces, unit: fluidOuncesUnit, fractionDigits: 0...1)
    }

    static func grams(_ value: Double, imperial: Bool = usesImperial) -> String {
        guard imperial else {
            return measurement(value / 1000, unit: UnitMass.kilograms, fractionDigits: 2...2)
        }
        let totalOunces = (value / gramsPerOunce * 2).rounded() / 2
        let pounds = Int(totalOunces / 16)
        let ounces = totalOunces - Double(pounds) * 16
        let poundsText = measurement(Double(pounds), unit: poundsUnit, fractionDigits: 0...0)
        let ouncesText = measurement(ounces, unit: ouncesUnit, fractionDigits: 0...1)
        return String(localized: "\(poundsText) \(ouncesText)")
    }

    /// A signed weight change, in the same units as `grams`.
    static func gramsChange(_ value: Double, imperial: Bool = usesImperial) -> String {
        let sign = value > 0 ? "+" : "−"
        guard imperial else {
            let amount = measurement(Double(Int(abs(value).rounded())), unit: UnitMass.grams, fractionDigits: 0...0)
            return String(localized: "\(sign)\(amount)")
        }
        let ounces = (abs(value) / gramsPerOunce * 2).rounded() / 2
        let amount = measurement(ounces, unit: ouncesUnit, fractionDigits: 0...1)
        return String(localized: "\(sign)\(amount)")
    }

    static func measurement(_ value: Double, unit: Dimension, fractionDigits: ClosedRange<Int>) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = .current
        numberFormatter.minimumFractionDigits = fractionDigits.lowerBound
        numberFormatter.maximumFractionDigits = fractionDigits.upperBound
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.numberFormatter = numberFormatter
        return formatter.string(from: Measurement<Unit>(value: value, unit: unit as Unit))
    }

    enum CountPhrase {
        case feed
        case entry
        case day
        case completeDay
        case partialOrUnloggedDay
    }

    static func count(_ n: Int, _ phrase: CountPhrase) -> String {
        switch phrase {
        case .feed: String(localized: "\(n) feed")
        case .entry: String(localized: "\(n) entry")
        case .day: String(localized: "\(n) day")
        case .completeDay: String(localized: "\(n) complete day")
        case .partialOrUnloggedDay: String(localized: "\(n) partial or unlogged day")
        }
    }

    static func diaperCount(_ n: Int, _ kind: EventKind, words: DiaperWords = .current) -> String {
        switch (kind, words) {
        case (.wet, .peePoop): String(localized: "\(n) pee")
        case (.wet, .wetDirty): String(localized: "\(n) wet")
        case (.dirty, .peePoop): String(localized: "\(n) poop")
        case (.dirty, .wetDirty): String(localized: "\(n) dirty")
        default: ""
        }
    }

    static func feedUnit(_ count: Int) -> String {
        switch pluralForm(count) {
        case .one: String(localized: "feed")
        case .other: String(localized: "feeds")
        }
    }
}
