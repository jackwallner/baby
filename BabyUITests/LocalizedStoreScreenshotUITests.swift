import XCTest

private struct StoreScreenshotLocale: Decodable {
    let storeLocale: String
    let appleLanguages: String
    let appleLocale: String

    enum CodingKeys: String, CodingKey {
        case storeLocale = "store_locale"
        case appleLanguages = "apple_languages"
        case appleLocale = "apple_locale"
    }
}

@MainActor
final class LocalizedStoreScreenshotUITests: XCTestCase {
    private let bundleID = "com.jackwallner.baby"
    private let scenes: [(name: String, tab: String, identifier: String)] = [
        ("log", "0", "log.feed"),
        ("history", "2", "history.layout"),
        ("first_weeks", "1", "tallyTable"),
        ("summary", "3", "reportRange"),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureAllLocales() throws {
        let locales = try screenshotLocales()
        for locale in locales {
            for scene in scenes {
                let app = XCUIApplication(bundleIdentifier: bundleID)
                app.launchArguments = [
                    "-SeedScreenshotData",
                    "-NoCloudKit",
                    "-ScreenshotTab", scene.tab,
                    "-AppleLanguages", locale.appleLanguages,
                    "-AppleLocale", locale.appleLocale,
                ]
                app.launch()

                let ready = app.descendants(matching: .any)
                    .matching(identifier: scene.identifier).firstMatch
                XCTAssertTrue(ready.waitForExistence(timeout: 180), "\(locale.storeLocale)/\(scene.name) did not load")
                Thread.sleep(forTimeInterval: 14)

                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "\(locale.storeLocale)__\(scene.name).png"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }

    private func screenshotLocales() throws -> [StoreScreenshotLocale] {
        let bundles = [Bundle(for: Self.self), Bundle.main] + Bundle.allBundles
        guard let url = bundles.compactMap({
            $0.url(forResource: "StoreScreenshotLocales", withExtension: "json")
        }).first else {
            throw NSError(domain: "LocalizedStoreScreenshotUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "StoreScreenshotLocales.json is missing from the test bundle"])
        }
        return try JSONDecoder().decode([StoreScreenshotLocale].self, from: Data(contentsOf: url))
    }
}
