import AppKit
import CTorrent
import Foundation

extension TorrentEngine {
    /// Coalesces the edits of a settings field: applying on every keystroke
    /// rebinds the listening port (and resets the port mapping) for partial
    /// values like `6` or `68`. Closing the sheet still flushes immediately.
    func applySettingsSoon() {
        settingsApplyTask?.cancel()
        settingsApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.settingsApplyTask = nil
            self.applySettings()
        }
    }

    /// Cancels a pending debounced update and applies the current preferences
    /// immediately.
    func applySettingsNow() {
        settingsApplyTask?.cancel()
        settingsApplyTask = nil
        applySettings()
    }

    func applySettings() {
        guard !isShuttingDown, !isRestartingSession, hasSession else { return }

        let configuration: SessionConfiguration
        if let configurationOverride {
            configuration = configurationOverride
        } else {
            let defaults = UserDefaults.standard
            let rawPort = defaults.integer(forKey: PrefKey.listenPort)
            guard Preferences.isValidPort(rawPort) else {
                showToast(
                    L("Porta non valida"),
                    kind: .error,
                    detail: L("Inserisci un valore tra 1 e 65535.")
                )
                return
            }
            guard Preferences.isValidLimitKB(defaults.integer(forKey: PrefKey.downloadLimitKB)),
                  Preferences.isValidLimitKB(defaults.integer(forKey: PrefKey.uploadLimitKB)) else {
                showToast(
                    L("Limite non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 o un valore positivo entro il massimo consentito.")
                )
                return
            }
            guard Preferences.isValidActiveLimit(defaults.integer(forKey: PrefKey.maxActiveTorrents)) else {
                showToast(
                    L("Numero di torrent attivi non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 (illimitato) o un valore tra 1 e 1000.")
                )
                return
            }
            guard Preferences.isValidSeedRatio(defaults.double(forKey: PrefKey.seedRatioLimit)) else {
                showToast(
                    L("Limite rapporto non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 (illimitato) o un valore positivo fino a 100.")
                )
                return
            }
            if defaults.bool(forKey: PrefKey.proxyEnabled) {
                let rawProxyPort = defaults.integer(forKey: PrefKey.proxyPort)
                guard Preferences.isValidPort(rawProxyPort) else {
                    showToast(
                        L("Porta proxy non valida"),
                        kind: .error,
                        detail: L("Inserisci un valore tra 1 e 65535.")
                    )
                    return
                }
            }
            configuration = Self.currentConfiguration()
        }

        if configuration.pex != sessionPexEnabled {
            restartSessionForPeerExchange(configuration: configuration, oldPex: sessionPexEnabled)
            return
        }

        // Apply only the parts that changed since the last successful apply.
        // This keeps a debounced settings edit from touching the filesystem or
        // rebinding the listening port when the value is unchanged.
        let previous = lastAppliedConfiguration
        if configuration == previous { return }

        let downloadPathChanged: Bool
        let networkChanged: Bool
        let queueChanged: Bool
        let proxyChanged: Bool
        if let previous {
            downloadPathChanged = previous.downloadPath != configuration.downloadPath
            queueChanged = previous.maxActive != configuration.maxActive
            networkChanged = previous.port != configuration.port
                || previous.downloadLimit != configuration.downloadLimit
                || previous.uploadLimit != configuration.uploadLimit
                || previous.dht != configuration.dht
                || previous.upnp != configuration.upnp
                || previous.lsd != configuration.lsd
                || previous.bindAddress != configuration.bindAddress
            proxyChanged = previous.proxyEnabled != configuration.proxyEnabled
                || previous.proxyHost != configuration.proxyHost
                || previous.proxyPort != configuration.proxyPort
                || previous.proxyUser != configuration.proxyUser
                || previous.proxyPassword != configuration.proxyPassword
        } else {
            downloadPathChanged = true
            networkChanged = true
            queueChanged = true
            proxyChanged = true
        }

        guard downloadPathChanged || networkChanged || queueChanged || proxyChanged else {
            lastAppliedConfiguration = configuration
            if configuration.seedRatioLimit > 0 {
                poll()
            }
            return
        }

        enqueueSessionOperation(
            errorTitle: L("Impostazioni non applicate"),
            operation: { session in
                if downloadPathChanged {
                    let pathResult = configuration.downloadPath.withCString {
                        vt_set_default_save_path(session, $0)
                    }
                    if pathResult != 0 {
                        return pathResult
                    }
                }
                if queueChanged {
                    let limitResult = vt_set_active_limit(session, configuration.maxActive)
                    if limitResult != 0 {
                        return limitResult
                    }
                }
                if networkChanged {
                    let netResult = configuration.bindAddress.withCString { bindAddress in
                        vt_apply_settings_ex(
                            session,
                            configuration.port,
                            configuration.downloadLimit,
                            configuration.uploadLimit,
                            configuration.dht ? 1 : 0,
                            configuration.upnp ? 1 : 0,
                            configuration.lsd ? 1 : 0,
                            bindAddress
                        )
                    }
                    if netResult != 0 {
                        return netResult
                    }
                }
                if proxyChanged {
                    return configuration.proxyHost.withCString { hostPointer in
                        configuration.proxyUser.withCString { userPointer in
                            configuration.proxyPassword.withCString { passPointer in
                                vt_apply_proxy_settings(
                                    session,
                                    configuration.proxyEnabled ? 1 : 0,
                                    hostPointer,
                                    configuration.proxyPort,
                                    userPointer,
                                    passPointer
                                )
                            }
                        }
                    }
                }
                return 0
            },
            onSuccess: { [weak self] in
                self?.lastAppliedConfiguration = configuration
                self?.poll()
            }
        )
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func showToast(
        _ text: String,
        kind: ToastMessage.Kind = .info,
        detail: String? = nil,
        actionTitle: String? = nil,
        action: ToastMessage.Action? = nil
    ) {
        let message = ToastMessage(
            kind: kind,
            text: text,
            detail: detail,
            actionTitle: actionTitle,
            action: action
        )
        toast = message
        if kind == .error { recordErrorToast(text) }
        // VoiceOver cannot see the toast overlay: post it as an announcement so
        // errors and completions are not silent for screen-reader users.
        if kind != .info { announce(text) }
        toastTask?.cancel()
        // An actionable toast stays a little longer so it can be clicked.
        let delay: UInt64 = action == nil ? 4_000_000_000 : 7_000_000_000
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    /// Moves the SOCKS5 password between the Keychain and the 0600 file after
    /// the user changes the storage preference. The migration touches the
    /// Keychain and the filesystem, so it runs off the main thread.
    func setProxyPasswordStorage(inFile: Bool) {
        let value = Preferences.proxyPassword
        // Same pattern as the session queue: the migration runs off the main
        // thread and hops back through DispatchQueue.main (Swift 6.1 rejects
        // capturing a task-isolated self in `Task.detached` + MainActor.run).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Preferences.migrateProxyPasswordStorage(toFile: inFile, value: value)
            DispatchQueue.main.async {
                self?.applySettingsNow()
            }
        }
    }

    private func announce(_ text: String) {
        guard let app = NSApp, app.isRunning else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func control(
        _ action: String,
        id: String,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        let queued = enqueueSessionOperation { session in
            id.withCString { idPointer in
                action.withCString { actionPointer in
                    vt_control(session, idPointer, actionPointer)
                }
            }
        } onSuccess: { [weak self] in
            onSuccess?()
            self?.poll()
        }
        // The command was refused because there is no session (startup, PEX
        // restart, shutdown): tell the user instead of letting the click vanish.
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    nonisolated static func preparedDestination(_ requested: String?) -> (path: String?, error: String?) {
        let raw = requested ?? UserDefaults.standard.string(forKey: PrefKey.downloadPath)
        let path = Preferences.resolvedDownloadPath(raw)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            return (nil, L("Impossibile creare la cartella di destinazione."))
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (nil, L("La destinazione non è una cartella."))
        }
        guard fileManager.isWritableFile(atPath: path) else {
            return (nil, L("La cartella di destinazione non è scrivibile."))
        }

        return (path, nil)
    }

    func localizedError(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return L("Operazione non riuscita.") }
        let lower = value.lowercased()
        if lower.contains("torrent already exists") || lower.contains("duplicate") {
            return L("Questo torrent è già presente.")
        }
        if lower.contains("file exists") {
            return L("Esiste già un file con lo stesso nome nella cartella di destinazione.")
        }
        if lower.contains("no such file") || lower.contains("cannot stat") { return L("File non trovato.") }
        if lower.contains("permission") || lower.contains("operation not permitted") { return L("Permesso negato.") }
        // The bridge reports a proxy request without a host in Italian: without
        // this branch the English UI would show the raw C++ string.
        if lower.contains("host proxy non valido") { return L("Host proxy non valido") }
        if lower.contains("invalid")
            || lower.contains("parse")
            || lower.contains("missing info-hash")
            || lower.contains("mismatching info-hash")
            || lower.contains("missing or invalid 'info'")
            || lower.contains("missing info-dictionary")
            || lower.contains("not a dictionary")
            || lower.contains("missing name in torrent")
            || lower.contains("no files in torrent")
            || lower.contains("incorrect number of piece hashes")
            || lower.contains("too many pieces in torrent")
            || lower.contains("bencoded")
            || lower.contains("bencoding")
            || lower.contains("unsupported url protocol")
            || lower.contains("unknown meta version")
            || lower.contains("no file tree")
            || lower.contains("meta version 2")
            || lower.contains("file metadata does not match")
            || lower.contains("missing piece layer hashes")
            || lower.contains("no root hash")
            || lower.contains("do not describe the same data")
            || lower.contains("exceeds depth limit")
            || lower.contains("exceeds maximum size")
            || lower.contains("not a regular file") {
            return L("Link o file non valido.")
        }
        switch value {
        case "Torrent non trovato": return L("Torrent non trovato")
        case "Metadati non disponibili": return L("In attesa dei metadati…")
        case "Comando non supportato": return L("Comando non supportato")
        case "Parametri non validi": return L("Parametri non validi.")
        case "La destinazione non è una cartella.": return L("La destinazione non è una cartella.")
        case "La cartella di destinazione non è scrivibile.": return L("La cartella di destinazione non è scrivibile.")
        case "Esiste già un file con lo stesso nome nella cartella di destinazione.":
            return L("Esiste già un file con lo stesso nome nella cartella di destinazione.")
        case "URL del tracker troppo lungo": return L("URL del tracker troppo lungo")
        case "URL del tracker non valido": return L("URL del tracker non valido")
        case "Troppi tracker": return L("Troppi tracker")
        case "Errore sconosciuto": return L("Errore sconosciuto")
        default: return RuntimeErrorLocalizer.torrent(value)
        }
    }
}
