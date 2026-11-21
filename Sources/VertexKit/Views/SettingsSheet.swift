import AppKit
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var engine: TorrentEngine

    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @AppStorage(PrefKey.downloadPath) var downloadPath = PrefDefault.downloadPath
    @AppStorage(PrefKey.downloadLimitKB) var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) var uploadLimitKB = PrefDefault.uploadLimitKB
    @AppStorage(PrefKey.listenPort) var listenPort = PrefDefault.listenPort
    @AppStorage(PrefKey.maxActiveTorrents) var maxActiveTorrents = PrefDefault.maxActiveTorrents
    @AppStorage(PrefKey.bindAddress) var bindAddress = PrefDefault.bindAddress
    @AppStorage(PrefKey.dhtEnabled) var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.pexEnabled) var pexEnabled = PrefDefault.pexEnabled
    @AppStorage(PrefKey.lsdEnabled) var lsdEnabled = PrefDefault.lsdEnabled
    @AppStorage(PrefKey.upnpEnabled) var upnpEnabled = PrefDefault.upnpEnabled
    @AppStorage(PrefKey.startPaused) var startPaused = PrefDefault.startPaused
    @AppStorage(PrefKey.sequentialDefault) var sequentialDefault = PrefDefault.sequentialDefault
    @AppStorage(PrefKey.seedRatioLimit) var seedRatioLimit = PrefDefault.seedRatioLimit
    @AppStorage(PrefKey.notificationsEnabled) var notificationsEnabled = PrefDefault.notificationsEnabled
    @AppStorage(PrefKey.uiDensity) var densityRaw = PrefDefault.uiDensity
    @AppStorage(PrefKey.proxyEnabled) var proxyEnabled = PrefDefault.proxyEnabled
    @AppStorage(PrefKey.proxyHost) var proxyHost = PrefDefault.proxyHost
    @AppStorage(PrefKey.proxyPort) var proxyPort = PrefDefault.proxyPort
    @AppStorage(PrefKey.proxyUser) var proxyUser = PrefDefault.proxyUser
    @AppStorage(PrefKey.proxyPasswordInFile) var proxyPasswordInFile = PrefDefault.proxyPasswordInFile
    /// The proxy password lives in the Keychain, not in UserDefaults. The field
    /// is edited locally and written after a short debounce (or on close) so a
    /// keystroke does not hit the keychain.
    @StateObject var proxyPasswordValue = UIState(
        UserDefaults.standard.bool(forKey: PrefKey.proxyEnabled) ? Preferences.proxyPassword : ""
    )
    @StateObject var proxyPasswordDirty = UIState(false)
    @StateObject var proxyPasswordSaveTask = UIState<Task<Void, Never>?>(nil)
    /// The raw appearance string is kept in UserDefaults; we bridge it to the
    /// enum for the picker and back so the `SegmentedPicker` works with the
    /// enum type directly.
    @AppStorage(PrefKey.appearance) var appearanceRaw = PrefDefault.appearance
    var appearance: Binding<AppearanceOption> {
        Binding(
            get: { AppearanceOption(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    /// Interfaces are read once per presentation instead of on every render;
    /// the menu is reopened when the user changes the network.
    @StateObject var interfaces = UIState(LocalNetwork.ipv4Interfaces())

    /// Placeholders for the proxy fields: technical literals, not localized. A
    /// `String` (not a literal) selects the non-localizing TextField overload.
    static let proxyHostPlaceholder = "127.0.0.1"
    static let proxyPortPlaceholder = "1080"
    @StateObject var selectedSection = UIState<SettingsSection>(.folders)
    @StateObject var sectionQuery = UIState("")

    let onClose: () -> Void
    let onOpenDiagnostics: () -> Void

    init(
        engine: TorrentEngine,
        initialSection: SettingsSection = .folders,
        initialQuery: String = "",
        onClose: @escaping () -> Void,
        onOpenDiagnostics: @escaping () -> Void
    ) {
        _engine = ObservedObject(wrappedValue: engine)
        _selectedSection = StateObject(wrappedValue: UIState(initialSection))
        _sectionQuery = StateObject(wrappedValue: UIState(initialQuery))
        self.onClose = onClose
        self.onOpenDiagnostics = onOpenDiagnostics
    }

}
