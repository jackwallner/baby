import Foundation

#if DEBUG
enum ScreenshotFixtures {
    static func samples(from start: Date, to end: Date) -> [BabySample] {
        let now = Date.now
        let all = [
            BabySample(
                id: "fixture-morning",
                sourceBundleID: "com.apple.Health",
                sourceName: "Apple Health",
                milligrams: 80,
                endDate: now.addingTimeInterval(-8 * 3600),
                isOurs: false
            ),
            BabySample(
                id: "fixture-coffee",
                sourceBundleID: babyOwnSourceBundleID,
                sourceName: "Baby",
                milligrams: 120,
                endDate: now.addingTimeInterval(-4 * 3600),
                isOurs: true
            ),
            BabySample(
                id: "fixture-tea",
                sourceBundleID: "com.apple.Health",
                sourceName: "Apple Health",
                milligrams: 60,
                endDate: now.addingTimeInterval(-90 * 60),
                isOurs: false
            ),
        ]
        return all.filter { $0.endDate >= start && $0.endDate < end }
    }

    static func history(days: Int) -> [BabyDaySummary] {
        let consumed = [160.0, 240, 180, 310, 120, 205, 260, 145, 280, 195, 225, 170, 300, 210]
        let bedtime = [18.0, 42, 27, 65, 12, 33, 48, 16, 54, 24, 39, 20, 61, 35]
        let count = max(days, 1)
        return (0..<count).map { offset in
            let index = (consumed.count - count + offset).modulo(consumed.count)
            return BabyDaySummary(
                date: DateHelpers.daysAgo(count - 1 - offset),
                milligrams: consumed[index],
                estimatedAtBedtime: bedtime[index]
            )
        }
    }
}

extension ScreenshotFixtures {
    /// Ninety plausible days so the Body tab renders a full report in App Store
    /// captures without needing real Apple Health data on the simulator.
    static func insightsReport() -> InsightsReport {
        var records: [DailyBodyRecord] = []
        for offset in stride(from: 89, through: 0, by: -1) {
            let day = DateHelpers.daysAgo(offset)
            let wave = sin(Double(offset) / 3.1)
            let consumed = 180 + wave * 90
            let bedtime = max(8, 34 + wave * 26)
            // A clear step at 40 mg, so the fixture exercises the "found a
            // cutoff" branch rather than the no-difference one.
            let sleep = (bedtime >= 40 ? 6.6 : 7.6) * 3600 + wave * 600
            records.append(DailyBodyRecord(
                date: day,
                consumedMilligrams: consumed,
                bedtimeMilligrams: bedtime,
                sleepDuration: sleep,
                sleepOnsetLatency: (14 + wave * 6) * 60,
                sleepInterruptions: Int((1.6 + wave).rounded()),
                restingHeartRate: 58 + wave * 3,
                heartRateVariability: 46 - wave * 6,
                respiratoryRate: 14.6 + wave * 0.4,
                oxygenSaturation: 0.968 - wave * 0.004,
                steps: 8200 + wave * 1400,
                activeEnergy: 520 + wave * 120
            ))
        }
        return InsightsReport(
            records: records,
            comparisons: BabyInsights.comparisons(records: records),
            cutoff: BabyInsights.personalCutoff(records: records),
            heartRateResponse: HeartRateResponse(doseCount: 42, baselineBPM: 68, afterBPM: 74.2),
            workouts: WorkoutBabySummary(workoutCount: 18, averageOnBoard: 84, typicalStartMinutes: 7 * 60 + 20),
            doseIntensity: DoseIntensity(milligrams: 240, bodyMassKilograms: 78),
            halfLifeSuggestion: BabyInsights.suggestedHalfLife(ageYears: 34),
            bodyMassKilograms: 78,
            ageYears: 34,
            biologicalSexDescription: nil
        )
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
#endif
