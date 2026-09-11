import StoreKit
import SwiftUI
import UIKit

struct CaffeineSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CaffeineSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = CaffeineLogService.shared
    @StateObject private var insights = HealthInsightsService.shared
    @State private var upgradeFocus: PlusFeature?
    @State private var editingPresetIndex: PresetIndex?
    @State private var reminderChangeInFlight = false

    private var bedtimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.bedtimeMinutes / 60,
                minute: settings.bedtimeMinutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            settings.bedtimeMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
        }
    }

    var body: some View {
        Form {
            forecastSection
            appleHealthSection
            bodyDataSection
            quickLogSection
            reminderSection
            subscriptionSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $upgradeFocus) { focus in
            CaffeinePaywallView(paywallImpressionID: "caffeine_settings_\(focus.rawValue)", focus: focus)
        }
        .sheet(item: $editingPresetIndex) { index in
            DrinkPickerSheet(
                initial: settings.quickAddDrinks[index.value],
                title: "Quick log \(index.value + 1)"
            ) { drink in
                settings.quickAddDrinks[index.value] = drink
            }
        }
        .task { health.refreshWriteAuthorization() }
    }

    // MARK: - Sections

    private var forecastSection: some View {
        Section("Forecast") {
            DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
            VStack(alignment: .leading) {
                HStack {
                    Text("Half-life")
                    Spacer()
                    Text("\(settings.halfLifeHours, specifier: "%.1f") hours")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.halfLifeHours, in: 3...8, step: 0.5)
            }
            Stepper(
                "Bedtime preference: \(CaffeineFormat.milligrams(settings.bedtimeThreshold))",
                value: $settings.bedtimeThreshold,
                in: 5...100,
                step: 5
            )
            Text("The FDA describes a typical caffeine half-life of about 4 to 6 hours. Yours is adjustable because clearance varies from person to person. The bedtime preference is a number you chose, not a safety limit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appleHealthSection: some View {
        Section {
            LabeledContent("Saving to Health", value: writeStatusText)
            if health.writeState == .denied {
                Text("Caffeine cannot write to Apple Health right now, so new entries are being kept on this device until access is restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = HealthKitService.privacySettingsURL {
                    Link("Open Settings to allow writing", destination: url)
                }
            } else if health.writeState == .notDetermined {
                Button("Connect Apple Health") {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
            }
            if log.pendingWriteCount > 0 {
                LabeledContent("Waiting to save", value: "\(log.pendingWriteCount)")
                Button("Retry now") { Task { _ = await log.retryPendingLocalEntries() } }
            }
            NavigationLink("Included sources") { CaffeineSourcesView() }
            Text("Your entries are saved as dietary caffeine in Apple Health, marked as manually entered and tagged with the drink name. Deleting one here deletes it there too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Apple Health")
        }
    }

    private var writeStatusText: String {
        switch health.writeState {
        case .authorized: "On"
        case .denied: "Off"
        case .notDetermined: "Not set up"
        case .unavailable: "Unavailable"
        }
    }

    private var bodyDataSection: some View {
        Section {
            Toggle("Read sleep and heart data", isOn: Binding(
                get: { settings.bodyInsightsEnabled },
                set: { enabled in
                    guard enabled else {
                        settings.bodyInsightsEnabled = false
                        return
                    }
                    Task {
                        let granted = await insights.requestAuthorization()
                        settings.bodyInsightsEnabled = granted
                        if granted { await insights.refresh(force: true) }
                    }
                }
            ))
            Text("Powers the Body tab. Caffeine reads sleep, resting heart rate, heart rate variability, heart rate, respiratory rate, blood oxygen, steps, active energy, workouts, body mass, age, and biological sex, and compares them against the days you drank more or less. It is read-only, stays on your device, and logging works fine without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.bodyInsightsEnabled, let url = HealthKitService.privacySettingsURL {
                Link("Change what Caffeine can read", destination: url)
            }
        } header: {
            Text("Body insights")
        }
    }

    private var quickLogSection: some View {
        Section {
            ForEach(Array(settings.quickAddDrinks.enumerated()), id: \.offset) { index, drink in
                Button {
                    guard store.isPro else {
                        upgradeFocus = .customDrinks
                        return
                    }
                    editingPresetIndex = PresetIndex(value: index)
                } label: {
                    HStack {
                        Label(drink.name, systemImage: drink.symbolName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(CaffeineFormat.milligrams(drink.milligrams))
                            .foregroundStyle(.secondary)
                        if !store.isPro {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !store.isPro {
                Button("Customize with Caffeine+") { upgradeFocus = .customDrinks }
            } else {
                Button("Reset to defaults") { settings.quickAddDrinks = DrinkCatalog.defaultPresets }
            }
        } header: {
            Text("Quick log")
        } footer: {
            Text("Typical amounts for a standard serving. Actual content varies with brew, bean, and size.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Bedtime estimate reminder", isOn: Binding(
                get: { settings.reminderEnabled },
                set: { enabled in
                    guard !reminderChangeInFlight else { return }
                    guard store.isPro else {
                        upgradeFocus = .reminder
                        return
                    }
                    reminderChangeInFlight = true
                    Task {
                        if enabled {
                            let granted = await NotificationService.requestAuthorization()
                            settings.reminderEnabled = granted
                            if granted { await HealthKitService.shared.refreshCache() }
                        } else {
                            settings.reminderEnabled = false
                            NotificationService.cancelReminder()
                        }
                        reminderChangeInFlight = false
                    }
                }
            ))
            if !store.isPro {
                Text("Included with Caffeine+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reminder")
        }
    }

    private var subscriptionSection: some View {
        Section("Caffeine+") {
            LabeledContent("Status", value: store.isPro ? "Active" : "Free")
            if store.isPro {
                Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            } else {
                Button("See Caffeine+") { upgradeFocus = .bodyComparisons }
            }
            Button("Restore purchases") { Task { await store.restore() } }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            Link("Rate Caffeine", destination: AppStoreReviewLinks.writeReviewURL)
            Link("Support", destination: CaffeineLinks.support)
            Link("Privacy policy", destination: CaffeineLinks.privacyPolicy)
            Link("Terms of use", destination: CaffeineLinks.standardEULA)
            LabeledContent("Version", value: Bundle.main.appVersionLabel)
            Text("Caffeine provides mathematical estimates for personal awareness. It is not medical advice, not a measurement of caffeine in your body, and it does not diagnose, treat, or prevent any condition.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// `sheet(item:)` needs an Identifiable payload, and a bare `Int` index is not
/// one. Wrapping it also keeps a stale index from reopening the wrong row.
private struct PresetIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

/// Picks a drink from the catalog, or dials in a custom amount. Shared by the
/// preset editor and the drink preview.
struct DrinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: DrinkPreset
    let title: String
    let onSelect: (DrinkPreset) -> Void

    @State private var name: String
    @State private var milligrams: Double

    init(initial: DrinkPreset, title: String, onSelect: @escaping (DrinkPreset) -> Void) {
        self.initial = initial
        self.title = title
        self.onSelect = onSelect
        _name = State(initialValue: initial.name)
        _milligrams = State(initialValue: initial.milligrams)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom") {
                    TextField("Name", text: $name)
                    Stepper(
                        CaffeineFormat.milligrams(milligrams),
                        value: $milligrams,
                        in: 1...600,
                        step: 5
                    )
                }
                ForEach(DrinkCatalog.categories) { category in
                    Section(category.name) {
                        ForEach(category.drinks) { drink in
                            Button {
                                name = drink.name
                                milligrams = drink.milligrams
                            } label: {
                                HStack {
                                    Label(drink.name, systemImage: drink.symbolName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(CaffeineFormat.milligrams(drink.milligrams))
                                        .foregroundStyle(.secondary)
                                    if name == drink.name && milligrams == drink.milligrams {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.cyan)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let symbol = DrinkCatalog.allDrinks
                            .first { $0.name == name }?.symbolName ?? "drop.fill"
                        onSelect(DrinkPreset(
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Caffeine" : name,
                            milligrams: milligrams,
                            symbolName: symbol
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CaffeineSourcesView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared

    private var sources: [CaffeineSourceStatus] {
        let live = CaffeineClearance.sources(samples: health.recentSamples, selection: settings.sourceSelection)
        let liveIDs = Set(live.map(\.bundleID))
        let stored = settings.excludedSourceNames.compactMap { id, name -> CaffeineSourceStatus? in
            guard !liveIDs.contains(id) else { return nil }
            return CaffeineSourceStatus(
                bundleID: id,
                name: name,
                milligrams: 0,
                latestEntry: .distantPast,
                sampleCount: 0,
                isOurs: false,
                isIncluded: false,
                localOnlyMilligrams: 0
            )
        }
        return live + stored
    }

    var body: some View {
        List {
            Section {
                Text("All included dietary caffeine samples contribute once. Your entries from Caffeine always remain included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Sources from the last 48 hours") {
                ForEach(sources) { source in
                    Toggle(isOn: Binding(
                        get: { source.isIncluded },
                        set: { settings.setSourceIncluded($0, bundleID: source.bundleID, name: source.name) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text("\(CaffeineFormat.milligrams(source.milligrams)) from \(source.sampleCount) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(source.isOurs)
                }
            }
        }
        .navigationTitle("Sources")
    }
}

/// The fleet enjoyment gate. Nobody reaches Apple's native prompt without first
/// saying they are enjoying the app, and anyone who is not is sent to support.
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @StateObject private var reviews = ReviewPromptService.shared
    @State private var step: Step = .enjoyment

    enum Step {
        case enjoyment
        case rate
        case feedback
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: step == .feedback ? "envelope.fill" : "cup.and.saucer.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.forecastGradient)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(PaywallCTAStyle())
                Button(secondaryTitle) {
                    switch step {
                    case .enjoyment: step = .feedback
                    case .rate, .feedback:
                        reviews.markDeferred()
                        dismiss()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(28)
        .presentationDetents([.height(380)])
        .background(Theme.background)
    }

    private var title: String {
        switch step {
        case .enjoyment: "Enjoying Caffeine?"
        case .rate: "Glad to hear it"
        case .feedback: "Tell us what's missing"
        }
    }

    private var detail: String {
        switch step {
        case .enjoyment: "You've been logging for a while now. How is it going?"
        case .rate: "A rating on the App Store helps other people find the app."
        case .feedback: "Send a note instead. Every message is read, and it shapes what gets built next."
        }
    }

    private var primaryTitle: String {
        switch step {
        case .enjoyment: "Yes, it's useful"
        case .rate: "Rate on the App Store"
        case .feedback: "Send feedback"
        }
    }

    private var secondaryTitle: String {
        switch step {
        case .enjoyment: "Not really"
        case .rate, .feedback: "Maybe later"
        }
    }

    private func primaryAction() {
        switch step {
        case .enjoyment:
            step = .rate
        case .rate:
            requestReview()
            reviews.markRated()
            dismiss()
        case .feedback:
            reviews.markDeferred()
            dismiss()
            #if os(iOS)
            UIApplication.shared.open(CaffeineLinks.support)
            #endif
        }
    }
}
