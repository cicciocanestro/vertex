import AppKit
import SwiftUI

private enum AppearanceOption: String, CaseIterable, Identifiable {
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

/// Sections of the settings sheet. The order is the same as the scroll content
/// and drives the section index shown at the top, so a section that is below
/// the fold (for example the SOCKS5 proxy) is always discoverable.
private enum SettingsSection: String, CaseIterable, Identifiable {
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

struct SettingsSheet: View {
    @ObservedObject var engine: TorrentEngine

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(PrefKey.downloadPath) private var downloadPath = PrefDefault.downloadPath
    @AppStorage(PrefKey.downloadLimitKB) private var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) private var uploadLimitKB = PrefDefault.uploadLimitKB
    @AppStorage(PrefKey.listenPort) private var listenPort = PrefDefault.listenPort
    @AppStorage(PrefKey.maxActiveTorrents) private var maxActiveTorrents = PrefDefault.maxActiveTorrents
    @AppStorage(PrefKey.bindAddress) private var bindAddress = PrefDefault.bindAddress
    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.pexEnabled) private var pexEnabled = PrefDefault.pexEnabled
    @AppStorage(PrefKey.lsdEnabled) private var lsdEnabled = PrefDefault.lsdEnabled
    @AppStorage(PrefKey.upnpEnabled) private var upnpEnabled = PrefDefault.upnpEnabled
    @AppStorage(PrefKey.startPaused) private var startPaused = PrefDefault.startPaused
    @AppStorage(PrefKey.sequentialDefault) private var sequentialDefault = PrefDefault.sequentialDefault
    @AppStorage(PrefKey.seedRatioLimit) private var seedRatioLimit = PrefDefault.seedRatioLimit
    @AppStorage(PrefKey.proxyEnabled) private var proxyEnabled = PrefDefault.proxyEnabled
    @AppStorage(PrefKey.proxyHost) private var proxyHost = PrefDefault.proxyHost
    @AppStorage(PrefKey.proxyPort) private var proxyPort = PrefDefault.proxyPort
    @AppStorage(PrefKey.proxyUser) private var proxyUser = PrefDefault.proxyUser
    /// The proxy password lives in the Keychain, not in UserDefaults. The field
    /// is edited locally and written after a short debounce (or on close) so a
    /// keystroke does not hit the keychain.
    @StateObject private var proxyPasswordValue = UIState(
        UserDefaults.standard.bool(forKey: PrefKey.proxyEnabled) ? Preferences.proxyPassword : ""
    )
    @StateObject private var proxyPasswordDirty = UIState(false)
    @StateObject private var proxyPasswordSaveTask = UIState<Task<Void, Never>?>(nil)
    /// The raw appearance string is kept in UserDefaults; we bridge it to the
    /// enum for the picker and back so the `SegmentedPicker` works with the
    /// enum type directly.
    @AppStorage(PrefKey.appearance) private var appearanceRaw = PrefDefault.appearance
    private var appearance: Binding<AppearanceOption> {
        Binding(
            get: { AppearanceOption(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    /// Interfaces are read once per presentation instead of on every render;
    /// the menu is reopened when the user changes the network.
    @StateObject private var interfaces = UIState(LocalNetwork.ipv4Interfaces())

    /// Placeholders for the proxy fields: technical literals, not localized. A
    /// `String` (not a literal) selects the non-localizing TextField overload.
    private static let proxyHostPlaceholder = "127.0.0.1"
    private static let proxyPortPlaceholder = "1080"
    @StateObject private var selectedSection = UIState<SettingsSection>(.folders)

    let onClose: () -> Void
    let onOpenDiagnostics: () -> Void

    init(
        engine: TorrentEngine,
        onClose: @escaping () -> Void,
        onOpenDiagnostics: @escaping () -> Void
    ) {
        _engine = ObservedObject(wrappedValue: engine)
        self.onClose = onClose
        self.onOpenDiagnostics = onOpenDiagnostics
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        settingsContainer(palette)
            .frame(width: 700, height: 540)
            .onAppear {
                interfaces.value = LocalNetwork.ipv4Interfaces()
                let resolved = Preferences.resolvedDownloadPath(downloadPath)
                if resolved != downloadPath {
                    downloadPath = resolved
                }
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
            .onChange(of: downloadLimitKB) { engine.applySettingsSoon() }
            .onChange(of: uploadLimitKB) { engine.applySettingsSoon() }
            .onChange(of: listenPort) { engine.applySettingsSoon() }
            .onChange(of: maxActiveTorrents) { engine.applySettingsSoon() }
            .onChange(of: bindAddress) { engine.applySettingsNow() }
            .onChange(of: dhtEnabled) { engine.applySettingsSoon() }
            .onChange(of: pexEnabled) { engine.applySettingsSoon() }
            .onChange(of: lsdEnabled) { engine.applySettingsSoon() }
            .onChange(of: upnpEnabled) { engine.applySettingsSoon() }
            .onChange(of: seedRatioLimit) { engine.applySettingsSoon() }
            .onChange(of: proxyEnabled) { _, enabled in
                if enabled, proxyPasswordValue.value.isEmpty {
                    proxyPasswordValue.value = Preferences.proxyPassword
                }
                engine.applySettingsNow()
            }
            .onChange(of: proxyHost) { engine.applySettingsSoon() }
            .onChange(of: proxyPort) { engine.applySettingsSoon() }
            .onChange(of: proxyUser) { engine.applySettingsSoon() }
            .onChange(of: proxyPasswordValue.value) { scheduleProxyPasswordSave() }
            .onChange(of: appearanceRaw) { AppAppearance.apply() }
            .onDisappear {
                flushProxyPassword()
                engine.applySettingsNow()
            }
    }

    private func settingsContainer(_ palette: Palette) -> some View {
        ZStack {
            AmbientBackground(ignoresSafeArea: false)

            VStack(spacing: 0) {
                modalHeader
                settingsBody(palette)
                modalFooter(palette)
            }
        }
    }

    private var modalHeader: some View {
        ModalHeader(
            icon: "gearshape.fill",
            title: "Impostazioni",
            subtitle: L("Preferenze dell'app e della rete") + "  ·  v\(AppInfo.version)",
            iconSize: 36,
            onClose: onClose
        )
    }

    private func settingsBody(_ palette: Palette) -> some View {
        HStack(spacing: 0) {
            settingsSidebar(palette)
                .frame(minWidth: 168, idealWidth: 176, maxWidth: 210)
                .fixedSize(horizontal: true, vertical: false)

            Hairline(palette: palette, axis: .vertical)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionContent(palette)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func modalFooter(_ palette: Palette) -> some View {
        ModalFooterBar(palette: palette) {
            Text(engine.isRestartingSession
                ? L("Riavvio del motore BitTorrent…")
                : L("Le modifiche di rete vengono applicate automaticamente."))
                .font(Typography.microText)
                .foregroundStyle(palette.tertiary)
        } trailing: {
            Button("Fine") {
                onClose()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Coalesces keychain writes while the user types.
    private func scheduleProxyPasswordSave() {
        proxyPasswordDirty.value = true
        proxyPasswordSaveTask.value?.cancel()

        let password = proxyPasswordValue
        let dirty = proxyPasswordDirty
        let taskState = proxyPasswordSaveTask
        let engine = engine
        taskState.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let saved = Preferences.setProxyPassword(password.value)
            if saved { dirty.value = false }
            taskState.value = nil
            engine.applySettingsNow()
            if !saved {
                engine.showToast(
                    L("Impossibile salvare la password nel Portachiavi"),
                    kind: .error
                )
            }
        }
    }

    /// Writes the pending password before the sheet closes. The dirty flag
    /// avoids touching the keychain when the password was never edited (for
    /// example in the off-screen rendering tests).
    private func flushProxyPassword() {
        proxyPasswordSaveTask.value?.cancel()
        proxyPasswordSaveTask.value = nil
        guard proxyPasswordDirty.value else { return }
        if Preferences.setProxyPassword(proxyPasswordValue.value) {
            proxyPasswordDirty.value = false
        } else {
            engine.showToast(
                L("Impossibile salvare la password nel Portachiavi"),
                kind: .error
            )
        }
    }

    @ViewBuilder
    private func sectionContent(_ palette: Palette) -> some View {
        switch selectedSection.value {
        case .folders:
            section(.folders, palette) {
                destinationRow(palette)
            }
        case .performance:
            section(.performance, palette) {
                numericRow(
                    icon: "arrow.down",
                    title: "Limite download",
                    subtitle: "0 significa illimitato",
                    value: $downloadLimitKB,
                    suffix: "KB/s",
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "arrow.up",
                    title: "Limite upload",
                    subtitle: "0 significa illimitato",
                    value: $uploadLimitKB,
                    suffix: "KB/s",
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "network",
                    title: "Porta di ascolto",
                    subtitle: "Usata per le connessioni in ingresso",
                    value: $listenPort,
                    suffix: "TCP/UDP",
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "square.stack",
                    title: "Torrent attivi",
                    subtitle: "Gli altri restano in coda",
                    value: $maxActiveTorrents,
                    suffix: "0 = tutti",
                    palette: palette
                )
            }
        case .network:
            section(.network, palette) {
                bindingRow(palette)
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "globe",
                    title: "DHT",
                    subtitle: "Trova peer senza tracker centralizzati",
                    isOn: $dhtEnabled,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "person.2",
                    title: "Peer Exchange (PEX)",
                    subtitle: "Scambia peer con i client connessi",
                    isOn: $pexEnabled,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Local Service Discovery (LSD)",
                    subtitle: "Scopre peer sulla rete locale",
                    isOn: $lsdEnabled,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "wifi.router",
                    title: "UPnP / NAT-PMP",
                    subtitle: "Apri automaticamente la porta sul router",
                    isOn: $upnpEnabled,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                diagnosticsRow(palette)
            }
            .disabled(engine.isRestartingSession)

            if !bindAddress.isEmpty {
                Text(L("Con un indirizzo associato Vertex rifiuta il traffico sulle altre interfacce. Se l'indirizzo sparisce, per esempio perché il tunnel è spento, la porta non viene aperta."))
                    .font(Typography.captionTinyNarrowText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        case .proxy:
            section(.proxy, palette) {
                toggleRow(
                    icon: "shield.lefthalf.filled",
                    title: "Usa proxy SOCKS5",
                    subtitle: "Instrada tracker e peer attraverso un proxy anonimo",
                    isOn: $proxyEnabled,
                    palette: palette
                )
                if proxyEnabled {
                    Hairline(palette: palette).padding(.leading, 28)
                    proxyHostRow(palette)
                    Hairline(palette: palette).padding(.leading, 28)
                    proxyAuthRow(palette)
                }
            }

            if proxyEnabled {
                Text(L("Tutte le connessioni verso tracker e peer passano dal proxy SOCKS5. UPnP e NAT-PMP vengono disabilitati per prevenire leak dell'IP locale."))
                    .font(Typography.captionTinyNarrowText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        case .behavior:
            section(.behavior, palette) {
                toggleRow(
                    icon: "pause.circle",
                    title: "Avvia i nuovi torrent in pausa",
                    subtitle: "Potrai riprenderli quando vuoi",
                    isOn: $startPaused,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "arrow.down.to.line",
                    title: "Download sequenziale",
                    subtitle: "Scarica i file in ordine, utile per lo streaming",
                    isOn: $sequentialDefault,
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                decimalRow(
                    icon: "arrow.left.arrow.right",
                    title: "Ferma seed al rapporto",
                    subtitle: "Mette in pausa quando il rapporto raggiunge il limite",
                    value: $seedRatioLimit,
                    suffix: L("0 = mai"),
                    palette: palette
                )
            }
        case .appearance:
            section(.appearance, palette) {
                appearancePicker(palette)
                    .padding(.vertical, 9)
            }
        case .info:
            section(.info, palette) {
                versionRow(palette)
            }
        }
    }

    private func section<Content: View>(
        _ item: SettingsSection,
        _ palette: Palette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(item.titleKey))
                .font(Typography.sectionTitleText)
                .foregroundStyle(palette.text)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .vertexCard(palette, radius: 12)
        }
    }

    /// Vertical section rail. It replaces the horizontal index: every section
    /// is always one click away and only the selected pane is rendered.
    private func settingsSidebar(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                let selected = selectedSection.value == item
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                        selectedSection.value = item
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(Typography.smallSemiboldText)
                            .frame(width: 16)
                        Text(L(item.titleKey))
                            .font(Typography.sidebarItemText(selected: selected))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? palette.text : palette.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minHeight: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected
                                  ? Theme.mint.opacity(scheme == .dark ? 0.16 : 0.2)
                                  : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L(item.titleKey)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel)
    }

    private func destinationRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(Typography.bodyLargeMediumText)
                .foregroundStyle(Theme.mint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cartella di download")
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(downloadPath)
                    .font(Typography.captionSmallText)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(downloadPath)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button("Scegli…") {
                chooseFolder()
            }
            .buttonStyle(SmallButtonStyle())
        }
        .padding(.vertical, 9)
    }

    private func numericRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<Int>,
        suffix: String,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.smallRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 62, maxWidth: 84)

                Text(suffix)
                    .font(Typography.microMediumText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .padding(.vertical, 8)
    }

    private func decimalRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<Double>,
        suffix: String,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.smallRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 52, maxWidth: 72)

                Text(suffix)
                    .font(Typography.microMediumText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .padding(.vertical, 8)
    }

    private func bindingRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Interfaccia di rete")
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Il traffico esce solo da questo indirizzo"))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Menu {
                Button {
                    bindAddress = ""
                } label: {
                    if bindAddress.isEmpty {
                        Label(L("Automatica"), systemImage: "checkmark")
                    } else {
                        Text(L("Automatica"))
                    }
                }

                if !interfaces.value.isEmpty {
                    Divider()
                    ForEach(interfaces.value) { interface in
                        Button {
                            bindAddress = interface.address
                        } label: {
                            if bindAddress == interface.address {
                                Label(interface.label, systemImage: "checkmark")
                            } else {
                                Text(interface.label)
                            }
                        }
                    }
                }
            } label: {
                bindingLabel(palette)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func bindingLabel(_ palette: Palette) -> some View {
        HStack(spacing: 5) {
            Text(bindingText)
                .font(Typography.captionMediumRoundedText)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(Typography.badgeText)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
    }

    private var bindingText: String {
        guard !bindAddress.isEmpty else { return L("Automatica") }
        if let match = interfaces.value.first(where: { $0.address == bindAddress }) {
            return match.label
        }
        return LF("%@ (non disponibile)", bindAddress)
    }

    private func diagnosticsRow(_ palette: Palette) -> some View {
        Button {
            onOpenDiagnostics()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Diagnostica rete")
                        .font(Typography.bodyLargeMediumText)
                        .foregroundStyle(palette.text)
                    Text("Porta effettiva, mapping e test esterno")
                        .font(Typography.microText)
                        .foregroundStyle(palette.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(Typography.captionTinySemiboldText)
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func proxyHostRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Server e porta"))
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Host proxy SOCKS5 e porta"))
                    .font(Typography.captionTinyText)
                    .foregroundStyle(palette.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            TextField(Self.proxyHostPlaceholder, text: $proxyHost)
                .textFieldStyle(.plain)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 110, maxWidth: 150, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            Text(verbatim: ":")
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.tertiary)

            TextField(Self.proxyPortPlaceholder, value: $proxyPort, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 55, maxWidth: 72, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )
        }
        .padding(.vertical, 7)
    }

    private func proxyAuthRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Autenticazione"))
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Facoltativa (RFC 1929)"))
                    .font(Typography.captionTinyText)
                    .foregroundStyle(palette.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            TextField(L("Utente"), text: $proxyUser)
                .textFieldStyle(.plain)
                .font(Typography.captionSmallText)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 85, maxWidth: 115, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            SecureField(L("Password"), text: $proxyPasswordValue.value)
                .textFieldStyle(.plain)
                .font(Typography.captionSmallText)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 85, maxWidth: 115, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )
        }
        .padding(.vertical, 7)
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.teal)
        }
        .padding(.vertical, 8)
    }

    private func appearancePicker(_ palette: Palette) -> some View {
        SegmentedPicker(
            selection: appearance,
            palette: palette,
            height: 25,
            corner: 7,
            horizontalPadding: 3,
            verticalPadding: 3,
            font: Typography.captionMediumText
        ) { (option: AppearanceOption, _) in
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(Typography.captionTinySemiboldText)
                Text(option.label)
            }
        }
    }

    private func versionRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Vertex")
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(LF("Versione %@ (build %@)", AppInfo.version, AppInfo.build))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = OpenPanelFactory.directory(startingAt: downloadPath)
        if panel.runModal() == .OK, let url = panel.url {
            downloadPath = url.path
            engine.applySettingsNow()
        }
    }
}
