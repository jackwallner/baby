import Foundation

/// The answer to the 3am question, computed once and shown everywhere: the Now
/// card, both widgets, the complication, and the Watch app. Codable so the
/// phone can push it to the Watch as-is.
struct NowSummary: Codable, Equatable, Sendable {
    var childName: String = "Baby"
    var dayOfLife: Int?
    var lastFeedAt: Date?
    var lastFeedSide: FeedSide?
    var lastDiaperAt: Date?
    var lastDiaperKind: EventKind?
    var runningSleepStart: Date?
    var runningFeedStart: Date?
    var runningFeedSide: FeedSide?
    var todayFeeds: Int = 0
    var todayWet: Int = 0
    var todayDirty: Int = 0
    var generatedAt: Date = .now

    static let empty = NowSummary()

    /// The side to offer next, for a one-tap feed with no side chosen.
    var suggestedSide: FeedSide { lastFeedSide?.next ?? .left }

    var isSleeping: Bool { runningSleepStart != nil }
    var isFeeding: Bool { runningFeedStart != nil }

    // MARK: - Lines

    /// "Fed 2h 14m ago · Left", or "Feeding · Left · 12m" while a timed feed runs.
    func feedLine(now: Date = .now) -> String {
        if let runningFeedStart {
            let side = runningFeedSide.map { " · \($0.label)" } ?? ""
            return "Feeding\(side) · \(Format.compactDuration(now.timeIntervalSince(runningFeedStart)))"
        }
        guard let lastFeedAt else { return "No feed logged yet" }
        let side = lastFeedSide.map { " · \($0.label)" } ?? ""
        return "Fed \(Format.ago(lastFeedAt, now: now))\(side)"
    }

    /// "Last diaper 48m ago · Wet".
    func diaperLine(now: Date = .now) -> String {
        guard let lastDiaperAt else { return "No diaper logged yet" }
        let kind = lastDiaperKind.map { " · \($0.label)" } ?? ""
        return "Last diaper \(Format.ago(lastDiaperAt, now: now))\(kind)"
    }

    /// "Asleep 1h 05m" while a sleep runs; nil otherwise.
    func sleepLine(now: Date = .now) -> String? {
        guard let runningSleepStart else { return nil }
        return "Asleep \(Format.compactDuration(now.timeIntervalSince(runningSleepStart)))"
    }

    /// "3 wet · 2 dirty · 7 feeds".
    var todayLine: String {
        "\(todayWet) wet · \(todayDirty) dirty · \(Format.count(todayFeeds, "feed"))"
    }

    // MARK: - Building

    /// Pure: derives the summary from the events list so tests can pin it.
    static func make(child: Child?, events: [LogEvent], now: Date = .now, calendar: Calendar = .current) -> NowSummary {
        var summary = NowSummary()
        summary.generatedAt = now
        guard let child else { return summary }
        summary.childName = child.displayName
        summary.dayOfLife = child.dayOfLife(on: now, calendar: calendar)
        let sorted = events.sorted { $0.start > $1.start }
        for event in sorted {
            switch event.eventKind {
            case .feed:
                if event.isRunning, summary.runningFeedStart == nil {
                    summary.runningFeedStart = event.startedAt
                    summary.runningFeedSide = event.feedSide
                } else if summary.lastFeedAt == nil, !event.isRunning {
                    summary.lastFeedAt = event.startedAt
                    summary.lastFeedSide = event.feedSide
                }
            case .wet, .dirty:
                if summary.lastDiaperAt == nil {
                    summary.lastDiaperAt = event.startedAt
                    summary.lastDiaperKind = event.eventKind
                }
            case .sleep:
                if event.isRunning, summary.runningSleepStart == nil {
                    summary.runningSleepStart = event.startedAt
                }
            case .weight:
                break
            }
            if calendar.isDate(event.start, inSameDayAs: now) {
                switch event.eventKind {
                case .feed: summary.todayFeeds += 1
                case .wet: summary.todayWet += 1
                case .dirty: summary.todayDirty += 1
                default: break
                }
            }
        }
        // A running feed still counts as the most recent feed for "which side".
        if summary.lastFeedAt == nil, let start = summary.runningFeedStart {
            summary.lastFeedAt = start
            summary.lastFeedSide = summary.runningFeedSide
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
    func applying(_ payload: WatchLogPayload, calendar: Calendar = .current) -> NowSummary {
        var s = self
        let sameDay = calendar.isDate(payload.at, inSameDayAs: s.generatedAt)
        switch payload.action {
        case .log:
            switch payload.kind {
            case .feed:
                if s.lastFeedAt == nil || payload.at >= (s.lastFeedAt ?? .distantPast) {
                    s.lastFeedAt = payload.at
                    s.lastFeedSide = payload.side
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
            s.runningSleepStart = payload.at
        case .stopSleep:
            s.runningSleepStart = nil
        }
        s.generatedAt = max(s.generatedAt, payload.at)
        return s
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
        for event in events {
            let start = event.start
            switch event.eventKind {
            case .feed where start >= dayStart && start < dayEnd:
                tally.feeds += 1
                if event.feedSide == .bottle { tally.bottleMillilitres += max(0, event.amount) }
            case .wet where start >= dayStart && start < dayEnd:
                tally.wet += 1
            case .dirty where start >= dayStart && start < dayEnd:
                tally.dirty += 1
            case .sleep:
                // Sleep is credited to the day it happened in, split at midnight.
                let end = event.endedAt ?? (event.isRunning ? now : start)
                let overlapStart = max(start, dayStart)
                let overlapEnd = min(end, dayEnd)
                if overlapEnd > overlapStart { tally.sleepSeconds += overlapEnd.timeIntervalSince(overlapStart) }
            default:
                break
            }
        }
        return tally
    }
}
