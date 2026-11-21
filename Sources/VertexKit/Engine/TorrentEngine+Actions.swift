import AppKit
import CTorrent
import Foundation

/// Hands a string out of the session actor: written there, read on the main
/// actor after the operation completed.
private final class StringBox: @unchecked Sendable {
    var value = ""
}

extension TorrentEngine {
    /// Adds a magnet link.
    ///
    /// The validation errors (not a magnet, unusable destination, engine not
    /// available) are returned synchronously so the add sheet can show them
    /// inline; `nil` means the request was accepted and queued. The outcome of
    /// the bridge call itself — for example a duplicate torrent — arrives on the
    /// main actor through `completion`.
    ///
    /// The destination validation runs off the main thread and the bridge call
    /// goes through the session actor, so neither blocks the UI.
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

        guard !isShuttingDown, hasSession else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return message
        }
        let generation = sessionGeneration

        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.preparedDestination(destination)
            }.value
            guard let self else { return }
            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                // Always answer: a dropped completion leaves the caller waiting
                // forever (the add sheet never closes).
                completion?(L("Motore non disponibile."))
                return
            }
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                self.showToast(message, kind: .error)
                completion?(message)
                return
            }

            let outcome = await self.sessionController.perform { session in
                trimmed.withCString { uriPointer in
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
            }

            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                completion?(L("Motore non disponibile."))
                return
            }
            if outcome.code != 0 {
                let message = self.localizedError(
                    outcome.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("Errore sconosciuto.")
                        : outcome.error
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

        guard !isShuttingDown, hasSession else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return message
        }
        let generation = sessionGeneration

        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.preparedDestination(destination)
            }.value
            guard let self else { return }
            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                // Always answer: a dropped completion leaves the caller waiting
                // forever (the add sheet never closes).
                completion?(L("Motore non disponibile."))
                return
            }
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                self.showToast(message, kind: .error)
                completion?(message)
                return
            }

            let outcome = await self.sessionController.perform { session in
                filePath.withCString { filePointer in
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
            }

            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                completion?(L("Motore non disponibile."))
                return
            }
            if outcome.code != 0 {
                let message = self.localizedError(
                    outcome.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("Errore sconosciuto.")
                        : outcome.error
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

    /// Reads the magnet URI off the main thread. The old synchronous variant
    /// blocked the main actor behind the session work (up to seconds with a
    /// large library), which is exactly what the actor exists to avoid.
    func magnetURI(for torrent: Torrent, completion: @escaping @MainActor (String) -> Void) {
        let box = StringBox()
        let queued = enqueueSessionOperation { session in
            let pointer = torrent.id.withCString { vt_magnet_uri(session, $0) }
            guard let pointer else { return -1 }
            defer { vt_free_string(pointer) }
            box.value = String(cString: pointer)
            return 0
        } onSuccess: {
            completion(box.value)
        } onFailure: { _ in
            completion("")
        }
        if !queued {
            completion("")
        }
    }

    func copyMagnet(for torrent: Torrent) {
        let id = torrent.id
        guard !isShuttingDown, hasSession else { return }
        let generation = sessionGeneration
        let box = StringBox()

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.sessionController.perform { session in
                let pointer = id.withCString { vt_magnet_uri(session, $0) }
                guard let pointer else { return -1 }
                defer { vt_free_string(pointer) }
                box.value = String(cString: pointer)
                return 0
            }
            guard outcome.code == 0,
                  !self.isShuttingDown,
                  self.sessionGeneration == generation,
                  !box.value.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(box.value, forType: .string)
            self.showToast(L("Link magnet copiato"), kind: .info)
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
    /// Directory validation runs on a background thread and the bridge call goes
    /// through the session actor, so the UI thread never touches the filesystem.
    package func moveStorage(
        _ torrent: Torrent,
        to destination: String,
        completion: (@MainActor (String?) -> Void)? = nil
    ) {
        guard !isShuttingDown, hasSession else {
            let message = L("Motore non disponibile.")
            completion?(message)
            return
        }
        let torrentID = torrent.id
        let currentSavePath = torrent.savePath
        let generation = sessionGeneration

        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.preparedDestination(destination)
            }.value
            guard let self else { return }
            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                completion?(L("Motore non disponibile."))
                return
            }
            guard let path = prepared.path else {
                let message = prepared.error ?? L("Cartella di destinazione non valida.")
                self.showToast(message, kind: .error)
                completion?(message)
                return
            }

            if URL(fileURLWithPath: path).standardizedFileURL.path
                == URL(fileURLWithPath: currentSavePath).standardizedFileURL.path {
                completion?(nil)
                return
            }

            let outcome = await self.sessionController.perform { session in
                torrentID.withCString { idPointer in
                    path.withCString { pathPointer in
                        vt_move_storage(session, idPointer, pathPointer)
                    }
                }
            }

            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                completion?(L("Motore non disponibile."))
                return
            }
            if outcome.code != 0 {
                let message = self.localizedError(
                    outcome.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("Errore sconosciuto.")
                        : outcome.error
                )
                self.showToast(message, kind: .error)
                completion?(message)
                return
            }

            // `move_storage` is asynchronous: the bridge returns as soon as
            // libtorrent accepts the request. The real completion is the save
            // path changing in a later snapshot (see `apply`).
            self.showToast(
                L("Spostamento in corso…"),
                kind: .info,
                detail: path
            )
            self.poll()
            completion?(nil)
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

}
