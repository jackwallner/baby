import Charts
import SwiftUI

/// A pending drink preview. Carries the drink so the sheet can log it with the
/// same name the button had.
struct PreviewRequest: Identifiable {
    let id = UUID()
    let drink: DrinkPreset
    /// The entry being edited, when the sheet was opened from the log rather
    /// than from a quick-log button.
    var editing: CaffeineSample?
}

struct CaffeineNowView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var log = CaffeineLogService.shared
    @StateObject private var reviews = ReviewPromptService.shared
    @State private var preview: PreviewRequest?

    /// How long the one-tap undo stays offered after a log.
    private static let undoWindow: TimeInterval = 120
    @State private var showSettings: Bool
    @State private var showBreakdown = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initialPreview = arguments.contains("-PreviewSnapshot")
            ? PreviewRequest(drink: DrinkPreset(name: "Latte", milligrams: 120, symbolName: "mug.fill"))
            : nil
        _preview = State(initialValue: initialPreview)
        _showBreakdown = State(initialValue: arguments.contains("-BreakdownSnapshot"))
        // Settings is a gear rather than a tab, so a capture run cannot reach it
        // with -ScreenshotTab. Tapping the gear and screenshotting races the
        // sheet's presentation animation, which caught the Now screen mid
        // transition, so the sheet opens from a launch argument like the others.
        _showSettings = State(initialValue: arguments.contains("-SettingsSnapshot"))
        #else
        _preview = State(initialValue: nil)
        _showBreakdown = State(initialValue: false)
        _showSettings = State(initialValue: false)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                remainingCard
                healthWriteBanner
                quickAdds
                previewButton
                undoRow
                todayCard
                recentEntries
                estimateNote
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Caffeine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await health.refreshCache() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
        .refreshable { await health.refreshCache() }
        .sheet(item: $preview) { request in
            DrinkPreviewSheet(request: request)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { CaffeineSettingsView() }
        }
        .sheet(isPresented: $showBreakdown) {
            RemainingBreakdownSheet(contributions: contributions)
        }
        .sheet(isPresented: $reviews.isPresented) {
            ReviewPromptSheet()
        }
    }

    private var remainingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CaffeineFormat.milligrams(health.remainingNow))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("estimated remaining now")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(Theme.cyan)
            }

            provenanceRow

            if health.remainingNow > 0 {
                CaffeineCurve(
                    samples: health.recentSamples,
                    start: .now,
                    end: settings.bedtimeDate,
                    halfLifeHours: settings.halfLifeHours,
                    selection: settings.sourceSelection,
                    threshold: settings.bedtimeThreshold
                )
                .frame(height: 130)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AT BEDTIME")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textSecondary)
                    Text(CaffeineFormat.milligrams(health.bedtimeForecast.estimatedMilligrams))
                        .font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CaffeineFormat.time(settings.bedtimeDate))
                        .font(.headline)
                    Text("4-6h range \(CaffeineFormat.range(health.bedtimeForecast))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(22)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cyan.opacity(0.22), lineWidth: 1)
        )
    }

    private var contributions: [CaffeineContribution] {
        CaffeineClearance.contributions(
            samples: health.recentSamples,
            at: .now,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    /// Where the running estimate came from.
    ///
    /// On a first launch the number is frequently non-zero before the user has
    /// tapped anything, because Apple Health already held dietary caffeine from
    /// another app. Without this line that reads as a figure the app invented,
    /// so the card always names its inputs and opens a per-dose breakdown.
    @ViewBuilder
    private var provenanceRow: some View {
        let entries = contributions
        if entries.isEmpty {
            Text("Nothing in the last \(Int(HealthKitService.lookbackHours)) hours. Log a drink and this fills in.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                showBreakdown = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text(provenanceSummary(entries))
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.cyan)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Where this estimate comes from")
        }
    }

    private func provenanceSummary(_ entries: [CaffeineContribution]) -> String {
        let count = entries.count
        let noun = count == 1 ? "entry" : "entries"
        var names: [String] = []
        for entry in entries {
            let name = entry.sample.isOurs ? "Caffeine" : entry.sample.sourceName
            if !names.contains(name) { names.append(name) }
        }
        let sources: String
        switch names.count {
        case 0: sources = "Apple Health"
        case 1, 2: sources = names.joined(separator: ", ")
        default: sources = "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
        return "From \(count) \(noun) · \(sources)"
    }

    /// Entries that could not reach Apple Health used to fail silently, so the
    /// Health app simply had nothing in it and there was no way to find out why.
    @ViewBuilder
    private var healthWriteBanner: some View {
        if log.pendingWriteCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "\(log.pendingWriteCount) \(log.pendingWriteCount == 1 ? "entry is" : "entries are") saved on this device only",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
                Text(health.writeState == .denied
                    ? "Apple Health is not accepting writes from Caffeine. Turn on Caffeine under Health data in Settings, then retry."
                    : "They still count in every estimate here. Caffeine retries automatically each time you open the app.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 14) {
                    Button("Retry now") {
                        Task { _ = await log.retryPendingLocalEntries() }
                    }
                    .font(.caption.weight(.semibold))
                    if health.writeState == .denied, let url = HealthKitService.privacySettingsURL {
                        Link("Open Settings", destination: url)
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.warning.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var quickAdds: some View {
        HStack(spacing: 10) {
            ForEach(Array(settings.quickAddDrinks.enumerated()), id: \.offset) { _, drink in
                Button {
                    preview = PreviewRequest(drink: drink)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: drink.symbolName)
                            .font(.title3)
                            .foregroundStyle(Theme.cyan)
                        Text(drink.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(CaffeineFormat.milligrams(drink.milligrams))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Preview \(drink.name), \(CaffeineFormat.milligrams(drink.milligrams))")
            }
        }
    }

    private var previewButton: some View {
        Button {
            preview = PreviewRequest(drink: DrinkPreset(name: "Caffeine", milligrams: 100, symbolName: "drop.fill"))
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Preview another drink")
                    .fontWeight(.semibold)
                Spacer()
                Text("before logging")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .buttonStyle(ForecastButtonStyle())
    }

    /// A short window to take back the last entry, which is faster than finding
    /// the row and deleting it.
    @ViewBuilder
    private var undoRow: some View {
        if let entry = log.lastEntry,
           let loggedAt = log.lastLoggedAt,
           Date.now.timeIntervalSince(loggedAt) < Self.undoWindow {
            HStack {
                Text("Logged \(entry.drinkName ?? "caffeine"), \(CaffeineFormat.milligrams(entry.milligrams))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Undo") {
                    Task { _ = await log.undoLast() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
            }
            .padding(14)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .transition(.opacity)
        }
    }

    private var todayCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONSUMED TODAY")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textSecondary)
                Text(CaffeineFormat.milligrams(health.consumedToday))
                    .font(.title.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("MODEL")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textSecondary)
                Text("\(settings.halfLifeHours, specifier: "%.1f") hour half-life")
                    .font(.headline)
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var recentEntries: some View {
        let entries = health.recentSamples
            .filter { $0.isOurs && Calendar.current.isDateInToday($0.endDate) }
            .sorted { $0.endDate > $1.endDate }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR LOG")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                ForEach(entries) { sample in
                    Button {
                        preview = PreviewRequest(
                            drink: DrinkPreset(
                                name: sample.drinkName ?? "Caffeine",
                                milligrams: sample.milligrams,
                                symbolName: "drop.fill"
                            ),
                            editing: sample
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: sample.isLocalOnly ? "icloud.slash" : "drop.fill")
                                .foregroundStyle(sample.isLocalOnly ? Theme.warning : Theme.violet)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sample.displayName)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(CaffeineFormat.milligrams(sample.milligrams))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(CaffeineFormat.time(sample.endDate))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { _ = await log.delete(sample: sample) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Text("Tap an entry to change the drink, amount, or time.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var estimateNote: some View {
        Text("The forecast is a mathematical estimate, not a blood measurement or a medical recommendation. Metabolism varies with the person, dose, and context.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
    }
}

/// Per-dose breakdown of the "estimated remaining now" figure.
///
/// The first launch of the app can show a number before the user has logged
/// anything, because Apple Health already holds dietary caffeine written by
/// something else. This names each dose that is still contributing, what it
/// started at, and what the half-life model says is left of it.
struct RemainingBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CaffeineSettings

    let contributions: [CaffeineContribution]

    private var total: Double {
        contributions.reduce(0) { $0 + $1.remainingMilligrams }
    }

    private var hasOutsideSources: Bool {
        contributions.contains { !$0.sample.isOurs }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    totalCard
                    rows
                    if hasOutsideSources {
                        outsideSourceNote
                    }
                    Text("Each dose decays on a \(settings.halfLifeHours, specifier: "%.1f") hour half-life: half of it is modeled as gone after that long, half of the rest after the same again. This is arithmetic on what was logged, not a measurement of your blood.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle("Where this comes from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CaffeineFormat.milligrams(total))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("estimated remaining now, across \(contributions.count) \(contributions.count == 1 ? "entry" : "entries")")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(contributions) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.sample.isOurs ? "drop.fill" : "square.and.arrow.down.fill")
                        .font(.subheadline)
                        .foregroundStyle(entry.sample.isOurs ? Theme.violet : Theme.cyan)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.sample.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle(for: entry))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(CaffeineFormat.milligrams(entry.remainingMilligrams))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// The source is only named when it is not already the row's title, which it
    /// is whenever a sample arrived without a drink name.
    private func subtitle(for entry: CaffeineContribution) -> String {
        let stamp = "\(CaffeineFormat.milligrams(entry.sample.milligrams)) at \(CaffeineFormat.time(entry.sample.endDate))"
        if entry.sample.isOurs { return "\(stamp) · logged here" }
        if entry.sample.displayName == entry.sample.sourceName { return stamp }
        return "\(stamp) · \(entry.sample.sourceName)"
    }

    private var outsideSourceNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Some of this arrived from another app", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Caffeine reads dietary caffeine that anything else already wrote to Apple Health, which is why the estimate can be non-zero before you log anything here. Settings › Apple Health sources controls which of them count.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// The drink preview, and the app's planner.
///
/// This is the one place that answers "what would another drink do?": pick the
/// drink, move the dose and time, and compare the bedtime estimate with and
/// without it, plus the latest time this specific dose still lands under the
/// bedtime preference. It doubles as the editor for an entry already logged.
struct DrinkPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CaffeineSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var reviews = ReviewPromptService.shared

    let request: PreviewRequest

    @State private var drinkName: String
    @State private var symbolName: String
    @State private var dose: Double
    @State private var drinkTime: Date
    @State private var isLogging = false
    @State private var showDrinkPicker = false

    init(request: PreviewRequest) {
        self.request = request
        _drinkName = State(initialValue: request.drink.name)
        _symbolName = State(initialValue: request.drink.symbolName)
        _dose = State(initialValue: request.drink.milligrams)
        _drinkTime = State(initialValue: request.editing?.endDate ?? .now)
    }

    private var isEditing: Bool { request.editing != nil }

    /// The entry being edited must not count twice: once as the existing sample
    /// and again as the proposed dose.
    private var baselineSamples: [CaffeineSample] {
        guard let editing = request.editing else { return health.recentSamples }
        return health.recentSamples.filter { $0.id != editing.id }
    }

    private var currentForecast: CaffeineForecast {
        CaffeineClearance.forecast(
            samples: baselineSamples,
            at: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var proposedForecast: CaffeineForecast {
        CaffeineClearance.forecastAdding(
            dose: dose,
            at: drinkTime,
            samples: baselineSamples,
            forecastDate: settings.bedtimeDate,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var doseContribution: Double {
        CaffeineClearance.remaining(
            dose: dose,
            elapsedHours: settings.bedtimeDate.timeIntervalSince(drinkTime) / 3600,
            halfLifeHours: settings.halfLifeHours
        )
    }

    private var latestTime: Date? {
        CaffeineClearance.latestTimeForDose(
            dose: dose,
            existingSamples: baselineSamples,
            bedtime: settings.bedtimeDate,
            threshold: settings.bedtimeThreshold,
            selection: settings.sourceSelection,
            halfLifeHours: settings.halfLifeHours
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    doseCard
                    forecastCard
                    logButton
                    if let editing = request.editing {
                        Button(role: .destructive) {
                            Task {
                                _ = await CaffeineLogService.shared.delete(sample: editing)
                                dismiss()
                            }
                        } label: {
                            Label("Delete this entry", systemImage: "trash")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    Text("Logging is free. The estimate uses your selected half-life and is not a measure of caffeine in your bloodstream.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit entry" : "Drink preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showDrinkPicker) {
                DrinkPickerSheet(
                    initial: DrinkPreset(name: drinkName, milligrams: dose, symbolName: symbolName),
                    title: "Choose a drink"
                ) { drink in
                    drinkName = drink.name
                    dose = drink.milligrams
                    symbolName = drink.symbolName
                }
            }
        }
    }

    private var doseCard: some View {
        VStack(spacing: 14) {
            Button {
                showDrinkPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbolName)
                    Text(drinkName)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)

            Text("\(Int(dose)) mg")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())

            Slider(value: $dose, in: 5...500, step: 5)
                .tint(Theme.violet)
                .accessibilityLabel("Dose in milligrams")

            DatePicker(
                "Time",
                selection: $drinkTime,
                in: Date.now.addingTimeInterval(-36 * 3600)...settings.bedtimeDate
            )
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "AT BEDTIME AFTER THIS EDIT" : "IF YOU LOG THIS")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .center) {
                forecastValue("WITHOUT", currentForecast.estimatedMilligrams)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.textSecondary)
                forecastValue(isEditing ? "AS EDITED" : "WITH DRINK", proposedForecast.estimatedMilligrams)
            }

            Divider()

            Label(
                "This drink adds about \(CaffeineFormat.milligrams(doseContribution)) to the bedtime estimate",
                systemImage: "moon.stars.fill"
            )
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)

            if let latestTime {
                Label(
                    latestTime >= settings.bedtimeDate
                        ? "At this size, the estimate stays under your \(CaffeineFormat.milligrams(settings.bedtimeThreshold)) preference right through bedtime"
                        : "Latest time this dose still lands under your preference: \(CaffeineFormat.time(latestTime))",
                    systemImage: "clock.badge.checkmark"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.mint)
            } else {
                Label(
                    "Your existing bedtime estimate is already above your \(CaffeineFormat.milligrams(settings.bedtimeThreshold)) preference",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.warning)
            }

            Text("Reference range at bedtime: \(CaffeineFormat.range(proposedForecast)). A preference is a number you chose, not a safety limit.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func forecastValue(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value))
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("at bedtime").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logButton: some View {
        Button {
            isLogging = true
            Task {
                if let editing = request.editing {
                    _ = await CaffeineLogService.shared.update(
                        sample: editing,
                        milligrams: dose,
                        at: drinkTime,
                        drinkName: drinkName
                    )
                } else {
                    _ = await CaffeineLogService.shared.log(
                        milligrams: dose,
                        at: drinkTime,
                        drinkName: drinkName
                    )
                    reviews.recordLoggingDay(drinkTime)
                    reviews.considerAfterGoodForecast(
                        estimatedAtBedtime: health.bedtimeForecast.estimatedMilligrams,
                        threshold: settings.bedtimeThreshold
                    )
                }
                dismiss()
            }
        } label: {
            if isLogging {
                ProgressView().tint(.white)
            } else {
                Text(isEditing ? "Save changes" : "Log \(Int(dose)) mg")
            }
        }
        .buttonStyle(ForecastButtonStyle())
        .disabled(isLogging)
    }
}

struct CaffeineTimelineView: View {
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @State private var days = 7
    @State private var history: [CaffeineDaySummary] = []
    @State private var isLoading = false
    /// Bumped on every load so a slow fetch for a range the user already moved
    /// off cannot write its rows over the newer ones. That stale write was what
    /// made the chart flick to the wrong shape after a fast range switch.
    @State private var loadToken = 0
    @State private var showUpgrade = false

    /// Free access is seven days. The picker used to offer 30 and 90 and then
    /// silently render seven, which read as a broken chart rather than a locked
    /// feature.
    private static let freeDays = 7
    private static let ranges = [7, 30, 90]

    private static let consumedSeries = "Consumed"
    private static let bedtimeSeries = "At bedtime"

    private var isLocked: Bool { !store.isPro && days > Self.freeDays }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                rangePicker

                if isLocked {
                    lockedRange
                } else {
                    chartCard
                    HStack(spacing: 12) {
                        metric("AVG DAILY", history.average(\.milligrams))
                        metric("AVG AT BED", history.average(\.estimatedAtBedtime))
                    }
                }

                if !store.isPro {
                    Button {
                        showUpgrade = true
                    } label: {
                        Label("Unlock full history and trends", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ForecastButtonStyle())
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Timeline")
        .task { await load() }
        // Buying from the sheet on this very screen unlocks the range the user
        // was looking at, so the locked panel has to become the chart without a
        // trip to another tab and back.
        .onChange(of: store.isPro) { _, _ in Task { await load() } }
        .sheet(isPresented: $showUpgrade) {
            CaffeinePaywallView(paywallImpressionID: "caffeine_timeline", focus: .fullHistory)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $days) {
            ForEach(Self.ranges, id: \.self) { range in
                Text("\(range)D").tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: days) { _, _ in Task { await load() } }
    }

    private var lockedRange: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.violet)
            Text("\(days) days is part of Caffeine+")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("The free timeline covers the last \(Self.freeDays) days. Caffeine+ opens the full \(Self.ranges.last ?? 90) days of intake and bedtime estimates.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("See Caffeine+") { showUpgrade = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// The chart lives in a card of fixed height in every state, so a load, an
    /// empty range, and a full range all occupy the same space. Reflowing the
    /// whole screen between them was most of what read as a glitchy graph.
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend
            ZStack {
                if isLoading && history.isEmpty {
                    ProgressView().tint(Theme.cyan)
                } else if history.allSatisfy({ $0.milligrams <= 0 }) {
                    VStack(spacing: 6) {
                        Text("No caffeine recorded in this range")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Logged drinks, and anything else writing dietary caffeine to Apple Health, show up here.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                } else {
                    chart
                }
            }
            .frame(height: 230)
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendKey(Self.consumedSeries, color: Theme.violet, isLine: false)
            legendKey(Self.bedtimeSeries, color: Theme.cyan, isLine: true)
            Spacer(minLength: 0)
        }
    }

    private func legendKey(_ title: String, color: Color, isLine: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: isLine ? 14 : 9, height: isLine ? 3 : 9)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Chart.js-free rules that keep this readable at 7 and at 90 days:
    /// an explicit y domain anchored at zero (an auto domain rescaled on every
    /// range change), monotone interpolation so the bedtime line cannot
    /// overshoot below zero between two days, a bar width tied to the range so
    /// 90 days does not render as hairlines, and a hand-built legend because
    /// two differently-typed marks give the built-in one nothing to key on.
    private var chart: some View {
        Chart(history) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Milligrams", day.milligrams),
                width: .ratio(0.6)
            )
            .foregroundStyle(Theme.violet.gradient)

            LineMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Milligrams", day.estimatedAtBedtime),
                series: .value("Series", Self.bedtimeSeries)
            )
            .foregroundStyle(Theme.cyan)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...yMaximum)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisStrideDays)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .animation(.easeInOut(duration: 0.2), value: history)
    }

    /// Anchored at zero with a little headroom, and never zero-height on a day
    /// with no intake, which would otherwise divide the scale by nothing.
    private var yMaximum: Double {
        let peak = history.map { max($0.milligrams, $0.estimatedAtBedtime) }.max() ?? 0
        return max(peak * 1.15, 50)
    }

    private var axisStrideDays: Int {
        switch days {
        case ...7: 1
        case ...30: 7
        default: 14
        }
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
            Text(CaffeineFormat.milligrams(value))
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        guard !isLocked else {
            history = []
            return
        }
        loadToken += 1
        let token = loadToken
        isLoading = true
        let requested = days
        let fetched = (try? await health.fetchHistory(days: requested)) ?? []
        guard token == loadToken else { return }
        history = fetched
        isLoading = false
    }
}

struct CaffeineCurve: View {
    let samples: [CaffeineSample]
    let start: Date
    let end: Date
    let halfLifeHours: Double
    let selection: CaffeineSourceSelection
    let threshold: Double

    var body: some View {
        GeometryReader { geometry in
            let values = (0...32).map { index -> Double in
                let fraction = Double(index) / 32
                let date = start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
                return CaffeineClearance.remaining(
                    samples: samples,
                    at: date,
                    selection: selection,
                    halfLifeHours: halfLifeHours
                )
            }
            // Headroom, so a peak does not sit on the frame's top edge with half
            // of its 4pt stroke clipped off.
            let peak = values.max() ?? 0
            let maximum = max(peak, threshold, 1) * 1.12
            ZStack(alignment: .bottomLeading) {
                // With nothing on board the threshold would pin itself to the top
                // of an otherwise empty frame, which reads as a broken chart
                // rather than an empty one.
                if peak > 0 {
                    Path { path in
                        let y = geometry.size.height * (1 - min(threshold / maximum, 1))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Theme.warning.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat(value / maximum))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Theme.forecastGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated caffeine clearance curve through bedtime")
    }
}

struct ForecastButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(Theme.forecastGradient, in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension Array where Element == CaffeineDaySummary {
    func average(_ keyPath: KeyPath<CaffeineDaySummary, Double>) -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0) { $0 + $1[keyPath: keyPath] } / Double(count)
    }
}
