import CTorrent
import Darwin
import Foundation

package enum PrefKey {
    package static let downloadPath = "downloadPath"
    package static let downloadLimitKB = "downloadLimitKB"
    package static let uploadLimitKB = "uploadLimitKB"
    package static let listenPort = "listenPort"
    package static let maxActiveTorrents = "maxActiveTorrents"
    package static let bindAddress = "bindAddress"
    package static let dhtEnabled = "dhtEnabled"
    package static let pexEnabled = "pexEnabled"
    package static let lsdEnabled = "lsdEnabled"
    package static let upnpEnabled = "upnpEnabled"
    package static let startPaused = "startPaused"
    package static let sequentialDefault = "sequentialDefault"
    package static let appearance = "appearance"
    package static let proxyEnabled = "proxyEnabled"
    package static let proxyHost = "proxyHost"
    package static let proxyPort = "proxyPort"
    package static let proxyUser = "proxyUser"
    package static let proxyPassword = "proxyPassword"
    /// Interface state (filter, sort, inspector width). Persisted separately
    /// from the engine preferences and not registered as defaults: a missing
    /// value falls back to the view's own default.
    package static let uiFilter = "uiFilter"
    package static let uiSort = "uiSort"
    package static let uiSortAscending = "uiSortAscending"
    package static let uiInspectorWidth = "uiInspectorWidth"
}

package enum Preferences {
    package static var suggestedDownloadPath: String {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads.appendingPathComponent("Vertex", isDirectory: true).path
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Downloads/Vertex", isDirectory: true)
            .path
    }

    package static func registerDefaults() {
        UserDefaults.standard.register(defaults: PrefDefault.dictionary)
    }

    package static func resolvedDownloadPath(_ raw: String?) -> String {
        let fallback = suggestedDownloadPath
        let requested = raw ?? ""
        let pointer = requested.withCString { requestedPointer in
            fallback.withCString { fallbackPointer in
                vt_normalize_save_path(requestedPointer, fallbackPointer)
            }
        }
        guard let pointer else {
            return requested.isEmpty ? fallback : requested
        }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    /// Maximum KB/s value that can be represented without overflowing the C bridge.
    package static let maximumLimitKB = Int(Int32.max) / 1024

    /// Whether a speed-limit value is valid for the C bridge.
    package static func isValidLimitKB(_ value: Int) -> Bool {
        (0...maximumLimitKB).contains(value)
    }

    /// Converts a KB/s preference into bytes/s for the C bridge, avoiding Int32 overflow.
    package static func limitBytes(fromKB kb: Int) -> Int32 {
        let clampedKB = min(max(kb, 0), maximumLimitKB)
        return Int32(clampedKB * 1024)
    }

    /// Upper bound for the active-torrent limit. Beyond this the setting stops
    /// being a limit and becomes a way to break the queue.
    package static let maximumActiveTorrents = 1000

    /// Whether an active-torrent limit is valid (0 = unlimited).
    package static func isValidActiveLimit(_ value: Int) -> Bool {
        (0...maximumActiveTorrents).contains(value)
    }

    /// Whether a port can be used for TCP/UDP listening.
    package static func isValidPort(_ value: Int) -> Bool {
        (1...65535).contains(value)
    }

    /// Valid TCP/UDP port, falling back to the BitTorrent default.
    package static func validPort(_ value: Int) -> Int32 {
        isValidPort(value) ? Int32(value) : 6881
    }

    /// Whether a value is a literal IPv4 address suitable for binding.
    /// Rejects: 0.0.0.0, loopback (127.x), link-local (169.254.x),
    /// short forms (e.g. "192.168.1"), leading zeros (e.g. "192.168.001.001"),
    /// and IPv6. Only dotted-quad octets 0-255 without leading zeros are accepted.
    package static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }

        var address = in_addr()
        // inet_pton validates the syntax; we also enforce canonical form
        guard value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return false }

        // Reject non-canonical forms (leading zeros, short forms)
        for part in parts {
            if part.hasPrefix("0") && part.count > 1 { return false }
            guard let octet = Int(part), (0...255).contains(octet) else { return false }
        }

        // Reject special ranges
        guard let first = Int(parts[0]),
              let second = Int(parts[1]) else { return false }
        if first == 0 { return false }                 // 0.0.0.0
        if first == 127 { return false }               // 127.x loopback
        if first == 169 && second == 254 { return false } // 169.254.x link-local

        return true
    }

    /// Normalizes the interface-binding preference. Anything that is not a
    /// literal IPv4 address falls back to an empty string, which means "bind to
    /// every interface".
    package static func normalizedBindAddress(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIPv4(value) else { return "" }
        return value
    }

    package static var downloadPath: String {
        resolvedDownloadPath(UserDefaults.standard.string(forKey: PrefKey.downloadPath))
    }

    /// The download path exactly as stored, without normalizing it. Reading a
    /// view's initial value must not touch the filesystem: `resolvedDownloadPath`
    /// calls into the bridge, which stats the path.
    package static var rawDownloadPath: String {
        UserDefaults.standard.string(forKey: PrefKey.downloadPath) ?? PrefDefault.downloadPath
    }

    package static var startPaused: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.startPaused)
    }

    package static var sequentialDefault: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault)
    }

    package static var resumeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Vertex/resume", isDirectory: true)
    }

    /// Cached SOCKS5 password. Reading the Keychain can block, and with an
    /// ad-hoc signature macOS may even show an access prompt, so the read never
    /// happens on the main thread: `warmProxyPasswordCache()` fills this once on
    /// the session queue and every later access is lock-protected memory.
    private static let proxyPasswordLock = NSLock()
    /// Guarded by `proxyPasswordLock`: every access below takes the lock.
    nonisolated(unsafe) private static var cachedProxyPassword: String?

    /// The SOCKS5 password for the current configuration. Never touches the
    /// Keychain: it returns the cached value, or the not-yet-migrated plaintext
    /// while the cache is still cold.
    package static var proxyPassword: String {
        proxyPasswordLock.lock()
        let cached = cachedProxyPassword
        proxyPasswordLock.unlock()
        if let cached {
            return cached
        }
        return UserDefaults.standard.string(forKey: PrefKey.proxyPassword) ?? ""
    }

    /// Reads the Keychain item once, migrating the legacy plaintext password.
    /// Must be called off the main thread: `TorrentEngine` does it on the session
    /// queue before creating the session, so the first configuration snapshot
    /// already contains the password.
    package static func warmProxyPasswordCache() {
        proxyPasswordLock.lock()
        let alreadyLoaded = cachedProxyPassword != nil
        proxyPasswordLock.unlock()
        if alreadyLoaded { return }

        let defaults = UserDefaults.standard
        let legacy = defaults.string(forKey: PrefKey.proxyPassword) ?? ""

        var resolved = Keychain.proxyPassword()
        if resolved == nil, !legacy.isEmpty {
            // One-time migration. A failed write must not lose the value, so the
            // plaintext is dropped only after the Keychain accepted it; when the
            // Keychain is unavailable (tests) the cache stays cold and
            // `proxyPassword` keeps reading the plaintext.
            guard Keychain.setProxyPassword(legacy) else { return }
            resolved = legacy
        }
        if resolved != nil, !legacy.isEmpty {
            defaults.removeObject(forKey: PrefKey.proxyPassword)
        }

        proxyPasswordLock.lock()
        cachedProxyPassword = resolved ?? ""
        proxyPasswordLock.unlock()
    }

    /// One-time migration of the old plaintext password, kept for callers that
    /// only need the side effect. An existing keychain item always wins: a stale
    /// UserDefaults value must not overwrite it.
    package static func migrateLegacyProxyPassword() {
        warmProxyPasswordCache()
    }

    @discardableResult
    package static func setProxyPassword(_ value: String) -> Bool {
        let saved = Keychain.setProxyPassword(value)
        if saved {
            // Clearing or replacing the password must not leave the legacy
            // plaintext value behind: proxyPassword would fall back to it.
            UserDefaults.standard.removeObject(forKey: PrefKey.proxyPassword)
            proxyPasswordLock.lock()
            cachedProxyPassword = value
            proxyPasswordLock.unlock()
        }
        return saved
    }
}

/// Single source of truth for preference defaults. `registerDefaults()` feeds
/// them to `UserDefaults`, and the views use the same constants as the initial
/// value of their `@AppStorage` properties.
package enum PrefDefault {
    package static let downloadPath: String = Preferences.suggestedDownloadPath
    package static let downloadLimitKB = 0
    package static let uploadLimitKB = 0
    package static let listenPort = 6881
    /// 0 = every torrent at once. A positive value caps the torrents that are
    /// actively downloading or seeding; the others wait in the queue.
    package static let maxActiveTorrents = 0
    /// Empty means every interface. Otherwise a literal IPv4 address, usually
    /// the tunnel address, so the client only exchanges traffic through it.
    package static let bindAddress = ""
    package static let dhtEnabled = true
    package static let pexEnabled = true
    package static let lsdEnabled = true
    package static let upnpEnabled = true
    package static let startPaused = false
    package static let sequentialDefault = false
    /// Follow the system appearance unless the user chose otherwise: opening a
    /// light-mode Mac into a dark window is a surprising default.
    package static let appearance = "system"
    package static let proxyEnabled = false
    package static let proxyHost = "127.0.0.1"
    package static let proxyPort = 1080
    package static let proxyUser = ""
    package static let proxyPassword = ""

    package static var dictionary: [String: Any] {
        [
            PrefKey.downloadPath: downloadPath,
            PrefKey.downloadLimitKB: downloadLimitKB,
            PrefKey.uploadLimitKB: uploadLimitKB,
            PrefKey.listenPort: listenPort,
            PrefKey.maxActiveTorrents: maxActiveTorrents,
            PrefKey.bindAddress: bindAddress,
            PrefKey.dhtEnabled: dhtEnabled,
            PrefKey.pexEnabled: pexEnabled,
            PrefKey.lsdEnabled: lsdEnabled,
            PrefKey.upnpEnabled: upnpEnabled,
            PrefKey.startPaused: startPaused,
            PrefKey.sequentialDefault: sequentialDefault,
            PrefKey.appearance: appearance,
            PrefKey.proxyEnabled: proxyEnabled,
            PrefKey.proxyHost: proxyHost,
            PrefKey.proxyPort: proxyPort,
            PrefKey.proxyUser: proxyUser,
            PrefKey.proxyPassword: proxyPassword
        ]
    }
}

package struct SessionConfiguration: Sendable, Equatable {
    package var downloadPath: String
    package var resumePath: String
    package var port: Int32
    /// Active-torrent limit enforced by libtorrent's auto-manager (0 = none).
    package var maxActive: Int32
    package var downloadLimit: Int32
    package var uploadLimit: Int32
    package var dht: Bool
    package var pex: Bool
    package var lsd: Bool
    package var upnp: Bool
    /// Local address the session is pinned to; empty means every interface.
    package var bindAddress: String
    package var proxyEnabled: Bool
    package var proxyHost: String
    package var proxyPort: Int32
    package var proxyUser: String
    package var proxyPassword: String

    package init(
        downloadPath: String,
        resumePath: String,
        port: Int32,
        maxActive: Int32 = 0,
        downloadLimit: Int32 = 0,
        uploadLimit: Int32 = 0,
        dht: Bool = false,
        pex: Bool = false,
        lsd: Bool = false,
        upnp: Bool = false,
        bindAddress: String = "",
        proxyEnabled: Bool = false,
        proxyHost: String = "127.0.0.1",
        proxyPort: Int32 = 1080,
        proxyUser: String = "",
        proxyPassword: String = ""
    ) {
        self.downloadPath = downloadPath
        self.resumePath = resumePath
        self.port = port
        self.maxActive = maxActive
        self.downloadLimit = downloadLimit
        self.uploadLimit = uploadLimit
        self.dht = dht
        self.pex = pex
        self.lsd = lsd
        self.upnp = upnp
        self.bindAddress = bindAddress
        self.proxyEnabled = proxyEnabled
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUser = proxyUser
        self.proxyPassword = proxyPassword
    }
}

extension TorrentEngine {
    /// LOW #9: validate all persisted preferences at startup. If a value has the
    /// wrong type or falls outside the expected range, reset it to the default
    /// so a corrupted plist or a migration bug cannot silently break the engine.
    nonisolated package static func validateAllPreferences() {
        let defaults = UserDefaults.standard

        // port
        let rawPort = defaults.integer(forKey: PrefKey.listenPort)
        let port = Preferences.validPort(rawPort)
        if Int(port) != rawPort {
            defaults.set(Int(port), forKey: PrefKey.listenPort)
        }

        // limits
        let rawDownloadLimit = defaults.integer(forKey: PrefKey.downloadLimitKB)
        let rawUploadLimit = defaults.integer(forKey: PrefKey.uploadLimitKB)
        let downloadLimit = Preferences.limitBytes(fromKB: rawDownloadLimit)
        let uploadLimit = Preferences.limitBytes(fromKB: rawUploadLimit)
        if !Preferences.isValidLimitKB(rawDownloadLimit) {
            defaults.set(Int(downloadLimit) / 1024, forKey: PrefKey.downloadLimitKB)
        }
        if !Preferences.isValidLimitKB(rawUploadLimit) {
            defaults.set(Int(uploadLimit) / 1024, forKey: PrefKey.uploadLimitKB)
        }

        // active-torrent limit
        let rawMaxActive = defaults.integer(forKey: PrefKey.maxActiveTorrents)
        if !Preferences.isValidActiveLimit(rawMaxActive) {
            defaults.set(PrefDefault.maxActiveTorrents, forKey: PrefKey.maxActiveTorrents)
        }

        // bind address
        let rawBind = defaults.string(forKey: PrefKey.bindAddress)
        let bindAddress = Preferences.normalizedBindAddress(rawBind)
        if rawBind != bindAddress {
            defaults.set(bindAddress, forKey: PrefKey.bindAddress)
        }

        // appearance: must be one of the known options
        if let appearance = defaults.string(forKey: PrefKey.appearance) {
            if appearance != "light" && appearance != "dark" && appearance != "system" {
                defaults.set(PrefDefault.appearance, forKey: PrefKey.appearance)
            }
        }

        // proxy port
        let rawProxyPort = defaults.integer(forKey: PrefKey.proxyPort)
        let proxyPort = Preferences.isValidPort(rawProxyPort) ? Int32(rawProxyPort) : Int32(PrefDefault.proxyPort)
        if Int(proxyPort) != rawProxyPort {
            defaults.set(Int(proxyPort), forKey: PrefKey.proxyPort)
        }

        // proxy host
        if let rawHost = defaults.string(forKey: PrefKey.proxyHost) {
            let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != rawHost {
                defaults.set(trimmed.isEmpty ? PrefDefault.proxyHost : trimmed, forKey: PrefKey.proxyHost)
            }
        }

        // proxy password: move the legacy plaintext value to the Keychain
        Preferences.migrateLegacyProxyPassword()

        // download path
        let rawPath = defaults.string(forKey: PrefKey.downloadPath)
        let resolved = Preferences.resolvedDownloadPath(rawPath)
        if rawPath != resolved {
            defaults.set(resolved, forKey: PrefKey.downloadPath)
        }
    }

    /// Snapshot of the preferences used to create a libtorrent session.
    /// Reads the preferences without validating or persisting them. Startup
    /// validation is done once by `validateAllPreferences()`; runtime edits are
    /// validated by `applySettings()` before this is called. This keeps a
    /// single write path and avoids sanitizing/writing on every read.
    nonisolated static func currentConfiguration() -> SessionConfiguration {
        let defaults = UserDefaults.standard
        let rawProxyPort = defaults.integer(forKey: PrefKey.proxyPort)
        let proxyPort = Preferences.isValidPort(rawProxyPort) ? Int32(rawProxyPort) : Int32(PrefDefault.proxyPort)
        let rawHost = defaults.string(forKey: PrefKey.proxyHost)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let proxyHost = rawHost.isEmpty ? PrefDefault.proxyHost : rawHost

        return SessionConfiguration(
            downloadPath: Preferences.downloadPath,
            resumePath: Preferences.resumeDirectory.path,
            port: Preferences.validPort(defaults.integer(forKey: PrefKey.listenPort)),
            maxActive: Int32(min(max(defaults.integer(forKey: PrefKey.maxActiveTorrents), 0),
                                 Preferences.maximumActiveTorrents)),
            downloadLimit: Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.downloadLimitKB)),
            uploadLimit: Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.uploadLimitKB)),
            dht: defaults.bool(forKey: PrefKey.dhtEnabled),
            pex: defaults.bool(forKey: PrefKey.pexEnabled),
            lsd: defaults.bool(forKey: PrefKey.lsdEnabled),
            upnp: defaults.bool(forKey: PrefKey.upnpEnabled),
            bindAddress: Preferences.normalizedBindAddress(defaults.string(forKey: PrefKey.bindAddress)),
            proxyEnabled: defaults.bool(forKey: PrefKey.proxyEnabled),
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            proxyUser: defaults.string(forKey: PrefKey.proxyUser) ?? "",
            proxyPassword: defaults.bool(forKey: PrefKey.proxyEnabled)
                ? Preferences.proxyPassword
                : ""
        )
    }
}
