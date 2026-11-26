import AppKit

@MainActor
package enum AppAppearance {
    package static func apply() {
        let value = Preferences.userDefaults.string(forKey: PrefKey.appearance) ?? PrefDefault.appearance
        let appearance: NSAppearance?
        switch value {
        case "light":
            appearance = NSAppearance(named: .aqua)
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }

        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}
