import Foundation
import XCTest
@testable import Baby

final class LocalizationTests: XCTestCase {
    func testEnglishPluralFormsCompileIntoTheAppBundle() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jackwallner.baby"))
        let english = Locale(identifier: "en")

        XCTAssertEqual(String(localized: "\(1) feed", bundle: bundle, locale: english), "1 feed")
        XCTAssertEqual(String(localized: "\(2) feed", bundle: bundle, locale: english), "2 feeds")
    }

    func testCountHelpersUseEnglishPluralForms() {
        XCTAssertEqual(Format.count(1, .entry), "1 entry")
        XCTAssertEqual(Format.count(2, .entry), "2 entries")
    }

    func testPluralSubstitutionsSayTheirTextOnce() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jackwallner.baby"))
        let english = Locale(identifier: "en")
        func text(_ value: String.LocalizationValue) -> String { String(localized: value, bundle: bundle, locale: english) }

        XCTAssertEqual(text("Move \(1) entry"), "Move 1 entry")
        XCTAssertEqual(text("Move \(2) entry"), "Move 2 entries")
        XCTAssertEqual(text("Today \(1) feed"), "Today 1 feed")
        XCTAssertEqual(text("Today \(2) feed"), "Today 2 feeds")
        XCTAssertEqual(text("\(1) feeds"), "1 feed")
        XCTAssertEqual(text("\(8) feeds"), "8 feeds")
        XCTAssertEqual(text("\(1) pee"), "1 pee")
        XCTAssertEqual(text("\(2) dirty"), "2 dirty")
        XCTAssertEqual(text("\(2) complete day"), "2 complete days")
        XCTAssertEqual(text("\(2) partial or unlogged day"), "2 partial or unlogged days")
        XCTAssertEqual(text("Averages use \(1) complete day."), "Averages use 1 complete day.")
        XCTAssertEqual(text("Averages use \(6) complete day."), "Averages use 6 complete days.")
        XCTAssertEqual(text("\(1) day with nothing logged is left out."), "1 day with nothing logged is left out.")
        XCTAssertEqual(text("\(2) day with nothing logged is left out."), "2 days with nothing logged are left out.")
        XCTAssertEqual(text("\(2) partial or unlogged day left out."), "2 partial or unlogged days left out.")
    }

    func testMultiPeriodPricesSayThePriceOnce() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jackwallner.baby"))
        let english = Locale(identifier: "en")
        func text(_ value: String.LocalizationValue) -> String { String(localized: value, bundle: bundle, locale: english) }
        let price = "$9.99"

        XCTAssertEqual(text("\(price) / \(2) days"), "$9.99 / 2 days")
        XCTAssertEqual(text("\(price) / \(3) months"), "$9.99 / 3 months")
        XCTAssertEqual(text("\(price) / \(2) weeks"), "$9.99 / 2 weeks")
        XCTAssertEqual(text("\(price) / \(2) years"), "$9.99 / 2 years")
        XCTAssertEqual(text("\(price) per \(2) days"), "$9.99 per 2 days")
        XCTAssertEqual(text("\(price) per \(3) months"), "$9.99 per 3 months")
        XCTAssertEqual(text("\(price) per \(2) weeks"), "$9.99 per 2 weeks")
        XCTAssertEqual(text("\(price) per \(2) years"), "$9.99 per 2 years")
    }

    func testCountWordsComeFromTheCatalog() {
        XCTAssertEqual(Format.unitLabel(.feed, count: 1), "feed")
        XCTAssertEqual(Format.unitLabel(.feed, count: 0), "feeds")
        XCTAssertEqual(Format.unitLabel(.feed, count: 2), "feeds")
        XCTAssertEqual(Format.unitLabel(.wet, count: 2, words: .peePoop), "pee")
        XCTAssertEqual(Format.unitLabel(.wet, count: 2, words: .wetDirty), "wet")
        XCTAssertEqual(Format.unitLabel(.dirty, count: 1, words: .peePoop), "poop")
        XCTAssertEqual(Format.unitLabel(.dirty, count: 1, words: .wetDirty), "dirty")
        XCTAssertEqual(Format.unitLabel(.sleep, count: 2), "sleep")
    }

    func testDurationsOmitZeroUnitsAndTruncate() {
        XCTAssertEqual(Format.compactDuration(-30), "0m")
        XCTAssertEqual(Format.compactDuration(0), "0m")
        XCTAssertEqual(Format.compactDuration(59), "0m")
        XCTAssertEqual(Format.compactDuration(12 * 60), "12m")
        XCTAssertEqual(Format.compactDuration(3599), "59m")
        XCTAssertEqual(Format.compactDuration(3600), "1h")
        XCTAssertEqual(Format.compactDuration(2 * 3600 + 14 * 60 + 59), "2h 14m")
        XCTAssertEqual(Format.compactDuration(86399), "23h 59m")
        XCTAssertEqual(Format.compactDuration(86400), "1d")
        XCTAssertEqual(Format.compactDuration(27 * 3600 + 59 * 60), "1d 3h")
        XCTAssertEqual(Format.duration(30), "under a minute")
        XCTAssertEqual(Format.asleep(65 * 60), "Asleep 1h 5m")
    }

    func testAmountsKeepTheirUnitsAndReadAsBefore() {
        XCTAssertEqual(Format.grams(3000, imperial: true), "6 lb 10 oz")
        XCTAssertEqual(Format.grams(3416, imperial: true), "7 lb 8.5 oz")
        XCTAssertEqual(Format.grams(3500, imperial: false), "3.50 kg")
        XCTAssertEqual(Format.gramsChange(30, imperial: true), "+1 oz")
        XCTAssertEqual(Format.gramsChange(-30, imperial: true), "−1 oz")
        XCTAssertEqual(Format.gramsChange(1200, imperial: false), "+1200 g")
        XCTAssertEqual(Format.millilitres(120, imperial: true), "4 oz")
        XCTAssertEqual(Format.millilitres(120, imperial: false), "120 ml")
        XCTAssertEqual(Format.millilitres(1200, imperial: false), "1200 ml")
    }

    func testWeightPickerLabelsStayInTheirOwnWheelsUnit() {
        XCTAssertEqual(Format.measurement(7, unit: UnitMass.pounds, fractionDigits: 0...0), "7 lb")
        XCTAssertEqual(Format.measurement(3.5, unit: UnitMass.ounces, fractionDigits: 0...1), "3.5 oz")
        XCTAssertEqual(Format.measurement(3, unit: UnitMass.kilograms, fractionDigits: 0...0), "3 kg")
        XCTAssertEqual(Format.measurement(990, unit: UnitMass.grams, fractionDigits: 0...0), "990 g")
    }

    @MainActor
    func testHeadingsStayCapitals() {
        XCTAssertEqual(SectionLabel(text: "For the doctor").displayText, "FOR THE DOCTOR")
        XCTAssertEqual(SectionLabel(text: "Baby+").displayText, "BABY+")
    }

    func testPDFWeightLabelStaysCapitals() throws {
        XCTAssertEqual(PDFReport.weightStatLabel(nil), "WEIGHT")
        let date = try XCTUnwrap(DateComponents(calendar: .current, year: 2026, month: 9, day: 9).date)
        XCTAssertEqual(PDFReport.weightStatLabel(date), "WEIGHT, SEP 9")
    }

    func testSiriRepliesKeepTheirCasing() {
        XCTAssertEqual(LogChoice.feed.feedDialog, "Logged a feed.")
        XCTAssertEqual(LogChoice.feedLeft.feedDialog, "Logged a feed, left.")
        XCTAssertEqual(LogChoice.feedRight.feedDialog, "Logged a feed, right.")
        XCTAssertEqual(LogChoice.bottle.feedDialog, "Logged a feed, bottle.")
    }

    func testTurnedOffErrorsAreCapitalizedInTheChosenWords() {
        defer { AppGroup.defaults.removeObject(forKey: AppGroup.Key.diaperWords) }
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.diaperWords)
        let tail = " is turned off in Baby Tracker's Settings, so nothing was logged."
        XCTAssertEqual(EventKind.feed.turnedOffMessage, "Feed" + tail)
        XCTAssertEqual(EventKind.wet.turnedOffMessage, "Pee" + tail)
        XCTAssertEqual(EventKind.dirty.turnedOffMessage, "Poop" + tail)
        XCTAssertEqual(EventKind.sleep.turnedOffMessage, "Sleep" + tail)
        XCTAssertEqual(EventKind.wet.loggedDiaperDialog, "Logged a pee diaper.")
        AppGroup.defaults.set(DiaperWords.wetDirty.rawValue, forKey: AppGroup.Key.diaperWords)
        XCTAssertEqual(EventKind.wet.turnedOffMessage, "Wet" + tail)
        XCTAssertEqual(EventKind.dirty.turnedOffMessage, "Dirty" + tail)
        XCTAssertEqual(EventKind.dirty.loggedDiaperDialog, "Logged a dirty diaper.")
    }

    func testSidesAreWholeLabels() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jackwallner.baby"))
        XCTAssertEqual(FeedSide.left.breastLabel, "Left breast")
        XCTAssertEqual(FeedSide.right.breastLabel, "Right breast")
        XCTAssertEqual(FeedSide.bottle.breastLabel, "Bottle")
        XCTAssertEqual(FeedSide.left.startOnLabel, "Start on Left")
        XCTAssertEqual(FeedSide.right.startOnLabel, "Start on Right")
        XCTAssertNil(FeedSide.bottle.startOnLabel)
        let (start, end) = ("9 PM", "1 AM")
        XCTAssertEqual(String(localized: "\(start) to \(end)", bundle: bundle, locale: Locale(identifier: "en")), "9 PM to 1 AM")
    }

    func testTrialDisclosuresReadAsBefore() {
        let week = TrialOffer(count: 7, unit: .day)
        let price = "$24.99 / year"
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        XCTAssertEqual(week.label, "7-day free trial")
        XCTAssertEqual(TrialOffer(count: 1, unit: .month).label, "1-month free trial")
        XCTAssertEqual(TrialOffer(count: 1, unit: .year).label, "1-year free trial")
        XCTAssertEqual(ConversionCopy.billedNote(trial: week, eligibleForTrial: true), "7-day free trial included · Cancel anytime")
        XCTAssertEqual(ConversionCopy.billedNote(trial: week, eligibleForTrial: false), "Billed automatically · Cancel anytime")
        XCTAssertEqual(ConversionCopy.disclosure(trial: week, priceLabel: price, eligibleForTrial: true), "\(price) after the 7-day free trial. \(renew)")
        XCTAssertEqual(ConversionCopy.disclosure(trial: TrialOffer(count: 1, unit: .month), priceLabel: price, eligibleForTrial: true), "\(price) after the 1-month free trial. \(renew)")
        XCTAssertEqual(ConversionCopy.disclosure(trial: TrialOffer(count: 1, unit: .year), priceLabel: price, eligibleForTrial: true), "\(price) after the 1-year free trial. \(renew)")
        XCTAssertEqual(ConversionCopy.disclosure(trial: nil, priceLabel: price, eligibleForTrial: false), "\(price). \(renew)")
        XCTAssertEqual(
            ConversionCopy.sheetDisclosure(trial: week, priceLabel: price, eligibleForTrial: true),
            "\(price) after the 7-day free trial. Auto-renews unless cancelled at least 24 hours before the trial ends."
        )
        XCTAssertEqual(
            ConversionCopy.sheetDisclosure(trial: week, priceLabel: price, eligibleForTrial: false),
            "\(price). Auto-renews unless cancelled 24h before the period ends."
        )
    }

    @MainActor
    func testDiaperTakeawayKeepsItsAveragesAsNumbers() {
        let all = TrackedKinds.all
        func takeaway(_ wet: Double, _ dirty: Double, _ tracked: TrackedKinds, _ words: DiaperWords) -> String {
            ReportChart.diaperTakeaway(wetAverage: wet, dirtyAverage: dirty, tracked: tracked, words: words)
        }
        XCTAssertEqual(takeaway(6, 2.5, all, .peePoop), "About 6 pee and 2.5 poop a day.")
        XCTAssertEqual(takeaway(1, 1, all, .wetDirty), "About 1 wet and 1 dirty a day.")
        XCTAssertEqual(takeaway(6.5, 2, TrackedKinds(hidden: [.dirty]), .peePoop), "About 6.5 pee a day.")
        XCTAssertEqual(takeaway(6.5, 2, TrackedKinds(hidden: [.dirty]), .wetDirty), "About 6.5 wet a day.")
        XCTAssertEqual(takeaway(6, 2.5, TrackedKinds(hidden: [.wet]), .peePoop), "About 2.5 poop a day.")
        XCTAssertEqual(takeaway(6, 12, TrackedKinds(hidden: [.wet]), .wetDirty), "About 12 dirty a day.")
    }
}
