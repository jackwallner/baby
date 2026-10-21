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

    /// Core Data's setup error when the phone has no iCloud account. It is a
    /// Cocoa error, not a CloudKit one.
    static let noAccountCode = 134400

    /// The fixable cause behind a failed CloudKit setup, import or export, if
    /// any, including one buried in a partial failure.
    init?(_ error: Error?) {
        guard let error = error as NSError? else { return nil }
        if error.domain == NSCocoaErrorDomain, error.code == Self.noAccountCode {
            self = .signedOut
            return
        }
        guard error.domain == CKError.errorDomain else { return nil }
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

/// When this phone last finished a CloudKit import or export, and what is
/// stopping sync while it is something the parent can fix. Its own object, so
/// the dozens of events a catching-up phone posts redraw only the Settings
/// line that shows them, never Now or History.
@MainActor
final class CloudSyncState: ObservableObject {
    enum Activity: Sendable { case setup, `import`, export }

    @Published private(set) var lastSynced: Date?
    @Published private(set) var problem: CloudSyncProblem?

    /// The line says "just now" or minutes ago, so finer updates show nothing.
    static let publishInterval: TimeInterval = 30

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        lastSynced = defaults.object(forKey: AppGroup.Key.lastCloudSync) as? Date
    }

    func ended(_ activity: Activity, at date: Date, succeeded: Bool, error: Error?) {
        guard succeeded else {
            if let found = CloudSyncProblem(error), found != problem { problem = found }
            return
        }
        // A working account answers "signed out" whichever way it shows. Only
        // an upload proves there is room again: downloads go on while iCloud
        // is full and this phone's own entries stay put.
        if problem == .signedOut || (problem == .iCloudFull && activity == .export) {
            problem = nil
        }
        guard activity != .setup else { return }
        if let lastSynced, date.timeIntervalSince(lastSynced) < Self.publishInterval { return }
        lastSynced = date
        defaults.set(date, forKey: AppGroup.Key.lastCloudSync)
    }
}
