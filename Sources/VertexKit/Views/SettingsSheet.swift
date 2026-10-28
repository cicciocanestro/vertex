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
    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.pexEnabled) private var pexEnabled = PrefDefault.pexEnabled
    @AppStorage(PrefKey.lsdEnabled) private var lsdEnabled = PrefDefault.lsdEnabled
    @AppStorage(PrefKey.upnpEnabled) private var upnpEnabled = PrefDefault.upnpEnabled
    @AppStorage(PrefKey.startPaused) private var startPaused = PrefDefault.startPaused
    @AppStorage(PrefKey.sequentialDefault) private var sequentialDefault = PrefDefault.sequentialDefault
    @AppStorage(PrefKey.appearance) private var appearance = PrefDefault.appearance

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
                        .font(.system(size: 9.5))
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
        .onChange(of: dhtEnabled) { engine.applySettingsSoon() }
        .onChange(of: pexEnabled) { engine.applySettingsSoon() }
        .onChange(of: lsdEnabled) { engine.applySettingsSoon() }
        .onChange(of: upnpEnabled) { engine.applySettingsSoon() }
        .onChange(of: appearance) { AppAppearance.apply() }
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
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.mint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cartella di download")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(downloadPath)
                    .font(.system(size: 9.8))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(.system(size: 9.5))
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

    private func diagnosticsRow(_ palette: Palette) -> some View {
        Button {
            onOpenDiagnostics()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Diagnostica rete")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.text)
                    Text("Porta effettiva, mapping e test esterno")
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(.system(size: 9.5))
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
        HStack(spacing: 3) {
            ForEach(AppearanceOption.allCases) { option in
                Button {
                    appearance = option.rawValue
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(option.label)
                    }
                    .font(.system(size: 10, weight: appearance == option.rawValue ? .semibold : .medium))
                    .foregroundStyle(appearance == option.rawValue ? palette.text : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(appearance == option.rawValue ? palette.cardHover : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func versionRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Vertex")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(LF("Versione %@ (build %@)", AppInfo.version, AppInfo.build))
                    .font(.system(size: 9.5))
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
