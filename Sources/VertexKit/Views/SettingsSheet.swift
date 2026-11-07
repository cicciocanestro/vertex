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

struct SettingsSheet: View {
    @ObservedObject var engine: TorrentEngine

    @Environment(\.colorScheme) private var scheme

    @AppStorage(PrefKey.downloadPath) private var downloadPath = PrefDefault.downloadPath
    @AppStorage(PrefKey.downloadLimitKB) private var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) private var uploadLimitKB = PrefDefault.uploadLimitKB
    @AppStorage(PrefKey.listenPort) private var listenPort = PrefDefault.listenPort
    @AppStorage(PrefKey.bindAddress) private var bindAddress = PrefDefault.bindAddress
    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.pexEnabled) private var pexEnabled = PrefDefault.pexEnabled
    @AppStorage(PrefKey.lsdEnabled) private var lsdEnabled = PrefDefault.lsdEnabled
    @AppStorage(PrefKey.upnpEnabled) private var upnpEnabled = PrefDefault.upnpEnabled
    @AppStorage(PrefKey.startPaused) private var startPaused = PrefDefault.startPaused
    @AppStorage(PrefKey.sequentialDefault) private var sequentialDefault = PrefDefault.sequentialDefault
    @AppStorage(PrefKey.proxyEnabled) private var proxyEnabled = PrefDefault.proxyEnabled
    @AppStorage(PrefKey.proxyHost) private var proxyHost = PrefDefault.proxyHost
    @AppStorage(PrefKey.proxyPort) private var proxyPort = PrefDefault.proxyPort
    @AppStorage(PrefKey.proxyUser) private var proxyUser = PrefDefault.proxyUser
    @AppStorage(PrefKey.proxyPassword) private var proxyPassword = PrefDefault.proxyPassword
    /// The raw appearance string is kept in UserDefaults; we bridge it to the
    /// enum for the picker and back so the `SegmentedPicker` works with the
    /// enum type directly.
    @AppStorage(PrefKey.appearance) private var appearanceRaw = PrefDefault.appearance
    private var appearance: Binding<AppearanceOption> {
        Binding(
            get: { AppearanceOption(rawValue: appearanceRaw) ?? .dark },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    /// Interfaces are read once per presentation instead of on every render;
    /// the menu is reopened when the user changes the network.
    @StateObject private var interfaces = UIState(LocalNetwork.ipv4Interfaces())

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
        ZStack {
            AmbientBackground(ignoresSafeArea: false)

            VStack(spacing: 0) {
                ModalHeader(
                    icon: "gearshape.fill",
                    title: "Impostazioni",
                    subtitle: L("Preferenze dell'app e della rete") + "  ·  v\(AppInfo.version)",
                    iconSize: 36,
                    onClose: onClose
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("Cartelle", palette) {
                            destinationRow(palette)
                        }

                        section("Prestazioni", palette) {
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
                        }

                        section("Rete", palette) {
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
                                .font(Typography.captionTinyNarrow)
                                .foregroundStyle(palette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }

                        section("Proxy SOCKS5", palette) {
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
                                .font(Typography.captionTinyNarrow)
                                .foregroundStyle(palette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }

                        section("Comportamento", palette) {
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
                        }

                        section("Aspetto", palette) {
                            appearancePicker(palette)
                                .padding(.vertical, 9)
                        }

                        section("Informazioni", palette) {
                            versionRow(palette)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)

                ModalFooterBar(palette: palette) {
                    Text(engine.isRestartingSession
                        ? L("Riavvio del motore BitTorrent…")
                        : L("Le modifiche di rete vengono applicate automaticamente."))
                        .font(Typography.micro)
                        .foregroundStyle(palette.tertiary)
                } trailing: {
                    Button("Fine") {
                        onClose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560, height: 700)
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
        .onChange(of: bindAddress) { engine.applySettingsNow() }
        .onChange(of: dhtEnabled) { engine.applySettingsSoon() }
        .onChange(of: pexEnabled) { engine.applySettingsSoon() }
        .onChange(of: lsdEnabled) { engine.applySettingsSoon() }
        .onChange(of: upnpEnabled) { engine.applySettingsSoon() }
        .onChange(of: appearanceRaw) { AppAppearance.apply() }
        .onDisappear { engine.applySettingsNow() }
    }

    private func section<Content: View>(
        _ title: String,
        _ palette: Palette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: title)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .vertexCard(palette, radius: 12)
        }
    }

    private func destinationRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(Typography.bodyLargeMedium)
                .foregroundStyle(Theme.mint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cartella di download")
                    .font(Typography.bodyLargeMedium)
                    .foregroundStyle(palette.text)
                Text(downloadPath)
                    .font(Typography.captionSmall)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(downloadPath)
            }

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
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMedium)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.micro)
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .frame(width: 62)

                Text(suffix)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
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
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Interfaccia di rete")
                    .font(Typography.bodyLargeMedium)
                    .foregroundStyle(palette.text)
                Text(L("Il traffico esce solo da questo indirizzo"))
                    .font(Typography.micro)
                    .foregroundStyle(palette.tertiary)
            }

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
                .font(Typography.captionMediumRounded)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 170, alignment: .trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(Typography.badge)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
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
                    .font(Typography.bodyMedium)
                    .foregroundStyle(palette.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Diagnostica rete")
                        .font(Typography.bodyLargeMedium)
                        .foregroundStyle(palette.text)
                    Text("Porta effettiva, mapping e test esterno")
                        .font(Typography.micro)
                        .foregroundStyle(palette.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(Typography.captionTinySemibold)
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
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Server e porta"))
                    .font(Typography.bodyMedium)
                    .foregroundStyle(palette.text)
                Text(L("Host proxy SOCKS5 e porta"))
                    .font(Typography.captionTiny)
                    .foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 8)

            TextField("127.0.0.1", text: $proxyHost)
                .textFieldStyle(.plain)
                .font(Typography.captionMono)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .frame(width: 120, height: 26)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            Text(":")
                .font(Typography.captionMono)
                .foregroundStyle(palette.tertiary)

            TextField("1080", value: $proxyPort, formatter: NumberFormatter())
                .textFieldStyle(.plain)
                .font(Typography.captionMono)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .frame(width: 55, height: 26)
                .padding(.horizontal, 7)
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
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Autenticazione"))
                    .font(Typography.bodyMedium)
                    .foregroundStyle(palette.text)
                Text(L("Facoltativa (RFC 1929)"))
                    .font(Typography.captionTiny)
                    .foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 8)

            TextField(L("Utente"), text: $proxyUser)
                .textFieldStyle(.plain)
                .font(Typography.captionSmall)
                .foregroundStyle(palette.text)
                .frame(width: 85, height: 26)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            SecureField(L("Password"), text: $proxyPassword)
                .textFieldStyle(.plain)
                .font(Typography.captionSmall)
                .foregroundStyle(palette.text)
                .frame(width: 85, height: 26)
                .padding(.horizontal, 7)
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
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMedium)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.micro)
                    .foregroundStyle(palette.tertiary)
            }

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
            font: .system(size: 10, weight: .medium)
        ) { (option: AppearanceOption, _) in
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(Typography.captionTinySemibold)
                Text(option.label)
            }
        }
    }

    private func versionRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(Typography.bodyMedium)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Vertex")
                    .font(Typography.bodyLargeMedium)
                    .foregroundStyle(palette.text)
                Text(LF("Versione %@ (build %@)", AppInfo.version, AppInfo.build))
                    .font(Typography.micro)
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
