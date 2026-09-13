import XCTest
@testable import Baby

final class GuidanceTests: XCTestCase {
    func testDayOfLifeStartsAtOneOnTheBirthDay() {
        let calendar = Calendar(identifier: .gregorian)
        let birth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 15))!
        let sameNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 50))!
        let nextMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 10))!
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: sameNight, calendar: calendar), 1)
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: nextMorning, calendar: calendar), 2)
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        XCTAssertNil(DateHelpers.dayOfLife(birthDate: birth, on: before, calendar: calendar))
    }

    func testTypicalRangesRiseWithTheDayOfLifeThenPlateau() {
        for day in 1...5 {
            XCTAssertEqual(Guidance.range(forDayOfLife: day).wetMin, day, "wet diapers track the day of life through day five")
        }
        XCTAssertEqual(Guidance.range(forDayOfLife: 6).wetMin, 6)
        XCTAssertEqual(Guidance.range(forDayOfLife: 40).wetMin, 6)
        XCTAssertEqual(Guidance.range(forDayOfLife: 2).dirtyMin, 1)
        XCTAssertEqual(Guidance.range(forDayOfLife: 3).dirtyMin, 2)
        XCTAssertEqual(Guidance.range(forDayOfLife: 12).dirtyMin, 2)
        XCTAssertEqual(Guidance.range(forDayOfLife: 0).day, 1)
    }

    func testReferenceIdentifiesItsScopeAndFeverAdviceHasAgeAndMethod() {
        XCTAssertTrue(Guidance.referenceScope.contains("breastfeeding"))
        XCTAssertTrue(Guidance.referenceScope.contains("Formula or mixed"))
        XCTAssertTrue(Guidance.referenceScope.contains("only what you log"))
        XCTAssertEqual(Guidance.diaperSource.host, "www.swlondon-healthiertogether.nhs.uk")
        let fever = Guidance.callIf.first { $0.contains("100.4") }
        XCTAssertNotNil(fever)
        XCTAssertTrue(fever?.contains("3 months or younger") == true)
        XCTAssertTrue(fever?.contains("rectal") == true)
        XCTAssertTrue(fever?.contains("immediate") == true)
    }

    func testClaimLanguageStaysOutOfEveryGuidanceString() {
        var strings = Guidance.callIf + [Guidance.sourceLine, Guidance.disclaimer]
        for day in 1...8 { strings.append(Guidance.range(forDayOfLife: day).summary) }
        for text in strings {
            for banned in ["abnormal", "dehydrated", "diagnose your", "will treat", "cures"] {
                XCTAssertFalse(text.lowercased().contains(banned), "\(text) contains \(banned)")
            }
        }
    }
}
