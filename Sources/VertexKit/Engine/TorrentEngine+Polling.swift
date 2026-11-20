import AppKit
import CTorrent
import Foundation

extension TorrentEngine {
    /// Data refreshed by the poll. Publishing a single value avoids four
    /// separate `objectWillChange` notifications and intermediate UI states.
    struct PollState: Equatable {
        var torrents: [Torrent] = []
        var stats = SessionStats()
        var downloadHistory: [Double] = []
        var uploadHistory: [Double] = []
        var torrentsByID: [String: Torrent] = [:]

        /// Compares everything but the rate history: the history appends on
        /// every poll, so comparing it would make the guard useless. The
        /// history is only meaningful when the rest of the state moved.
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.torrents == rhs.torrents
                && lhs.stats == rhs.stats
                && lhs.torrentsByID == rhs.torrentsByID
        }
    }

    var currentSeedRatioLimit: Double {
        if let configurationOverride {
            return Preferences.clampedSeedRatio(configurationOverride.seedRatioLimit)
        }
        return Preferences.clampedSeedRatio(UserDefaults.standard.double(forKey: PrefKey.seedRatioLimit))
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.poll()
                let interval = Self.pollInterval(
                    downloadRate: self.stats.downloadRate,
                    uploadRate: self.stats.uploadRate,
                    hasUnfinished: self.torrents.contains { !$0.finished },
                    isAppActive: NSApp?.isActive ?? true
                )
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Adaptive poll cadence: fast while data is moving or a download is
    /// unfinished, slower for an idle library, slowest when the app is in the
    /// background. Kept pure so the policy is testable without a session.
    nonisolated static func pollInterval(
        downloadRate: Int64,
        uploadRate: Int64,
        hasUnfinished: Bool,
        isAppActive: Bool
    ) -> TimeInterval {
        guard isAppActive else { return 2.5 }
        if downloadRate > 0 || uploadRate > 0 || hasUnfinished { return 0.8 }
        return 1.6
    }

    func poll() {
        #if DEBUG
        if DemoData.isEnabled {
            applyDemoSnapshot()
            return
        }
        #endif

        guard !isShuttingDown, !isPollInFlight, hasSession else { return }
        retryProxyPasswordWarmIfNeeded()
        isPollInFlight = true
        let generation = sessionGeneration

        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.sessionController.poll()
            self.finishPoll(snapshot, generation: generation)
        }
    }

    func finishPoll(_ snapshot: VertexSnapshot?, generation: Int) {
        isPollInFlight = false
        guard generation == sessionGeneration, !isShuttingDown else {
            return
        }
        guard let snapshot else { return }

        // Perform an active TCP health-check probe on the configured proxy:
        // - every ~8 seconds (every 10 polls) when healthy, to avoid connection spam on local daemons (Tor/SOCKS5)
        // - or every ~2.4 seconds (every 3 polls) if there is an active error, to quickly detect recovery.
        if snapshot.stats.proxy.enabled && !snapshot.stats.proxy.hostname.isEmpty && snapshot.stats.proxy.port > 0 {
            proxyCheckTick += 1
            let checkInterval = proxyHealthError != nil ? 3 : 10
            if !isProxyProbeInFlight && (proxyCheckTick % checkInterval == 0) {
                isProxyProbeInFlight = true
                let host = snapshot.stats.proxy.hostname
                let port = snapshot.stats.proxy.port
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let isReachable = Self.probeTCPConnection(host: host, port: port, timeoutSeconds: 0.5)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isProxyProbeInFlight = false
                        guard self.sessionGeneration == generation, !self.isShuttingDown else { return }
                        // Ensure the probed target still matches the currently active proxy configuration
                        let currentProxy = self.pollState.stats.proxy
                        guard currentProxy.enabled, currentProxy.hostname == host, currentProxy.port == port else { return }
                        let newError: String? = isReachable ? nil : L("Connessione rifiutata")
                        if self.proxyHealthError != newError {
                            self.proxyHealthError = newError
                            if let newError {
                                self.pollState.stats.proxy.error = newError
                            }
                            if isReachable, self.hasSession {
                                Task {
                                    await self.sessionController.perform { pointer in
                                        vt_clear_proxy_error(pointer)
                                        return 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            proxyHealthError = nil
            proxyCheckTick = 0
            isProxyProbeInFlight = false
        }

        apply(snapshot)
    }

    nonisolated static func probeTCPConnection(host: String, port: Int, timeoutSeconds: Double) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var res: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        guard getaddrinfo(host, portStr, &hints, &res) == 0, let first = res else {
            return false
        }
        defer { freeaddrinfo(res) }

        var connected = false
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let current = ptr {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                // Set non-blocking to honor timeout
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

                let connRes = connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen)
                if connRes == 0 {
                    connected = true
                    close(fd)
                    break
                } else if errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let timeoutMs = Int32(max(1, Int(timeoutSeconds * 1000)))
                    let pollRes = Darwin.poll(&pfd, 1, timeoutMs)
                    if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                        var soError: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 && soError == 0 {
                            connected = true
                        }
                    }
                }
                close(fd)
                if connected {
                    break
                }
            }
            ptr = current.pointee.ai_next
        }
        return connected
    }

    private func appendHistory(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 80 {
            history.removeFirst(history.count - 80)
        }
    }

    func apply(_ snapshot: VertexSnapshot) {
        // Every asynchronous error collected between two polls: the bridge used
        // to keep a single slot, so with several torrents failing in the same
        // window only the last message reached the user.
        let alertMessages = snapshot.alertErrors.isEmpty
            ? (snapshot.alertError.isEmpty ? [] : [snapshot.alertError])
            : snapshot.alertErrors
        for raw in alertMessages {
            let message = localizedError(raw)
            if !hasRecentErrorToast(message) {
                showToast(message, kind: .error)
            }
        }

        // A storage move finishes asynchronously: the save path changes only
        // once the disk thread has moved the files, so a change here is the
        // real completion signal (the bridge returns when the request is
        // accepted, not when the move is done).
        if hasLoadedSnapshot {
            for torrent in snapshot.torrents {
                guard let previous = pollState.torrentsByID[torrent.id],
                      !previous.savePath.isEmpty,
                      !torrent.savePath.isEmpty,
                      previous.savePath != torrent.savePath else { continue }
                // The raw strings differ: normalize before reporting, so a
                // trailing slash is not mistaken for a completed move.
                let oldPath = URL(fileURLWithPath: previous.savePath).standardizedFileURL.path
                let newPath = URL(fileURLWithPath: torrent.savePath).standardizedFileURL.path
                guard oldPath != newPath else { continue }
                showToast(
                    L("File spostati"),
                    kind: .success,
                    detail: torrent.savePath,
                    actionTitle: L("Apri cartella"),
                    action: .openFolder(path: torrent.savePath)
                )
            }
        }

        // Notify only for torrents we have seen actively unfinished (not while verifying),
        // so resumed torrents settling after launch don't trigger a false "completed" toast.
        let finished = Set(snapshot.torrents.filter { $0.finished }.map(\.id))
        // stateCode 1 = checking files, 7 = checking resume data. `phase` can't be used here
        // because it reports .paused before .checking.
        let unfinished = Set(snapshot.torrents.filter {
            !$0.finished
                && $0.stateCode != LibtorrentStateCode.checkingFiles.rawValue
                && $0.stateCode != LibtorrentStateCode.checkingResumeData.rawValue
        }.map(\.id))
        if hasLoadedSnapshot {
            let newlyFinished = finished.intersection(unfinishedIDs)
            if !newlyFinished.isEmpty {
                // A download that completes while the window is in the
                // background is exactly the event the user wants to know about.
                completionAttention()
                let completed = snapshot.torrents.filter { newlyFinished.contains($0.id) }
                completionNotification(completed.map(\.name))
                if completed.count == 1, let torrent = completed.first {
                    let path = URL(fileURLWithPath: torrent.savePath)
                        .appendingPathComponent(torrent.name)
                        .path
                    showToast(
                        L("Download completato"),
                        kind: .success,
                        detail: torrent.name,
                        actionTitle: L("Mostra nel Finder"),
                        action: .reveal(path: path)
                    )
                } else {
                    showToast(LF("%ld download completati", completed.count), kind: .success)
                }
            }
        }
        unfinishedIDs = unfinished
        if !hasLoadedSnapshot { hasLoadedSnapshot = true }

        // Enforce the automatic seed ratio limit (0 = unlimited). Once a finished
        // torrent reaches the configured ratio we pause it once and remember its
        // ID in `ratioLimitSatisfiedIDs`, so if the user manually resumes it later
        // it is not immediately paused again on the next poll.
        let ratioLimit = currentSeedRatioLimit
        if ratioLimit > 0 {
            let presentIDs = Set(snapshot.torrents.map(\.id))
            ratioLimitSatisfiedIDs.formIntersection(presentIDs)
            for torrent in snapshot.torrents {
                if torrent.ratio < ratioLimit {
                    ratioLimitSatisfiedIDs.remove(torrent.id)
                    continue
                }
                guard torrent.finished, !torrent.paused else {
                    if torrent.finished && torrent.paused {
                        ratioLimitSatisfiedIDs.insert(torrent.id)
                    }
                    continue
                }
                guard !ratioLimitSatisfiedIDs.contains(torrent.id) else { continue }
                ratioLimitSatisfiedIDs.insert(torrent.id)
                let name = torrent.name
                control("pause", id: torrent.id) { [weak self] in
                    self?.showToast(
                        L("Seed completato (limite rapporto raggiunto)"),
                        kind: .info,
                        detail: name
                    )
                }
            }
        } else if !ratioLimitSatisfiedIDs.isEmpty {
            ratioLimitSatisfiedIDs.removeAll()
        }

        var next = pollState
        next.torrents = snapshot.torrents
        next.stats = snapshot.stats
        if let proxyHealthError {
            next.stats.proxy.error = proxyHealthError
        } else if !snapshot.stats.proxy.error.isEmpty {
            next.stats.proxy.error = snapshot.stats.proxy.error
        } else {
            next.stats.proxy.error = ""
        }
        next.torrentsByID = Dictionary(
            snapshot.torrents.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        // Idle poll: libtorrent answers every 800 ms, and most of the time
        // nothing changed. Skipping the publish keeps the UI out of re-render
        // loops when the user is not interacting with the app. We keep
        // appending to the rate history while rates are non-zero or while the
        // existing history still has non-zero samples, so the sparkline decays
        // back to zero after a transfer finishes instead of freezing on its
        // last wave.
        let stateChanged = next != pollState
        let historyActive = snapshot.downloadRate > 0
            || snapshot.uploadRate > 0
            || next.downloadHistory.contains(where: { $0 > 0 })
            || next.uploadHistory.contains(where: { $0 > 0 })
        if stateChanged || historyActive {
            appendHistory(Double(snapshot.downloadRate), to: &next.downloadHistory)
            appendHistory(Double(snapshot.uploadRate), to: &next.uploadHistory)
            pollState = next
        }

        if !selectedIDs.isEmpty {
            let validSelected = selectedIDs.intersection(Set(next.torrentsByID.keys))
            if validSelected != selectedIDs {
                let nextAnchor = validSelected.contains(selectionAnchorID ?? "") ? selectionAnchorID : validSelected.first
                setSelection(TorrentListSelection.State(selectedIDs: validSelected, anchorID: nextAnchor))
            }
        }

        if let id = selectedID {
            if next.torrentsByID[id] != nil {
                detailTick += 1
                // Without state changes there is no file progress to refresh:
                // poll trackers at a slower cadence instead of every 2.4 s.
                if forceDetailRefresh || (stateChanged && detailTick % 3 == 0) || detailTick % 15 == 0 {
                    forceDetailRefresh = false
                    loadDetail(id)
                }
            } else {
                select(nil)
            }
        }
    }

    #if DEBUG
    func applyDemoSnapshot() {
        let list = DemoData.torrents()
        let down = list.reduce(Int64(0)) { $0 + $1.downloadRate }
        let up = list.reduce(Int64(0)) { $0 + $1.uploadRate }
        var stats = SessionStats(
            downloadRate: down,
            uploadRate: up,
            active: list.filter { !$0.paused }.count,
            paused: list.filter { $0.paused }.count,
            dhtNodes: 284,
            port: 6881
        )
        stats.actualPort = 6881
        stats.isListening = true
        stats.portmap = PortMapSnapshot(
            tcp: PortMapInfo(mapped: true, externalPort: 6881, transport: "UPnP"),
            udp: PortMapInfo(mapped: true, externalPort: 6881, transport: "UPnP"),
            error: ""
        )
        var next = PollState()
        next.torrents = list
        next.stats = stats
        next.torrentsByID = Dictionary(
            list.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        next.downloadHistory = DemoData.history(base: 8_400_000, spread: 0.42)
        next.uploadHistory = DemoData.history(base: 2_900_000, spread: 0.5)
        pollState = next
        if !hasLoadedSnapshot { hasLoadedSnapshot = true }
        if let id = selectedID {
            detail = DemoData.detail(for: list.first { $0.id == id })
        }
    }
    #endif

    func loadDetail(_ id: String) {
        guard selectedID == id, !isShuttingDown, hasSession else {
            if selectedID == id {
                detail = nil
            }
            return
        }
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            let decoded = await self.sessionController.detail(id: id)
            self.applyDetail(decoded, id: id, generation: generation)
        }
    }

    func applyDetail(_ decoded: TorrentDetail?, id: String, generation: Int? = nil) {
        guard selectedID == id else { return }
        if let generation, generation != sessionGeneration {
            return
        }
        guard let decoded else {
            // Never keep showing the previous snapshot when the fetch fails.
            detail = nil
            return
        }
        // Avoid republishing identical data: it re-renders the whole inspector.
        if decoded != detail {
            detail = decoded
        }
    }

    func applyDetailJSON(_ json: String?, id: String, generation: Int? = nil) {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? decoder.decode(TorrentDetail.self, from: data) else {
            applyDetail(nil, id: id, generation: generation)
            return
        }
        applyDetail(decoded, id: id, generation: generation)
    }

    #if DEBUG
    package func pollNowForTesting() {
        guard !isShuttingDown, let pointer = sessionController.testPointerBox.value else { return }
        let generation = sessionGeneration
        let snapshot = SessionController.readSnapshot(pointer)
        finishPoll(snapshot, generation: generation)
        if let id = selectedID {
            let decoded = SessionController.readDetail(pointer, id: id)
            applyDetail(decoded, id: id, generation: generation)
        }
    }

    package func applySnapshotForTesting(_ snapshot: VertexSnapshot) {
        apply(snapshot)
    }

    package func applyDetailJSONForTesting(_ json: String?, id: String) {
        applyDetailJSON(json, id: id)
    }

    package func setConfigurationForTesting(_ configuration: SessionConfiguration) {
        configurationOverride = configuration
    }

    /// Test-only hook used to render the diagnostics view with the UPnP/NAT-PMP
    /// states (mapped, error, unmapped) without a real router or a live session.
    package func setStatsForTesting(_ stats: SessionStats) {
        var next = pollState
        next.stats = stats
        pollState = next
    }
    #endif
}
