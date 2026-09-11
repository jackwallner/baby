import Foundation

/// Day-boundary helpers shared by the services, the widgets, and the tests.
/// Deliberately free of HealthKit and SwiftUI so the widget targets can compile
/// it without dragging the whole app in.
enum DateHelpers {
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func startOfDay(_ date: Date = .now) -> Date {
        gregorian.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int, from date: Date = .now) -> Date {
        gregorian.date(byAdding: .day, value: -max(days, 0), to: startOfDay(date)) ?? startOfDay(date)
    }

    /// Exclusive upper bound for a query that should include all of `date`'s day.
    static func endOfDay(_ date: Date = .now) -> Date {
        gregorian.date(byAdding: .day, value: 1, to: startOfDay(date)) ?? date
    }

    /// "yyyy-MM-dd" key, built by component so it never depends on a formatter's
    /// locale or on the store's calendar.
    static func dayKey(for date: Date) -> String {
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        gregorian.isDate(lhs, inSameDayAs: rhs)
    }
}
