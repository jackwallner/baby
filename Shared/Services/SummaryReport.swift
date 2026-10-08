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
        /// The longest wait between two logged feeds, measured start to start
        /// and credited to the day the later feed began. Zero when the day has
        /// no gap to measure. At a newborn visit this is asked before sleep.
        var longestFeedGapSeconds: TimeInterval = 0
        /// Bottle feeds with an amount entered, so the page can say how much
        /// each bottle held.
        var bottleFeeds: Int = 0
        var weightGrams: Double?
        var stoolColors: [StoolColor]
        /// Why the day is left out of the averages; nil for a complete day.
        var partial: Partial?

        var id: Date { date }
        var isComplete: Bool { partial == nil }
        /// A weigh-in alone does not make a logged day: the averages are of
        /// feeds, diapers and sleep.
        var hasEntries: Bool { feeds > 0 || wet > 0 || dirty > 0 || sleepSeconds > 0 }
    }

    /// A day that would distort an average: the doctor sees it in the table,
    /// but a day with eight hours of entries is not a day of eight hours.
    enum Partial: Equatable, Sendable {
        /// The day the log began, with the first entry's time.
        case loggingBegan(Date)
        /// Today, still being filled in.
        case today
        /// Nothing was logged, which for a newborn means nobody was logging.
        case nothingLogged

        var label: String {
            switch self {
            case .loggingBegan(let at): "from \(Format.time(at))"
            case .today: "so far"
            case .nothingLogged: "not logged"
            }
        }
    }

    var childName: String
    var birthDate: Date?
    var start: Date
    var end: Date
    var days: [Day]
    var notes: [(date: Date, text: String)]
    /// The buttons this family uses. The page, the charts and the export
    /// leave out the rest rather than print a column of zeros.
    var tracked: TrackedKinds = .all

    static func == (lhs: SummaryReport, rhs: SummaryReport) -> Bool {
        lhs.childName == rhs.childName && lhs.birthDate == rhs.birthDate && lhs.tracked == rhs.tracked
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.days == rhs.days
            && lhs.notes.map(\.text) == rhs.notes.map(\.text)
    }

    // MARK: - Totals

    var dayCount: Int { days.count }
    var totalFeeds: Int { days.reduce(0) { $0 + $1.feeds } }
    var totalWet: Int { days.reduce(0) { $0 + $1.wet } }
    var totalDirty: Int { days.reduce(0) { $0 + $1.dirty } }

    /// The days an average may use: not today, not the day logging began, and
    /// not a day with nothing in it. Until the log has a complete day, every
    /// day with entries counts: "no average yet" is less use than a rough one.
    var completeDays: [Day] {
        let complete = days.filter(\.isComplete)
        if !complete.isEmpty { return complete }
        let logged = days.filter(\.hasEntries)
        return logged.isEmpty ? days : logged
    }

    /// True when the averages rest on complete days rather than the fallback.
    var hasCompleteDays: Bool { days.contains(where: \.isComplete) }

    /// The days the table shows but the averages leave out.
    var partialDays: [Day] { hasCompleteDays ? days.filter { !$0.isComplete } : [] }

    var averageFeedsPerDay: Double { average(\.feeds) }
    var averageWetPerDay: Double { average(\.wet) }
    var averageDirtyPerDay: Double { average(\.dirty) }

    var averageSleepSeconds: TimeInterval {
        let complete = completeDays
        guard !complete.isEmpty else { return 0 }
        return complete.reduce(0) { $0 + $1.sleepSeconds } / Double(complete.count)
    }

    var longestSleepSeconds: TimeInterval { days.map(\.longestSleepSeconds).max() ?? 0 }
    var longestFeedGapSeconds: TimeInterval { days.map(\.longestFeedGapSeconds).max() ?? 0 }

    /// Bottle volume a day, over the complete days that had a bottle, and the
    /// typical bottle, which is what a formula-fed baby's doctor asks.
    var averageBottleMillilitresPerDay: Double {
        let bottleDays = completeDays.filter { $0.bottleMillilitres > 0 }
        guard !bottleDays.isEmpty else { return 0 }
        return bottleDays.reduce(0) { $0 + $1.bottleMillilitres } / Double(bottleDays.count)
    }

    var averageBottleMillilitresPerFeed: Double {
        let feeds = days.reduce(0) { $0 + $1.bottleFeeds }
        guard feeds > 0 else { return 0 }
        return days.reduce(0) { $0 + $1.bottleMillilitres } / Double(feeds)
    }

    /// The lowest complete day, which is the day a doctor asks about.
    func lowestDay<T: Comparable>(_ key: KeyPath<Day, T>) -> Day? {
        completeDays.min { $0[keyPath: key] < $1[keyPath: key] }
    }

    var firstWeight: Double? { days.compactMap(\.weightGrams).first }
    var latestWeight: Double? { days.compactMap(\.weightGrams).last }
    var firstWeightDate: Date? { days.first { $0.weightGrams != nil }?.date }
    var latestWeightDate: Date? { days.last { $0.weightGrams != nil }?.date }

    var weightChangeGrams: Double? {
        guard let first = firstWeight, let latest = latestWeight, first != latest else { return nil }
        return latest - first
    }

    /// Change as a share of the first weigh-in, the figure a newborn's loss or
    /// regain is judged by.
    var weightChangePercent: Double? {
        guard let first = firstWeight, first > 0, let change = weightChangeGrams else { return nil }
        return change / first * 100
    }

    /// "+210 g (+6.6%) since Sep 29": the change from the first weigh-in in
    /// the range, as grams and as the share a newborn's loss is judged by.
    var weightChangeDescription: String? {
        guard let change = weightChangeGrams, let percent = weightChangePercent, let since = firstWeightDate else {
            return latestWeight == nil ? nil : "One weigh-in"
        }
        let sign = percent > 0 ? "+" : "−"
        let share = "\(sign)\(abs(percent).formatted(.number.precision(.fractionLength(1))))%"
        return "\(Format.gramsChange(change)) (\(share)) since \(since.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "Averages use 6 complete days." with the days left out named, or the
    /// fallback spelled out. Shown wherever an average is.
    var averagesNote: String {
        guard hasCompleteDays else {
            return "No complete day yet, so averages use every day logged so far."
        }
        var note = "Averages use \(Format.count(completeDays.count, "complete day"))."
        let partial = partialDays
        guard !partial.isEmpty else { return note }
        let skipped = partial.map { day -> String in
            switch day.partial {
            case .today: "today (so far)"
            case .loggingBegan(let at): "\(day.date.formatted(.dateTime.month(.abbreviated).day())) (logging began \(Format.time(at)))"
            case .nothingLogged, .none: day.date.formatted(.dateTime.month(.abbreviated).day())
            }
        }
        let unlogged = partial.filter { $0.partial == .nothingLogged }.count
        if unlogged == partial.count {
            note += " \(Format.count(unlogged, "day")) with nothing logged \(unlogged == 1 ? "is" : "are") left out."
        } else if skipped.count <= 3 {
            note += " Left out: \(skipped.joined(separator: ", "))."
        } else {
            note += " \(Format.count(partial.count, "partial or unlogged day")) left out."
        }
        return note
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
        tracked: TrackedKinds = .all,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SummaryReport {
        let firstDay = calendar.startOfDay(for: min(start, end))
        let lastDay = calendar.startOfDay(for: max(start, end))
        // Months of history should not be rescanned for every day of a short
        // range. Keep entries that touch the range, including a sleep that
        // started the night before it.
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        // Read before the range filter, so the first day's first gap reaches
        // back to the feed before it.
        let lookback = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        let feedStarts = events
            .filter { $0.eventKind == .feed && $0.start >= lookback && $0.start < rangeEnd }
            .map(\.start)
            .sorted()
        // The log's first entry of any kind: the day it fell on is partial.
        let loggingBegan = events.map(\.start).min()
        let today = calendar.startOfDay(for: now)
        let events = events.filter { event in
            guard tracked.contains(event.eventKind) else { return false }
            let finish = event.endedAt ?? (event.isRunning ? now : event.start)
            return event.start < rangeEnd && max(finish, event.start) >= firstDay
        }
        // A gap that spans a whole calendar day is a day nobody logged, not a
        // baby who went a day without feeding, so it is never the longest gap.
        let feedGaps = zip(feedStarts.dropFirst(), feedStarts)
            .filter { later, earlier in
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier), to: calendar.startOfDay(for: later)).day ?? 0
                return days <= 1
            }
            .map { (at: $0, seconds: $0.timeIntervalSince($1)) }
        let sleepBouts = DayTally.coveredIntervals(events.compactMap { event -> (start: Date, end: Date)? in
            guard event.eventKind == .sleep else { return nil }
            let finish = event.endedAt ?? (event.isRunning ? now : event.start)
            guard finish > event.start else { return nil }
            return (event.start, finish)
        })
        var days: [Day] = []
        var cursor = firstDay
        while cursor <= lastDay {
            let tally = DayTally.make(events: events, on: cursor, now: now, calendar: calendar)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            let inDay = events.filter { $0.start >= cursor && $0.start < dayEnd }
            let longest = sleepBouts
                .filter { $0.start >= cursor && $0.start < dayEnd }
                .map { $0.end.timeIntervalSince($0.start) }
                .max() ?? 0
            var day = Day(
                date: cursor,
                dayOfLife: birthDate.flatMap { DateHelpers.dayOfLife(birthDate: $0, on: cursor, calendar: calendar) },
                feeds: tally.feeds,
                wet: tally.wet,
                dirty: tally.dirty,
                bottleMillilitres: tally.bottleMillilitres,
                sleepSeconds: tally.sleepSeconds,
                longestSleepSeconds: longest,
                longestFeedGapSeconds: feedGaps.filter { $0.at >= cursor && $0.at < dayEnd }.map(\.seconds).max() ?? 0,
                bottleFeeds: inDay.filter { $0.eventKind == .feed && $0.feedSides.contains(.bottle) && $0.amount > 0 }.count,
                weightGrams: inDay.filter { $0.eventKind == .weight && $0.amount > 0 }.map(\.amount).last,
                stoolColors: inDay.compactMap { $0.eventKind == .dirty ? $0.stool : nil }
            )
            if cursor >= today {
                day.partial = .today
            } else if let began = loggingBegan, began >= cursor, began < dayEnd {
                day.partial = .loggingBegan(began)
            } else if !day.hasEntries {
                day.partial = .nothingLogged
            }
            days.append(day)
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
            notes: notes,
            tracked: tracked
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
                event.feedSides.map(\.rawValue).joined(separator: "+"),
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
