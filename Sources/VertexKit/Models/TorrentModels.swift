import Foundation

private func clampedUnit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private func clampedNonNegative(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return max(value, 0)
}

/// Phase of a torrent as shown by the row pill and by the filters.
package enum TorrentPhase: Equatable {
    case downloading
    case metadata
    case checking
    case seeding
    case completed
    case completedPaused
    case paused
    /// Paused by the queue manager: the torrent is waiting for an active slot.
    case queued

    package var label: String {
        switch self {
        case .downloading: return L("Download")
        case .metadata: return L("Metadati")
        case .checking: return L("Verifica")
        case .seeding: return L("In seed")
        case .completed: return L("Completato")
        case .completedPaused: return L("Completato · In pausa")
        case .paused: return L("In pausa")
        case .queued: return L("In coda")
        }
    }
}

/// libtorrent `torrent_status::state_t` codes that the UI cares about. Named
/// so that `Torrent.phase` and the completion toast stop using magic numbers.
/// See `Sources/CTorrent/vertex_torrent.cpp` for the values that reach Swift.
enum LibtorrentStateCode: Int {
    case checkingFiles = 1
    case downloadingMetadata = 2
    /// Everything the torrent wants has been downloaded, but it is not a pure
    /// seeder: libtorrent uses this state when some pieces are filtered (files
    /// set to Skip), so the full data set is not available.
    case finished = 4
    /// The torrent is a pure seeder. libtorrent reports this state for every
    /// fully downloaded torrent, paused ones included: being paused is a
    /// separate flag, not a different state.
    case seeding = 5
    case checkingResumeData = 7
}

package struct Torrent: Decodable, Identifiable, Equatable {
    package let id: String
    package let name: String
    package let stateCode: Int
    package let progress: Double
    package let size: Int64
    package let downloaded: Int64
    package let uploaded: Int64
    package let downloadRate: Int64
    package let uploadRate: Int64
    package let peers: Int
    package let seeds: Int
    package let eta: Int64
    package let finished: Bool
    package let seeding: Bool
    package let paused: Bool
    /// True while the queue manager owns the torrent. `paused && autoManaged` is
    /// the queued state.
    package let autoManaged: Bool
    package let sequential: Bool
    package let hasMetadata: Bool
    package let savePath: String
    package let ratio: Double
    package let added: Int64
    package let error: String

    package init(
        id: String,
        name: String,
        stateCode: Int,
        progress: Double,
        size: Int64,
        downloaded: Int64,
        uploaded: Int64,
        downloadRate: Int64,
        uploadRate: Int64,
        peers: Int,
        seeds: Int,
        eta: Int64,
        finished: Bool,
        seeding: Bool,
        paused: Bool,
        autoManaged: Bool = false,
        sequential: Bool,
        hasMetadata: Bool,
        savePath: String,
        ratio: Double,
        added: Int64,
        error: String
    ) {
        self.id = id
        self.name = name
        self.stateCode = stateCode
        self.progress = clampedUnit(progress)
        self.size = size
        self.downloaded = downloaded
        self.uploaded = uploaded
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.peers = peers
        self.seeds = seeds
        self.eta = eta
        self.finished = finished
        self.seeding = seeding
        self.paused = paused
        self.autoManaged = autoManaged
        self.sequential = sequential
        self.hasMetadata = hasMetadata
        self.savePath = savePath
        self.ratio = clampedNonNegative(ratio)
        self.added = added
        self.error = error
    }

    /// MEDIUM #4: decode with bounds instead of trusting the JSON. A negative
    /// progress, peer count or eta would otherwise flow into the UI and the
    /// sort pipeline; clamping here keeps every consumer honest.
    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        stateCode = max(try c.decode(Int.self, forKey: .stateCode), 0)
        progress = clampedUnit(try c.decode(Double.self, forKey: .progress))
        size = max(try c.decode(Int64.self, forKey: .size), 0)
        downloaded = max(try c.decode(Int64.self, forKey: .downloaded), 0)
        uploaded = max(try c.decode(Int64.self, forKey: .uploaded), 0)
        downloadRate = max(try c.decode(Int64.self, forKey: .downloadRate), 0)
        uploadRate = max(try c.decode(Int64.self, forKey: .uploadRate), 0)
        peers = max(try c.decode(Int.self, forKey: .peers), 0)
        seeds = max(try c.decode(Int.self, forKey: .seeds), 0)
        // -1 is the bridge sentinel for "ETA not computable" (paused, queued,
        // metadata or no payload rate). It must survive decoding: clamping it to
        // 0 would make Fmt.eta report "Completato" for unfinished torrents.
        eta = max(try c.decode(Int64.self, forKey: .eta), -1)
        finished = try c.decode(Bool.self, forKey: .finished)
        seeding = try c.decode(Bool.self, forKey: .seeding)
        paused = try c.decode(Bool.self, forKey: .paused)
        // Optional so an older snapshot (or a hand written fixture) still decodes.
        autoManaged = try c.decodeIfPresent(Bool.self, forKey: .autoManaged) ?? false
        sequential = try c.decode(Bool.self, forKey: .sequential)
        hasMetadata = try c.decode(Bool.self, forKey: .hasMetadata)
        savePath = try c.decode(String.self, forKey: .savePath)
        ratio = clampedNonNegative(try c.decode(Double.self, forKey: .ratio))
        added = max(try c.decode(Int64.self, forKey: .added), 0)
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, name, progress, size, downloaded, uploaded, peers, seeds, eta
        case stateCode = "state_code"
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case finished, seeding, paused, sequential
        case autoManaged = "auto_managed"
        case hasMetadata = "has_metadata"
        case savePath = "save_path"
        case ratio, added, error
    }

    package var displayProgress: Double {
        clampedUnit(finished ? 1 : progress)
    }

    package var phase: TorrentPhase {
        // `paused` alone does not say who paused the torrent: the auto-manager
        // pauses the torrents that do not fit in the active limit, so a paused
        // auto-managed torrent is waiting in the queue, not stopped by the user.
        if paused {
            if autoManaged { return .queued }
            // A torrent that finished downloading and was paused by the user is completed (paused).
            // State 4 (`finished` with skipped files) counts as completed only when `finished` is true,
            // so setting all files to Skip (0 wanted bytes, `finished == false`) does not report completed.
            if finished || (seeding && stateCode == LibtorrentStateCode.seeding.rawValue) {
                return .completedPaused
            }
            return .paused
        }
        if !hasMetadata || stateCode == LibtorrentStateCode.downloadingMetadata.rawValue {
            return .metadata
        }
        if stateCode == LibtorrentStateCode.checkingFiles.rawValue
            || stateCode == LibtorrentStateCode.checkingResumeData.rawValue
        {
            return .checking
        }
        // When completed or seeding, distinguish active uploading from completed idle:
        // if actively uploading (uploadRate > 0) show seeding (purple ↑),
        // if finished with uploadRate == 0 show completed (green ✓).
        let isFullyDownloaded =
            finished
            || (seeding && stateCode == LibtorrentStateCode.seeding.rawValue)
        if isFullyDownloaded {
            return uploadRate > 0 ? .seeding : .completed
        }
        return .downloading
    }

    package var hasError: Bool { !error.isEmpty }
    package var localizedError: String { RuntimeErrorLocalizer.torrent(error) }

    /// Waiting for an active slot inside the queue.
    package var isQueued: Bool { phase == .queued }
}

/// The three priority levels exposed by the inspector. The raw values are the
/// libtorrent download priorities (0 = skip, 4 = default, 7 = maximum).
package enum FilePriority: Int, CaseIterable {
    case skip = 0
    case normal = 4
    case high = 7
}

package struct TorrentFile: Decodable, Identifiable, Equatable {
    package let index: Int
    package let path: String
    package let size: Int64
    package let progress: Double
    package let priority: Int

    package var id: Int { index }
    package var isWanted: Bool { priority > 0 }

    package init(
        index: Int,
        path: String,
        size: Int64,
        progress: Double,
        priority: Int
    ) {
        self.index = max(index, 0)
        self.path = path
        self.size = max(size, 0)
        self.progress = clampedUnit(progress)
        self.priority = min(max(priority, 0), 7)
    }

    enum CodingKeys: String, CodingKey {
        case index, path, size, progress, priority
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = max(try c.decode(Int.self, forKey: .index), 0)
        path = try c.decode(String.self, forKey: .path)
        size = max(try c.decode(Int64.self, forKey: .size), 0)
        progress = clampedUnit(try c.decode(Double.self, forKey: .progress))
        priority = min(max(try c.decode(Int.self, forKey: .priority), 0), 7)
    }

    /// Resume data may contain intermediate values (1-6); they map to the two
    /// wanted levels so the UI always has an unambiguous state.
    package var priorityLevel: FilePriority {
        if priority <= 0 { return .skip }
        return priority >= FilePriority.high.rawValue ? .high : .normal
    }
}

package struct TorrentTracker: Decodable, Identifiable, Equatable {
    package let url: String
    package let verified: Bool
    package let fails: Int
    package let message: String
    package let peers: Int
    package let seeds: Int
    package let tier: Int

    package var id: String { "\(tier):\(url)" }

    package init(
        url: String,
        verified: Bool,
        fails: Int,
        message: String,
        peers: Int,
        seeds: Int,
        tier: Int = 0
    ) {
        self.url = url
        self.verified = verified
        self.fails = max(fails, 0)
        self.message = message
        self.peers = peers
        self.seeds = seeds
        self.tier = max(tier, 0)
    }

    enum CodingKeys: String, CodingKey {
        case url, verified, fails, message, peers, seeds, tier
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        verified = try c.decode(Bool.self, forKey: .verified)
        fails = max(try c.decode(Int.self, forKey: .fails), 0)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        peers = try c.decode(Int.self, forKey: .peers)
        seeds = try c.decode(Int.self, forKey: .seeds)
        tier = max(try c.decodeIfPresent(Int.self, forKey: .tier) ?? 0, 0)
    }
}

package struct TorrentPeer: Decodable, Identifiable, Equatable {
    package let id: String
    package let endpoint: String
    package let client: String
    package let progress: Double
    package let downloadRate: Int64
    package let uploadRate: Int64
    package let flags: String
    package let source: String

    package init(
        id: String? = nil,
        endpoint: String,
        client: String,
        progress: Double,
        downloadRate: Int64,
        uploadRate: Int64,
        flags: String,
        source: String
    ) {
        self.id = id ?? endpoint
        self.endpoint = endpoint
        self.client = client
        self.progress = clampedUnit(progress)
        self.downloadRate = max(downloadRate, 0)
        self.uploadRate = max(uploadRate, 0)
        self.flags = flags
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case endpoint, client, progress, flags, source
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEndpoint = try c.decode(String.self, forKey: .endpoint)
        id = decodedEndpoint
        endpoint = decodedEndpoint
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        progress = clampedUnit(try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0)
        downloadRate = max(try c.decodeIfPresent(Int64.self, forKey: .downloadRate) ?? 0, 0)
        uploadRate = max(try c.decodeIfPresent(Int64.self, forKey: .uploadRate) ?? 0, 0)
        flags = try c.decodeIfPresent(String.self, forKey: .flags) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}

package struct TorrentDetail: Decodable, Equatable {
    package let files: [TorrentFile]
    package let trackers: [TorrentTracker]
    package let peers: [TorrentPeer]
    package let metadata: Bool

    package init(
        files: [TorrentFile],
        trackers: [TorrentTracker],
        peers: [TorrentPeer] = [],
        metadata: Bool
    ) {
        self.files = files
        self.trackers = Self.disambiguatedTrackers(trackers)
        self.peers = Self.disambiguatedPeers(peers)
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case files, trackers, peers, metadata
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = try c.decode([TorrentFile].self, forKey: .files)
        let decodedTrackers = try c.decode([TorrentTracker].self, forKey: .trackers)
        trackers = Self.disambiguatedTrackers(decodedTrackers)
        let decodedPeers = try c.decodeIfPresent([TorrentPeer].self, forKey: .peers) ?? []
        peers = Self.disambiguatedPeers(decodedPeers)
        metadata = try c.decode(Bool.self, forKey: .metadata)
    }

    private static func disambiguatedTrackers(_ trackers: [TorrentTracker]) -> [TorrentTracker] {
        var seen: Set<String> = []
        seen.reserveCapacity(trackers.count)
        return trackers.map { tracker in
            var candidate = tracker
            while !seen.insert(candidate.id).inserted {
                candidate = TorrentTracker(
                    url: tracker.url,
                    verified: tracker.verified,
                    fails: tracker.fails,
                    message: tracker.message,
                    peers: tracker.peers,
                    seeds: tracker.seeds,
                    tier: candidate.tier + 1
                )
            }
            return candidate
        }
    }

    private static func disambiguatedPeers(_ peers: [TorrentPeer]) -> [TorrentPeer] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(peers.count)
        var usedIDs: Set<String> = []
        usedIDs.reserveCapacity(peers.count)
        return peers.map { peer in
            let occurrence = (counts[peer.endpoint] ?? 0) + 1
            counts[peer.endpoint] = occurrence
            var candidateID = occurrence == 1 ? peer.endpoint : "\(peer.endpoint)#\(occurrence)"
            var suffix = occurrence
            while !usedIDs.insert(candidateID).inserted {
                suffix += 1
                candidateID = "\(peer.endpoint)#\(suffix)"
            }
            guard candidateID != peer.id else { return peer }
            return TorrentPeer(
                id: candidateID,
                endpoint: peer.endpoint,
                client: peer.client,
                progress: peer.progress,
                downloadRate: peer.downloadRate,
                uploadRate: peer.uploadRate,
                flags: peer.flags,
                source: peer.source
            )
        }
    }
}
