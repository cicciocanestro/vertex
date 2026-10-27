import Foundation

enum TorrentPhase {
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
        if !hasMetadata || stateCode == 2 { return .metadata }
        if stateCode == 1 || stateCode == 7 { return .checking }
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

    package init(
        downloadRate: Int64 = 0,
        uploadRate: Int64 = 0,
        active: Int = 0,
        paused: Int = 0,
        dhtNodes: Int = 0,
        port: Int = 0,
        actualPort: Int = 0,
        isListening: Bool = false,
        portmap: PortMapSnapshot = PortMapSnapshot()
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
            portmap: portmap
        )
    }
}

package struct TorrentFile: Decodable, Identifiable, Equatable {
    package let index: Int
    package let path: String
    package let size: Int64
    package let progress: Double
    package let priority: Int

    package var id: Int { index }
    package var isWanted: Bool { priority > 0 }
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

    package func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return !torrent.finished && !torrent.paused
        case .seeding: return torrent.seeding && !torrent.paused
        case .completed: return torrent.finished
        case .paused: return torrent.paused
        }
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
        sort: TorrentSort
    ) -> [Torrent] {
        applyWithCounts(to: torrents, filter: filter, search: search, sort: sort).torrents
    }

    /// Returns the visible torrents and the per-filter counts in a single pass
    /// over the list, so `FilterBar` does not traverse it again.
    package static func applyWithCounts(
        to torrents: [Torrent],
        filter: TorrentFilter,
        search: String,
        sort: TorrentSort
    ) -> TorrentListResult {
        var counts = Dictionary(
            uniqueKeysWithValues: TorrentFilter.allCases.map { ($0, 0) }
        )
        var list: [Torrent] = []
        list.reserveCapacity(torrents.count)

        for torrent in torrents {
            for filterCase in TorrentFilter.allCases where filterCase.matches(torrent) {
                counts[filterCase, default: 0] += 1
            }

            guard filter.matches(torrent) else { continue }
            if !search.isEmpty,
               !torrent.name.localizedCaseInsensitiveContains(search),
               !torrent.id.localizedCaseInsensitiveContains(search) {
                continue
            }
            list.append(torrent)
        }

        switch sort {
        case .recent:
            list.sort { $0.added > $1.added }
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { $0.size > $1.size }
        case .progress:
            list.sort { $0.displayProgress > $1.displayProgress }
        case .speed:
            list.sort { $0.downloadRate > $1.downloadRate }
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

    package let id: UUID
    package let kind: Kind
    package let text: String
    package let detail: String?

    package init(id: UUID = UUID(), kind: Kind, text: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
    }
}
