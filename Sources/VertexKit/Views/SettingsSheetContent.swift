import SwiftUI

extension SettingsSheet {
    var body: some View {
        let palette = Palette(scheme: scheme)
        return settingsContainer(palette)
            // Minimum sizes let the sheet grow with Dynamic Type instead of
            // clipping the sidebar and the footer at large text sizes.
            .frame(minWidth: 640, idealWidth: 700, minHeight: 440, idealHeight: 540)
            .modifier(
                SettingsSheetEventHandlers(
                    onAppearAction: handleOnAppear,
                    onDisappearAction: handleOnDisappear
                )
            )
            .modifier(
                SettingsSheetChangeHandlers(
                    engine: engine,
                    proxyPasswordValue: proxyPasswordValue,
                    scheduleSave: scheduleProxyPasswordSave
                ))
    }

    func handleOnAppear() {
        interfaces.value = LocalNetwork.ipv4Interfaces()
        let resolved = Preferences.resolvedDownloadPath(downloadPath)
        if resolved != downloadPath {
            downloadPath = resolved
        }
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    func handleOnDisappear() {
        flushProxyPassword()
        engine.applySettingsNow()
    }

    func settingsContainer(_ palette: Palette) -> some View {
        ZStack {
            AmbientBackground(ignoresSafeArea: false)

            VStack(spacing: 0) {
                modalHeader
                settingsBody(palette)
                modalFooter(palette)
            }
        }
    }

    var modalHeader: some View {
        ModalHeader(
            icon: "gearshape.fill",
            title: "Impostazioni",
            subtitle: "Preferenze dell'app e della rete",
            versionSuffix: "  ·  v\(AppInfo.version)",
            iconSize: 36,
            onClose: onClose
        )
    }

    func settingsBody(_ palette: Palette) -> some View {
        HStack(spacing: 0) {
            // The rail scrolls: at accessibility text sizes seven rows no longer
            // fit the sheet height and used to run under the footer.
            ScrollView(.vertical) {
                settingsSidebar(palette)
            }
            .scrollIndicators(.automatic)
            .frame(minWidth: 168, idealWidth: 176, maxWidth: 210)

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

    func modalFooter(_ palette: Palette) -> some View {
        ModalFooterBar(palette: palette) {
            Text(
                engine.isRestartingSession
                    ? L("Riavvio del motore BitTorrent…")
                    : L("Le modifiche di rete vengono applicate automaticamente.")
            )
            .font(Typography.microText)
            .foregroundStyle(palette.tertiary)
        } trailing: {
            Button(L("Fine")) {
                onClose()
            }
            .buttonStyle(PrimaryButtonStyle())
            // Not the default action: Return in a numeric field used to close
            // the sheet mid-edit. Esc closes instead (when no field is editing).
            .keyboardShortcut(.cancelAction)
        }
    }

    /// Coalesces keychain writes while the user types.
    func scheduleProxyPasswordSave() {
        proxyPasswordDirty.value = true
        proxyPasswordSaveTask.value?.cancel()

        let password = proxyPasswordValue
        let dirty = proxyPasswordDirty
        let taskState = proxyPasswordSaveTask
        let engine = engine
        taskState.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            taskState.value = nil
            // `SecItemUpdate` can block and may show an access prompt: keep it
            // off the main thread so typing in the field never freezes the UI.
            let value = password.value
            let saved = await Task.detached(priority: .userInitiated) {
                Preferences.setProxyPassword(value)
            }.value
            if saved { dirty.value = false }
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
    func flushProxyPassword() {
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
    func sectionContent(_ palette: Palette) -> some View {
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
                    suffix: L("0 = tutti"),
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
                Text(
                    L(
                        "Con un indirizzo associato Vertex rifiuta il traffico sulle altre interfacce. Se l'indirizzo sparisce, per esempio perché il tunnel è spento, la porta non viene aperta."
                    )
                )
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
                    Hairline(palette: palette).padding(.leading, 28)
                    toggleRow(
                        icon: "doc.badge.key",
                        title: "Memorizza la password in un file locale",
                        subtitle: "Evita i prompt del Portachiavi; permessi 0600, non cifrata",
                        isOn: Binding(
                            get: { proxyPasswordInFile },
                            set: { newValue in
                                proxyPasswordInFile = newValue
                                engine.setProxyPasswordStorage(inFile: newValue)
                            }
                        ),
                        palette: palette
                    )
                }
            }

            if proxyEnabled {
                Text(
                    L(
                        "Tutte le connessioni verso tracker e peer passano dal proxy SOCKS5. UPnP e NAT-PMP vengono disabilitati per prevenire leak dell'IP locale."
                    )
                )
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
                Hairline(palette: palette).padding(.leading, 28)
                toggleRow(
                    icon: "bell.badge",
                    title: "Notifiche di completamento",
                    subtitle: SystemNotifications.isBundleSignedWithIdentity
                        ? "Mostra una notifica di macOS al termine di un download"
                        : "Richiede un bundle firmato con Developer ID",
                    isOn: $notificationsEnabled,
                    palette: palette
                )
                .disabled(!SystemNotifications.isBundleSignedWithIdentity)
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

    func section<Content: View>(
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
    func settingsSidebar(_ palette: Palette) -> some View {
        let matches = SettingsSearch.matchingSections(
            SettingsSection.allCases,
            query: sectionQuery.value
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.smallText)
                    .foregroundStyle(palette.tertiary)
                TextField(L("Cerca"), text: $sectionQuery.value)
                    .textFieldStyle(.plain)
                    .font(Typography.smallText)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.input)
            )
            .padding(.bottom, 6)

            if matches.isEmpty {
                Text(L("Nessuna sezione"))
                    .font(Typography.captionSmallText)
                    .foregroundStyle(palette.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            } else {
                ForEach(matches) { item in
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
                                .fill(
                                    selected
                                        ? Theme.mint.opacity(scheme == .dark ? 0.16 : 0.2)
                                        : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L(item.titleKey)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: sectionQuery.value) { _, query in
            let updated = SettingsSearch.matchingSections(
                SettingsSection.allCases,
                query: query
            )
            if !updated.contains(selectedSection.value), let first = updated.first {
                selectedSection.value = first
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel)
    }

    func destinationRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(Typography.bodyLargeMediumText)
                .foregroundStyle(Theme.mint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Cartella di download"))
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

            Button(L("Scegli…")) {
                chooseFolder()
            }
            .buttonStyle(SmallButtonStyle())
        }
        .padding(.vertical, 9)
    }

}
