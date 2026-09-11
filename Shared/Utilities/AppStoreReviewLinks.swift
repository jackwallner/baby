import Foundation
import StoreKit

/// App Store review deep links for Baby Tracker.
enum AppStoreReviewLinks {
    /// App Store Connect record `Baby Tracker: Feeds & Diapers`.
    static let appStoreID = "6811133796"

    static var writeReviewURL: URL {
        URL(string: writeReviewURLString)!
    }

    private static var writeReviewURLString: String {
        if let country = storefrontCountryCode {
            return "https://apps.apple.com/\(country)/app/id\(appStoreID)?action=write-review"
        }
        return "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    }

    private static var storefrontCountryCode: String? {
        if let alpha3 = SKPaymentQueue.default().storefront?.countryCode.lowercased(),
           let mapped = alpha3ToAppStoreCountry[alpha3] {
            return mapped
        }
        if let region = Locale.current.region?.identifier.lowercased(), region.count == 2 {
            return region
        }
        return nil
    }

    private static let alpha3ToAppStoreCountry: [String: String] = [
        "usa": "us", "gbr": "gb", "deu": "de", "fra": "fr", "ita": "it",
        "esp": "es", "can": "ca", "aus": "au", "jpn": "jp", "kor": "kr",
        "chn": "cn", "hkg": "hk", "twn": "tw", "nld": "nl", "bel": "be",
        "che": "ch", "aut": "at", "swe": "se", "nor": "no", "dnk": "dk",
        "fin": "fi", "irl": "ie", "prt": "pt", "pol": "pl", "bra": "br",
        "mex": "mx", "ind": "in", "sgp": "sg", "nzl": "nz", "are": "ae",
        "sau": "sa", "tur": "tr", "rus": "ru", "ukr": "ua", "cze": "cz",
        "rou": "ro", "hun": "hu", "grc": "gr", "isr": "il", "tha": "th",
        "mys": "my", "idn": "id", "phl": "ph", "vnm": "vn", "zaf": "za",
        "arg": "ar", "chl": "cl", "col": "co", "per": "pe",
    ]
}

/// Static legal URLs shared by onboarding, Settings, and the paywall.
enum BabyLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/baby/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/baby/support.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}
