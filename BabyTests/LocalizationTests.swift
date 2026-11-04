import Foundation
import XCTest
@testable import Baby

final class LocalizationTests: XCTestCase {
    func testEnglishPluralFormsCompileIntoTheAppBundle() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jackwallner.baby"))
        let english = Locale(identifier: "en")

        XCTAssertEqual(String(localized: "\(1) feed", bundle: bundle, locale: english), "1 feed")
        XCTAssertEqual(String(localized: "\(2) feed", bundle: bundle, locale: english), "2 feeds")
        XCTAssertEqual(String(localized: "\(1) plural category", bundle: bundle, locale: english), "one 1")
        XCTAssertEqual(String(localized: "\(2) plural category", bundle: bundle, locale: english), "other 2")
    }

    func testCountHelpersUseEnglishPluralForms() {
        XCTAssertEqual(Format.count(1, .entry), "1 entry")
        XCTAssertEqual(Format.count(2, .entry), "2 entries")
        XCTAssertEqual(Format.feedUnit(1), "feed")
        XCTAssertEqual(Format.feedUnit(2), "feeds")
    }
}
