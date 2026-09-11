import AppIntents
import Foundation
import WidgetKit

struct LogShotIntent: AppIntent {
    static let title: LocalizedStringResource = "Log shot"
    static let description = IntentDescription("Log a GLP-1 shot instantly.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let timestamp = Date()
        let pending = PendingWidgetShot(timestamp: timestamp)
        GLPAppGroup.enqueueWidgetShot(pending)

        let defaults = GLPAppGroup.userDefaults
        defaults.set(timestamp, forKey: GLPStorageKey.widgetLastLoggedAt.rawValue)
        RecentShotsStore.record(RecentShot(id: pending.id, timestamp: timestamp))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
