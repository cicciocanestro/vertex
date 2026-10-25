import AppKit

package enum AppAppearance {
    package static func apply() {
        let value = UserDefaults.standard.string(forKey: PrefKey.appearance) ?? "dark"
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
