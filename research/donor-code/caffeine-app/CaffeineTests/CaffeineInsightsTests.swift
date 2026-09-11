import XCTest
@testable import Caffeine

final class CaffeineInsightsTests: XCTestCase {

    // MARK: - Group comparison

    func testComparisonSplitsAtMedianAndReportsBothMeans() {
        // Twenty nights: the ten higher-caffeine ones slept an hour less.
        let records = (0..<20).map { index in
            record(
                daysAgo: index,
                bedtime: index < 10 ? 10 : 60,
                sleep: index < 10 ? 8 * 3600 : 7 * 3600
            )
        }
        guard let comparison = CaffeineInsights.compare(records: records, metric: .sleepDuration) else {
            return XCTFail("Expected a comparison")
        }
        XCTAssertEqual(comparison.lowerCount, 10)
        XCTAssertEqual(comparison.higherCount, 10)
        XCTAssertEqual(comparison.delta, -3600, accuracy: 1)
        XCTAssertTrue(comparison.isMeaningful)
    }

    func testComparisonNeedsMinimumRecords() {
        let records = (0..<(CaffeineInsights.minimumRecords - 1)).map {
            record(daysAgo: $0, bedtime: Double($0) * 5, sleep: 7 * 3600)
        }
        XCTAssertNil(CaffeineInsights.compare(records: records, metric: .sleepDuration))
    }

    func testComparisonIsNilWhenExposureNeverVaries() {
        let records = (0..<30).map { record(daysAgo: $0, bedtime: 40, sleep: 7 * 3600) }
        XCTAssertNil(CaffeineInsights.compare(records: records, metric: .sleepDuration))
    }

    func testSmallDifferenceIsReportedButNotMeaningful() {
        // Five minutes apart, well inside the sleep-duration noise floor.
        let records = (0..<20).map { index in
            record(
                daysAgo: index,
                bedtime: index < 10 ? 10 : 60,
                sleep: index < 10 ? 7 * 3600 : 7 * 3600 - 300
            )
        }
        let comparison = CaffeineInsights.compare(records: records, metric: .sleepDuration)
        XCTAssertNotNil(comparison)
        XCTAssertEqual(comparison?.isMeaningful, false)
    }

    func testComparisonSkipsRecordsMissingTheMetric() {
        // Only the even days recorded sleep, so half the records drop out and
        // the comparison is built from the fifteen that remain.
        let records = (0..<30).map { index in
            record(
                daysAgo: index,
                bedtime: Double(index) * 5,
                sleep: index.isMultiple(of: 2) ? 7 * 3600 : nil
            )
        }
        let comparison = CaffeineInsights.compare(records: records, metric: .sleepDuration)
        XCTAssertEqual(comparison?.sampleCount, 15)
    }

    /// A split needs the median to sit above the lowest exposure. When most days
    /// carry the same amount there is no honest way to draw the line, and the
    /// comparison is withheld rather than drawn against a tie.
    func testComparisonIsNilWhenTheMedianEqualsTheMinimum() {
        let records = (0..<20).map { index in
            record(daysAgo: index, bedtime: index < 15 ? 0 : 80, sleep: 7 * 3600)
        }
        XCTAssertNil(CaffeineInsights.compare(records: records, metric: .sleepDuration))
    }

    func testDayMetricsCompareAgainstConsumedNotBedtime() {
        // Bedtime is flat, so a split can only come from the consumed total.
        let records = (0..<20).map { index in
            DailyBodyRecord(
                date: DateHelpers.daysAgo(index),
                consumedMilligrams: index < 10 ? 50 : 400,
                bedtimeMilligrams: 20,
                steps: index < 10 ? 6000 : 9000
            )
        }
        let comparison = CaffeineInsights.compare(records: records, metric: .steps)
        XCTAssertEqual(comparison?.delta ?? 0, 3000, accuracy: 1)
    }

    // MARK: - Personal cutoff

    func testCutoffNeedsEnoughNights() {
        let records = (0..<10).map { record(daysAgo: $0, bedtime: Double($0) * 10, sleep: 7 * 3600) }
        guard case let .insufficientData(have, need) = CaffeineInsights.personalCutoff(records: records) else {
            return XCTFail("Expected insufficientData")
        }
        XCTAssertEqual(have, 10)
        XCTAssertEqual(need, CaffeineInsights.minimumCutoffNights)
    }

    func testCutoffReportsNoDifferenceWhenSleepIsFlat() {
        let records = (0..<40).map { index in
            record(daysAgo: index, bedtime: Double(index) * 3, sleep: 7 * 3600)
        }
        guard case let .noMeasurableDifference(nights) = CaffeineInsights.personalCutoff(records: records) else {
            return XCTFail("Expected noMeasurableDifference")
        }
        XCTAssertEqual(nights, 40)
    }

    func testCutoffFindsTheThresholdWhereSleepDrops() {
        // Sleep is a full hour shorter once the bedtime estimate reaches 50 mg.
        let records = (0..<40).map { index in
            let bedtime = Double(index % 20) * 5
            return record(
                daysAgo: index,
                bedtime: bedtime,
                sleep: bedtime >= 50 ? 6.5 * 3600 : 7.5 * 3600
            )
        }
        guard case let .found(cutoff) = CaffeineInsights.personalCutoff(records: records) else {
            return XCTFail("Expected a cutoff")
        }
        // The step is at 50, and that is the threshold that separates the two
        // groups most cleanly. A lower one would mix short nights into the
        // "below" group and shrink the difference.
        XCTAssertEqual(cutoff.milligrams, 50)
        XCTAssertEqual(cutoff.sleepDelta, -3600, accuracy: 1)
        XCTAssertEqual(cutoff.nightsAbove, 20)
        XCTAssertEqual(cutoff.nightsBelow, 20)
    }

    /// A threshold that leaves a handful of nights on one side must not be
    /// reported, however large the difference across that split looks.
    func testCutoffRejectsLopsidedSplits() {
        // Thirty-six nights at one of two levels: thirty-two quiet ones and four
        // heavy ones that slept badly. Every threshold either puts all of them
        // on the same side or leaves four nights against thirty-two.
        let records = (0..<36).map { index in
            let bedtime = index < 32 ? 10.0 : 120.0
            return record(daysAgo: index, bedtime: bedtime, sleep: bedtime >= 120 ? 4 * 3600 : 8 * 3600)
        }
        guard case .noMeasurableDifference = CaffeineInsights.personalCutoff(records: records) else {
            return XCTFail("Expected the lopsided split to be rejected")
        }
    }

    func testCutoffIgnoresNightsWithoutSleep() {
        let records = (0..<40).map { index in
            record(daysAgo: index, bedtime: Double(index) * 3, sleep: nil)
        }
        guard case let .insufficientData(have, _) = CaffeineInsights.personalCutoff(records: records) else {
            return XCTFail("Expected insufficientData")
        }
        XCTAssertEqual(have, 0)
    }

    // MARK: - Correlation

    func testPearsonIsOneForAPerfectLine() throws {
        let x = [1.0, 2, 3, 4, 5]
        let y = [2.0, 4, 6, 8, 10]
        XCTAssertEqual(try XCTUnwrap(CaffeineInsights.pearson(x, y)), 1, accuracy: 0.0001)
    }

    func testPearsonIsNilForAFlatSeries() {
        XCTAssertNil(CaffeineInsights.pearson([1, 1, 1, 1], [1, 2, 3, 4]))
    }

    // MARK: - Heart rate response

    func testHeartRateResponseComparesBeforeAndAfterEachDose() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var doses: [CaffeineSample] = []
        var readings: [(date: Date, bpm: Double)] = []
        for index in 0..<6 {
            let doseTime = start.addingTimeInterval(Double(index) * 24 * 3600)
            doses.append(CaffeineSample(
                id: "dose-\(index)",
                sourceBundleID: caffeineOwnSourceBundleID,
                sourceName: "Caffeine",
                milligrams: 120,
                endDate: doseTime,
                isOurs: true
            ))
            readings.append((doseTime.addingTimeInterval(-30 * 60), 60))
            readings.append((doseTime.addingTimeInterval(45 * 60), 70))
        }
        let response = CaffeineInsights.heartRateResponse(doses: doses, heartRates: readings)
        XCTAssertEqual(response?.doseCount, 6)
        XCTAssertEqual(response?.delta ?? 0, 10, accuracy: 0.001)
    }

    func testHeartRateResponseSkipsDosesMissingEitherSide() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let dose = CaffeineSample(
            id: "dose",
            sourceBundleID: caffeineOwnSourceBundleID,
            sourceName: "Caffeine",
            milligrams: 120,
            endDate: start,
            isOurs: true
        )
        // Only a "before" reading, so this dose contributes nothing and the
        // sample count never reaches the minimum.
        let response = CaffeineInsights.heartRateResponse(
            doses: [dose],
            heartRates: [(start.addingTimeInterval(-30 * 60), 60)]
        )
        XCTAssertNil(response)
    }

    func testHeartRateResponseIgnoresSmallDoses() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let doses = (0..<6).map { index in
            CaffeineSample(
                id: "dose-\(index)",
                sourceBundleID: caffeineOwnSourceBundleID,
                sourceName: "Caffeine",
                milligrams: 10,
                endDate: start.addingTimeInterval(Double(index) * 24 * 3600),
                isOurs: true
            )
        }
        let readings = doses.flatMap { dose in
            [
                (date: dose.endDate.addingTimeInterval(-30 * 60), bpm: 60.0),
                (date: dose.endDate.addingTimeInterval(45 * 60), bpm: 70.0),
            ]
        }
        XCTAssertNil(CaffeineInsights.heartRateResponse(doses: doses, heartRates: readings))
    }

    // MARK: - Workouts

    func testWorkoutSummaryUsesTheModelAtEachStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let dose = CaffeineSample(
            id: "dose",
            sourceBundleID: caffeineOwnSourceBundleID,
            sourceName: "Caffeine",
            milligrams: 200,
            endDate: start,
            isOurs: true
        )
        // One half-life after the dose, so exactly half remains.
        let summary = CaffeineInsights.workoutSummary(
            workoutStarts: [start.addingTimeInterval(5 * 3600)],
            samples: [dose],
            selection: .init(),
            halfLifeHours: 5
        )
        XCTAssertEqual(summary?.workoutCount, 1)
        XCTAssertEqual(summary?.averageOnBoard ?? 0, 100, accuracy: 0.001)
    }

    func testWorkoutSummaryIsNilWithoutWorkouts() {
        XCTAssertNil(CaffeineInsights.workoutSummary(
            workoutStarts: [],
            samples: [],
            selection: .init(),
            halfLifeHours: 5
        ))
    }

    // MARK: - Body-derived defaults

    func testSuggestedHalfLifeStaysInsideTheReferenceRange() {
        for age in [13, 25, 30, 49, 50, 64, 65, 90] {
            let suggestion = CaffeineInsights.suggestedHalfLife(ageYears: age)
            XCTAssertNotNil(suggestion, "age \(age)")
            let hours = suggestion?.hours ?? 0
            XCTAssertTrue(
                CaffeineClearance.referenceHalfLifeRange.contains(hours),
                "age \(age) produced \(hours)"
            )
        }
    }

    func testSuggestedHalfLifeRisesWithAge() {
        let young = CaffeineInsights.suggestedHalfLife(ageYears: 25)?.hours ?? 0
        let older = CaffeineInsights.suggestedHalfLife(ageYears: 70)?.hours ?? 0
        XCTAssertLessThan(young, older)
    }

    func testSuggestedHalfLifeRejectsImplausibleAges() {
        XCTAssertNil(CaffeineInsights.suggestedHalfLife(ageYears: nil))
        XCTAssertNil(CaffeineInsights.suggestedHalfLife(ageYears: 4))
        XCTAssertNil(CaffeineInsights.suggestedHalfLife(ageYears: 130))
    }

    func testDoseIntensityNeedsABodyMass() {
        XCTAssertNil(CaffeineInsights.doseIntensity(milligrams: 200, bodyMassKilograms: nil))
        XCTAssertNil(CaffeineInsights.doseIntensity(milligrams: 200, bodyMassKilograms: 0))
        let intensity = CaffeineInsights.doseIntensity(milligrams: 200, bodyMassKilograms: 80)
        XCTAssertEqual(intensity?.milligramsPerKilogram ?? 0, 2.5, accuracy: 0.0001)
    }

    // MARK: - Sleep merging

    func testOverlappingSleepSamplesAreCountedOnce() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // A watch and a phone both recording the same two hours.
        let merged = HealthInsightsService.mergedDuration([
            (start, start.addingTimeInterval(2 * 3600)),
            (start.addingTimeInterval(3600), start.addingTimeInterval(2 * 3600)),
        ])
        XCTAssertEqual(merged, 2 * 3600, accuracy: 0.001)
    }

    func testDisjointSleepSamplesAreSummed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let merged = HealthInsightsService.mergedDuration([
            (start, start.addingTimeInterval(3600)),
            (start.addingTimeInterval(7200), start.addingTimeInterval(3 * 3600)),
        ])
        XCTAssertEqual(merged, 2 * 3600, accuracy: 0.001)
    }

    // MARK: - Drink presets

    func testLegacyMilligramsMapToTheNearestNamedDrink() {
        XCTAssertEqual(DrinkCatalog.closestName(to: 95).name, "Drip coffee")
        XCTAssertEqual(DrinkCatalog.closestName(to: 80).name, "Energy drink")
    }

    func testAnUnrecognisedAmountKeepsAGenericName() {
        let preset = DrinkCatalog.closestName(to: 333)
        XCTAssertEqual(preset.name, "Caffeine")
        XCTAssertEqual(preset.milligrams, 333)
    }

    func testCatalogAmountsAreAllPlausible() {
        for drink in DrinkCatalog.allDrinks {
            XCTAssertGreaterThanOrEqual(drink.milligrams, 0, drink.name)
            XCTAssertLessThanOrEqual(drink.milligrams, 400, drink.name)
        }
    }

    // MARK: - Helpers

    private func record(daysAgo: Int, bedtime: Double, sleep: TimeInterval?) -> DailyBodyRecord {
        DailyBodyRecord(
            date: DateHelpers.daysAgo(daysAgo),
            consumedMilligrams: bedtime * 4,
            bedtimeMilligrams: bedtime,
            sleepDuration: sleep
        )
    }
}
