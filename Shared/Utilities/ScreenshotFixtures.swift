import CoreData
import Foundation

#if DEBUG
/// Seeds a believable day-three newborn log for App Store captures and for
/// looking at the screens headlessly. Never runs in Release.
@MainActor
enum ScreenshotFixtures {
    static func seed(into store: EventStore, now: Date = .now) {
        let calendar = Calendar.current
        let birth = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        if store.child == nil {
            store.createChild(name: "Nora", birthDate: birth)
        } else if let child = store.child {
            store.update(child: child, name: "Nora", birthDate: birth)
        }
        guard let child = store.child else { return }
        let context = store.context
        for event in store.events { context.delete(event) }

        func add(_ kind: EventKind, hoursAgo: Double, side: FeedSide? = nil, minutes: Double = 0, stool: StoolColor? = nil) {
            let start = now.addingTimeInterval(-hoursAgo * 3600)
            let end: Date? = kind == .feed ? start.addingTimeInterval(minutes * 60) : (kind == .sleep ? start.addingTimeInterval(minutes * 60) : nil)
            let event = store.persistence.insert(kind: kind, at: start, side: side, ended: end, for: child, in: context)
            event.stool = stool
        }
        // Today (day 3): feeds every 2-3 hours, three wet, three dirty so far.
        add(.feed, hoursAgo: 2.23, side: .left, minutes: 18)
        add(.wet, hoursAgo: 0.8)
        add(.dirty, hoursAgo: 3.1, stool: .green)
        add(.feed, hoursAgo: 4.9, side: .right, minutes: 22)
        add(.sleep, hoursAgo: 4.5, minutes: 95)
        add(.wet, hoursAgo: 5.2)
        add(.feed, hoursAgo: 7.4, side: .left, minutes: 15)
        add(.dirty, hoursAgo: 7.6, stool: .green)
        add(.sleep, hoursAgo: 9.9, minutes: 130)
        add(.feed, hoursAgo: 10.1, side: .right, minutes: 20)
        add(.wet, hoursAgo: 10.3)
        add(.dirty, hoursAgo: 12.5, stool: .black)
        add(.feed, hoursAgo: 12.8, side: .bottle, minutes: 12)
        // Yesterday (day 2) and the day before (day 1).
        for hour in stride(from: 26.0, through: 46.0, by: 3.0) {
            add(.feed, hoursAgo: hour, side: Int(hour) % 2 == 0 ? .left : .right, minutes: 17)
        }
        add(.wet, hoursAgo: 27); add(.wet, hoursAgo: 38); add(.dirty, hoursAgo: 30, stool: .black); add(.dirty, hoursAgo: 41, stool: .black)
        add(.sleep, hoursAgo: 33, minutes: 150)
        add(.feed, hoursAgo: 50, side: .left, minutes: 10); add(.feed, hoursAgo: 54, side: .right, minutes: 12)
        add(.feed, hoursAgo: 58, side: .left, minutes: 9); add(.feed, hoursAgo: 61, side: .right, minutes: 14)
        add(.wet, hoursAgo: 52); add(.dirty, hoursAgo: 56, stool: .black)
        store.persistence.save(context)
        store.reload()
    }
}
#endif
