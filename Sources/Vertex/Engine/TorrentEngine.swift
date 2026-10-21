import AppKit
import CTorrent
import Foundation

enum PrefKey {
    static let downloadPath = "downloadPath"
    static let downloadLimitKB = "downloadLimitKB"
    static let uploadLimitKB = "uploadLimitKB"
    static let listenPort = "listenPort"
    static let dhtEnabled = "dhtEnabled"
    static let upnpEnabled = "upnpEnabled"
    static let startPaused = "startPaused"
    static let sequentialDefault = "sequentialDefault"
    static let appearance = "appearance"
}

enum Preferences {
    static var suggestedDownloadPath: String {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads.appendingPathComponent("Vertex", isDirectory: true).path
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Downloads/Vertex", isDirectory: true)
            .path
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.downloadPath: suggestedDownloadPath,
            PrefKey.downloadLimitKB: 0,
            PrefKey.uploadLimitKB: 0,
            PrefKey.listenPort: 6881,
            PrefKey.dhtEnabled: true,
            PrefKey.upnpEnabled: true,
            PrefKey.startPaused: false,
            PrefKey.sequentialDefault: false,
            PrefKey.appearance: "dark"
        ])
    }

    static func resolvedDownloadPath(_ raw: String?) -> String {
        let fallback = suggestedDownloadPath
        var path = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            path = fallback
        }
        path = (path as NSString).expandingTildeInPath

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return path
            }
            // A file was chosen as destination (e.g. a .torrent): use its folder.
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }

        if path.lowercased().hasSuffix(".torrent") {
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }

        return path
    }

    /// Converts a KB/s preference into bytes/s for the C bridge, avoiding Int32 overflow.
    static func limitBytes(fromKB kb: Int) -> Int32 {
        let clampedKB = min(max(kb, 0), Int(Int32.max) / 1024)
        return Int32(clampedKB * 1024)
    }

    /// Valid TCP/UDP port, falling back to the BitTorrent default.
    static func validPort(_ value: Int) -> Int32 {
        (1...65535).contains(value) ? Int32(value) : 6881
    }

    static var downloadPath: String {
        resolvedDownloadPath(UserDefaults.standard.string(forKey: PrefKey.downloadPath))
    }

    static var resumeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Vertex/resume", isDirectory: true)
    }
}

@MainActor
final class TorrentEngine: ObservableObject {
    static let shared = TorrentEngine()

    @Published private(set) var torrents: [Torrent] = []
    @Published private(set) var stats = SessionStats()
    @Published private(set) var detail: TorrentDetail?
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    @Published var toast: ToastMessage?
    @Published private(set) var isReady = false

    private var session: OpaquePointer?
    private var pollTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var detailID: String?
    private var unfinishedIDs: Set<String> = []
    private var detailTick = 0
    private var forceDetailRefresh = false
    private var hasLoadedSnapshot = false
    private var isShuttingDown = false
    private let decoder = JSONDecoder()

    private init() {
        Preferences.registerDefaults()

        #if DEBUG
        if DemoData.isEnabled {
            isReady = true
            startPolling()
            return
        }
        #endif

        let defaults = UserDefaults.standard
        let downloadPath = Preferences.downloadPath
        let resumeDirectory = Preferences.resumeDirectory

        if defaults.string(forKey: PrefKey.downloadPath) != downloadPath {
            defaults.set(downloadPath, forKey: PrefKey.downloadPath)
        }

        try? FileManager.default.createDirectory(
            atPath: downloadPath,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: resumeDirectory,
            withIntermediateDirectories: true
        )

        let downloadLimit = Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.downloadLimitKB))
        let uploadLimit = Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.uploadLimitKB))
        let port = Preferences.validPort(defaults.integer(forKey: PrefKey.listenPort))
        let dht = defaults.bool(forKey: PrefKey.dhtEnabled)

        session = vt_session_create(
            downloadPath,
            resumeDirectory.path,
            port,
            downloadLimit,
            uploadLimit,
            dht ? 1 : 0
        )

        isReady = session != nil

        if session == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showToast(
                    "Impossibile avviare il motore BitTorrent",
                    kind: .error,
                    detail: "Controlla che libtorrent-rasterbar sia installata."
                )
            }
        } else {
            startPolling()
        }
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Public API

    func addMagnet(
        _ uri: String,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard let session else { return "Motore non disponibile." }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("magnet:") else {
            let message = "Il link magnet non è valido."
            showToast(message, kind: .error)
            return message
        }

        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? "Cartella di destinazione non valida."
            showToast(message, kind: .error)
            return message
        }

        let result = trimmed.withCString { uriPointer in
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

        if result != 0 {
            let message = localizedError(takeLastError())
            showToast(message, kind: .error)
            return message
        }

        showToast("Torrent aggiunto", kind: .success)
        poll()
        return nil
    }

    func addTorrentFile(
        _ url: URL,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard let session else { return "Motore non disponibile." }
        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? "Cartella di destinazione non valida."
            showToast(message, kind: .error)
            return message
        }

        let result = url.path.withCString { filePointer in
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

        if result != 0 {
            let message = localizedError(takeLastError())
            showToast(message, kind: .error)
            return message
        }

        showToast("Torrent aggiunto", kind: .success, detail: url.deletingPathExtension().lastPathComponent)
        poll()
        return nil
    }

    func togglePause(_ torrent: Torrent) {
        _ = control(torrent.paused ? "resume" : "pause", id: torrent.id)
    }

    func pause(_ torrent: Torrent) {
        _ = control("pause", id: torrent.id)
    }

    func resume(_ torrent: Torrent) {
        _ = control("resume", id: torrent.id)
    }

    func reannounce(_ torrent: Torrent) {
        if control("reannounce", id: torrent.id) {
            showToast("Annuncio inviato ai tracker", kind: .info)
        }
    }

    func toggleSequential(_ torrent: Torrent) {
        _ = control(torrent.sequential ? "sequential_off" : "sequential_on", id: torrent.id)
    }

    func remove(_ torrent: Torrent, deleteFiles: Bool) {
        if control(deleteFiles ? "remove_files" : "remove", id: torrent.id) {
            if detailID == torrent.id {
                select(nil)
            }
            showToast(
                deleteFiles ? "Torrent e file rimossi" : "Torrent rimosso",
                kind: .info,
                detail: torrent.name
            )
        }
    }

    func select(_ id: String?) {
        detailID = id
        detailTick = 0
        detail = nil
        if let id {
            loadDetail(id)
        } else {
            detail = nil
        }
    }

    func setFilePriority(_ file: TorrentFile, wanted: Bool, torrentID: String) {
        guard let session else { return }
        let result = torrentID.withCString { idPointer in
            vt_set_file_priority(session, idPointer, Int32(file.index), wanted ? 4 : 0)
        }
        if result != 0 {
            showToast(localizedError(takeLastError()), kind: .error)
        }
        forceDetailRefresh = true
        poll()
    }

    func magnetURI(for torrent: Torrent) -> String {
        guard let session else { return "" }
        let pointer = torrent.id.withCString { vt_magnet_uri(session, $0) }
        return string(from: pointer) ?? ""
    }

    func copyMagnet(for torrent: Torrent) {
        let uri = magnetURI(for: torrent)
        guard !uri.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uri, forType: .string)
        showToast("Link magnet copiato", kind: .info)
    }

    func reveal(_ torrent: Torrent) {
        let direct = URL(fileURLWithPath: torrent.savePath).appendingPathComponent(torrent.name)
        if FileManager.default.fileExists(atPath: direct.path) {
            NSWorkspace.shared.activateFileViewerSelecting([direct])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: torrent.savePath))
        }
    }

    func applySettings() {
        guard let session else { return }
        let defaults = UserDefaults.standard
        let path = Preferences.downloadPath
        if defaults.string(forKey: PrefKey.downloadPath) != path {
            defaults.set(path, forKey: PrefKey.downloadPath)
        }
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        let downloadLimit = Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.downloadLimitKB))
        let uploadLimit = Preferences.limitBytes(fromKB: defaults.integer(forKey: PrefKey.uploadLimitKB))
        let port = Preferences.validPort(defaults.integer(forKey: PrefKey.listenPort))
        let dht = defaults.bool(forKey: PrefKey.dhtEnabled)
        let upnp = defaults.bool(forKey: PrefKey.upnpEnabled)

        _ = vt_apply_settings(
            session,
            port,
            downloadLimit,
            uploadLimit,
            dht ? 1 : 0,
            upnp ? 1 : 0
        )
        poll()
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func showToast(_ text: String, kind: ToastMessage.Kind = .info, detail: String? = nil) {
        let message = ToastMessage(kind: kind, text: text, detail: detail)
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        pollTask?.cancel()
        pollTask = nil
        toastTask?.cancel()
        if let session {
            vt_session_destroy(session)
            self.session = nil
        }
        isReady = false
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.poll()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func poll() {
        #if DEBUG
        if DemoData.isEnabled {
            applyDemoSnapshot()
            return
        }
        #endif

        guard !isShuttingDown, let session else { return }
        vt_session_poll(session)

        guard let pointer = vt_snapshot_json(session) else { return }
        let json = String(cString: pointer)
        vt_free_string(pointer)

        guard let data = json.data(using: .utf8),
              let snapshot = try? decoder.decode(VertexSnapshot.self, from: data) else {
            return
        }

        // Notify only for torrents we have seen actively unfinished (not while verifying),
        // so resumed torrents settling after launch don't trigger a false "completed" toast.
        let finished = Set(snapshot.torrents.filter { $0.finished }.map(\.id))
        let unfinished = Set(snapshot.torrents.filter { !$0.finished && $0.phase != .checking }.map(\.id))
        if hasLoadedSnapshot {
            let newlyFinished = finished.intersection(unfinishedIDs)
            if !newlyFinished.isEmpty {
                let names = snapshot.torrents
                    .filter { newlyFinished.contains($0.id) }
                    .map(\.name)
                if names.count == 1 {
                    showToast("Download completato", kind: .success, detail: names[0])
                } else {
                    showToast("\(names.count) download completati", kind: .success)
                }
            }
        }
        unfinishedIDs = unfinished
        hasLoadedSnapshot = true

        torrents = snapshot.torrents
        stats = snapshot.stats

        downloadHistory.append(Double(snapshot.downloadRate))
        uploadHistory.append(Double(snapshot.uploadRate))
        if downloadHistory.count > 80 {
            downloadHistory.removeFirst(downloadHistory.count - 80)
        }
        if uploadHistory.count > 80 {
            uploadHistory.removeFirst(uploadHistory.count - 80)
        }

        if let id = detailID {
            if snapshot.torrents.contains(where: { $0.id == id }) {
                detailTick += 1
                if forceDetailRefresh || detailTick % 3 == 0 {
                    forceDetailRefresh = false
                    loadDetail(id)
                }
            } else {
                detailID = nil
                detail = nil
            }
        }
    }

    #if DEBUG
    private func applyDemoSnapshot() {
        let list = DemoData.torrents()
        torrents = list
        let down = list.reduce(Int64(0)) { $0 + $1.downloadRate }
        let up = list.reduce(Int64(0)) { $0 + $1.uploadRate }
        stats = SessionStats(
            downloadRate: down,
            uploadRate: up,
            totalDownload: list.reduce(Int64(0)) { $0 + $1.downloaded },
            totalUpload: list.reduce(Int64(0)) { $0 + $1.uploaded },
            active: list.filter { !$0.paused }.count,
            paused: list.filter { $0.paused }.count,
            dhtNodes: 284,
            port: 6881
        )
        downloadHistory = DemoData.history(base: 8_400_000, spread: 0.42)
        uploadHistory = DemoData.history(base: 2_900_000, spread: 0.5)
        hasLoadedSnapshot = true
        if let id = detailID {
            detail = DemoData.detail(for: list.first { $0.id == id })
        }
    }
    #endif

    private func loadDetail(_ id: String) {
        guard let session else {
            detail = nil
            return
        }
        let pointer = id.withCString { vt_detail_json(session, $0) }
        guard let json = string(from: pointer),
              let data = json.data(using: .utf8),
              let decoded = try? decoder.decode(TorrentDetail.self, from: data) else {
            return
        }
        // Avoid republishing identical data: it re-renders the whole inspector.
        if decoded != detail {
            detail = decoded
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func control(_ action: String, id: String) -> Bool {
        guard let session else { return false }
        let result = id.withCString { idPointer in
            action.withCString { actionPointer in
                vt_control(session, idPointer, actionPointer)
            }
        }
        if result != 0 {
            showToast(localizedError(takeLastError()), kind: .error)
            return false
        }
        poll()
        return true
    }

    private func preparedDestination(_ requested: String?) -> (path: String?, error: String?) {
        let raw = requested ?? UserDefaults.standard.string(forKey: PrefKey.downloadPath)
        let path = Preferences.resolvedDownloadPath(raw)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            return (nil, "Impossibile creare la cartella di destinazione.")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (nil, "La destinazione non è una cartella.")
        }
        guard fileManager.isWritableFile(atPath: path) else {
            return (nil, "La cartella di destinazione non è scrivibile.")
        }

        return (path, nil)
    }

    private func takeLastError() -> String {
        guard let session else { return "Errore sconosciuto." }
        let pointer = vt_last_error(session)
        return string(from: pointer) ?? "Errore sconosciuto."
    }

    private func string(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    private func localizedError(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Operazione non riuscita." }
        let lower = value.lowercased()
        if lower.contains("already exists") || lower.contains("duplicate") { return "Questo torrent è già presente." }
        if lower.contains("no such file") { return "File non trovato." }
        if lower.contains("permission") { return "Permesso negato." }
        if lower.contains("invalid") || lower.contains("parse") { return "Link o file non valido." }
        return value
    }
}
