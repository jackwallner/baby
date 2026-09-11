import XCTest
@testable import Caffeine

final class CaffeineClearanceTests: XCTestCase {
    private let source = "com.jackwallner.caffeine"

    func testDoseHalvesAfterOneHalfLife() {
        XCTAssertEqual(
            CaffeineClearance.remaining(dose: 200, elapsedHours: 5, halfLifeHours: 5),
            100,
            accuracy: 0.001
        )
    }

    func testDoseQuartersAfterTwoHalfLives() {
        XCTAssertEqual(
            CaffeineClearance.remaining(dose: 200, elapsedHours: 10, halfLifeHours: 5),
            50,
            accuracy: 0.001
        )
    }

    func testFutureDoseDoesNotContributeYet() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [sample(100, at: now.addingTimeInterval(3600))]
        XCTAssertEqual(
            CaffeineClearance.remaining(
                samples: samples,
                at: now,
                selection: .init(),
                halfLifeHours: 5
            ),
            0
        )
    }

    func testMultipleDosesDecayIndependently() {
        let now = Date(timeIntervalSince1970: 100_000)
        let samples = [
            sample(200, at: now.addingTimeInterval(-10 * 3600)),
            sample(100, at: now.addingTimeInterval(-5 * 3600)),
        ]
        XCTAssertEqual(
            CaffeineClearance.remaining(
                samples: samples,
                at: now,
                selection: .init(),
                halfLifeHours: 5
            ),
            100,
            accuracy: 0.001
        )
    }

    func testExcludedSourceDoesNotContribute() {
        let now = Date(timeIntervalSince1970: 100_000)
        let external = "com.example.logger"
        let samples = [
            sample(100, at: now, bundleID: source, isOurs: true),
            sample(200, at: now, bundleID: external, isOurs: false),
        ]
        let selection = CaffeineSourceSelection(excludedBundleIDs: [external])
        XCTAssertEqual(
            CaffeineClearance.remaining(
                samples: samples,
                at: now,
                selection: selection,
                halfLifeHours: 5
            ),
            100
        )
    }

    func testOwnSourceCannotBeExcluded() {
        let now = Date(timeIntervalSince1970: 100_000)
        let selection = CaffeineSourceSelection(excludedBundleIDs: [source])
        XCTAssertEqual(
            CaffeineClearance.remaining(
                samples: [sample(100, at: now)],
                at: now,
                selection: selection,
                halfLifeHours: 5
            ),
            100
        )
    }

    func testForecastRangeUsesFourAndSixHourHalfLives() {
        let now = Date(timeIntervalSince1970: 100_000)
        let sample = sample(200, at: now.addingTimeInterval(-10 * 3600))
        let forecast = CaffeineClearance.forecast(
            samples: [sample],
            at: now,
            selection: .init(),
            halfLifeHours: 5
        )
        XCTAssertEqual(forecast.fasterEstimate, 35.355, accuracy: 0.01)
        XCTAssertEqual(forecast.estimatedMilligrams, 50, accuracy: 0.01)
        XCTAssertEqual(forecast.slowerEstimate, 62.996, accuracy: 0.01)
    }

    func testTimeToThreshold() {
        let interval = CaffeineClearance.timeToReach(
            currentMilligrams: 200,
            threshold: 25,
            halfLifeHours: 5
        )
        XCTAssertEqual(try XCTUnwrap(interval), 15 * 3600, accuracy: 0.01)
    }

    func testLatestTimeForDoseAccountsForExistingEstimate() throws {
        let bedtime = Date(timeIntervalSince1970: 200_000)
        let result = CaffeineClearance.latestTimeForDose(
            dose: 100,
            existingSamples: [],
            bedtime: bedtime,
            threshold: 25,
            selection: .init(),
            halfLifeHours: 5
        )
        XCTAssertEqual(try XCTUnwrap(result), bedtime.addingTimeInterval(-10 * 3600))
    }

    func testLatestTimeIsNilWhenExistingEstimateExceedsPreference() {
        let bedtime = Date(timeIntervalSince1970: 200_000)
        let existing = sample(100, at: bedtime)
        XCTAssertNil(CaffeineClearance.latestTimeForDose(
            dose: 50,
            existingSamples: [existing],
            bedtime: bedtime,
            threshold: 25,
            selection: .init(),
            halfLifeHours: 5
        ))
    }

    func testSourcesCollapsePhoneAndWatch() {
        let now = Date(timeIntervalSince1970: 200_000)
        let samples = [
            sample(80, at: now, bundleID: source, isOurs: true),
            sample(120, at: now, bundleID: "com.jackwallner.caffeine.watch", isOurs: true),
        ]
        let rows = CaffeineClearance.sources(samples: samples, selection: .init())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].milligrams, 200)
    }

    func testContributionsSumToRemainingAndRankByShare() {
        let now = Date(timeIntervalSince1970: 300_000)
        let samples = [
            sample(200, at: now.addingTimeInterval(-10 * 3600)),
            sample(100, at: now.addingTimeInterval(-5 * 3600)),
        ]
        let entries = CaffeineClearance.contributions(
            samples: samples,
            at: now,
            selection: .init(),
            halfLifeHours: 5
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].remainingMilligrams, 50, accuracy: 0.001)
        XCTAssertEqual(entries[1].remainingMilligrams, 50, accuracy: 0.001)
        XCTAssertEqual(
            entries.reduce(0) { $0 + $1.remainingMilligrams },
            CaffeineClearance.remaining(
                samples: samples,
                at: now,
                selection: .init(),
                halfLifeHours: 5
            ),
            accuracy: 0.001
        )
    }

    func testContributionsDropSpentAndFutureDoses() {
        let now = Date(timeIntervalSince1970: 300_000)
        let samples = [
            sample(100, at: now.addingTimeInterval(-1 * 3600)),
            sample(100, at: now.addingTimeInterval(-60 * 3600)),
            sample(100, at: now.addingTimeInterval(3600)),
        ]
        let entries = CaffeineClearance.contributions(
            samples: samples,
            at: now,
            selection: .init(),
            halfLifeHours: 5
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sample.endDate, now.addingTimeInterval(-1 * 3600))
    }

    func testContributionsRespectExcludedSources() {
        let now = Date(timeIntervalSince1970: 300_000)
        let samples = [
            sample(100, at: now),
            sample(100, at: now, bundleID: "com.other.app", isOurs: false),
        ]
        var selection = CaffeineSourceSelection()
        selection.setIncluded(false, bundleID: "com.other.app")
        let entries = CaffeineClearance.contributions(
            samples: samples,
            at: now,
            selection: selection,
            halfLifeHours: 5
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].sample.isOurs)
    }

    private func sample(
        _ milligrams: Double,
        at date: Date,
        bundleID: String? = nil,
        isOurs: Bool = true
    ) -> CaffeineSample {
        CaffeineSample(
            id: UUID().uuidString,
            sourceBundleID: bundleID ?? source,
            sourceName: "Caffeine",
            milligrams: milligrams,
            endDate: date,
            isOurs: isOurs
        )
    }
}
