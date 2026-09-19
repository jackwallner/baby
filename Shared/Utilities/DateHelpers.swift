import Foundation

enum DateHelpers {
    /// "2026-09-11" style key used to bucket events by local day.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
    /// "just now", "12m ago", "2h 14m ago", "1d 3h ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        return "\(compactDuration(seconds)) ago"
    }

    /// "12m", "2h 14m", "1d 3h". Minutes only under an hour, no seconds.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if days >= 1 {
            let remHours = hours % 24
            return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
        }
        if hours >= 1 {
            let remMinutes = minutes % 60
            return remMinutes > 0 ? "\(hours)h \(remMinutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 0))m"
    }

    /// Same as `compactDuration` but "0m" reads as "under a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "under a minute" : compactDuration(seconds)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Asleep 1h 5m", or "Asleep just now" in the first minute rather than "0m".
    static func asleep(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "Asleep just now" : "Asleep \(compactDuration(seconds))"
    }

    /// Amounts are stored metric and shown the way the parent's pediatrician
    /// talks: ounces and pounds in the US, millilitres and kilograms elsewhere.
    static var usesImperial: Bool { Locale.current.measurementSystem == .us }

    static let millilitresPerOunce = 29.5735
    static let gramsPerOunce = 28.3495

    static func millilitres(_ value: Double, imperial: Bool = usesImperial) -> String {
        guard imperial else { return "\(Int(value.rounded())) ml" }
        let ounces = (value / millilitresPerOunce * 2).rounded() / 2
        return "\(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz"
    }

    static func grams(_ value: Double, imperial: Bool = usesImperial) -> String {
        guard imperial else { return String(format: "%.2f kg", value / 1000) }
        let totalOunces = (value / gramsPerOunce * 2).rounded() / 2
        let pounds = Int(totalOunces / 16)
        let ounces = totalOunces - Double(pounds) * 16
        return "\(pounds) lb \(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz"
    }

    /// A signed weight change, in the same units as `grams`.
    static func gramsChange(_ value: Double, imperial: Bool = usesImperial) -> String {
        let sign = value > 0 ? "+" : "−"
        guard imperial else { return "\(sign)\(Int(abs(value).rounded())) g" }
        let ounces = (abs(value) / gramsPerOunce * 2).rounded() / 2
        return "\(sign)\(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz"
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        n == 1 ? "\(n) \(singular)" : "\(n) \(plural ?? singular + "s")"
    }
}
