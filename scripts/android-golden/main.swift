import CoreData
import Foundation

// Writes the answers the iOS sources compute for a fixed log, so the Android
// port's JVM tests can assert the same numbers and words. Run through
// scripts/android-golden/export.sh; never edit golden.json by hand.

let zone = TimeZone(identifier: "America/Los_Angeles")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = zone
calendar.locale = Locale(identifier: "en_US")
NSTimeZone.default = zone

func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

let container = NSPersistentContainer(name: "Golden", managedObjectModel: BabyModel.model)
let description = NSPersistentStoreDescription()
description.type = NSInMemoryStoreType
container.persistentStoreDescriptions = [description]
container.loadPersistentStores { _, error in if let error { fatalError("\(error)") } }
let context = container.viewContext

let now = at(2026, 10, 14, 15, 30)
let birth = at(2026, 10, 9, 4, 12)
let child = Child.make(in: context, name: "Elsa", birthDate: birth)

var eventJSON: [[String: Any]] = []
var seq = 0
@discardableResult
func add(_ kind: EventKind, _ start: Date, end: Date? = nil, running: Bool = false, sides: [FeedSide] = [], amount: Double = 0, stool: StoolColor? = nil, note: String? = nil) -> LogEvent {
    let e = LogEvent.make(in: context, child: child, kind: kind, at: start)
    seq += 1
    e.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", seq))
    e.createdAt = start
    if kind == .feed && !running { e.endedAt = end ?? start }
    if kind == .sleep && !running { e.endedAt = end }
    e.feedSides = sides
    e.amount = amount
    e.stool = stool
    e.note = note
    var row: [String: Any] = ["id": e.id!.uuidString, "kind": kind.rawValue, "start": start.timeIntervalSince1970, "amount": amount]
    if let endedAt = e.endedAt { row["end"] = endedAt.timeIntervalSince1970 }
    if let side = e.side { row["side"] = side }
    if let stool { row["stool"] = stool.rawValue }
    if let note { row["note"] = note }
    eventJSON.append(row)
    return e
}

// Logging began the afternoon of Oct 10 (day 2).
add(.weight, at(2026, 10, 10, 14, 5), amount: 3300, note: "Hospital scale")
add(.feed, at(2026, 10, 10, 14, 20), end: at(2026, 10, 10, 14, 45), sides: [.left])
add(.wet, at(2026, 10, 10, 16, 0))
add(.dirty, at(2026, 10, 10, 18, 10), stool: .black)
add(.feed, at(2026, 10, 10, 19, 0), sides: [.right, .left])
add(.sleep, at(2026, 10, 10, 22, 30), end: at(2026, 10, 11, 1, 15))
// Oct 11 complete
for (h, m, s) in [(2, 0, [FeedSide.left]), (5, 10, [.right]), (8, 0, [.bottle]), (11, 30, [.left, .right]), (14, 45, []), (18, 0, [.bottle]), (21, 20, [.right])] {
    add(.feed, at(2026, 10, 11, h, m), sides: s, amount: s == [.bottle] ? 60 : 0)
}
for h in [3, 9, 13, 17] { add(.wet, at(2026, 10, 11, h, 5)) }
add(.dirty, at(2026, 10, 11, 10, 0), stool: .green, note: "Seemed fussy, \"a lot\" of gas")
add(.dirty, at(2026, 10, 11, 20, 0), stool: .yellow)
add(.sleep, at(2026, 10, 11, 12, 0), end: at(2026, 10, 11, 13, 30))
add(.sleep, at(2026, 10, 11, 13, 0), end: at(2026, 10, 11, 14, 0)) // overlaps: second parent
add(.sleep, at(2026, 10, 11, 23, 0), end: at(2026, 10, 12, 2, 40))
// Oct 12 nothing logged at all (beyond the sleep spill)
// Oct 13 complete
for (h, m) in [(1, 0), (4, 30), (7, 45), (12, 0), (16, 10), (20, 30), (23, 50)] {
    add(.feed, at(2026, 10, 13, h, m), sides: [.left])
}
for h in [2, 6, 10, 14, 18, 22] { add(.wet, at(2026, 10, 13, h, 15)) }
add(.dirty, at(2026, 10, 13, 9, 0), stool: .yellow)
add(.weight, at(2026, 10, 13, 10, 0), amount: 3450)
add(.sleep, at(2026, 10, 13, 13, 0), end: at(2026, 10, 13, 16, 0))
// Oct 14 (today, so far)
add(.feed, at(2026, 10, 14, 3, 0), sides: [.right])
add(.wet, at(2026, 10, 14, 5, 40))
add(.feed, at(2026, 10, 14, 7, 0), end: at(2026, 10, 14, 7, 35), sides: [.left, .bottle], amount: 45)
add(.dirty, at(2026, 10, 14, 11, 0), stool: .brown)
add(.sleep, at(2026, 10, 14, 9, 0), end: at(2026, 10, 14, 10, 20))
add(.feed, at(2026, 10, 14, 13, 10), sides: [.bottle])
add(.wet, at(2026, 10, 14, 13, 55))
add(.sleep, at(2026, 10, 14, 14, 5), running: true)
try! context.save()

let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
let events = try! context.fetch(request).sorted { $0.start > $1.start }

func iso(_ d: Date?) -> Any { d.map { $0.timeIntervalSince1970 } ?? NSNull() }

func summaryOut(_ s: NowSummary) -> [String: Any] {
    [
        "feedLine": s.feedLine(now: now), "diaperLine": s.diaperLine(now: now), "awakeLine": s.awakeLine(now: now),
        "sleepLine": s.sleepLine(now: now) ?? NSNull(), "todayLine": s.todayLine, "nextSideLine": s.nextSideLine ?? NSNull(),
        "leadLine": s.leadLine(now: now), "supportingLines": s.supportingLines(now: now), "leadElapsed": s.leadElapsed(now: now),
        "dayOfLife": s.dayOfLife ?? NSNull(), "todayFeeds": s.todayFeeds, "todayWet": s.todayWet, "todayDirty": s.todayDirty,
        "lastFeedAt": iso(s.lastFeedAt), "runningSleepStart": iso(s.runningSleepStart), "lastWokeAt": iso(s.lastWokeAt),
        "recentTitles": (s.recent ?? []).prefix(8).map { $0.title(now: now) },
    ]
}

var summaries: [[String: Any]] = []
let trackedCases: [(String, Set<EventKind>)] = [("all", []), ("noFeed", [.feed]), ("sleepOnly", [.feed, .wet, .dirty]), ("noDirty", [.dirty])]
let windows: [TotalsWindow] = [.midnight, .day(startHour: 6), .last24Hours]
for words in DiaperWords.allCases {
    AppGroup.defaults.set(words.rawValue, forKey: AppGroup.Key.diaperWords)
    for (name, hidden) in trackedCases {
        for window in windows {
            let tracked = TrackedKinds(hidden: hidden)
            let s = NowSummary.make(child: child, events: events, now: now, calendar: calendar, window: window, tracked: tracked)
            let visible = events.filter { tracked.contains($0.eventKind) }
            let totals = WindowTotals.make(events: visible, window: window, now: now, calendar: calendar)
            var hours: [String: [Double]] = [:]
            for (k, v) in totals.hours { hours[k.rawValue] = v }
            summaries.append([
                "words": words.rawValue, "tracked": name, "hidden": hidden.map(\.rawValue).sorted(), "window": window.storedValue,
                "summary": summaryOut(s), "headline": tracked.headline,
                "totals": ["feeds": totals.feeds, "wet": totals.wet, "dirty": totals.dirty, "sleepSeconds": totals.sleepSeconds,
                           "futureFrom": totals.futureFrom, "gridStart": totals.gridStart.timeIntervalSince1970, "line": totals.line(tracked), "hours": hours],
                "windowTitle": window.title(calendar: calendar),
            ])
        }
    }
}
AppGroup.defaults.set(DiaperWords.peePoop.rawValue, forKey: AppGroup.Key.diaperWords)

var tallies: [[String: Any]] = []
for day in 9...15 {
    let t = DayTally.make(events: events, on: at(2026, 10, day, 12, 0), now: now, calendar: calendar)
    tallies.append(["day": day, "feeds": t.feeds, "wet": t.wet, "dirty": t.dirty, "sleepSeconds": t.sleepSeconds, "bottle": t.bottleMillilitres])
}

func reportOut(_ r: SummaryReport) -> [String: Any] {
    [
        "start": r.start.timeIntervalSince1970, "end": r.end.timeIntervalSince1970, "rangeLabel": r.rangeLabel,
        "averageFeeds": r.averageFeedsPerDay, "averageWet": r.averageWetPerDay, "averageDirty": r.averageDirtyPerDay,
        "averageSleep": r.averageSleepSeconds, "longestSleep": r.longestSleepSeconds, "longestGap": r.longestFeedGapSeconds,
        "bottlePerDay": r.averageBottleMillilitresPerDay, "bottlePerFeed": r.averageBottleMillilitresPerFeed,
        "averagesNote": r.averagesNote, "weightChange": r.weightChangeDescription ?? NSNull(),
        "weightChangeMetric": r.weightChangeGrams.map { Format.gramsChange($0, imperial: false) } ?? NSNull(),
        "lowestWetDay": r.lowestDay(\.wet)?.date.timeIntervalSince1970 ?? NSNull(),
        "notes": r.notes.map { ["date": $0.date.timeIntervalSince1970, "text": $0.text] },
        "days": r.days.map { d in [
            "date": d.date.timeIntervalSince1970, "dayOfLife": d.dayOfLife ?? NSNull(), "feeds": d.feeds, "wet": d.wet, "dirty": d.dirty,
            "bottle": d.bottleMillilitres, "sleep": d.sleepSeconds, "longestSleep": d.longestSleepSeconds, "gap": d.longestFeedGapSeconds,
            "bottleFeeds": d.bottleFeeds, "weight": d.weightGrams ?? NSNull(), "stools": d.stoolColors.map(\.rawValue),
            "partial": d.partial?.label ?? NSNull(),
        ] as [String: Any] },
    ]
}
let reports: [[String: Any]] = [
    ["from": at(2026, 10, 8, 9, 0).timeIntervalSince1970, "to": now.timeIntervalSince1970, "hidden": [String](), "report": reportOut(SummaryReport.make(childName: "Elsa", birthDate: birth, events: events, from: at(2026, 10, 8, 9, 0), to: now, now: now, calendar: calendar))],
    ["from": at(2026, 10, 11, 0, 0).timeIntervalSince1970, "to": at(2026, 10, 13, 0, 0).timeIntervalSince1970, "hidden": ["sleep"], "report": reportOut(SummaryReport.make(childName: "Elsa", birthDate: birth, events: events, from: at(2026, 10, 11, 0, 0), to: at(2026, 10, 13, 0, 0), tracked: TrackedKinds(hidden: [.sleep]), now: now, calendar: calendar))],
]

let csv = SummaryReport.csv(events: events, childName: "Elsa")

var format: [String: Any] = [:]
let durations: [Double] = [0, 59, 60, 61, 3599, 3600, 3660, 7980, 86399, 86400, 90000, 200000]
format["compact"] = durations.map { ["s": $0, "v": Format.compactDuration($0)] }
format["duration"] = durations.map { ["s": $0, "v": Format.duration($0)] }
format["asleep"] = durations.map { ["s": $0, "v": Format.asleep($0)] }
format["ml"] = [0.0, 30, 45, 59.1, 60, 88.7, 120, 240].map { ["v": $0, "metric": Format.millilitres($0, imperial: false), "imperial": Format.millilitres($0, imperial: true)] }
format["grams"] = [2950.0, 3300, 3450, 3999, 4210].map { ["v": $0, "metric": Format.grams($0, imperial: false), "imperial": Format.grams($0, imperial: true)] }
format["gramsChange"] = [-210.0, -5, 0.4, 150, 312].map { ["v": $0, "metric": Format.gramsChange($0, imperial: false), "imperial": Format.gramsChange($0, imperial: true)] }

var guidance: [[String: Any]] = []
for day in 0...16 {
    let r = Guidance.range(forDayOfLife: day)
    guidance.append(["day": day, "outDay": r.day, "wet": r.wetMin, "dirty": r.dirtyMin, "stool": r.stoolNote, "feedsMin": r.feedsMin, "feedsMax": r.feedsMax, "summary": r.summary])
}

var stains: [[String: Any]] = []
let supplySets: [[StainGuide.Supply]] = [[], StainGuide.Supply.allCases, [.dishSoap], [.detergent, .oxygenBleach], [.hydrogenPeroxide, .whiteVinegar, .bakingSoda]]
for stain in StainGuide.Stain.allCases {
    for set in supplySets {
        let owned = Set(set)
        stains.append([
            "stain": stain.rawValue, "owned": set.map(\.rawValue), "label": stain.label, "firstMove": stain.firstMove,
            "steps": StainGuide.steps(for: stain, owning: owned).map { ["title": $0.title, "detail": $0.detail, "caution": $0.caution ?? NSNull(), "supply": $0.supply?.rawValue ?? NSNull()] as [String: Any] },
            "missing": StainGuide.missing(for: stain, owning: owned).map(\.rawValue),
        ])
    }
}
let supplies = StainGuide.Supply.allCases.map { ["id": $0.rawValue, "label": $0.label, "hint": $0.hint] }

// Reminders: the last summary with every button, midnight window.
let base = NowSummary.make(child: child, events: events, now: now, calendar: calendar, window: .midnight, tracked: .all)
var reminders: [[String: Any]] = []
for interval in FeedReminderInterval.allCases {
    let p = Reminders.feedReminder(for: base, interval: interval, now: now)
    reminders.append(["minutes": interval.rawValue, "label": interval.label, "date": iso(p?.date), "title": p?.title ?? NSNull(), "body": p?.body ?? NSNull()])
}
let checkups = Reminders.checkupReminders(birthDate: birth, nextCheckup: nil, now: at(2026, 10, 9, 9, 0), calendar: calendar).map { ["id": $0.id, "date": $0.date.timeIntervalSince1970, "title": $0.title, "body": $0.body] }
let entered = Reminders.checkupReminders(birthDate: birth, nextCheckup: at(2026, 10, 20, 10, 0), now: now, calendar: calendar).map { ["id": $0.id, "date": $0.date.timeIntervalSince1970, "title": $0.title, "body": $0.body] }

var headlines: [[String: Any]] = []
for mask in 0..<16 {
    let hidden = Set(TrackedKinds.buttons.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
    let t = TrackedKinds(hidden: hidden)
    headlines.append(["hidden": hidden.map(\.rawValue).sorted(), "headline": t.headline, "buttons": t.buttons.map(\.rawValue)])
}

let out: [String: Any] = [
    "zone": zone.identifier, "now": now.timeIntervalSince1970, "birth": birth.timeIntervalSince1970, "childName": "Elsa",
    "events": eventJSON, "summaries": summaries, "tallies": tallies, "reports": reports, "csv": csv, "format": format,
    "guidance": guidance, "guidanceText": ["sourceLine": Guidance.sourceLine, "referenceScope": Guidance.referenceScope, "disclaimer": Guidance.disclaimer, "callIf": Guidance.callIf],
    "stains": stains, "supplies": supplies, "stainRules": ["careLabel": StainGuide.careLabelRule, "never": StainGuide.neverRule],
    "feedReminders": reminders, "checkups": checkups, "enteredCheckup": entered, "headlines": headlines,
]
let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
FileManager.default.createFile(atPath: CommandLine.arguments[1], contents: data)
print("wrote \(CommandLine.arguments[1]) with \(eventJSON.count) events")
