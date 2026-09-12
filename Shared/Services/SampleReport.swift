import Foundation

/// A worked example of the pediatrician summary, for a parent who has just
/// installed the app and has nothing logged yet (and for the reviewer, who
/// never will: App Review 4.3).
///
/// Every number here is invented. The page it renders is stamped
/// "EXAMPLE, NOT YOUR BABY'S DATA", and nothing in this file may ever be shown
/// without that stamp.
enum SampleReport {
    static func make(now: Date = .now, calendar: Calendar = .current) -> SummaryReport {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let birth = calendar.date(byAdding: .day, value: -9, to: today) ?? today
        let feeds = [9, 10, 8, 9, 11, 9, 8, 6]
        let wet = [5, 6, 7, 6, 8, 7, 6, 4]
        let dirty = [3, 4, 3, 3, 4, 3, 3, 2]
        let sleep = [14.5, 15.0, 14.0, 15.5, 14.8, 15.2, 14.6, 9.0]
        let longest = [3.1, 3.5, 2.9, 4.0, 3.4, 4.4, 3.2, 2.8]
        let weights: [Double?] = [3180, nil, nil, 3260, nil, nil, nil, 3390]
        var days: [SummaryReport.Day] = []
        for index in 0..<8 {
            let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
            days.append(SummaryReport.Day(
                date: date,
                dayOfLife: DateHelpers.dayOfLife(birthDate: birth, on: date, calendar: calendar),
                feeds: feeds[index],
                wet: wet[index],
                dirty: dirty[index],
                bottleMillilitres: index % 3 == 0 ? 60 : 0,
                sleepSeconds: sleep[index] * 3600,
                longestSleepSeconds: longest[index] * 3600,
                weightGrams: weights[index],
                stoolColors: index < 2 ? [.green] : [.yellow]
            ))
        }
        return SummaryReport(
            childName: "Example baby",
            birthDate: birth,
            start: start,
            end: today,
            days: days,
            notes: [(date: start, text: "Feed: latch felt better on the left")]
        )
    }
}
