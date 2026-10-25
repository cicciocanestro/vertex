import Foundation

/// Version information read from the app bundle.
enum AppInfo {
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }()

    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }()
}
