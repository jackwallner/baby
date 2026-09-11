import Foundation

extension Bundle {
    /// "1.0.0 (4)" style label sourced from the bundle so About never drifts.
    var appVersionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
