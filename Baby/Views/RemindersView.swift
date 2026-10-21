import SwiftUI
import UIKit
import UserNotifications

/// The reminder offer stays out of UI tests, which all run with
/// `-NoCloudKit` and assert on Now; `-ShowReminderOffer` brings it back.
enum ReminderOfferGate {
    static var isEnabled: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ShowReminderOffer") { return true }
        return !args.contains("-NoCloudKit") && !ScreenshotConfig.isEnabled
        #else
        true
        #endif
    }
}

/// Where a tapped notification sends the app. A checkup note opens the
/// pediatrician summary: the reports for Baby+, its preview and trial before.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Counts taps, so the same route twice still moves the tab.
    @Published private(set) var checkupRequests = 0
    /// The Reports tab leads with the summary the note promised.
    @Published var showsCheckupPitch = false

    func openCheckup() {
        showsCheckupPitch = true
        checkupRequests += 1
    }
}

/// The app's notification delegate: banners in the foreground too (a
/// reminder at 3am arrives with the app open), and taps routed.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo[Reminders.routeKey] as? String
        guard route == Reminders.checkupRoute else { return }
        await MainActor.run { AppRouter.shared.openCheckup() }
    }
}

/// Offered once, a few seconds after the first feed is logged: the moment a
/// parent knows what the next one will need. Both reminders are this phone's
/// alone and can be changed in Settings.
struct FeedReminderOfferView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var events: EventStore
    @State private var interval: FeedReminderInterval = Reminders.feedingStyle?.suggestedInterval ?? .twoAndAHalfHours
    @State private var checkups = true
    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            // Scrolls at large text sizes, so the two buttons stay on screen.
            ScrollView {
                choices
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: AppTheme.tightSpacing) {
                Button(isAsking ? "Turning on…" : "Turn on reminders") { accept() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isAsking)
                    .accessibilityIdentifier("reminderOffer.accept")
                Button("Not now") { decline() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("reminderOffer.decline")
            }
        }
        .padding(AppTheme.margin)
        .padding(.top, AppTheme.tightSpacing)
        .background(AppTheme.paper.ignoresSafeArea())
        .tint(AppTheme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            Reminders.hasOfferedFeedReminder = true
            // Someone helping with a log they joined rarely takes the baby
            // to checkups; the parents' phones carry those notes.
            if let child = events.child, events.persistence.isShared(child) { checkups = false }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                Text("Remind you about the next feed?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A nudge on this phone, counted from when the last feed started, with the side to start on if you breastfeed.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            IntervalChips(selection: $interval)
            Toggle(isOn: $checkups) {
                VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                    Text("Before checkups too")
                        .font(.subheadline.weight(.semibold))
                    Text(events.child?.birthDate == nil && Reminders.nextCheckup == nil
                        ? "The evening before a newborn visit. Add the birth date or the visit date in Settings > Reminders."
                        : "The evening before a newborn visit, a note that your summary for the doctor is ready.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("reminderOffer.checkups")
        }
    }

    private func accept() {
        isAsking = true
        Task {
            let allowed = await Reminders.requestPermission()
            if allowed {
                Reminders.feedInterval = interval
                Reminders.checkupRemindersOn = checkups
                Reminders.reschedule(summary: events.summary, birthDate: events.child?.birthDate)
            }
            isAsking = false
            dismiss()
        }
    }

    private func decline() {
        dismiss()
    }
}

/// 2h, 2½h, 3h, 3½h, 4h: one choice, the feed colour when on.
struct IntervalChips: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: FeedReminderInterval

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AppTheme.tightSpacing))
            : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
            ForEach(FeedReminderInterval.choices) { choice in
                let isOn = selection == choice
                Button {
                    Haptics.selected()
                    selection = choice
                } label: {
                    Text(choice.shortLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? AppTheme.feed : AppTheme.card, in: AppTheme.buttonShape)
                        .overlay(AppTheme.buttonShape.strokeBorder(isOn ? AppTheme.feed : AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
                        .contentShape(AppTheme.buttonShape)
                }
                .pressableCard()
                .accessibilityLabel("Every \(choice.label)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("reminderInterval.\(choice.rawValue)")
            }
        }
    }
}

/// Settings > Reminders: the same two choices, plus the next visit date.
struct RemindersSection: View {
    @EnvironmentObject private var events: EventStore
    @State private var interval = Reminders.feedInterval
    @State private var checkups = Reminders.checkupRemindersOn
    @State private var hasCheckupDate = Reminders.nextCheckup != nil
    @State private var checkupDate = Reminders.nextCheckup ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var isDenied = false

    var body: some View {
        Section {
            Picker("Feed reminder", selection: $interval) {
                Text("Off").tag(FeedReminderInterval.off)
                ForEach(FeedReminderInterval.choices) { choice in
                    Text("Every \(choice.label)").tag(choice)
                }
            }
            .accessibilityIdentifier("settings.feedReminder")
            Toggle("Checkup reminders", isOn: $checkups)
                .accessibilityIdentifier("settings.checkupReminders")
            if checkups {
                Toggle("Add next checkup date", isOn: $hasCheckupDate)
                if hasCheckupDate {
                    LabeledContent("Next checkup") {
                        DatePicker("Next checkup", selection: $checkupDate, in: Date.now..., displayedComponents: .date)
                            .labelsHidden()
                            .themedDatePicker()
                    }
                }
            }
            if isDenied, interval != .off || checkups {
                Button("Allow notifications in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(footer)
        }
        .task { isDenied = await Reminders.isDenied() }
        .onChange(of: interval) { _, value in
            Reminders.feedInterval = value
            apply(asking: value != .off)
        }
        .onChange(of: checkups) { _, value in
            Reminders.checkupRemindersOn = value
            apply(asking: value)
        }
        .onChange(of: hasCheckupDate) { _, _ in saveDate() }
        .onChange(of: checkupDate) { _, _ in saveDate() }
    }

    private var footer: String {
        if isDenied, interval != .off || checkups {
            return "Notifications are off for Baby Tracker, so these can't arrive."
        }
        return "On this phone only. The feed reminder counts from when the last feed started. Checkup reminders arrive the evening before the date you add, or before the usual newborn visits when there is a birth date."
    }

    private func saveDate() {
        Reminders.nextCheckup = hasCheckupDate ? checkupDate : nil
        apply(asking: false)
    }

    private func apply(asking: Bool) {
        Task {
            if asking { _ = await Reminders.requestPermission() }
            isDenied = await Reminders.isDenied()
            Reminders.reschedule(summary: events.summary, birthDate: events.child?.birthDate)
        }
    }
}
