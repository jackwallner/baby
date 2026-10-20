import CloudKit
import Foundation

/// Why this phone's log stopped reaching iCloud, when it is something the
/// parent can fix. A dropped connection or a busy server is not on this list:
/// CloudKit retries those by itself and nobody needs to hear about them.
enum CloudSyncProblem: String, Equatable, Sendable {
    case iCloudFull
    case signedOut

    var message: String {
        switch self {
        case .iCloudFull:
            "Your iCloud storage is full, so new entries stay on this iPhone until there is room."
        case .signedOut:
            "Sign in to iCloud in the Settings app to keep this log in step with your other devices."
        }
    }

    /// The fixable cause behind a failed CloudKit import or export, if any,
    /// including one buried in a partial failure.
    init?(_ error: Error?) {
        guard let error = error as NSError?, error.domain == CKError.errorDomain else { return nil }
        switch CKError.Code(rawValue: error.code) {
        case .quotaExceeded?:
            self = .iCloudFull
        case .notAuthenticated?:
            self = .signedOut
        case .partialFailure?:
            let parts = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] ?? [:]).values
            guard let problem = parts.lazy.compactMap(CloudSyncProblem.init).first else { return nil }
            self = problem
        default:
            return nil
        }
    }
}
