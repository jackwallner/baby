import Foundation
@preconcurrency import UserNotifications

/// The gap a parent picked between the start of one feed and a nudge for the
/// next. A timer they chose, never a prediction.
enum FeedReminderInterval: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case twoHours = 120
    case twoAndAHalfHours = 150
    case threeHours = 180
    case threeAndAHalfHours = 210
    case fourHours = 240

    var id: Int { rawValue }

    static let choices: [FeedReminderInterval] = [.twoHours, .twoAndAHalfHours, .threeHours, .threeAndAHalfHours, .fourHours]

    var duration: TimeInterval { TimeInterval(rawValue * 60) }

    /// "2½ hours".
    var label: String {
        switch self {
        case .off: "Off"
        case .twoHours: "2 hours"
        case .twoAndAHalfHours: "2½ hours"
        case .threeHours: "3 hours"
        case .threeAndAHalfHours: "3½ hours"
        case .fourHours: "4 hours"
        }
    }

    /// "2½h", for the chips.
    var shortLabel: String {
        switch self {
        case .off: "Off"
        case .twoHours: "2h"
        case .twoAndAHalfHours: "2½h"
        case .threeHours: "3h"
        case .threeAndAHalfHours: "3½h"
        case .fourHours: "4h"
        }
    }
}

/// How the baby is fed, asked once at setup. It only picks which reminder
/// gap is selected first; it changes no button and no number.
enum FeedingStyle: String, CaseIterable, Identifiable, Sendable {
    case breast
    case bottle
    case both
    case pumped
    case expecting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breast: "Breast"
        case .bottle: "Formula"
        case .both: "Both"
        case .pumped: "Pumped milk"
        case .expecting: "Not born yet"
        }
    }

    var suggestedInterval: FeedReminderInterval {
        self == .bottle ? .threeHours : .twoAndAHalfHours
    }
}

/// This phone's local notifications: the feed reminder and the evening-before
/// checkup note. Settings live in the App Group so the widget, which logs
/// without the app, reschedules with the same choices.
enum Reminders {
    static let feedID = "baby.feed"
    static let checkupPrefix = "baby.checkup."
    /// A tapped notification's `userInfo[routeKey]`.
    static let routeKey = "route"
    static let checkupRoute = "checkup"
    /// The hour the checkup note arrives the evening before.
    static let checkupEveningHour = 19
    /// Newborn checkups by day of life when no date was entered: the first
    /// visit a few days after birth, about two weeks, about a month.
    static let typicalCheckupDays = [4, 14, 30]

    private enum Key {
        static let feedInterval = "reminder.feedMinutes"
        static let hasOffered = "reminder.offered"
        static let checkups = "reminder.checkups"
        static let nextCheckup = "reminder.nextCheckup"
        static let feedingStyle = "setup.feedingStyle"
    }

    /// Overridable so tests never touch the real App Group.
    nonisolated(unsafe) static var defaultsOverride: UserDefaults?
    private static var defaults: UserDefaults { defaultsOverride ?? AppGroup.defaults }

    static var feedInterval: FeedReminderInterval {
        get { FeedReminderInterval(rawValue: defaults.integer(forKey: Key.feedInterval)) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.feedInterval) }
    }

    /// The after-the-first-feed offer is shown once, whatever the answer.
    static var hasOfferedFeedReminder: Bool {
        get { defaults.bool(forKey: Key.hasOffered) }
        set { defaults.set(newValue, forKey: Key.hasOffered) }
    }

    static var checkupRemindersOn: Bool {
        get { defaults.bool(forKey: Key.checkups) }
        set { defaults.set(newValue, forKey: Key.checkups) }
    }

    /// This phone only: a visit date is not part of the shared log.
    static var nextCheckup: Date? {
        get {
            let value = defaults.double(forKey: Key.nextCheckup)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue { defaults.set(newValue.timeIntervalSince1970, forKey: Key.nextCheckup) } else { defaults.removeObject(forKey: Key.nextCheckup) }
        }
    }

    static var feedingStyle: FeedingStyle? {
        get { defaults.string(forKey: Key.feedingStyle).flatMap(FeedingStyle.init) }
        set { defaults.set(newValue?.rawValue, forKey: Key.feedingStyle) }
    }

    /// One notification to schedule. Pure data, so tests read it directly.
    struct Planned: Equatable, Sendable {
        var id: String
        var date: Date
        var title: String
        var body: String
        var route: String?
    }

    // MARK: - Planning

    /// "2½ hours since the last feed", due that long after the last feed
    /// started. Nothing while a feed runs, before any feed, or once it is due.
    static func feedReminder(for summary: NowSummary, interval: FeedReminderInterval, now: Date = .now) -> Planned? {
        guard interval != .off, !summary.isFeeding, let last = summary.lastFeedAt else { return nil }
        let due = last.addingTimeInterval(interval.duration)
        guard due > now.addingTimeInterval(30) else { return nil }
        let started = "Last feed started at \(Format.time(last))."
        let body = summary.nextBreastSide.map { "\(started) Start on \($0.label)." } ?? started
        return Planned(id: feedID, date: due, title: "\(interval.label) since \(summary.childName)'s last feed", body: body, route: nil)
    }

    /// The evening before a checkup: the date the parent entered, else the
    /// usual newborn visits counted from the birth date. Never a guessed
    /// birth date, and nothing once the first month is over.
    static func checkupReminders(
        birthDate: Date?,
        nextCheckup: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Planned] {
        if let nextCheckup, nextCheckup > now {
            guard let evening = eveningBefore(nextCheckup, calendar: calendar), evening > now else { return [] }
            return [Planned(
                id: checkupPrefix + "entered",
                date: evening,
                title: "Checkup tomorrow",
                body: "Your summary for the doctor is ready: feeds, diapers, sleep and weight since the last visit.",
                route: checkupRoute
            )]
        }
        guard let birthDate else { return [] }
        return typicalCheckupDays.compactMap { day in
            let visit = DateHelpers.date(forDayOfLife: day, birthDate: birthDate, calendar: calendar)
            guard let evening = eveningBefore(visit, calendar: calendar), evening > now else { return nil }
            return Planned(
                id: checkupPrefix + "day\(day)",
                date: evening,
                title: "Checkup coming up?",
                body: "Newborn visits come often in the first month. Your summary for the doctor is ready.",
                route: checkupRoute
            )
        }
    }

    private static func eveningBefore(_ date: Date, calendar: Calendar) -> Date? {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
        return dayBefore.flatMap { calendar.date(bySettingHour: checkupEveningHour, minute: 0, second: 0, of: $0) }
    }

    // MARK: - Scheduling

    /// Replaces this phone's pending reminders with the ones the summary and
    /// the stored choices call for. Cheap enough to run on every change.
    static func reschedule(summary: NowSummary, birthDate: Date?, now: Date = .now) {
        var planned: [Planned] = []
        if let feed = feedReminder(for: summary, interval: feedInterval, now: now) { planned.append(feed) }
        if checkupRemindersOn {
            planned += checkupReminders(birthDate: birthDate, nextCheckup: nextCheckup, now: now)
        }
        let center = UNUserNotificationCenter.current()
        let keep = Set(planned.map(\.id))
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { ($0 == feedID || $0.hasPrefix(checkupPrefix)) && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for item in planned {
            center.add(request(for: item, now: now))
        }
    }

    private static func request(for item: Planned, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = item.route ?? "feed"
        if let route = item.route { content.userInfo = [routeKey: route] }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSince(now)), repeats: false)
        // The same identifier replaces the pending one in place.
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }

    /// Asks once. True when this phone may show notifications.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
