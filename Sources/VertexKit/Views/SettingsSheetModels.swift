import SwiftUI

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("Sistema")
        case .dark: return L("Scuro")
        case .light: return L("Chiaro")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// Filters the settings rail by the localized section title. Case and
/// diacritics are ignored so "rete" matches "Rete" on any keyboard.
enum SettingsSearch {
    static func matchingSections(
        _ sections: [SettingsSection],
        query: String
    ) -> [SettingsSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }
        return sections.filter { section in
            L(section.titleKey).range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}

/// Sections of the settings sheet. The order is the same as the scroll content
/// and drives the section index shown at the top, so a section that is below
/// the fold (for example the SOCKS5 proxy) is always discoverable.
enum SettingsSection: String, CaseIterable, Identifiable {
    case folders
    case performance
    case network
    case proxy
    case behavior
    case appearance
    case info

    var id: String { rawValue }

    /// Localization key, shared with the section header.
    var titleKey: String {
        switch self {
        case .folders: return "Cartelle"
        case .performance: return "Prestazioni"
        case .network: return "Rete"
        case .proxy: return "Proxy SOCKS5"
        case .behavior: return "Comportamento"
        case .appearance: return "Aspetto"
        case .info: return "Informazioni"
        }
    }

    var icon: String {
        switch self {
        case .folders: return "folder"
        case .performance: return "speedometer"
        case .network: return "network"
        case .proxy: return "shield.lefthalf.filled"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "circle.lefthalf.filled"
        case .info: return "info.circle"
        }
    }
}

struct SettingsSheetEventHandlers: ViewModifier {
    let onAppearAction: () -> Void
    let onDisappearAction: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearAction)
            .onDisappear(perform: onDisappearAction)
    }
}

struct SettingsSheetChangeHandlers: ViewModifier {
    let engine: TorrentEngine
    @ObservedObject var proxyPasswordValue: UIState<String>
    let scheduleSave: () -> Void

    @AppStorage(PrefKey.downloadLimitKB) var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) var uploadLimitKB = PrefDefault.uploadLimitKB
    @AppStorage(PrefKey.listenPort) var listenPort = PrefDefault.listenPort
    @AppStorage(PrefKey.maxActiveTorrents) var maxActiveTorrents = PrefDefault.maxActiveTorrents
    @AppStorage(PrefKey.bindAddress) var bindAddress = PrefDefault.bindAddress
    @AppStorage(PrefKey.dhtEnabled) var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.pexEnabled) var pexEnabled = PrefDefault.pexEnabled
    @AppStorage(PrefKey.lsdEnabled) var lsdEnabled = PrefDefault.lsdEnabled
    @AppStorage(PrefKey.upnpEnabled) var upnpEnabled = PrefDefault.upnpEnabled
    @AppStorage(PrefKey.seedRatioLimit) var seedRatioLimit = PrefDefault.seedRatioLimit
    @AppStorage(PrefKey.notificationsEnabled) var notificationsEnabled = PrefDefault.notificationsEnabled
    @AppStorage(PrefKey.proxyEnabled) var proxyEnabled = PrefDefault.proxyEnabled
    @AppStorage(PrefKey.proxyHost) var proxyHost = PrefDefault.proxyHost
    @AppStorage(PrefKey.proxyPort) var proxyPort = PrefDefault.proxyPort
    @AppStorage(PrefKey.proxyUser) var proxyUser = PrefDefault.proxyUser
    @AppStorage(PrefKey.proxyPasswordInFile) var proxyPasswordInFile = PrefDefault.proxyPasswordInFile
    @AppStorage(PrefKey.appearance) var appearanceRaw = PrefDefault.appearance

    func body(content: Content) -> some View {
        let v1 =
            content
            .onChange(of: downloadLimitKB) { engine.applySettingsSoon() }
            .onChange(of: uploadLimitKB) { engine.applySettingsSoon() }
            .onChange(of: listenPort) { engine.applySettingsSoon() }
            .onChange(of: maxActiveTorrents) { engine.applySettingsSoon() }
            .onChange(of: bindAddress) { engine.applySettingsNow() }
            .onChange(of: dhtEnabled) { engine.applySettingsSoon() }

        let v2 =
            v1
            .onChange(of: pexEnabled) { engine.applySettingsSoon() }
            .onChange(of: lsdEnabled) { engine.applySettingsSoon() }
            .onChange(of: upnpEnabled) { engine.applySettingsSoon() }
            .onChange(of: seedRatioLimit) { engine.applySettingsSoon() }
            .onChange(of: notificationsEnabled) { _, enabled in
                if enabled {
                    SystemNotifications.requestAuthorizationIfNeeded()
                }
            }

        return
            v2
            .onChange(of: proxyEnabled) { _, enabled in
                if enabled, proxyPasswordValue.value.isEmpty {
                    proxyPasswordValue.value = Preferences.proxyPassword
                }
                engine.applySettingsNow()
            }
            .onChange(of: proxyHost) { engine.applySettingsSoon() }
            .onChange(of: proxyPort) { engine.applySettingsSoon() }
            .onChange(of: proxyUser) { engine.applySettingsSoon() }
            .onChange(of: proxyPasswordValue.value) { scheduleSave() }
            .onChange(of: appearanceRaw) { AppAppearance.apply() }
    }
}
