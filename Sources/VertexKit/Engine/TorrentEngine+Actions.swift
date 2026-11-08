import AppKit
import CTorrent
import Foundation

extension TorrentEngine {
    package func addMagnet(
        _ uri: String,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard session != nil else { return L("Motore non disponibile.") }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TorrentInput.isMagnet(trimmed) else {
            let message = L("Il link magnet non è valido.")
            showToast(message, kind: .error)
            return message
        }

        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? L("Cartella di destinazione non valida.")
            showToast(message, kind: .error)
            return message
        }

        let outcome = withSession { session -> (Int32, String) in
            let code = trimmed.withCString { uriPointer in
                path.withCString { pathPointer in
                    vt_add_magnet(
                        session,
                        uriPointer,
                        pathPointer,
                        startPaused ? 1 : 0,
                        sequential ? 1 : 0
                    )
                }
            }
            return (code, code != 0 ? Self.readLastError(session) : "")
        }
        guard let (result, rawError) = outcome else { return L("Motore non disponibile.") }

        if result != 0 {
            let message = localizedError(
                rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L("Errore sconosciuto.")
                    : rawError
            )
            showToast(message, kind: .error)
            return message
        }

        showToast(L("Torrent aggiunto"), kind: .success)
        poll()
        return nil
    }

    package func addTorrentFile(
        _ url: URL,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard session != nil else { return L("Motore non disponibile.") }
        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? L("Cartella di destinazione non valida.")
            showToast(message, kind: .error)
            return message
        }

        let outcome = withSession { session -> (Int32, String) in
            let code = url.path.withCString { filePointer in
                path.withCString { pathPointer in
                    vt_add_torrent_file(
                        session,
                        filePointer,
                        pathPointer,
                        startPaused ? 1 : 0,
                        sequential ? 1 : 0
                    )
                }
            }
            return (code, code != 0 ? Self.readLastError(session) : "")
        }
        guard let (result, rawError) = outcome else { return L("Motore non disponibile.") }

        if result != 0 {
            let message = localizedError(
                rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L("Errore sconosciuto.")
                    : rawError
            )
            showToast(message, kind: .error)
            return message
        }

        showToast(L("Torrent aggiunto"), kind: .success, detail: url.deletingPathExtension().lastPathComponent)
        poll()
        return nil
    }

    func togglePause(_ torrent: Torrent) {
        control(torrent.paused ? "resume" : "pause", id: torrent.id)
    }

    func pause(_ torrent: Torrent) {
        control("pause", id: torrent.id)
    }

    func resume(_ torrent: Torrent) {
        control("resume", id: torrent.id)
    }

    func reannounce(_ torrent: Torrent) {
        control("reannounce", id: torrent.id) { [weak self] in
            self?.showToast(L("Annuncio inviato ai tracker"), kind: .info)
        }
    }

    func toggleSequential(_ torrent: Torrent) {
        control(torrent.sequential ? "sequential_off" : "sequential_on", id: torrent.id)
    }

    func remove(_ torrent: Torrent, deleteFiles: Bool) {
        let torrentID = torrent.id
        let torrentName = torrent.name
        control(deleteFiles ? "remove_files" : "remove", id: torrentID) { [weak self] in
            guard let self else { return }
            if self.selectedID == torrentID {
                self.select(nil)
            }
            self.showToast(
                L(deleteFiles ? "Torrent e file rimossi" : "Torrent rimosso"),
                kind: .info,
                detail: torrentName
            )
        }
    }

    func select(_ id: String?) {
        selectedID = id
        detailTick = 0
        detail = nil
        if let id {
            loadDetail(id)
        }
    }

    func setFilePriority(_ file: TorrentFile, wanted: Bool, torrentID: String) {
        let index = Int32(file.index)
        let priority: Int32 = wanted ? 4 : 0
        enqueueSessionOperation { session in
            torrentID.withCString { idPointer in
                vt_set_file_priority(session, idPointer, index, priority)
            }
        } onSuccess: { [weak self] in
            self?.forceDetailRefresh = true
            self?.poll()
        }
    }

    func setAllFilePriorities(wanted: Bool, torrentID: String) {
        let priority: Int32 = wanted ? 4 : 0
        enqueueSessionOperation { session in
            torrentID.withCString { idPointer in
                vt_set_all_file_priorities(session, idPointer, priority)
            }
        } onSuccess: { [weak self] in
            self?.forceDetailRefresh = true
            self?.poll()
        }
    }

    func magnetURI(for torrent: Torrent) -> String {
        withSession { session in
            let pointer = torrent.id.withCString { vt_magnet_uri(session, $0) }
            guard let pointer else { return "" }
            defer { vt_free_string(pointer) }
            return String(cString: pointer)
        } ?? ""
    }

    func copyMagnet(for torrent: Torrent) {
        let id = torrent.id
        guard !isShuttingDown, let session else { return }
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)
        sessionQueue.async { [weak self] in
            let uri: String = {
                guard let s = pointer.value else { return "" }
                guard let cStr = id.withCString({ vt_magnet_uri(s, $0) }) else { return "" }
                defer { vt_free_string(cStr) }
                return String(cString: cStr)
            }()
            DispatchQueue.main.async {
                guard let self, !self.isShuttingDown, self.sessionGeneration == generation, !uri.isEmpty else {
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(uri, forType: .string)
                self.showToast(L("Link magnet copiato"), kind: .info)
            }
        }
    }

    func reveal(_ torrent: Torrent) {
        let direct = URL(fileURLWithPath: torrent.savePath).appendingPathComponent(torrent.name)
        if FileManager.default.fileExists(atPath: direct.path) {
            NSWorkspace.shared.activateFileViewerSelecting([direct])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: torrent.savePath))
        }
    }

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
        guard !isShuttingDown, !isRestartingSession, session != nil else { return }

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
        let proxyChanged: Bool
        if let previous {
            downloadPathChanged = previous.downloadPath != configuration.downloadPath
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
            proxyChanged = true
        }

        guard downloadPathChanged || networkChanged || proxyChanged else {
            lastAppliedConfiguration = configuration
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

    func showToast(_ text: String, kind: ToastMessage.Kind = .info, detail: String? = nil) {
        let message = ToastMessage(kind: kind, text: text, detail: detail)
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    func control(
        _ action: String,
        id: String,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        enqueueSessionOperation { session in
            id.withCString { idPointer in
                action.withCString { actionPointer in
                    vt_control(session, idPointer, actionPointer)
                }
            }
        } onSuccess: { [weak self] in
            onSuccess?()
            self?.poll()
        }
    }

    func preparedDestination(_ requested: String?) -> (path: String?, error: String?) {
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
        if lower.contains("already exists") || lower.contains("duplicate") { return L("Questo torrent è già presente.") }
        if lower.contains("no such file") || lower.contains("cannot stat") { return L("File non trovato.") }
        if lower.contains("permission") { return L("Permesso negato.") }
        if lower.contains("invalid")
            || lower.contains("parse")
            || lower.contains("exceeds maximum size")
            || lower.contains("not a regular file") {
            return L("Link o file non valido.")
        }
        switch value {
        case "Torrent non trovato": return L("Torrent non trovato")
        case "Metadati non disponibili": return L("In attesa dei metadati…")
        case "Comando non supportato": return L("Comando non supportato")
        case "Parametri non validi": return L("Link o file non valido.")
        case "La destinazione non è una cartella.": return L("La destinazione non è una cartella.")
        case "La cartella di destinazione non è scrivibile.": return L("La cartella di destinazione non è scrivibile.")
        case "Errore sconosciuto": return L("Errore sconosciuto")
        default: return value
        }
    }
}
