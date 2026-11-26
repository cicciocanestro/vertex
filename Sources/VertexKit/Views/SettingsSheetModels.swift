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

/// Sections of the settings sheet.
package enum SettingsSection: String, CaseIterable, Identifiable {
    case folders
    case performance
    case network
    case proxy
    case behavior
    case appearance
    case info

    package var id: String { rawValue }

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
    @ObservedObject var suppressNextPasswordSave: UIState<Bool>
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
                    let cached = Preferences.proxyPassword
                    if !cached.isEmpty {
                        suppressNextPasswordSave.value = true
                        proxyPasswordValue.value = cached
                    }
                }
                engine.applySettingsNow()
            }
            .onChange(of: proxyHost) { engine.applySettingsSoon() }
            .onChange(of: proxyPort) { engine.applySettingsSoon() }
            .onChange(of: proxyUser) { engine.applySettingsSoon() }
            .onChange(of: proxyPasswordValue.value) {
                if suppressNextPasswordSave.value {
                    suppressNextPasswordSave.value = false
                    return
                }
                scheduleSave()
            }
            .onChange(of: appearanceRaw) { AppAppearance.apply() }
    }
}

package enum SettingsFieldValidation {
    package static func isProxyHostValid(_ raw: String, proxyEnabled: Bool) -> Bool {
        guard proxyEnabled else { return true }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package static func isProxyPortValid(_ port: Int, proxyEnabled: Bool) -> Bool {
        guard proxyEnabled else { return true }
        return Preferences.isValidPort(port)
    }

    package static func proxyIssueMessage(
        host: String,
        port: Int,
        proxyEnabled: Bool
    ) -> String? {
        guard proxyEnabled else { return nil }
        if !isProxyHostValid(host, proxyEnabled: true) {
            return L("Host proxy non valido")
        }
        if !isProxyPortValid(port, proxyEnabled: true) {
            return "\(L("Porta proxy non valida")) — \(L("Inserisci un valore tra 1 e 65535."))"
        }
        return nil
    }

    package static func hasSectionIssue(
        _ section: SettingsSection,
        downloadLimitKB: Int,
        uploadLimitKB: Int,
        listenPort: Int,
        maxActiveTorrents: Int,
        seedRatioLimit: Double,
        proxyEnabled: Bool,
        proxyHost: String,
        proxyPort: Int
    ) -> Bool {
        switch section {
        case .performance:
            return !Preferences.isValidLimitKB(downloadLimitKB)
                || !Preferences.isValidLimitKB(uploadLimitKB)
                || !Preferences.isValidPort(listenPort)
                || !Preferences.isValidActiveLimit(maxActiveTorrents)
        case .proxy:
            return !isProxyHostValid(proxyHost, proxyEnabled: proxyEnabled)
                || !isProxyPortValid(proxyPort, proxyEnabled: proxyEnabled)
        case .behavior:
            return !Preferences.isValidSeedRatio(seedRatioLimit)
        case .folders, .network, .appearance, .info:
            return false
        }
    }
}
