import Foundation

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
    package var localizedError: String { RuntimeErrorLocalizer.portmap(error) }

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
    package var localizedError: String { RuntimeErrorLocalizer.portmap(error) }
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
    package var localizedError: String { RuntimeErrorLocalizer.proxy(error) }

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
    /// Every asynchronous error collected between two polls. `alertError` keeps
    /// the last message for older payloads; the UI prefers this array.
    package let alertErrors: [String]
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
        case alertErrors = "alert_errors"
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
        alertErrors = try c.decodeIfPresent([String].self, forKey: .alertErrors) ?? []
        proxy = try c.decodeIfPresent(ProxyInfo.self, forKey: .proxy) ?? ProxyInfo()
    }
}
