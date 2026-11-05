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

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.poll()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func poll() {
        #if DEBUG
        if DemoData.isEnabled {
            applyDemoSnapshot()
            return
        }
        #endif

        guard !isShuttingDown, !isPollInFlight, let session else { return }
        isPollInFlight = true
        nextPollID += 1
        let pollID = nextPollID
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)

        sessionQueue.async { [weak self] in
            let snapshot = pointer.value.flatMap { Self.readSnapshot($0) }
            DispatchQueue.main.async {
                self?.finishPoll(snapshot, id: pollID, generation: generation)
            }
        }
    }

    func finishPoll(_ snapshot: VertexSnapshot?, id: Int, generation: Int) {
        isPollInFlight = false
        guard generation == sessionGeneration, id >= lastAppliedPollID, !isShuttingDown else {
            return
        }
        lastAppliedPollID = id
        guard let snapshot else { return }
        apply(snapshot)
    }

    private func appendHistory(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 80 {
            history.removeFirst(history.count - 80)
        }
    }

    func apply(_ snapshot: VertexSnapshot) {
        if !snapshot.alertError.isEmpty {
            showToast(localizedError(snapshot.alertError), kind: .error)
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
                let names = snapshot.torrents
                    .filter { newlyFinished.contains($0.id) }
                    .map(\.name)
                if names.count == 1 {
                    showToast(L("Download completato"), kind: .success, detail: names[0])
                } else {
                    showToast(LF("%ld download completati", names.count), kind: .success)
                }
            }
        }
        unfinishedIDs = unfinished
        hasLoadedSnapshot = true

        var next = pollState
        next.torrents = snapshot.torrents
        next.stats = snapshot.stats
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
                selectedID = nil
                detail = nil
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
        hasLoadedSnapshot = true
        if let id = selectedID {
            detail = DemoData.detail(for: list.first { $0.id == id })
        }
    }
    #endif

    func loadDetail(_ id: String) {
        guard selectedID == id, !isShuttingDown, let session else {
            if selectedID == id {
                detail = nil
            }
            return
        }
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)
        sessionQueue.async { [weak self] in
            let json = pointer.value.flatMap { Self.readDetailJSON($0, id: id) }
            DispatchQueue.main.async {
                self?.applyDetailJSON(json, id: id, generation: generation)
            }
        }
    }

    func applyDetailJSON(_ json: String?, id: String, generation: Int? = nil) {
        guard selectedID == id else { return }
        if let generation, generation != sessionGeneration {
            return
        }
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? decoder.decode(TorrentDetail.self, from: data) else {
            // Never keep showing the previous snapshot when the fetch fails.
            detail = nil
            return
        }
        // Avoid republishing identical data: it re-renders the whole inspector.
        if decoded != detail {
            detail = decoded
        }
    }

    nonisolated static func readSnapshot(_ session: OpaquePointer) -> VertexSnapshot? {
        vt_session_poll(session)
        guard let pointer = vt_snapshot_json(session) else { return nil }
        let json = String(cString: pointer)
        vt_free_string(pointer)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VertexSnapshot.self, from: data)
    }

    nonisolated static func readDetailJSON(
        _ session: OpaquePointer,
        id: String
    ) -> String? {
        let pointer = id.withCString { vt_detail_json(session, $0) }
        guard let pointer else { return nil }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    #if DEBUG
    package func pollNowForTesting() {
        guard !isShuttingDown, let session else { return }
        nextPollID += 1
        let pollID = nextPollID
        let generation = sessionGeneration
        let snapshot = sessionQueue.sync { Self.readSnapshot(session) }
        finishPoll(snapshot, id: pollID, generation: generation)
        if let id = selectedID {
            let json = sessionQueue.sync { Self.readDetailJSON(session, id: id) }
            applyDetailJSON(json, id: id, generation: generation)
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
