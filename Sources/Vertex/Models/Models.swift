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
        case .downloading: return "Download"
        case .metadata: return "Metadati"
        case .checking: return "Verifica"
        case .seeding: return "In seed"
        case .completed: return "Completato"
        case .paused: return "In pausa"
        }
    }
}

struct Torrent: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let state: String
    let stateCode: Int
    let progress: Double
    let size: Int64
    let downloaded: Int64
    let uploaded: Int64
    let downloadRate: Int64
    let uploadRate: Int64
    let peers: Int
    let seeds: Int
    let eta: Int64
    let finished: Bool
    let seeding: Bool
    let paused: Bool
    let sequential: Bool
    let hasMetadata: Bool
    let savePath: String
    let files: Int
    let ratio: Double
    let added: Int64
    let error: String

    enum CodingKeys: String, CodingKey {
        case id, name, state, progress, size, downloaded, uploaded, peers, seeds, eta
        case stateCode = "state_code"
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case finished, seeding, paused, sequential
        case hasMetadata = "has_metadata"
        case savePath = "save_path"
        case files, ratio, added, error
    }

    var displayProgress: Double {
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

    var hasError: Bool { !error.isEmpty }

    var downloadedFraction: Double {
        size > 0 ? min(max(Double(downloaded) / Double(size), 0), 1) : 0
    }
}

struct PortMapInfo: Decodable, Equatable {
    var mapped: Bool = false
    var externalPort: Int = 0
    var transport: String = ""

    enum CodingKeys: String, CodingKey {
        case mapped
        case externalPort = "external_port"
        case transport
    }
}

struct PortMapSnapshot: Decodable, Equatable {
    var tcp = PortMapInfo()
    var udp = PortMapInfo()
    var error: String = ""
}

struct SessionStats: Equatable {
    var downloadRate: Int64 = 0
    var uploadRate: Int64 = 0
    var totalDownload: Int64 = 0
    var totalUpload: Int64 = 0
    var active: Int = 0
    var paused: Int = 0
    var dhtNodes: Int = 0
    var port: Int = 0
    var actualPort: Int = 0
    var isListening: Bool = false
    var portmap = PortMapSnapshot()
}

struct VertexSnapshot: Decodable {
    let torrents: [Torrent]
    let downloadRate: Int64
    let uploadRate: Int64
    let totalDownload: Int64
    let totalUpload: Int64
    let active: Int
    let pausedCount: Int
    let dhtNodes: Int
    let port: Int
    let listenActualPort: Int
    let listening: Bool
    let portmap: PortMapSnapshot

    enum CodingKeys: String, CodingKey {
        case torrents
        case downloadRate = "download_rate"
        case uploadRate = "upload_rate"
        case totalDownload = "total_download"
        case totalUpload = "total_upload"
        case active
        case pausedCount = "paused_count"
        case dhtNodes = "dht_nodes"
        case port
        case listenActualPort = "listen_actual_port"
        case listening
        case portmap
    }

    var stats: SessionStats {
        SessionStats(
            downloadRate: downloadRate,
            uploadRate: uploadRate,
            totalDownload: totalDownload,
            totalUpload: totalUpload,
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

struct TorrentFile: Decodable, Identifiable, Equatable {
    let index: Int
    let path: String
    let size: Int64
    let progress: Double
    let priority: Int

    var id: Int { index }
    var isWanted: Bool { priority > 0 }
}

struct TorrentTracker: Decodable, Identifiable, Equatable {
    let url: String
    let verified: Bool
    let fails: Int
    let message: String
    let peers: Int
    let seeds: Int

    var id: String { url }

    var statusLabel: String {
        if verified { return "Attivo" }
        if fails > 0 { return "Errore" }
        return "In attesa"
    }
}

struct TorrentDetail: Decodable, Equatable {
    let files: [TorrentFile]
    let trackers: [TorrentTracker]
    let metadata: Bool
}

enum TorrentFilter: String, CaseIterable, Identifiable {
    case all
    case downloading
    case seeding
    case completed
    case paused

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tutti"
        case .downloading: return "Download"
        case .seeding: return "Seed"
        case .completed: return "Completati"
        case .paused: return "In pausa"
        }
    }

    func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return !torrent.finished && !torrent.paused
        case .seeding: return torrent.seeding && !torrent.paused
        case .completed: return torrent.finished
        case .paused: return torrent.paused
        }
    }
}

enum TorrentSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case size
    case progress
    case speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recenti"
        case .name: return "Nome"
        case .size: return "Dimensione"
        case .progress: return "Progresso"
        case .speed: return "Velocità"
        }
    }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat"
        case .size: return "externaldrive"
        case .progress: return "chart.bar"
        case .speed: return "speedometer"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Kind {
        case success
        case error
        case info
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let detail: String?
}
