import Foundation

/// Everything the pediatrician summary, the trends and the CSV are built from,
/// derived once from the log so the PDF, the charts and the export can never
/// disagree. Pure values: no Core Data, no SwiftUI, so it is straightforward
/// to test.
struct SummaryReport: Equatable, Sendable {
    struct Day: Equatable, Sendable, Identifiable {
        var date: Date
        var dayOfLife: Int?
        var feeds: Int
        var wet: Int
        var dirty: Int
        var bottleMillilitres: Double
        var sleepSeconds: TimeInterval
        /// The longest single sleep, which is the number parents are asked for.
        var longestSleepSeconds: TimeInterval
        var weightGrams: Double?
        var stoolColors: [StoolColor]

        var id: Date { date }
    }

    var childName: String
    var birthDate: Date?
    var start: Date
    var end: Date
    var days: [Day]
    var notes: [(date: Date, text: String)]

    static func == (lhs: SummaryReport, rhs: SummaryReport) -> Bool {
        lhs.childName == rhs.childName && lhs.birthDate == rhs.birthDate
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.days == rhs.days
            && lhs.notes.map(\.text) == rhs.notes.map(\.text)
    }

    // MARK: - Totals

    var dayCount: Int { days.count }
    var totalFeeds: Int { days.reduce(0) { $0 + $1.feeds } }
    var totalWet: Int { days.reduce(0) { $0 + $1.wet } }
    var totalDirty: Int { days.reduce(0) { $0 + $1.dirty } }

    /// Averages skip today, which is still being filled in and would drag every
    /// average down on the day the report is made. A report whose only day is
    /// today keeps it: "no average yet" is less use than today's own count.
    var completeDays: [Day] {
        guard days.count > 1, let last = days.last, Calendar.current.isDateInToday(last.date) else { return days }
        return days.dropLast()
    }

    var averageFeedsPerDay: Double { average(\.feeds) }
    var averageWetPerDay: Double { average(\.wet) }
    var averageDirtyPerDay: Double { average(\.dirty) }

    var averageSleepSeconds: TimeInterval {
        let complete = completeDays
        guard !complete.isEmpty else { return 0 }
        return complete.reduce(0) { $0 + $1.sleepSeconds } / Double(complete.count)
    }

    var longestSleepSeconds: TimeInterval { days.map(\.longestSleepSeconds).max() ?? 0 }

    var firstWeight: Double? { days.compactMap(\.weightGrams).first }
    var latestWeight: Double? { days.compactMap(\.weightGrams).last }

    var weightChangeGrams: Double? {
        guard let first = firstWeight, let latest = latestWeight, first != latest else { return nil }
        return latest - first
    }

    private func average<T: BinaryInteger>(_ key: KeyPath<Day, T>) -> Double {
        let complete = completeDays
        guard !complete.isEmpty else { return 0 }
        return complete.reduce(0.0) { $0 + Double($1[keyPath: key]) } / Double(complete.count)
    }

    var rangeLabel: String {
        let formatter = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return "\(start.formatted(formatter)) to \(end.formatted(formatter))"
    }

    // MARK: - Building

    /// One row per calendar day from `start` to `end` inclusive, including days
    /// with nothing logged: a blank row is information at a well visit.
    static func make(
        childName: String,
        birthDate: Date?,
        events: [LogEvent],
        from start: Date,
        to end: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SummaryReport {
        let firstDay = calendar.startOfDay(for: min(start, end))
        let lastDay = calendar.startOfDay(for: max(start, end))
        // Months of history should not be rescanned for every day of a short
        // range. Keep entries that touch the range, including a sleep that
        // started the night before it.
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let events = events.filter { event in
            let finish = event.endedAt ?? (event.isRunning ? now : event.start)
            return event.start < rangeEnd && max(finish, event.start) >= firstDay
        }
        var days: [Day] = []
        var cursor = firstDay
        while cursor <= lastDay {
            let tally = DayTally.make(events: events, on: cursor, now: now, calendar: calendar)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            let inDay = events.filter { $0.start >= cursor && $0.start < dayEnd }
            let longest = inDay
                .filter { $0.eventKind == .sleep }
                .map { event -> TimeInterval in
                    let finish = event.endedAt ?? (event.isRunning ? now : event.start)
                    return max(0, finish.timeIntervalSince(event.start))
                }
                .max() ?? 0
            days.append(Day(
                date: cursor,
                dayOfLife: birthDate.flatMap { DateHelpers.dayOfLife(birthDate: $0, on: cursor, calendar: calendar) },
                feeds: tally.feeds,
                wet: tally.wet,
                dirty: tally.dirty,
                bottleMillilitres: tally.bottleMillilitres,
                sleepSeconds: tally.sleepSeconds,
                longestSleepSeconds: longest,
                weightGrams: inDay.filter { $0.eventKind == .weight && $0.amount > 0 }.map(\.amount).last,
                stoolColors: inDay.compactMap { $0.eventKind == .dirty ? $0.stool : nil }
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let notes = events
            .filter { $0.start >= firstDay && $0.start < (calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay) }
            .compactMap { event -> (date: Date, text: String)? in
                guard let note = event.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
                return (date: event.start, text: "\(event.eventKind.label(words: .wetDirty)): \(note)")
            }
            .sorted { $0.date < $1.date }
        return SummaryReport(
            childName: childName,
            birthDate: birthDate,
            start: firstDay,
            end: lastDay,
            days: days,
            notes: notes
        )
    }

    /// Every entry as a spreadsheet. One row per event, newest last, with the
    /// header row spelled out so a column is readable without the app.
    static func csv(events: [LogEvent], childName: String) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        var lines = ["baby,date,time,kind,side,amount_ml,weight_g,stool_color,duration_min,note,logged_at"]
        for event in events.sorted(by: { $0.start < $1.start }) {
            let start = event.start
            let duration = event.duration.map { String(Int(($0 / 60).rounded())) } ?? ""
            let amount = event.eventKind == .feed && event.amount > 0 ? String(Int(event.amount)) : ""
            let weight = event.eventKind == .weight && event.amount > 0 ? String(Int(event.amount)) : ""
            let fields = [
                childName,
                start.formatted(.iso8601.year().month().day()),
                start.formatted(date: .omitted, time: .shortened),
                event.eventKind.rawValue,
                event.feedSide?.rawValue ?? "",
                amount,
                weight,
                event.stool?.rawValue ?? "",
                duration,
                event.note ?? "",
                (event.createdAt ?? start).formatted(.iso8601),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180: quote anything with a comma, a quote or a newline in it, and
    /// double the quotes inside.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
