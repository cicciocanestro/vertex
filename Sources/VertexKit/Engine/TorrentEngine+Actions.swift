import AppKit
import CTorrent
import Foundation

extension TorrentEngine {
    /// Adds a magnet link.
    ///
    /// The validation errors (not a magnet, unusable destination, engine not
    /// available) are returned synchronously so the add sheet can show them
    /// inline; `nil` means the request was accepted and queued. The outcome of
    /// the bridge call itself — for example a duplicate torrent — arrives on the
    /// main actor through `completion`.
    ///
    /// The bridge call runs on `sessionQueue`: parsing the URI and touching the
    /// filesystem must never block the UI.
    @discardableResult
    package func addMagnet(
        _ uri: String,
        destination: String?,
        startPaused: Bool,
        sequential: Bool,
        completion: (@MainActor (String?) -> Void)? = nil
    ) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TorrentInput.isMagnet(trimmed) else {
            let message = L("Il link magnet non è valido.")
            showToast(message, kind: .error)
            completion?(message)
            return message
        }

        guard !isShuttingDown, let session else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return message
        }
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)

        sessionQueue.async { [weak self] in
            guard let s = pointer.value else {
                DispatchQueue.main.async { completion?(L("Motore non disponibile.")) }
                return
            }
            let prepared = Self.preparedDestination(destination)
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                DispatchQueue.main.async {
                    guard let self, !self.isShuttingDown, self.sessionGeneration == generation else {
                        completion?(L("Motore non disponibile."))
                        return
                    }
                    self.showToast(message, kind: .error)
                    completion?(message)
                }
                return
            }

            let code = trimmed.withCString { uriPointer in
                path.withCString { pathPointer in
                    vt_add_magnet(
                        s,
                        uriPointer,
                        pathPointer,
                        startPaused ? 1 : 0,
                        sequential ? 1 : 0
                    )
                }
            }

            let rawError = code != 0 ? Self.readLastError(s) : ""
            DispatchQueue.main.async {
                guard let self, !self.isShuttingDown, self.sessionGeneration == generation else {
                    // Always answer: a dropped completion leaves the caller
                    // waiting forever (the add sheet never closes).
                    completion?(L("Motore non disponibile."))
                    return
                }

                if code != 0 {
                    let message = self.localizedError(
                        rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? L("Errore sconosciuto.")
                            : rawError
                    )
                    self.showToast(message, kind: .error)
                    completion?(message)
                    return
                }

                self.showToast(
                    L("Torrent aggiunto"),
                    kind: .success,
                    actionTitle: L("Apri cartella"),
                    action: .openFolder(path: path)
                )
                self.poll()
                completion?(nil)
            }
        }

        return nil
    }

    /// Adds a `.torrent` file. Same contract as `addMagnet`: validation errors
    /// are returned synchronously, the bridge outcome arrives through
    /// `completion`, and the file is parsed off the main thread.
    @discardableResult
    package func addTorrentFile(
        _ url: URL,
        destination: String?,
        startPaused: Bool,
        sequential: Bool,
        completion: (@MainActor (String?) -> Void)? = nil
    ) -> String? {
        let filePath = url.path
        let detail = url.deletingPathExtension().lastPathComponent

        guard !isShuttingDown, let session else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return message
        }
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)

        sessionQueue.async { [weak self] in
            guard let s = pointer.value else {
                DispatchQueue.main.async { completion?(L("Motore non disponibile.")) }
                return
            }
            let prepared = Self.preparedDestination(destination)
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                DispatchQueue.main.async {
                    guard let self, !self.isShuttingDown, self.sessionGeneration == generation else {
                        completion?(L("Motore non disponibile."))
                        return
                    }
                    self.showToast(message, kind: .error)
                    completion?(message)
                }
                return
            }

            let code = filePath.withCString { filePointer in
                path.withCString { pathPointer in
                    vt_add_torrent_file(
                        s,
                        filePointer,
                        pathPointer,
                        startPaused ? 1 : 0,
                        sequential ? 1 : 0
                    )
                }
            }

            let rawError = code != 0 ? Self.readLastError(s) : ""
            DispatchQueue.main.async {
                guard let self, !self.isShuttingDown, self.sessionGeneration == generation else {
                    // Always answer: a dropped completion leaves the caller
                    // waiting forever (the add sheet never closes).
                    completion?(L("Motore non disponibile."))
                    return
                }

                if code != 0 {
                    let message = self.localizedError(
                        rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? L("Errore sconosciuto.")
                            : rawError
                    )
                    self.showToast(message, kind: .error)
                    completion?(message)
                    return
                }

                self.showToast(
                    L("Torrent aggiunto"),
                    kind: .success,
                    detail: detail,
                    actionTitle: L("Apri cartella"),
                    action: .openFolder(path: path)
                )
                self.poll()
                completion?(nil)
            }
        }

        return nil
    }

    func togglePause(_ torrent: Torrent) {
        guard !torrent.isQueued else {
            // A queued torrent is paused by the queue manager: "pause" here means
            // leaving the queue, not stopping a running transfer.
            control("dequeue", id: torrent.id)
            return
        }
        control(torrent.paused ? "resume" : "pause", id: torrent.id)
    }

    func pause(_ torrent: Torrent) {
        control("pause", id: torrent.id)
    }

    func resume(_ torrent: Torrent) {
        control("resume", id: torrent.id)
    }

    func forceStart(_ torrent: Torrent) {
        control("force_start", id: torrent.id)
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
        remove([torrent], deleteFiles: deleteFiles)
    }

    func remove(_ list: [Torrent], deleteFiles: Bool) {
        guard !list.isEmpty else { return }
        if list.count == 1, let single = list.first {
            let torrentID = single.id
            let torrentName = single.name
            control(deleteFiles ? "remove_files" : "remove", id: torrentID) { [weak self] in
                guard let self else { return }
                if self.selectedIDs.contains(torrentID) {
                    var remaining = self.selectedIDs
                    remaining.remove(torrentID)
                    self.setSelection(TorrentListSelection.State(selectedIDs: remaining, anchorID: remaining.first))
                }
                self.showToast(
                    L(deleteFiles ? "Torrent e file rimossi" : "Torrent rimosso"),
                    kind: .info,
                    detail: torrentName
                )
            }
            return
        }

        let ids = list.map(\.id)
        let action = deleteFiles ? "remove_files" : "remove"
        let queued = enqueueSessionOperation(
            errorTitle: L("Alcuni torrent non sono stati rimossi")
        ) { session in
            var failures: Int32 = 0
            for id in ids {
                let code = id.withCString { idPointer in
                    action.withCString { actionPointer in
                        vt_control(session, idPointer, actionPointer)
                    }
                }
                if code != 0 { failures += 1 }
            }
            return failures == 0 ? 0 : -1
        } onSuccess: { [weak self] in
            guard let self else { return }
            let remaining = self.selectedIDs.subtracting(ids)
            self.setSelection(TorrentListSelection.State(selectedIDs: remaining, anchorID: remaining.first))
            self.showToast(
                deleteFiles
                    ? LF("%ld torrent e file rimossi", ids.count)
                    : LF("%ld torrent rimossi", ids.count),
                kind: .info
            )
            self.poll()
        }
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    func pause(_ list: [Torrent]) {
        guard !list.isEmpty else { return }
        if list.count == 1, let single = list.first {
            if single.isQueued {
                control("dequeue", id: single.id)
            } else {
                pause(single)
            }
            return
        }
        let commands = list.map { ($0.id, $0.isQueued ? "dequeue" : "pause") }
        let queued = enqueueSessionOperation(
            errorTitle: L("Alcuni torrent non sono stati messi in pausa")
        ) { session in
            var failures: Int32 = 0
            for (id, action) in commands {
                let code = id.withCString { idPtr in
                    action.withCString { actPtr in vt_control(session, idPtr, actPtr) }
                }
                if code != 0 { failures += 1 }
            }
            return failures == 0 ? 0 : -1
        } onSuccess: { [weak self] in
            self?.poll()
        }
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    func resume(_ list: [Torrent]) {
        guard !list.isEmpty else { return }
        if list.count == 1, let single = list.first {
            resume(single)
            return
        }
        let ids = list.map(\.id)
        let queued = enqueueSessionOperation(
            errorTitle: L("Alcuni torrent non sono stati ripresi")
        ) { session in
            var failures: Int32 = 0
            for id in ids {
                let code = id.withCString { idPtr in
                    "resume".withCString { actPtr in vt_control(session, idPtr, actPtr) }
                }
                if code != 0 { failures += 1 }
            }
            return failures == 0 ? 0 : -1
        } onSuccess: { [weak self] in
            self?.poll()
        }
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    func togglePause(_ list: [Torrent]) {
        guard !list.isEmpty else { return }
        if list.count == 1, let single = list.first {
            togglePause(single)
            return
        }
        let anyActiveOrQueued = list.contains { !$0.paused || $0.isQueued }
        if anyActiveOrQueued {
            pause(list)
        } else {
            resume(list)
        }
    }

    func reannounce(_ list: [Torrent]) {
        guard !list.isEmpty else { return }
        if list.count == 1, let single = list.first {
            reannounce(single)
            return
        }
        let ids = list.map(\.id)
        let queued = enqueueSessionOperation(
            errorTitle: L("Annuncio non inviato")
        ) { session in
            var failures: Int32 = 0
            for id in ids {
                let code = id.withCString { idPtr in
                    "reannounce".withCString { actPtr in vt_control(session, idPtr, actPtr) }
                }
                if code != 0 { failures += 1 }
            }
            return failures == 0 ? 0 : -1
        } onSuccess: { [weak self] in
            self?.showToast(L("Annuncio inviato ai tracker"), kind: .info)
            self?.poll()
        }
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    package var selectedTorrents: [Torrent] {
        guard !selectedIDs.isEmpty else { return [] }
        return torrents.filter { selectedIDs.contains($0.id) }
    }

    func select(_ id: String?) {
        if let id {
            setSelection(TorrentListSelection.State(selectedIDs: [id], anchorID: id))
        } else {
            setSelection(TorrentListSelection.State())
        }
    }

    package func setSelection(_ state: TorrentListSelection.State) {
        selectedIDs = state.selectedIDs
        selectionAnchorID = state.anchorID
        let singleID = state.selectedIDs.count == 1 ? state.selectedIDs.first : nil
        if let singleID {
            if selectedID != singleID || detail == nil {
                selectedID = singleID
                detailTick = 0
                detail = nil
                loadDetail(singleID)
            }
        } else {
            selectedID = nil
            detailTick = 0
            detail = nil
        }
    }

    package func selectClick(
        _ id: String,
        visibleIDs: [String],
        command: Bool,
        shift: Bool
    ) {
        let next = TorrentListSelection.handleClick(
            on: id,
            in: visibleIDs,
            current: selectedIDs,
            anchor: selectionAnchorID ?? selectedID,
            command: command,
            shift: shift
        )
        setSelection(next)
    }

    package func selectAll(visibleIDs: [String]) {
        let next = TorrentListSelection.selectAll(
            in: visibleIDs,
            currentAnchor: selectionAnchorID ?? selectedID
        )
        setSelection(next)
    }

    func setFilePriority(_ file: TorrentFile, priority: FilePriority, torrentID: String) {
        let index = Int32(file.index)
        let value = Int32(priority.rawValue)
        enqueueSessionOperation { session in
            torrentID.withCString { idPointer in
                vt_set_file_priority(session, idPointer, index, value)
            }
        } onSuccess: { [weak self] in
            self?.forceDetailRefresh = true
            self?.poll()
        }
    }

    /// Backwards-compatible binary helper used by tests and older call sites.
    func setFilePriority(_ file: TorrentFile, wanted: Bool, torrentID: String) {
        setFilePriority(file, priority: wanted ? .normal : .skip, torrentID: torrentID)
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

    /// Replaces the tracker list of a torrent. The inspector always sends the
    /// whole list, so adding and removing a tracker are the same operation and
    /// the bridge never has to merge anything.
    func setTrackers(_ urls: [String], torrentID: String) {
        let list = urls.joined(separator: "\n")
        enqueueSessionOperation(
            operation: { session in
                torrentID.withCString { idPointer in
                    list.withCString { listPointer in
                        vt_set_trackers(session, idPointer, listPointer)
                    }
                }
            },
            onSuccess: { [weak self] in
                self?.forceDetailRefresh = true
                self?.poll()
            }
        )
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

    /// Moves the downloaded files of an already-added torrent to `destination`.
    /// Directory validation and the bridge call run on `sessionQueue`, so the UI
    /// thread never touches the filesystem.
    package func moveStorage(
        _ torrent: Torrent,
        to destination: String,
        completion: (@MainActor (String?) -> Void)? = nil
    ) {
        guard !isShuttingDown, let session else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return
        }
        let torrentID = torrent.id
        let currentSavePath = torrent.savePath
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)

        sessionQueue.async { [weak self] in
            guard let s = pointer.value else { return }
            let prepared = Self.preparedDestination(destination)
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                DispatchQueue.main.async {
                    guard let self, !self.isShuttingDown, self.sessionGeneration == generation else { return }
                    self.showToast(message, kind: .error)
                    completion?(message)
                }
                return
            }

            if URL(fileURLWithPath: path).standardizedFileURL.path
                == URL(fileURLWithPath: currentSavePath).standardizedFileURL.path {
                DispatchQueue.main.async {
                    completion?(nil)
                }
                return
            }

            let code = torrentID.withCString { idPointer in
                path.withCString { pathPointer in
                    vt_move_storage(s, idPointer, pathPointer)
                }
            }

            let rawError = code != 0 ? Self.readLastError(s) : ""
            DispatchQueue.main.async {
                guard let self, !self.isShuttingDown, self.sessionGeneration == generation else {
                    // Always answer: a dropped completion leaves the caller
                    // waiting forever (the add sheet never closes).
                    completion?(L("Motore non disponibile."))
                    return
                }

                if code != 0 {
                    let message = self.localizedError(
                        rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? L("Errore sconosciuto.")
                            : rawError
                    )
                    self.showToast(message, kind: .error)
                    completion?(message)
                    return
                }

                // `move_storage` is asynchronous: the bridge returns as soon as
                // libtorrent accepts the request. The real completion is the
                // save path changing in a later snapshot (see `apply`).
                self.showToast(
                    L("Spostamento in corso…"),
                    kind: .info,
                    detail: path
                )
                self.poll()
                completion?(nil)
            }
        }
    }

    func chooseAndMoveStorage(for torrent: Torrent) {
        let panel = OpenPanelFactory.directory(
            startingAt: torrent.savePath,
            prompt: L("Sposta")
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        moveStorage(torrent, to: url.path)
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
        DispatchQueue.global(qos: .userInitiated).async {
            Preferences.migrateProxyPasswordStorage(toFile: inFile, value: value)
            DispatchQueue.main.async { [weak self] in
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
