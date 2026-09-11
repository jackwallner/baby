import Foundation
import HealthKit
import os

/// Reads the Apple Health categories beyond dietary caffeine and turns them
/// into the comparisons the Body tab shows.
///
/// Deliberately separate from `HealthKitService`: caffeine read/write is the
/// permission the app cannot work without, and this is the strictly optional
/// one the user opts into. Keeping the request calls apart means declining body
/// data never touches logging or the bedtime forecast.
@MainActor
final class HealthInsightsService: ObservableObject {
    static let shared = HealthInsightsService()
    /// Window for the day/night records. Ninety days is enough for a stable
    /// comparison without querying a decade of samples on every open.
    static let historyDays = 90
    /// Heart rate is by far the highest-volume type here, so the post-dose
    /// response looks at a much shorter window.
    static let heartRateDays = 14

    @Published private(set) var report = InsightsReport()
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthorizationRequested: Bool
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshed: Date?

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.jackwallner.caffeine", category: "Insights")
    private let defaults = UserDefaults(suiteName: caffeineAppGroupID) ?? .standard
    private static let requestedKey = "bodyInsightsAuthorizationRequested"

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let heartRateType = HKQuantityType(.heartRate)
    private let respiratoryRateType = HKQuantityType(.respiratoryRate)
    private let oxygenSaturationType = HKQuantityType(.oxygenSaturation)
    private let stepsType = HKQuantityType(.stepCount)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private let bodyMassType = HKQuantityType(.bodyMass)

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            sleepType,
            restingHeartRateType,
            hrvType,
            heartRateType,
            respiratoryRateType,
            oxygenSaturationType,
            stepsType,
            activeEnergyType,
            bodyMassType,
            HKObjectType.workoutType(),
        ]
        // Age and biological sex feed the suggested half-life. They are
        // characteristics rather than samples, so they are requested here but
        // read through `dateOfBirthComponents()` and `biologicalSex()`.
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKCharacteristicType(.biologicalSex))
        return types
    }

    private init() {
        isAuthorizationRequested = defaults.bool(forKey: Self.requestedKey)
        if ScreenshotConfig.isEnabled {
            isAuthorizationRequested = true
        }
    }

    /// Asks for the body categories. Separate sheet from the caffeine request,
    /// so the purpose string the user reads is about insights specifically.
    func requestAuthorization() async -> Bool {
        if ScreenshotConfig.isEnabled {
            isAuthorizationRequested = true
            return true
        }
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorizationRequested = true
            defaults.set(true, forKey: Self.requestedKey)
            return true
        } catch {
            logger.error("Body authorization failed: \(String(describing: error), privacy: .public)")
            lastError = "Apple Health did not return a response for those categories."
            return false
        }
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastRefreshed, Date.now.timeIntervalSince(lastRefreshed) < 300 { return }

        #if DEBUG
        if ScreenshotConfig.isEnabled {
            report = ScreenshotFixtures.insightsReport()
            lastRefreshed = .now
            return
        }
        #endif

        guard HKHealthStore.isHealthDataAvailable(), isAuthorizationRequested else { return }
        isLoading = true
        defer { isLoading = false }

        let settings = CaffeineSettings.shared
        let start = DateHelpers.daysAgo(Self.historyDays - 1)
        let end = DateHelpers.endOfDay()

        do {
            let doses = try await HealthKitService.shared.fetchSamples(from: start, to: end)
            async let nightsTask = fetchNights(from: start, to: end)
            async let restingTask = dailyAverages(type: restingHeartRateType, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end)
            async let hrvTask = dailyAverages(type: hrvType, unit: .secondUnit(with: .milli), from: start, to: end)
            async let respiratoryTask = dailyAverages(type: respiratoryRateType, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end)
            async let oxygenTask = dailyAverages(type: oxygenSaturationType, unit: .percent(), from: start, to: end)
            async let stepsTask = dailySums(type: stepsType, unit: .count(), from: start, to: end)
            async let energyTask = dailySums(type: activeEnergyType, unit: .kilocalorie(), from: start, to: end)
            async let workoutTask = fetchWorkoutStarts(from: start, to: end)
            async let massTask = fetchLatestBodyMass()
            async let heartRateTask = fetchHeartRateSeries(days: Self.heartRateDays)

            let nights = await nightsTask
            let resting = await restingTask
            let hrv = await hrvTask
            let respiratory = await respiratoryTask
            let oxygen = await oxygenTask
            let steps = await stepsTask
            let energy = await energyTask
            let workoutStarts = await workoutTask
            let bodyMass = await massTask
            let heartRates = await heartRateTask

            let selection = settings.sourceSelection
            let halfLife = settings.halfLifeHours
            var records: [DailyBodyRecord] = []

            for offset in stride(from: Self.historyDays - 1, through: 0, by: -1) {
                let day = DateHelpers.daysAgo(offset)
                let dayStart = DateHelpers.startOfDay(day)
                let dayEnd = DateHelpers.endOfDay(day)
                let nextDayKey = DateHelpers.dayKey(for: dayEnd)
                let key = DateHelpers.dayKey(for: dayStart)

                let consumed = doses
                    .filter { $0.endDate >= dayStart && $0.endDate < dayEnd }
                    .filter { selection.includes(bundleID: $0.sourceBundleID, isOurs: $0.isOurs) }
                    .reduce(0) { $0 + max($1.milligrams, 0) }
                let bedtime = settings.bedtime(onOrAfter: dayStart)
                let atBedtime = CaffeineClearance.remaining(
                    samples: doses,
                    at: bedtime,
                    selection: selection,
                    halfLifeHours: halfLife
                )
                let night = nights[key]

                records.append(DailyBodyRecord(
                    date: dayStart,
                    consumedMilligrams: consumed,
                    bedtimeMilligrams: atBedtime,
                    sleepDuration: night?.duration,
                    sleepOnsetLatency: night?.onsetLatency,
                    sleepInterruptions: night?.interruptions,
                    // Apple dates the daily resting figure on the morning after,
                    // so the night of day D is read from day D+1.
                    restingHeartRate: resting[nextDayKey] ?? resting[key],
                    heartRateVariability: hrv[nextDayKey] ?? hrv[key],
                    respiratoryRate: respiratory[nextDayKey] ?? respiratory[key],
                    oxygenSaturation: oxygen[nextDayKey] ?? oxygen[key],
                    steps: steps[key],
                    activeEnergy: energy[key]
                ))
            }

            let ageYears = fetchAgeYears()
            var built = InsightsReport(
                records: records,
                comparisons: CaffeineInsights.comparisons(records: records),
                cutoff: CaffeineInsights.personalCutoff(records: records),
                heartRateResponse: CaffeineInsights.heartRateResponse(
                    doses: CaffeineClearance.included(samples: doses, selection: selection)
                        .filter { $0.endDate >= DateHelpers.daysAgo(Self.heartRateDays) },
                    heartRates: heartRates
                ),
                workouts: CaffeineInsights.workoutSummary(
                    workoutStarts: workoutStarts,
                    samples: doses,
                    selection: selection,
                    halfLifeHours: halfLife
                ),
                doseIntensity: CaffeineInsights.doseIntensity(
                    milligrams: records.last?.consumedMilligrams ?? 0,
                    bodyMassKilograms: bodyMass
                ),
                halfLifeSuggestion: CaffeineInsights.suggestedHalfLife(ageYears: ageYears),
                bodyMassKilograms: bodyMass,
                ageYears: ageYears,
                biologicalSexDescription: fetchBiologicalSexDescription()
            )
            built.emptyMetrics = BodyMetric.allCases.filter { metric in
                records.allSatisfy { $0.value(for: metric) == nil }
            }

            report = built
            lastRefreshed = .now
            lastError = nil
        } catch {
            logger.error("Insights refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Some Apple Health categories could not be read."
        }
    }

    // MARK: - Sleep

    private struct NightSummary: Sendable {
        let duration: TimeInterval
        let onsetLatency: TimeInterval?
        let interruptions: Int
    }

    /// Groups sleep samples into nights keyed by the day whose caffeine came
    /// first. A session starting after noon belongs to that day; one starting
    /// after midnight belongs to the day before.
    private func fetchNights(from start: Date, to end: Date) async -> [String: NightSummary] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start.addingTimeInterval(-12 * 3600),
            end: end,
            options: []
        )
        let raw: [(key: String, start: Date, end: Date, state: Int)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let mapped = (samples as? [HKCategorySample] ?? []).map { sample in
                    let anchor = sample.startDate.addingTimeInterval(-12 * 3600)
                    return (
                        key: DateHelpers.dayKey(for: DateHelpers.startOfDay(anchor)),
                        start: sample.startDate,
                        end: sample.endDate,
                        state: sample.value
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let inBedValue = HKCategoryValueSleepAnalysis.inBed.rawValue
        let awakeValue = HKCategoryValueSleepAnalysis.awake.rawValue

        var grouped: [String: [(start: Date, end: Date, state: Int)]] = [:]
        for row in raw {
            grouped[row.key, default: []].append((row.start, row.end, row.state))
        }

        var result: [String: NightSummary] = [:]
        for (key, rows) in grouped {
            let asleep = rows.filter { asleepValues.contains($0.state) }
            guard !asleep.isEmpty else { continue }
            // Overlapping samples from several sources would otherwise be summed
            // twice, so time asleep is measured over merged intervals.
            let duration = Self.mergedDuration(asleep.map { ($0.start, $0.end) })
            guard duration >= 3 * 3600 else { continue }

            let firstAsleep = asleep.map(\.start).min()
            let inBedStart = rows.filter { $0.state == inBedValue }.map(\.start).min()
            let latency: TimeInterval? = {
                guard let firstAsleep, let inBedStart, firstAsleep > inBedStart else { return nil }
                let value = firstAsleep.timeIntervalSince(inBedStart)
                // A multi-hour "latency" means the in-bed window covered
                // something other than falling asleep. Drop it rather than
                // report it.
                return value <= 3 * 3600 ? value : nil
            }()

            let sleepStart = firstAsleep ?? rows.map(\.start).min() ?? .distantPast
            let sleepEnd = asleep.map(\.end).max() ?? .distantPast
            let interruptions = rows.filter {
                $0.state == awakeValue && $0.start > sleepStart && $0.end < sleepEnd
            }.count

            result[key] = NightSummary(
                duration: duration,
                onsetLatency: latency,
                interruptions: interruptions
            )
        }
        return result
    }

    /// Union of the intervals, so overlapping samples are counted once.
    /// Pure arithmetic, so it stays off the main actor and is directly testable.
    nonisolated static func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total
    }

    // MARK: - Quantity helpers

    private func dailyAverages(
        type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> [String: Double] {
        await dailyStatistics(type: type, unit: unit, from: start, to: end, options: .discreteAverage)
    }

    private func dailySums(
        type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> [String: Double] {
        await dailyStatistics(type: type, unit: unit, from: start, to: end, options: .cumulativeSum)
    }

    private func dailyStatistics(
        type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date,
        options: HKStatisticsOptions
    ) async -> [String: Double] {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                options: options,
                anchorDate: DateHelpers.startOfDay(start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    guard let quantity else { return }
                    result[DateHelpers.dayKey(for: statistics.startDate)] = quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// Fifteen-minute average buckets. Raw heart rate samples run to tens of
    /// thousands of rows over two weeks, and the post-dose comparison does not
    /// need that resolution.
    private func fetchHeartRateSeries(days: Int) async -> [(date: Date, bpm: Double)] {
        let start = DateHelpers.daysAgo(days)
        let end = Date.now
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                options: .discreteAverage,
                anchorDate: DateHelpers.startOfDay(start),
                intervalComponents: DateComponents(minute: 15)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [(date: Date, bpm: Double)] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.averageQuantity() else { return }
                    result.append((statistics.startDate, quantity.doubleValue(for: unit)))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func fetchWorkoutStarts(from start: Date, to end: Date) async -> [Date] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let starts = (samples as? [HKWorkout] ?? []).map(\.startDate)
                continuation.resume(returning: starts)
            }
            store.execute(query)
        }
    }

    private func fetchLatestBodyMass() async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchAgeYears() -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = DateHelpers.gregorian.date(from: components) else { return nil }
        return DateHelpers.gregorian.dateComponents([.year], from: birthDate, to: .now).year
    }

    private func fetchBiologicalSexDescription() -> String? {
        guard let sex = try? store.biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        case .notSet: return nil
        @unknown default: return nil
        }
    }
}
