import Foundation

enum TorrentPhase: Equatable {
    case downloading
    case metadata
    case checking
    case seeding
    case completed
    case paused

    var label: String {
        switch self {
        case .downloading: return L("Download")
        case .metadata: return L("Metadati")
        case .checking: return L("Verifica")
        case .seeding: return L("In seed")
        case .completed: return L("Completato")
        case .paused: return L("In pausa")
        }
    }
}

/// libtorrent `torrent_status::state_t` codes that the UI cares about. Named
/// so that `Torrent.phase` and the completion toast stop using magic numbers.
/// See `Sources/CTorrent/vertex_torrent.cpp` for the values that reach Swift.
enum LibtorrentStateCode: Int {
    case checkingFiles = 1
    case downloadingMetadata = 2
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
        self.progress = progress
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
        self.sequential = sequential
        self.hasMetadata = hasMetadata
        self.savePath = savePath
        self.ratio = ratio
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
        progress = min(max(try c.decode(Double.self, forKey: .progress), 0), 1)
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
        sequential = try c.decode(Bool.self, forKey: .sequential)
        hasMetadata = try c.decode(Bool.self, forKey: .hasMetadata)
        savePath = try c.decode(String.self, forKey: .savePath)
        ratio = max(try c.decode(Double.self, forKey: .ratio), 0)
        added = max(try c.decode(Int64.self, forKey: .added), 0)
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, name, progress, size, downloaded, uploaded, peers, seeds, eta
        case stateCode = "state_code"
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case finished, seeding, paused, sequential
        case hasMetadata = "has_metadata"
        case savePath = "save_path"
        case ratio, added, error
    }

    package var displayProgress: Double {
        min(max(finished ? 1 : progress, 0), 1)
    }

    var phase: TorrentPhase {
        if paused { return .paused }
        if !hasMetadata || stateCode == LibtorrentStateCode.downloadingMetadata.rawValue {
            return .metadata
        }
        if stateCode == LibtorrentStateCode.checkingFiles.rawValue
            || stateCode == LibtorrentStateCode.checkingResumeData.rawValue {
            return .checking
        }
        if seeding { return .seeding }
        if finished { return .completed }
        return .downloading
    }

    package var hasError: Bool { !error.isEmpty }
}

package struct PortMapInfo: Decodable, Equatable {
    package var mapped: Bool = false
    package var externalPort: Int = 0
    package var transport: String = ""
    package var error: String = ""

    package init(
        mapped: Bool = false,
        externalPort: Int = 0,
        transport: String = "",
        error: String = ""
    ) {
        self.mapped = mapped
        self.externalPort = externalPort
        self.transport = transport
        self.error = error
    }

    package var hasError: Bool { !error.isEmpty }

    enum CodingKeys: String, CodingKey {
        case mapped
        case externalPort = "external_port"
        case transport
        case error
    }
}

package struct PortMapSnapshot: Decodable, Equatable {
    package var tcp = PortMapInfo()
    package var udp = PortMapInfo()
    package var error: String = ""

    package init(tcp: PortMapInfo = PortMapInfo(), udp: PortMapInfo = PortMapInfo(), error: String = "") {
        self.tcp = tcp
        self.udp = udp
        self.error = error
    }

    package var hasError: Bool { tcp.hasError || udp.hasError || !error.isEmpty }
}

package struct ProxyInfo: Decodable, Equatable {
    package var enabled: Bool = false
    package var type: String = "None"
    package var hostname: String = ""
    package var port: Int = 0
    /// True when credentials are configured and libtorrent uses the socks5_pw
    /// proxy type (RFC 1929). Exposed for diagnostics and regression tests.
    package var auth: Bool = false
    package var error: String = ""

    package var hasError: Bool { !error.isEmpty }

    package init(
        enabled: Bool = false,
        type: String = "None",
        hostname: String = "",
        port: Int = 0,
        auth: Bool = false,
        error: String = ""
    ) {
        self.enabled = enabled
        self.type = type
        self.hostname = hostname
        self.port = port
        self.auth = auth
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case enabled, type, hostname, port, auth, error
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "None"
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        auth = try c.decodeIfPresent(Bool.self, forKey: .auth) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
    }
}

package struct SessionStats: Equatable {
    package var downloadRate: Int64 = 0
    package var uploadRate: Int64 = 0
    package var active: Int = 0
    package var paused: Int = 0
    package var dhtNodes: Int = 0
    package var port: Int = 0
    package var actualPort: Int = 0
    package var isListening: Bool = false
    package var portmap = PortMapSnapshot()
    /// Local address the engine is pinned to. Empty means every interface.
    package var bindAddress: String = ""
    /// Last listen failure reported by libtorrent, empty when the socket is open.
    package var listenError: String = ""
    package var proxy = ProxyInfo()

    package var effectivePort: Int {
        actualPort > 0 ? actualPort : port
    }

    package var isBoundToAddress: Bool { !bindAddress.isEmpty }
    package var isProxyActive: Bool { proxy.enabled && !proxy.hostname.isEmpty && proxy.port > 0 }

    package init(
        downloadRate: Int64 = 0,
        uploadRate: Int64 = 0,
        active: Int = 0,
        paused: Int = 0,
        dhtNodes: Int = 0,
        port: Int = 0,
        actualPort: Int = 0,
        isListening: Bool = false,
        portmap: PortMapSnapshot = PortMapSnapshot(),
        bindAddress: String = "",
        listenError: String = "",
        proxy: ProxyInfo = ProxyInfo()
    ) {
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.active = active
        self.paused = paused
        self.dhtNodes = dhtNodes
        self.port = port
        self.actualPort = actualPort
        self.isListening = isListening
        self.portmap = portmap
        self.bindAddress = bindAddress
        self.listenError = listenError
        self.proxy = proxy
    }
}

package struct VertexSnapshot: Decodable {
    package let torrents: [Torrent]
    package let downloadRate: Int64
    package let uploadRate: Int64
    package let active: Int
    package let pausedCount: Int
    package let dhtNodes: Int
    package let port: Int
    package let listenActualPort: Int
    package let listening: Bool
    package let portmap: PortMapSnapshot
    package let bindAddress: String
    package let listenError: String
    package let alertError: String
    package let proxy: ProxyInfo

    enum CodingKeys: String, CodingKey {
        case torrents
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case active
        case pausedCount = "paused_count"
        case dhtNodes = "dht_nodes"
        case port
        case listenActualPort = "listen_actual_port"
        case listening
        case portmap
        case bindAddress = "bind_address"
        case listenError = "listen_error"
        case alertError = "alert_error"
        case proxy
    }

    package var stats: SessionStats {
        SessionStats(
            downloadRate: downloadRate,
            uploadRate: uploadRate,
            active: active,
            paused: pausedCount,
            dhtNodes: dhtNodes,
            port: port,
            actualPort: listenActualPort,
            isListening: listening,
            portmap: portmap,
            bindAddress: bindAddress,
            listenError: listenError,
            proxy: proxy
        )
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        torrents = try c.decode([Torrent].self, forKey: .torrents)
        downloadRate = try c.decode(Int64.self, forKey: .downloadRate)
        uploadRate = try c.decode(Int64.self, forKey: .uploadRate)
        active = try c.decode(Int.self, forKey: .active)
        pausedCount = try c.decode(Int.self, forKey: .pausedCount)
        dhtNodes = try c.decode(Int.self, forKey: .dhtNodes)
        port = try c.decode(Int.self, forKey: .port)
        listenActualPort = try c.decode(Int.self, forKey: .listenActualPort)
        listening = try c.decode(Bool.self, forKey: .listening)
        portmap = try c.decode(PortMapSnapshot.self, forKey: .portmap)
        bindAddress = try c.decode(String.self, forKey: .bindAddress)
        listenError = try c.decode(String.self, forKey: .listenError)
        alertError = try c.decode(String.self, forKey: .alertError)
        proxy = try c.decodeIfPresent(ProxyInfo.self, forKey: .proxy) ?? ProxyInfo()
    }
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

    package var id: String { url }
}

package struct TorrentDetail: Decodable, Equatable {
    package let files: [TorrentFile]
    package let trackers: [TorrentTracker]
    package let metadata: Bool
}

package enum TorrentFilter: String, CaseIterable, Identifiable {
    case all
    case downloading
    case seeding
    case completed
    case paused

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .all: return L("Tutti")
        case .downloading: return L("Download")
        case .seeding: return L("Seed")
        case .completed: return L("Completati")
        case .paused: return L("In pausa")
        }
    }

    /// The single exclusive category for a torrent. `Torrent.phase` is the
    /// source of truth: pause prevails, and "Download" includes metadata and
    /// verification.
    package static func category(for torrent: Torrent) -> TorrentFilter {
        switch torrent.phase {
        case .downloading, .metadata, .checking: return .downloading
        case .seeding: return .seeding
        case .completed: return .completed
        case .paused: return .paused
        }
    }

    /// Filters are mutually exclusive: every torrent belongs to exactly one
    /// category. A seeding torrent is counted in "Seed", not in "Completati";
    /// a paused finished torrent is only "In pausa".
    package func matches(_ torrent: Torrent) -> Bool {
        self == .all || Self.category(for: torrent) == self
    }
}

package enum TorrentSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case size
    case progress
    case speed

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .recent: return L("Recenti")
        case .name: return L("Nome")
        case .size: return L("Dimensione")
        case .progress: return L("Progresso")
        case .speed: return L("Velocità")
        }
    }

    package var icon: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat"
        case .size: return "externaldrive"
        case .progress: return "chart.bar"
        case .speed: return "speedometer"
        }
    }
}

package struct TorrentListResult {
    package let torrents: [Torrent]
    package let counts: [TorrentFilter: Int]
}

/// Filtering and sorting applied by the torrent list. It lives in the model
/// layer so the behaviour can be tested without rendering `RootView`.
package enum TorrentListPipeline {
    package static func apply(
        to torrents: [Torrent],
        filter: TorrentFilter,
        search: String,
        sort: TorrentSort,
        ascending: Bool = false
    ) -> [Torrent] {
        applyWithCounts(
            to: torrents,
            filter: filter,
            search: search,
            sort: sort,
            ascending: ascending
        ).torrents
    }

    /// Returns the visible torrents and the per-filter counts in a single pass
    /// over the list, so `FilterBar` does not traverse it again.
    package static func applyWithCounts(
        to torrents: [Torrent],
        filter: TorrentFilter,
        search: String,
        sort: TorrentSort,
        ascending: Bool = false
    ) -> TorrentListResult {
        var counts = Dictionary(
            uniqueKeysWithValues: TorrentFilter.allCases.map { ($0, 0) }
        )
        var list: [Torrent] = []
        list.reserveCapacity(torrents.count)

        for torrent in torrents {
            let category = TorrentFilter.category(for: torrent)
            counts[.all, default: 0] += 1
            counts[category, default: 0] += 1

            guard filter == .all || filter == category else { continue }
            if !search.isEmpty,
               !torrent.name.localizedCaseInsensitiveContains(search),
               !torrent.id.localizedCaseInsensitiveContains(search) {
                continue
            }
            list.append(torrent)
        }

        switch sort {
        case .recent:
            list.sort { ascending ? ($0.added < $1.added) : ($0.added > $1.added) }
        case .name:
            let target: ComparisonResult = ascending ? .orderedDescending : .orderedAscending
            list.sort { $0.name.localizedStandardCompare($1.name) == target }
        case .size:
            list.sort { ascending ? ($0.size < $1.size) : ($0.size > $1.size) }
        case .progress:
            list.sort { ascending ? ($0.displayProgress < $1.displayProgress) : ($0.displayProgress > $1.displayProgress) }
        case .speed:
            list.sort { ascending ? ($0.downloadRate < $1.downloadRate) : ($0.downloadRate > $1.downloadRate) }
        }

        return TorrentListResult(torrents: list, counts: counts)
    }
}

package struct ToastMessage: Identifiable, Equatable {
    package enum Kind {
        case success
        case error
        case info
    }

    /// Optional action rendered inside the toast. The view stays presentation
    /// only: the root view performs the side effect.
    package enum Action: Equatable {
        case reveal(path: String)
        case openFolder(path: String)
    }

    package let id: UUID
    package let kind: Kind
    package let text: String
    package let detail: String?
    package let actionTitle: String?
    package let action: Action?

    package init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        detail: String? = nil,
        actionTitle: String? = nil,
        action: Action? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }
}
