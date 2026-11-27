import SwiftUI

package struct ProxyPasswordSaveTracker: Equatable {
    package private(set) var editGeneration = 0
    package private(set) var flushedGeneration = 0

    package init() {}

    package var hasUnflushedEdits: Bool {
        editGeneration > flushedGeneration
    }

    @discardableResult
    package mutating func recordEdit() -> Int {
        editGeneration &+= 1
        return editGeneration
    }

    package mutating func completeDebounceSave(generation: Int, succeeded: Bool) {
        guard succeeded, generation > flushedGeneration else { return }
        flushedGeneration = generation
    }

    @discardableResult
    package mutating func consumePendingFlush() -> Int? {
        guard hasUnflushedEdits else { return nil }
        flushedGeneration = editGeneration
        return editGeneration
    }
}

@MainActor
private enum ProxyPasswordSaveRegistry {
    private static var trackers: [ObjectIdentifier: ProxyPasswordSaveTracker] = [:]

    @discardableResult
    static func recordEdit(for dirty: UIState<Bool>) -> Int {
        let key = ObjectIdentifier(dirty)
        var tracker = trackers[key, default: ProxyPasswordSaveTracker()]
        let generation = tracker.recordEdit()
        trackers[key] = tracker
        dirty.value = tracker.hasUnflushedEdits
        return generation
    }

    static func currentEditGeneration(for dirty: UIState<Bool>) -> Int {
        trackers[ObjectIdentifier(dirty)]?.editGeneration ?? (dirty.value ? 1 : 0)
    }

    static func completeDebounceSave(for dirty: UIState<Bool>, generation: Int, succeeded: Bool) {
        let key = ObjectIdentifier(dirty)
        guard var tracker = trackers[key] else {
            if succeeded { dirty.value = false }
            return
        }
        tracker.completeDebounceSave(generation: generation, succeeded: succeeded)
        trackers[key] = tracker
        dirty.value = tracker.hasUnflushedEdits
    }

    @discardableResult
    static func consumePendingFlush(for dirty: UIState<Bool>) -> Int? {
        let key = ObjectIdentifier(dirty)
        if var tracker = trackers[key] {
            let generation = tracker.consumePendingFlush()
            trackers[key] = tracker
            dirty.value = tracker.hasUnflushedEdits
            return generation
        }
        guard dirty.value else { return nil }
        dirty.value = false
        return 1
    }

    static func clear(for dirty: UIState<Bool>) {
        trackers.removeValue(forKey: ObjectIdentifier(dirty))
    }
}

extension SettingsSheet {
    var body: some View {
        let palette = Palette(scheme: scheme)
        return settingsContainer(palette)
            // Bounded to the compact 700×700 card proportions of 1.10.0 while
            // still shrinking vertically on the minimum 900×640 window.
            .frame(
                minWidth: 640,
                idealWidth: 700,
                maxWidth: 700,
                minHeight: 480,
                idealHeight: 700,
                maxHeight: 700
            )
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
                    suppressNextPasswordSave: suppressNextPasswordSave,
                    scheduleSave: scheduleProxyPasswordSave
                ))
    }

    func handleOnAppear() {
        interfaces.value = LocalNetwork.ipv4Interfaces()
        let current = downloadPath
        Task.detached(priority: .utility) {
            let resolved = Preferences.resolvedDownloadPath(current)
            guard resolved != current else { return }
            await MainActor.run {
                let defaults = Preferences.userDefaults
                if defaults.string(forKey: PrefKey.downloadPath) == current {
                    defaults.set(resolved, forKey: PrefKey.downloadPath)
                }
            }
        }
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    func handleOnDisappear() {
        flushProxyPassword()
        ProxyPasswordSaveRegistry.clear(for: proxyPasswordDirty)
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
            // The rail scrolls at large accessibility text sizes while keeping
            // the continuous panel background all the way down to the footer.
            ScrollView(.vertical) {
                settingsSidebar(palette)
            }
            .scrollIndicators(.automatic)
            .frame(minWidth: 168, idealWidth: 172, maxWidth: 188, maxHeight: .infinity)
            .background(palette.panel)

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
        ProxyPasswordSaveRegistry.recordEdit(for: proxyPasswordDirty)
        proxyPasswordSaveTask.value?.cancel()

        let password = proxyPasswordValue
        let dirty = proxyPasswordDirty
        let taskState = proxyPasswordSaveTask
        let inFile = proxyPasswordInFile
        let engine = engine
        taskState.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            taskState.value = nil
            // `SecItemUpdate` can block and may show an access prompt: keep it
            // off the main thread so typing in the field never freezes the UI.
            let value = password.value
            let savedGeneration = ProxyPasswordSaveRegistry.currentEditGeneration(for: dirty)
            let saved = await Task.detached(priority: .userInitiated) {
                Preferences.setProxyPassword(value)
            }.value
            ProxyPasswordSaveRegistry.completeDebounceSave(
                for: dirty,
                generation: savedGeneration,
                succeeded: saved
            )
            engine.applySettingsNow()
            if !saved {
                engine.showToast(
                    inFile
                        ? L("Impossibile salvare la password nel file locale")
                        : L("Impossibile salvare la password nel Portachiavi"),
                    kind: .error
                )
            }
        }
    }

    /// Updates the in-memory cache immediately so `applySettingsNow()` sees the
    /// edited password, then persists it off `@MainActor` so closing the sheet
    /// never blocks the UI thread on Keychain or `fsync` I/O.
    func flushProxyPassword() {
        proxyPasswordSaveTask.value?.cancel()
        proxyPasswordSaveTask.value = nil
        guard ProxyPasswordSaveRegistry.consumePendingFlush(for: proxyPasswordDirty) != nil else { return }
        let value = proxyPasswordValue.value
        let inFile = proxyPasswordInFile
        Preferences.updateCachedProxyPassword(value)
        let engine = engine
        Task { @MainActor in
            let saved = await Task.detached(priority: .userInitiated) {
                Preferences.setProxyPassword(value)
            }.value
            if !saved {
                engine.showToast(
                    inFile
                        ? L("Impossibile salvare la password nel file locale")
                        : L("Impossibile salvare la password nel Portachiavi"),
                    kind: .error
                )
            }
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
                    isInvalid: !Preferences.isValidLimitKB(downloadLimitKB),
                    invalidDetail: L("Inserisci 0 o un valore positivo entro il massimo consentito."),
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "arrow.up",
                    title: "Limite upload",
                    subtitle: "0 significa illimitato",
                    value: $uploadLimitKB,
                    suffix: "KB/s",
                    isInvalid: !Preferences.isValidLimitKB(uploadLimitKB),
                    invalidDetail: L("Inserisci 0 o un valore positivo entro il massimo consentito."),
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "network",
                    title: "Porta di ascolto",
                    subtitle: "Usata per le connessioni in ingresso",
                    value: $listenPort,
                    suffix: "TCP/UDP",
                    isInvalid: !Preferences.isValidPort(listenPort),
                    invalidDetail: L("Inserisci un valore tra 1 e 65535."),
                    palette: palette
                )
                Hairline(palette: palette).padding(.leading, 28)
                numericRow(
                    icon: "square.stack",
                    title: "Torrent attivi",
                    subtitle: "Gli altri restano in coda",
                    value: $maxActiveTorrents,
                    suffix: L("0 = tutti"),
                    isInvalid: !Preferences.isValidActiveLimit(maxActiveTorrents),
                    invalidDetail: L("Inserisci 0 (illimitato) o un valore tra 1 e 1000."),
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
                                if ProxyPasswordSaveRegistry.consumePendingFlush(for: proxyPasswordDirty) != nil {
                                    proxyPasswordSaveTask.value?.cancel()
                                    proxyPasswordSaveTask.value = nil
                                    Preferences.updateCachedProxyPassword(proxyPasswordValue.value)
                                }
                                proxyPasswordInFile = newValue
                                engine.setProxyPasswordStorage(inFile: newValue)
                            }
                        ),
                        palette: palette
                    )
                }
            }

            if proxyEnabled {
                if let issue = SettingsFieldValidation.proxyIssueMessage(
                    host: proxyHost,
                    port: proxyPort,
                    proxyEnabled: proxyEnabled
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.captionTinyText)
                        Text(issue)
                            .font(Typography.captionTinyNarrowText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(palette.coralText)
                    .padding(.horizontal, 4)
                }

                Text(
                    L(
                        "Tutte le connessioni verso tracker e peer passano dal proxy SOCKS5. DHT, UPnP e NAT-PMP vengono disabilitati per prevenire leak dell'IP locale."
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
                    isInvalid: !Preferences.isValidSeedRatio(seedRatioLimit),
                    invalidDetail: L("Inserisci 0 (illimitato) o un valore positivo fino a 100."),
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
                Hairline(palette: palette)
                densityPicker(palette)
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

    /// Vertical section rail. Every section is always one click away and only
    /// the selected pane is rendered.
    func settingsSidebar(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                let selected = selectedSection.value == item
                let hasIssue = SettingsFieldValidation.hasSectionIssue(
                    item,
                    downloadLimitKB: downloadLimitKB,
                    uploadLimitKB: uploadLimitKB,
                    listenPort: listenPort,
                    maxActiveTorrents: maxActiveTorrents,
                    seedRatioLimit: seedRatioLimit,
                    proxyEnabled: proxyEnabled,
                    proxyHost: proxyHost,
                    proxyPort: proxyPort
                )
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
                        if hasIssue {
                            Circle()
                                .fill(Theme.coral)
                                .frame(width: 6, height: 6)
                        }
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func destinationRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(Typography.bodyLargeMediumText)
                .foregroundStyle(palette.mintText)
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
