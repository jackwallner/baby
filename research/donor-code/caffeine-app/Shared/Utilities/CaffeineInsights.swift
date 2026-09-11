import Foundation

/// A body measurement Caffeine compares against caffeine exposure.
///
/// Every case here is backed by a HealthKit type the app requests, and every
/// requested type appears in this list or in one of the dedicated summaries
/// below (`HeartRateResponse`, `WorkoutCaffeineSummary`, `DoseIntensity`,
/// `HalfLifeSuggestion`). That mapping is what keeps the authorization sheet
/// honest: nothing is requested that no shipped surface reads.
enum BodyMetric: String, CaseIterable, Identifiable, Sendable {
    case sleepDuration
    case sleepOnset
    case sleepInterruptions
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case steps
    case activeEnergy

    var id: String { rawValue }

    /// Overnight metrics describe the night after the caffeine day. Day metrics
    /// describe the day itself, so the two groups are labelled separately.
    var isOvernight: Bool {
        switch self {
        case .steps, .activeEnergy: false
        default: true
        }
    }

    var title: String {
        switch self {
        case .sleepDuration: "Time asleep"
        case .sleepOnset: "Time to fall asleep"
        case .sleepInterruptions: "Times awake"
        case .restingHeartRate: "Resting heart rate"
        case .heartRateVariability: "Heart rate variability"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        }
    }

    var symbolName: String {
        switch self {
        case .sleepDuration: "bed.double.fill"
        case .sleepOnset: "hourglass"
        case .sleepInterruptions: "eye.fill"
        case .restingHeartRate: "heart.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .respiratoryRate: "lungs.fill"
        case .oxygenSaturation: "drop.fill"
        case .steps: "figure.walk"
        case .activeEnergy: "flame.fill"
        }
    }

    /// Smallest difference between the two groups worth showing. Below this the
    /// comparison is reported as "no measurable difference" rather than dressed
    /// up as a finding.
    var noiseFloor: Double {
        switch self {
        case .sleepDuration: 15 * 60
        case .sleepOnset: 5 * 60
        case .sleepInterruptions: 0.5
        case .restingHeartRate: 1.5
        case .heartRateVariability: 3
        case .respiratoryRate: 0.3
        case .oxygenSaturation: 0.4
        case .steps: 500
        case .activeEnergy: 40
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .sleepDuration, .sleepOnset:
            return CaffeineInsights.durationText(value)
        case .sleepInterruptions:
            return String(format: "%.1f", value)
        case .restingHeartRate:
            return "\(Int(value.rounded())) bpm"
        case .heartRateVariability:
            return "\(Int(value.rounded())) ms"
        case .respiratoryRate:
            return String(format: "%.1f br/min", value)
        case .oxygenSaturation:
            return String(format: "%.1f%%", value * 100)
        case .steps:
            return "\(Int(value.rounded()))"
        case .activeEnergy:
            return "\(Int(value.rounded())) kcal"
        }
    }

    /// Signed difference in words, phrased as an observation of what was
    /// recorded rather than as an effect the caffeine caused.
    func differenceText(_ delta: Double) -> String {
        let magnitude = abs(delta)
        switch self {
        case .sleepDuration, .sleepOnset:
            return CaffeineInsights.durationText(magnitude)
        case .sleepInterruptions:
            return String(format: "%.1f", magnitude)
        case .oxygenSaturation:
            return String(format: "%.1f points", magnitude * 100)
        default:
            return formatted(magnitude)
        }
    }
}

/// One caffeine day and the night that followed it.
struct DailyBodyRecord: Sendable, Equatable, Identifiable {
    var id: Date { date }
    /// Start of the day the caffeine was consumed.
    let date: Date
    /// Total dietary caffeine consumed that day, from the included sources.
    let consumedMilligrams: Double
    /// Modeled milligrams still present at that evening's bedtime.
    let bedtimeMilligrams: Double
    let sleepDuration: TimeInterval?
    let sleepOnsetLatency: TimeInterval?
    let sleepInterruptions: Int?
    let restingHeartRate: Double?
    let heartRateVariability: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?
    let steps: Double?
    let activeEnergy: Double?

    init(
        date: Date,
        consumedMilligrams: Double,
        bedtimeMilligrams: Double,
        sleepDuration: TimeInterval? = nil,
        sleepOnsetLatency: TimeInterval? = nil,
        sleepInterruptions: Int? = nil,
        restingHeartRate: Double? = nil,
        heartRateVariability: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        steps: Double? = nil,
        activeEnergy: Double? = nil
    ) {
        self.date = date
        self.consumedMilligrams = consumedMilligrams
        self.bedtimeMilligrams = bedtimeMilligrams
        self.sleepDuration = sleepDuration
        self.sleepOnsetLatency = sleepOnsetLatency
        self.sleepInterruptions = sleepInterruptions
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.steps = steps
        self.activeEnergy = activeEnergy
    }

    func value(for metric: BodyMetric) -> Double? {
        switch metric {
        case .sleepDuration: sleepDuration
        case .sleepOnset: sleepOnsetLatency
        case .sleepInterruptions: sleepInterruptions.map(Double.init)
        case .restingHeartRate: restingHeartRate
        case .heartRateVariability: heartRateVariability
        case .respiratoryRate: respiratoryRate
        case .oxygenSaturation: oxygenSaturation
        case .steps: steps
        case .activeEnergy: activeEnergy
        }
    }

    /// Overnight metrics are compared against the caffeine still modeled at
    /// bedtime. Day metrics are compared against the whole day's intake.
    func exposure(for metric: BodyMetric) -> Double {
        metric.isOvernight ? bedtimeMilligrams : consumedMilligrams
    }
}

/// Higher-caffeine days measured against lower-caffeine days, for one metric.
struct MetricComparison: Sendable, Equatable, Identifiable {
    var id: String { metric.rawValue }
    let metric: BodyMetric
    /// The exposure value that separated the two groups.
    let splitMilligrams: Double
    let lowerMean: Double
    let higherMean: Double
    let lowerCount: Int
    let higherCount: Int

    /// Higher-caffeine mean minus lower-caffeine mean.
    var delta: Double { higherMean - lowerMean }

    var sampleCount: Int { lowerCount + higherCount }

    /// False when the two groups land within the metric's noise floor, which is
    /// a real and reportable answer rather than a reason to hide the row.
    var isMeaningful: Bool { abs(delta) >= metric.noiseFloor }
}

/// The lowest bedtime estimate above which this person's own recorded sleep was
/// measurably shorter. Never a limit, a target, or a recommendation.
struct PersonalCutoff: Sendable, Equatable {
    let milligrams: Double
    /// Negative when sleep was shorter on the higher nights.
    let sleepDelta: TimeInterval
    let nightsAbove: Int
    let nightsBelow: Int
}

enum CutoffFinding: Sendable, Equatable {
    case insufficientData(have: Int, need: Int)
    case noMeasurableDifference(nights: Int)
    case found(PersonalCutoff)
}

/// Heart rate around logged doses, averaged over every dose with usable
/// readings on both sides.
struct HeartRateResponse: Sendable, Equatable {
    let doseCount: Int
    let baselineBPM: Double
    let afterBPM: Double
    var delta: Double { afterBPM - baselineBPM }
}

/// What was modeled to be on board when workouts started.
struct WorkoutCaffeineSummary: Sendable, Equatable {
    let workoutCount: Int
    let averageOnBoard: Double
    /// Mean start time expressed as minutes after midnight.
    let typicalStartMinutes: Int
}

/// Today's intake relative to body mass. A description of the dose, not a
/// safety threshold.
struct DoseIntensity: Sendable, Equatable {
    let milligrams: Double
    let bodyMassKilograms: Double
    var milligramsPerKilogram: Double {
        guard bodyMassKilograms > 0 else { return 0 }
        return milligrams / bodyMassKilograms
    }
}

/// A starting half-life drawn from published population averages for an age
/// band, offered as a default the user can change. Not a measurement.
struct HalfLifeSuggestion: Sendable, Equatable {
    let hours: Double
    let reason: String
}

/// A simple linear trend between daily intake and a metric.
struct MetricTrend: Sendable, Equatable {
    let metric: BodyMetric
    let coefficient: Double
    let sampleCount: Int

    var strengthLabel: String {
        switch abs(coefficient) {
        case 0.5...: "a clear pattern"
        case 0.3..<0.5: "a modest pattern"
        case 0.15..<0.3: "a faint pattern"
        default: "no clear pattern"
        }
    }

    var hasPattern: Bool { abs(coefficient) >= 0.15 }
}

/// Everything the Body tab renders, produced in one pass so the view never
/// fires its own queries.
struct InsightsReport: Sendable, Equatable {
    var records: [DailyBodyRecord] = []
    var comparisons: [MetricComparison] = []
    var cutoff: CutoffFinding = .insufficientData(have: 0, need: CaffeineInsights.minimumCutoffNights)
    var heartRateResponse: HeartRateResponse?
    var workouts: WorkoutCaffeineSummary?
    var doseIntensity: DoseIntensity?
    var halfLifeSuggestion: HalfLifeSuggestion?
    var bodyMassKilograms: Double?
    var ageYears: Int?
    var biologicalSexDescription: String?
    /// Types that returned no samples at all. Surfaced so the user can tell
    /// "you didn't grant this" apart from "you have no data".
    var emptyMetrics: [BodyMetric] = []

    var hasAnyBodyData: Bool {
        !records.contains { record in
            BodyMetric.allCases.allSatisfy { record.value(for: $0) == nil }
        } && !records.isEmpty
    }
}

enum CaffeineInsights {
    /// Days needed before any comparison is shown. Small samples produce
    /// confident-looking noise, which is the one thing this feature must not do.
    static let minimumRecords = 14
    static let minimumPerGroup = 5
    /// Nights needed before a personal cutoff is attempted.
    static let minimumCutoffNights = 21
    /// A cutoff has to move sleep by at least this much to be reported.
    static let cutoffSleepFloor: TimeInterval = 20 * 60

    // MARK: - Group comparison

    /// Splits `records` at the median exposure and compares the metric's mean on
    /// each side. Returns nil when there is not enough data, or when every day
    /// carried the same exposure.
    static func compare(records: [DailyBodyRecord], metric: BodyMetric) -> MetricComparison? {
        let usable = records.filter { $0.value(for: metric) != nil }
        guard usable.count >= minimumRecords else { return nil }

        let exposures = usable.map { $0.exposure(for: metric) }.sorted()
        let splitValue = exposures[exposures.count / 2]
        guard let lowest = exposures.first, splitValue > lowest else { return nil }

        let lower = usable.filter { $0.exposure(for: metric) < splitValue }
        let higher = usable.filter { $0.exposure(for: metric) >= splitValue }
        guard lower.count >= minimumPerGroup, higher.count >= minimumPerGroup else { return nil }

        guard let lowerMean = mean(lower.compactMap { $0.value(for: metric) }),
              let higherMean = mean(higher.compactMap { $0.value(for: metric) }) else { return nil }

        return MetricComparison(
            metric: metric,
            splitMilligrams: splitValue,
            lowerMean: lowerMean,
            higherMean: higherMean,
            lowerCount: lower.count,
            higherCount: higher.count
        )
    }

    static func comparisons(records: [DailyBodyRecord]) -> [MetricComparison] {
        BodyMetric.allCases.compactMap { compare(records: records, metric: $0) }
    }

    // MARK: - Personal cutoff

    /// Smallest share of nights each side of a candidate cutoff must hold. A
    /// threshold that leaves four nights on one side can clear the sleep floor
    /// on noise alone, and reporting it as "your cutoff" would be the exact
    /// false confidence this feature has to avoid.
    static let minimumGroupShare = 0.25

    /// Scans candidate bedtime estimates and reports the one at which this
    /// person's recorded sleep separates most clearly.
    ///
    /// Candidates must split the nights into two reasonably sized groups, and
    /// the winner is the largest sleep difference rather than the first
    /// threshold to clear the floor. Taking the first would drift toward the
    /// edge of the distribution, where a handful of nights on the short side can
    /// qualify without describing anything real.
    ///
    /// Deliberately returns a distinct "no measurable difference" answer: for
    /// plenty of people there genuinely isn't one, and saying so is more useful
    /// than manufacturing a number.
    static func personalCutoff(records: [DailyBodyRecord]) -> CutoffFinding {
        let nights = records.filter { $0.sleepDuration != nil }
        guard nights.count >= minimumCutoffNights else {
            return .insufficientData(have: nights.count, need: minimumCutoffNights)
        }

        let floor = max(minimumPerGroup, Int((Double(nights.count) * minimumGroupShare).rounded(.up)))
        var best: PersonalCutoff?
        for candidate in stride(from: 10.0, through: 150.0, by: 5.0) {
            let above = nights.filter { $0.bedtimeMilligrams >= candidate }
            let below = nights.filter { $0.bedtimeMilligrams < candidate }
            guard above.count >= floor, below.count >= floor else { continue }
            guard let aboveMean = mean(above.compactMap(\.sleepDuration)),
                  let belowMean = mean(below.compactMap(\.sleepDuration)) else { continue }
            let delta = aboveMean - belowMean
            guard delta <= -cutoffSleepFloor else { continue }
            // Strictly less than, so an exact tie keeps the lower threshold:
            // when two cutoffs describe the data equally well, the earlier one
            // is the more useful thing to tell someone.
            if best == nil || delta < (best?.sleepDelta ?? 0) {
                best = PersonalCutoff(
                    milligrams: candidate,
                    sleepDelta: delta,
                    nightsAbove: above.count,
                    nightsBelow: below.count
                )
            }
        }

        if let best { return .found(best) }
        return .noMeasurableDifference(nights: nights.count)
    }

    // MARK: - Trend

    static func trend(records: [DailyBodyRecord], metric: BodyMetric) -> MetricTrend? {
        let usable = records.filter { $0.value(for: metric) != nil }
        guard usable.count >= minimumRecords else { return nil }
        let x = usable.map { $0.exposure(for: metric) }
        let y = usable.compactMap { $0.value(for: metric) }
        guard let coefficient = pearson(x, y) else { return nil }
        return MetricTrend(metric: metric, coefficient: coefficient, sampleCount: usable.count)
    }

    /// Pearson correlation. Returns nil when either series is flat, which is the
    /// case where the coefficient is undefined rather than zero.
    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 2 else { return nil }
        guard let meanX = mean(x), let meanY = mean(y) else { return nil }
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for index in x.indices {
            let dx = x[index] - meanX
            let dy = y[index] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX * varianceY).squareRoot()
    }

    // MARK: - Dose-level summaries

    /// Mean heart rate shortly after a dose against the hour before it. Doses
    /// without readings on both sides are skipped rather than filled in.
    static func heartRateResponse(
        doses: [CaffeineSample],
        heartRates: [(date: Date, bpm: Double)],
        minimumDose: Double = 40,
        baselineWindow: TimeInterval = 60 * 60,
        settleWindow: TimeInterval = 20 * 60,
        responseWindow: TimeInterval = 90 * 60
    ) -> HeartRateResponse? {
        guard !heartRates.isEmpty else { return nil }
        var baselines: [Double] = []
        var afters: [Double] = []

        for dose in doses where dose.milligrams >= minimumDose {
            let before = heartRates
                .filter { $0.date >= dose.endDate.addingTimeInterval(-baselineWindow) && $0.date < dose.endDate }
                .map(\.bpm)
            let after = heartRates
                .filter {
                    $0.date >= dose.endDate.addingTimeInterval(settleWindow)
                        && $0.date <= dose.endDate.addingTimeInterval(responseWindow)
                }
                .map(\.bpm)
            guard let baseline = mean(before), let response = mean(after) else { continue }
            baselines.append(baseline)
            afters.append(response)
        }

        guard baselines.count >= 5, let baseline = mean(baselines), let after = mean(afters) else { return nil }
        return HeartRateResponse(doseCount: baselines.count, baselineBPM: baseline, afterBPM: after)
    }

    /// What the model says was on board when each workout started.
    static func workoutSummary(
        workoutStarts: [Date],
        samples: [CaffeineSample],
        selection: CaffeineSourceSelection,
        halfLifeHours: Double,
        calendar: Calendar = DateHelpers.gregorian
    ) -> WorkoutCaffeineSummary? {
        guard !workoutStarts.isEmpty else { return nil }
        let onBoard = workoutStarts.map { start in
            CaffeineClearance.remaining(
                samples: samples,
                at: start,
                selection: selection,
                halfLifeHours: halfLifeHours
            )
        }
        let minutes = workoutStarts.map { start -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: start)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        guard let averageOnBoard = mean(onBoard), let averageMinutes = mean(minutes.map(Double.init)) else {
            return nil
        }
        return WorkoutCaffeineSummary(
            workoutCount: workoutStarts.count,
            averageOnBoard: averageOnBoard,
            typicalStartMinutes: Int(averageMinutes.rounded())
        )
    }

    // MARK: - Body-derived defaults

    /// Reference half-life for an age band, clamped to the 4-6 hour range the
    /// app shows everywhere else. A starting point the user can move, never a
    /// measurement of their own clearance.
    static func suggestedHalfLife(ageYears: Int?) -> HalfLifeSuggestion? {
        guard let ageYears, ageYears >= 13, ageYears <= 110 else { return nil }
        let hours: Double
        let reason: String
        switch ageYears {
        case ..<30:
            hours = 4.5
            reason = "Adults under 30 sit toward the faster end of the reference range."
        case 30..<50:
            hours = 5.0
            reason = "The commonly cited adult average sits near the middle of the range."
        case 50..<65:
            hours = 5.5
            reason = "Reported clearance slows gradually with age."
        default:
            hours = 6.0
            reason = "Reported clearance slows gradually with age."
        }
        return HalfLifeSuggestion(hours: hours, reason: reason)
    }

    static func doseIntensity(milligrams: Double, bodyMassKilograms: Double?) -> DoseIntensity? {
        guard let bodyMassKilograms, bodyMassKilograms > 0 else { return nil }
        return DoseIntensity(milligrams: milligrams, bodyMassKilograms: bodyMassKilograms)
    }

    // MARK: - Helpers

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((abs(interval) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    static func clockText(minutesAfterMidnight: Int, calendar: Calendar = DateHelpers.gregorian) -> String {
        let normalized = ((minutesAfterMidnight % 1440) + 1440) % 1440
        let base = calendar.startOfDay(for: .now)
        let date = calendar.date(byAdding: .minute, value: normalized, to: base) ?? base
        return CaffeineFormat.time(date)
    }
}
