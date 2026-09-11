import Foundation
import UserNotifications

@MainActor
enum NotificationService {
    static let reminderIdentifier = "caffeine.bedtime.preview"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    static func scheduleBedtimePreview(at bedtime: Date, estimatedMilligrams: Double) async {
        cancelReminder()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let fireDate = bedtime.addingTimeInterval(-2 * 3600)
        guard fireDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tonight's caffeine estimate"
        content.body = "About \(CaffeineFormat.milligrams(estimatedMilligrams)) may remain at bedtime based on your current half-life setting."
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        )
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
