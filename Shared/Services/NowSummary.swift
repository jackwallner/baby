import Foundation

/// The answer to the 3am question, computed once and shown everywhere: the Now
/// card, both widgets, the complication, and the Watch app. Codable so the
/// phone can push it to the Watch as-is.
struct NowSummary: Codable, Equatable, Sendable {
    var childName: String = "Baby"
    /// Identifies the profile this summary belongs to. Optional for summaries
    /// written by older builds, and for the empty state before setup.
    var childID: UUID?
    var dayOfLife: Int?
    var lastFeedAt: Date?
    /// The first side of the last feed. Kept beside `lastFeedSides` so a
    /// Watch still running an older build reads a side.
    var lastFeedSide: FeedSide?
    /// Every side of the last feed, in order. Optional for older summaries.
    var lastFeedSides: [FeedSide]?
    var lastDiaperAt: Date?
    var lastDiaperKind: EventKind?
    var runningSleepStart: Date?
    var runningFeedStart: Date?
    var runningFeedSide: FeedSide?
    var runningFeedSides: [FeedSide]?
    /// `TotalsWindow.storedValue` the today counts were made with, so the
    /// Watch resets them at the same hour the phone does. Nil means midnight.
    var totalsWindow: Int?
    var todayFeeds: Int = 0
    var todayWet: Int = 0
    var todayDirty: Int = 0
    var generatedAt: Date = .now
    /// Recent event IDs already represented by this summary. Optional keeps
    /// cached summaries from older builds decodable and gives Watch replay a
    /// real acknowledgement watermark instead of guessing from `generatedAt`.
    var knownEventIDs: [UUID]?

    static let empty = NowSummary()
    static let knownEventLimit = 256

    /// The side to offer next: the other breast after a breastfeed.
    var suggestedSide: FeedSide { feedSides.last?.next ?? .left }

    /// Every side of the last feed, including from summaries that only knew one.
    var feedSides: [FeedSide] { lastFeedSides ?? lastFeedSide.map { [$0] } ?? [] }

    var runningSides: [FeedSide] { runningFeedSides ?? runningFeedSide.map { [$0] } ?? [] }

    mutating func setLastFeedSides(_ sides: [FeedSide]) {
        lastFeedSides = sides
        lastFeedSide = sides.first
    }

    mutating func setRunningFeedSides(_ sides: [FeedSide]) {
        runningFeedSides = sides
        runningFeedSide = sides.first
    }

    var isSleeping: Bool { runningSleepStart != nil }
    var isFeeding: Bool { runningFeedStart != nil }

    // MARK: - Lines

    /// "Fed 2h 14m ago · Left", or "Feeding · Left · 12m" while a timed feed runs.
    func feedLine(now: Date = .now) -> String {
        if let runningFeedStart {
            let side = FeedSide.label(for: runningSides).map { " · \($0)" } ?? ""
            return "Feeding\(side) · \(Format.compactDuration(now.timeIntervalSince(runningFeedStart)))"
        }
        guard let lastFeedAt else { return "No feed logged yet" }
        let side = FeedSide.label(for: feedSides).map { " · \($0)" } ?? ""
        return "Fed \(Format.ago(lastFeedAt, now: now))\(side)"
    }

    /// "Last diaper 48m ago · Pee".
    func diaperLine(now: Date = .now) -> String {
        guard let lastDiaperAt else { return "No diaper logged yet" }
        let kind = lastDiaperKind.map { " · \($0.label)" } ?? ""
        return "Last diaper \(Format.ago(lastDiaperAt, now: now))\(kind)"
    }

    /// "Asleep 1h 05m" while a sleep runs; nil otherwise.
    func sleepLine(now: Date = .now) -> String? {
        guard let runningSleepStart else { return nil }
        return Format.asleep(now.timeIntervalSince(runningSleepStart))
    }

    /// "3 pee · 2 poop · 7 feeds".
    var todayLine: String {
        "\(todayWet) \(EventKind.wet.label.lowercased()) · \(todayDirty) \(EventKind.dirty.label.lowercased()) · \(Format.count(todayFeeds, "feed"))"
    }

    // MARK: - Building

    /// Pure: derives the summary from the events list so tests can pin it.
    static func make(
        child: Child?,
        events: [LogEvent],
        now: Date = .now,
        calendar: Calendar = .current,
        window: TotalsWindow = .current
    ) -> NowSummary {
        var summary = NowSummary()
        summary.generatedAt = now
        summary.totalsWindow = window.storedValue
        guard let child else { return summary }
        let today = window.interval(at: now, calendar: calendar)
        summary.childName = child.displayName
        summary.childID = child.id
        summary.dayOfLife = child.dayOfLife(on: now, calendar: calendar)
        let sorted = events.sorted { $0.start > $1.start }
        summary.knownEventIDs = Array(sorted.prefix(Self.knownEventLimit).reversed().compactMap(\.id))
        for event in sorted {
            switch event.eventKind {
            case .feed:
                if event.isRunning, summary.runningFeedStart == nil {
                    summary.runningFeedStart = event.startedAt
                    summary.setRunningFeedSides(event.feedSides)
                } else if summary.lastFeedAt == nil, !event.isRunning {
                    summary.lastFeedAt = event.startedAt
                    summary.setLastFeedSides(event.feedSides)
                }
            case .wet, .dirty:
                if summary.lastDiaperAt == nil {
                    summary.lastDiaperAt = event.startedAt
                    summary.lastDiaperKind = event.eventKind
                }
            case .sleep:
                // Newest first, so this keeps the earliest open sleep: if both
                // parents started one, the baby has been asleep since the first.
                if event.isRunning {
                    summary.runningSleepStart = event.startedAt
                }
            case .weight:
                break
            }
            if window.holds(event.start, in: today) {
                switch event.eventKind {
                case .feed: summary.todayFeeds += 1
                case .wet: summary.todayWet += 1
                case .dirty: summary.todayDirty += 1
                default: break
                }
            }
        }
        // A running feed still counts as the most recent feed for "which side".
        if let start = summary.runningFeedStart, start >= (summary.lastFeedAt ?? .distantPast) {
            summary.lastFeedAt = start
            summary.setLastFeedSides(summary.runningSides)
        }
        return summary
    }

    // MARK: - App Group cache

    static func load() -> NowSummary {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.nowSummary),
              let summary = try? JSONDecoder().decode(NowSummary.self, from: data) else { return .empty }
        return summary
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: AppGroup.Key.nowSummary)
    }
}

extension NowSummary {
    /// A wrist tap replayed onto a summary, so the Watch shows the tap before
    /// the phone confirms it. Pure, and shared with the tests.
    func applying(
        _ payload: WatchLogPayload,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> NowSummary {
        var s = resetTodayIfNeeded(calendar: calendar, now: now)
        guard payload.childID == nil || payload.childID == s.childID else { return s }
        // `generatedAt` is a sync timestamp, not a calendar-day watermark.
        // An overnight offline tap must be compared with the current day.
        let today = window.interval(at: now, calendar: calendar)
        let sameDay = window.holds(payload.at, in: today)
        if s.knownEventIDs?.contains(payload.id) == true { return s }
        switch payload.action {
        case .log:
            switch payload.kind {
            case .feed:
                let mostRecentFeedAt = max(s.lastFeedAt ?? .distantPast, s.runningFeedStart ?? .distantPast)
                if payload.at >= mostRecentFeedAt {
                    s.lastFeedAt = payload.at
                    s.setLastFeedSides(payload.side.map { [$0] } ?? [])
                }
                if sameDay { s.todayFeeds += 1 }
            case .wet, .dirty:
                if s.lastDiaperAt == nil || payload.at >= (s.lastDiaperAt ?? .distantPast) {
                    s.lastDiaperAt = payload.at
                    s.lastDiaperKind = payload.kind
                }
                if sameDay {
                    if payload.kind == .wet { s.todayWet += 1 } else { s.todayDirty += 1 }
                }
            default:
                break
            }
        case .startSleep:
            if s.runningSleepStart == nil || payload.at >= (s.runningSleepStart ?? .distantPast) {
                s.runningSleepStart = payload.at
            }
        case .stopSleep:
            if s.runningSleepStart == nil || payload.at >= (s.runningSleepStart ?? .distantPast) {
                s.runningSleepStart = nil
            }
        }
        var ids = s.knownEventIDs ?? []
        ids.removeAll { $0 == payload.id }
        ids.append(payload.id)
        if ids.count > Self.knownEventLimit {
            ids.removeFirst(ids.count - Self.knownEventLimit)
        }
        s.knownEventIDs = ids
        s.generatedAt = now
        return s
    }

    /// Reapplies only Watch actions that are not already represented by the
    /// phone summary. The summary generation time cannot acknowledge an event
    /// because a summary may be generated after an offline tap but before that
    /// tap reaches the phone.
    func applyingPending(
        _ pending: [WatchLogPayload],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> NowSummary {
        pending.reduce(resetTodayIfNeeded(calendar: calendar, now: now)) { summary, payload in
            guard payload.childID == nil || payload.childID == summary.childID else { return summary }
            return summary.applying(payload, calendar: calendar, now: now)
        }
    }

    /// The window the phone counted "today" in.
    var window: TotalsWindow { TotalsWindow(storedValue: totalsWindow) }

    private func resetTodayIfNeeded(calendar: Calendar, now: Date) -> NowSummary {
        let today = window.interval(at: now, calendar: calendar)
        guard !window.holds(generatedAt, in: today) else { return self }
        var summary = self
        summary.todayFeeds = 0
        summary.todayWet = 0
        summary.todayDirty = 0
        summary.generatedAt = now
        return summary
    }
}

/// Per-day totals for the tally and the history headers.
struct DayTally: Equatable, Sendable {
    var feeds = 0
    var wet = 0
    var dirty = 0
    var sleepSeconds: TimeInterval = 0
    var bottleMillilitres: Double = 0

    static func make(events: [LogEvent], on day: Date, now: Date = .now, calendar: Calendar = .current) -> DayTally {
        var tally = DayTally()
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return tally }
        var sleeps: [(start: Date, end: Date)] = []
        for event in events {
            let start = event.start
            switch event.eventKind {
            case .feed where start >= dayStart && start < dayEnd:
                tally.feeds += 1
                if event.feedSides.contains(.bottle) { tally.bottleMillilitres += max(0, event.amount) }
            case .wet where start >= dayStart && start < dayEnd:
                tally.wet += 1
            case .dirty where start >= dayStart && start < dayEnd:
                tally.dirty += 1
            case .sleep:
                // Sleep is credited to the day it happened in, split at midnight.
                let end = event.endedAt ?? (event.isRunning ? now : start)
                let overlapStart = max(start, dayStart)
                let overlapEnd = min(end, dayEnd)
                if overlapEnd > overlapStart { sleeps.append((overlapStart, overlapEnd)) }
            default:
                break
            }
        }
        tally.sleepSeconds = coveredSeconds(sleeps)
        return tally
    }

    /// Time covered by the intervals, counting overlaps once. Two parents who
    /// both logged the same nap before their phones synced still get the
    /// nap's length, not twice it.
    static func coveredSeconds(_ intervals: [(start: Date, end: Date)]) -> TimeInterval {
        coveredIntervals(intervals).reduce(0) { total, interval in
            total + interval.end.timeIntervalSince(interval.start)
        }
    }

    /// Merges simultaneous or back-to-back sleep entries into individual bouts.
    static func coveredIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        var covered: [(start: Date, end: Date)] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            guard let last = covered.last else {
                covered.append(interval)
                continue
            }
            if interval.start <= last.end {
                covered[covered.count - 1] = (last.start, max(last.end, interval.end))
            } else {
                covered.append(interval)
            }
        }
        return covered
    }
}

/// What "today" means for the totals under the log buttons: a day that
/// starts at a chosen hour (midnight unless the parent picks another), or the
/// last 24 hours. History and the pediatrician report keep calendar days.
enum TotalsWindow: Hashable, Sendable {
    case day(startHour: Int)
    case last24Hours

    static let midnight = TotalsWindow.day(startHour: 0)

    /// The start hour, or -1 for the last 24 hours. Missing means midnight.
    init(storedValue: Int?) {
        switch storedValue {
        case -1: self = .last24Hours
        case let hour? where (0...23).contains(hour): self = .day(startHour: hour)
        default: self = .midnight
        }
    }

    var storedValue: Int {
        switch self {
        case .day(let hour): hour
        case .last24Hours: -1
        }
    }

    static var current: TotalsWindow {
        TotalsWindow(storedValue: AppGroup.defaults.object(forKey: AppGroup.Key.totalsWindow) as? Int)
    }

    /// The window containing `now`: from the most recent start hour to the
    /// next one, or the 24 hours ending now.
    func interval(at now: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .last24Hours:
            return DateInterval(start: now.addingTimeInterval(-24 * 3600), end: now)
        case .day(let hour):
            let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? calendar.startOfDay(for: now)
            let start = today <= now ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
            return DateInterval(start: start, end: end)
        }
    }

    /// Whether a moment falls in `interval`. A day ends where the next one
    /// starts; the last 24 hours has no future edge, so a tap stamped a
    /// moment ahead of this clock still counts.
    func holds(_ date: Date, in interval: DateInterval) -> Bool {
        switch self {
        case .day: date >= interval.start && date < interval.end
        case .last24Hours: date >= interval.start
        }
    }

    /// The label above the totals: "Today", "Since 6 AM", "Last 24 hours".
    func title(calendar: Calendar = .current) -> String {
        switch self {
        case .last24Hours: return "Last 24 hours"
        case .day(0): return "Today"
        case .day(let hour): return "Since \(Self.hourLabel(hour, calendar: calendar))"
        }
    }

    /// "6 AM", or "06:00" on a 24-hour clock.
    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// The totals under the log buttons and the hour strip beneath them, from
/// one pass over the log, so the numbers and the squares always agree.
struct WindowTotals: Equatable, Sendable {
    static let kinds: [EventKind] = [.feed, .wet, .dirty, .sleep]
    static let columns = 24

    var interval: DateInterval
    /// The first column's hour. A day's window starts on the hour; the last
    /// 24 hours is drawn as the 24 whole hours ending with the current one.
    var gridStart: Date
    var feeds = 0
    var wet = 0
    var dirty = 0
    var sleepSeconds: TimeInterval = 0
    /// Per kind, one value per hour of the window: entries started in that
    /// hour, or for sleep the fraction of the hour asleep.
    var hours: [EventKind: [Double]] = [:]
    /// Columns that start after now: an empty future, not an empty past.
    var futureFrom: Int = columns

    static func make(events: [LogEvent], window: TotalsWindow, now: Date = .now, calendar: Calendar = .current) -> WindowTotals {
        let interval = window.interval(at: now, calendar: calendar)
        let start: Date = switch window {
        case .day: interval.start
        case .last24Hours: (calendar.dateInterval(of: .hour, for: now)?.start ?? now).addingTimeInterval(-Double(columns - 1) * 3600)
        }
        var totals = WindowTotals(interval: interval, gridStart: start)
        for kind in kinds { totals.hours[kind] = Array(repeating: 0, count: columns) }
        func column(_ date: Date) -> Int? {
            let index = Int(date.timeIntervalSince(start) / 3600)
            return (0..<columns).contains(index) ? index : nil
        }
        var sleeps: [(start: Date, end: Date)] = []
        for event in events {
            let at = event.start
            switch event.eventKind {
            case .feed, .wet, .dirty:
                guard window.holds(at, in: interval) else { continue }
                switch event.eventKind {
                case .feed: totals.feeds += 1
                case .wet: totals.wet += 1
                default: totals.dirty += 1
                }
                if let index = column(at) { totals.hours[event.eventKind]?[index] += 1 }
            case .sleep:
                let end = min(event.endedAt ?? (event.isRunning ? now : at), now)
                let clippedStart = max(at, min(interval.start, start))
                let clippedEnd = min(end, interval.end)
                if clippedEnd > clippedStart { sleeps.append((clippedStart, clippedEnd)) }
            case .weight:
                break
            }
        }
        for bout in DayTally.coveredIntervals(sleeps) {
            let counted = min(bout.end, interval.end).timeIntervalSince(max(bout.start, interval.start))
            if counted > 0 { totals.sleepSeconds += counted }
            for index in 0..<columns {
                let hourStart = start.addingTimeInterval(Double(index) * 3600)
                let overlap = min(bout.end, hourStart.addingTimeInterval(3600)).timeIntervalSince(max(bout.start, hourStart))
                if overlap > 0 { totals.hours[.sleep]?[index] += overlap / 3600 }
            }
        }
        totals.futureFrom = max(0, min(columns, Int(ceil(now.timeIntervalSince(start) / 3600))))
        return totals
    }

    func count(_ kind: EventKind) -> Int {
        switch kind {
        case .feed: feeds
        case .wet: wet
        case .dirty: dirty
        default: 0
        }
    }

    /// "7 feeds · 3 pee · 2 poop · 5h 10m sleep", in the order of the strip.
    var line: String {
        var parts = [
            Format.count(feeds, "feed"),
            "\(wet) \(EventKind.wet.label.lowercased())",
            "\(dirty) \(EventKind.dirty.label.lowercased())",
        ]
        if sleepSeconds >= 60 { parts.append("\(Format.compactDuration(sleepSeconds)) sleep") }
        return parts.joined(separator: " · ")
    }
}
