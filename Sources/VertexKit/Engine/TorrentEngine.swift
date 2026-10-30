import AppKit
import CTorrent
import Darwin
import Foundation

package enum PrefKey {
    package static let downloadPath = "downloadPath"
    package static let downloadLimitKB = "downloadLimitKB"
    package static let uploadLimitKB = "uploadLimitKB"
    package static let listenPort = "listenPort"
    package static let bindAddress = "bindAddress"
    package static let dhtEnabled = "dhtEnabled"
    package static let pexEnabled = "pexEnabled"
    package static let lsdEnabled = "lsdEnabled"
    package static let upnpEnabled = "upnpEnabled"
    package static let startPaused = "startPaused"
    package static let sequentialDefault = "sequentialDefault"
    package static let appearance = "appearance"
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

    /// Whether a port can be used for TCP/UDP listening.
    package static func isValidPort(_ value: Int) -> Bool {
        (1...65535).contains(value)
    }

    /// Valid TCP/UDP port, falling back to the BitTorrent default.
    package static func validPort(_ value: Int) -> Int32 {
        isValidPort(value) ? Int32(value) : 6881
    }

    /// Whether a value is a literal IPv4 address. Device names ("utun3") and
    /// hostnames are rejected on purpose: the engine passes the value straight
    /// to libtorrent, and only a literal address pins both the listening socket
    /// and the outgoing source.
    package static func isValidIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
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
}

/// Single source of truth for preference defaults. `registerDefaults()` feeds
/// them to `UserDefaults`, and the views use the same constants as the initial
/// value of their `@AppStorage` properties.
package enum PrefDefault {
    package static let downloadPath: String = Preferences.suggestedDownloadPath
    package static let downloadLimitKB = 0
    package static let uploadLimitKB = 0
    package static let listenPort = 6881
    /// Empty means every interface. Otherwise a literal IPv4 address, usually
    /// the tunnel address, so the client only exchanges traffic through it.
    package static let bindAddress = ""
    package static let dhtEnabled = true
    package static let pexEnabled = true
    package static let lsdEnabled = true
    package static let upnpEnabled = true
    package static let startPaused = false
    package static let sequentialDefault = false
    package static let appearance = "dark"

    package static var dictionary: [String: Any] {
        [
            PrefKey.downloadPath: downloadPath,
            PrefKey.downloadLimitKB: downloadLimitKB,
            PrefKey.uploadLimitKB: uploadLimitKB,
            PrefKey.listenPort: listenPort,
            PrefKey.bindAddress: bindAddress,
            PrefKey.dhtEnabled: dhtEnabled,
            PrefKey.pexEnabled: pexEnabled,
            PrefKey.lsdEnabled: lsdEnabled,
            PrefKey.upnpEnabled: upnpEnabled,
            PrefKey.startPaused: startPaused,
            PrefKey.sequentialDefault: sequentialDefault,
            PrefKey.appearance: appearance
        ]
    }
}

package struct SessionConfiguration: Sendable {
    package var downloadPath: String
    package var resumePath: String
    package var port: Int32
    package var downloadLimit: Int32
    package var uploadLimit: Int32
    package var dht: Bool
    package var pex: Bool
    package var lsd: Bool
    package var upnp: Bool
    /// Local address the session is pinned to; empty means every interface.
    package var bindAddress: String

    package init(
        downloadPath: String,
        resumePath: String,
        port: Int32,
        downloadLimit: Int32 = 0,
        uploadLimit: Int32 = 0,
        dht: Bool = false,
        pex: Bool = false,
        lsd: Bool = false,
        upnp: Bool = false,
        bindAddress: String = ""
    ) {
        self.downloadPath = downloadPath
        self.resumePath = resumePath
        self.port = port
        self.downloadLimit = downloadLimit
        self.uploadLimit = uploadLimit
        self.dht = dht
        self.pex = pex
        self.lsd = lsd
        self.upnp = upnp
        self.bindAddress = bindAddress
    }
}

/// A session pointer is only handed to one lifecycle queue at a time. The box
/// makes that ownership explicit to the compiler; libtorrent itself is
/// thread-safe and the pointer is not used by the UI while it is in flight.
private final class SessionPointerBox: @unchecked Sendable {
    let value: OpaquePointer?

    init(_ value: OpaquePointer?) {
        self.value = value
    }

    func destroy() {
        if let value {
            vt_session_destroy(value)
        }
    }
}

@MainActor
package final class TorrentEngine: ObservableObject {
    package static let shared = TorrentEngine()

    /// Data refreshed by the poll. Publishing a single value avoids four
    /// separate `objectWillChange` notifications and intermediate UI states.
    struct PollState {
        var torrents: [Torrent] = []
        var stats = SessionStats()
        var downloadHistory: [Double] = []
        var uploadHistory: [Double] = []
        var torrentsByID: [String: Torrent] = [:]
    }

    @Published private(set) var pollState = PollState()
    @Published private(set) var detail: TorrentDetail?

    package var torrents: [Torrent] { pollState.torrents }
    package var stats: SessionStats { pollState.stats }
    package var downloadHistory: [Double] { pollState.downloadHistory }
    package var uploadHistory: [Double] { pollState.uploadHistory }

    package func torrent(withID id: String) -> Torrent? {
        pollState.torrentsByID[id]
    }
    @Published var toast: ToastMessage?
    @Published private(set) var isReady = false
    @Published private(set) var isRestartingSession = false
    /// Torrent shown in the inspector. It is the single source of truth for
    /// the selection: `RootView` reads it instead of keeping a parallel copy.
    @Published private(set) var selectedID: String?

    private var session: OpaquePointer?
    private var pollTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var settingsApplyTask: Task<Void, Never>?
    private var unfinishedIDs: Set<String> = []
    private var detailTick = 0
    private var forceDetailRefresh = false
    private var hasLoadedSnapshot = false
    private var isShuttingDown = false
    private var sessionPexEnabled = true
    private var shutdownCompletion: (() -> Void)?
    private var isShutdownComplete = false
    /// All `vt_*` calls run on this serial queue. Creating, polling, reading
    /// details and destroying a session are therefore ordered, and the poll no
    /// longer blocks the main actor.
    private let sessionQueue = DispatchQueue(
        label: "com.vertex.session",
        qos: .userInitiated
    )
    private let decoder = JSONDecoder()
    private var isPollInFlight = false
    private var sessionGeneration = 0
    private var nextPollID = 0
    private var lastAppliedPollID = 0
    private var configurationOverride: SessionConfiguration?

    private init() {
        Preferences.registerDefaults()

        #if DEBUG
        if DemoData.isEnabled {
            isReady = true
            startPolling()
            return
        }
        #endif

        let configuration = Self.currentConfiguration()
        sessionPexEnabled = configuration.pex
        session = Self.makeSession(configuration)
        isReady = session != nil

        if session == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showToast(
                    L("Impossibile avviare il motore BitTorrent"),
                    kind: .error,
                    detail: L("Il motore incluso nell'app non è riuscito ad avviarsi. Riavvia Vertex; se il problema persiste, reinstalla l'app.")
                )
            }
        } else {
            startPolling()
        }
    }

    #if DEBUG
    /// Test-only initializer: it uses an explicit configuration instead of the
    /// user's preferences and never starts a polling task unless asked to.
    package init(configuration: SessionConfiguration, startPollingImmediately: Bool = false) {
        Preferences.registerDefaults()
        configurationOverride = configuration
        sessionPexEnabled = configuration.pex
        session = Self.makeSession(configuration)
        isReady = session != nil
        if isReady && startPollingImmediately {
            startPolling()
        }
    }
    #endif

    /// Snapshot of the preferences used to create a libtorrent session.
    /// It is read before handing the work to the session lifecycle queue.
    nonisolated private static func currentConfiguration() -> SessionConfiguration {
        let defaults = UserDefaults.standard
        let downloadPath = Preferences.downloadPath

        if defaults.string(forKey: PrefKey.downloadPath) != downloadPath {
            defaults.set(downloadPath, forKey: PrefKey.downloadPath)
        }

        let rawPort = defaults.integer(forKey: PrefKey.listenPort)
        let port = Preferences.validPort(rawPort)
        if Int(port) != rawPort {
            defaults.set(Int(port), forKey: PrefKey.listenPort)
        }

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

        let rawBind = defaults.string(forKey: PrefKey.bindAddress)
        let bindAddress = Preferences.normalizedBindAddress(rawBind)
        if rawBind != bindAddress {
            defaults.set(bindAddress, forKey: PrefKey.bindAddress)
        }

        return SessionConfiguration(
            downloadPath: downloadPath,
            resumePath: Preferences.resumeDirectory.path,
            port: port,
            downloadLimit: downloadLimit,
            uploadLimit: uploadLimit,
            dht: defaults.bool(forKey: PrefKey.dhtEnabled),
            pex: defaults.bool(forKey: PrefKey.pexEnabled),
            lsd: defaults.bool(forKey: PrefKey.lsdEnabled),
            upnp: defaults.bool(forKey: PrefKey.upnpEnabled),
            bindAddress: bindAddress
        )
    }

    /// Creates and configures a session. This runs off the main actor when
    /// called by the lifecycle queue, so libtorrent I/O cannot block the UI.
    nonisolated private static func makeSession(_ configuration: SessionConfiguration) -> OpaquePointer? {
        do {
            try FileManager.default.createDirectory(
                atPath: configuration.downloadPath,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                atPath: configuration.resumePath,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        return configuration.downloadPath.withCString { downloadPath in
            configuration.resumePath.withCString { resumePath in
                configuration.bindAddress.withCString { bindAddress in
                    vt_session_create_full(
                        downloadPath,
                        resumePath,
                        configuration.port,
                        configuration.downloadLimit,
                        configuration.uploadLimit,
                        configuration.dht ? 1 : 0,
                        configuration.pex ? 1 : 0,
                        configuration.lsd ? 1 : 0,
                        configuration.upnp ? 1 : 0,
                        bindAddress
                    )
                }
            }
        }
    }

    /// PEX is a session plugin in libtorrent: changing it requires recreating
    /// the session. Destruction and creation run off the main thread, and the
    /// previous PEX value is used as a fallback if the new session cannot start.
    private func restartSessionForPeerExchange(
        configuration: SessionConfiguration,
        oldPex: Bool
    ) {
        guard !isRestartingSession, !isShuttingDown else { return }
        isRestartingSession = true
        sessionGeneration += 1
        isPollInFlight = false

        let previousSession = SessionPointerBox(session)
        session = nil
        isReady = false
        hasLoadedSnapshot = false
        unfinishedIDs.removeAll()
        pollTask?.cancel()
        pollTask = nil

        showToast(L("Riavvio del motore BitTorrent…"), kind: .info)

        sessionQueue.async { [self] in
            previousSession.destroy()

            let newSession = SessionPointerBox(Self.makeSession(configuration))
            let fallbackSession: SessionPointerBox?
            if newSession.value == nil, configuration.pex != oldPex {
                var fallbackConfiguration = configuration
                fallbackConfiguration.pex = oldPex
                fallbackSession = SessionPointerBox(Self.makeSession(fallbackConfiguration))
            } else {
                fallbackSession = nil
            }

            DispatchQueue.main.async {
                self.finishSessionRestart(
                    newSession: newSession.value,
                    fallbackSession: fallbackSession?.value,
                    configuration: configuration,
                    oldPex: oldPex
                )
            }
        }
    }

    private func finishSessionRestart(
        newSession: OpaquePointer?,
        fallbackSession: OpaquePointer?,
        configuration: SessionConfiguration,
        oldPex: Bool
    ) {
        isRestartingSession = false

        if isShuttingDown {
            let pointer = SessionPointerBox(newSession ?? fallbackSession)
            sessionQueue.async { [self] in
                pointer.destroy()
                DispatchQueue.main.async { self.completeShutdown() }
            }
            return
        }

        if let newSession {
            session = newSession
            sessionPexEnabled = configuration.pex
            isReady = true
            startPolling()
            poll()
            // Apply changes made while the restart was in progress.
            applySettings()
            return
        }

        // The new session failed. Put the preference back and, when possible,
        // restore a session using the previous PEX value.
        UserDefaults.standard.set(oldPex, forKey: PrefKey.pexEnabled)
        sessionPexEnabled = oldPex

        if let fallbackSession {
            session = fallbackSession
            isReady = true
            startPolling()
            poll()
            showToast(
                L("La modifica a Peer Exchange non è stata applicata."),
                kind: .error,
                detail: L("La sessione precedente è stata ripristinata.")
            )
        } else {
            session = nil
            isReady = false
            pollState = PollState()
            detail = nil
            selectedID = nil
            showToast(
                L("Impossibile riavviare il motore BitTorrent"),
                kind: .error,
                detail: L("La modifica a Peer Exchange non è stata applicata. Riavvia Vertex.")
            )
        }
    }

    private func completeShutdown() {
        guard !isShutdownComplete else { return }
        isShutdownComplete = true
        let completion = shutdownCompletion
        shutdownCompletion = nil
        completion?()
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Public API

    package func addMagnet(
        _ uri: String,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard session != nil else { return L("Motore non disponibile.") }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TorrentInput.isMagnet(trimmed) else {
            let message = L("Il link magnet non è valido.")
            showToast(message, kind: .error)
            return message
        }

        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? L("Cartella di destinazione non valida.")
            showToast(message, kind: .error)
            return message
        }

        let result = withSession { session in
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
        guard let result else { return L("Motore non disponibile.") }

        if result != 0 {
            let message = localizedError(takeLastError())
            showToast(message, kind: .error)
            return message
        }

        showToast(L("Torrent aggiunto"), kind: .success)
        poll()
        return nil
    }

    package func addTorrentFile(
        _ url: URL,
        destination: String?,
        startPaused: Bool,
        sequential: Bool
    ) -> String? {
        guard session != nil else { return L("Motore non disponibile.") }
        let prepared = preparedDestination(destination)
        guard let path = prepared.path else {
            let message = prepared.error ?? L("Cartella di destinazione non valida.")
            showToast(message, kind: .error)
            return message
        }

        let result = withSession { session in
            url.path.withCString { filePointer in
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
        guard let result else { return L("Motore non disponibile.") }

        if result != 0 {
            let message = localizedError(takeLastError())
            showToast(message, kind: .error)
            return message
        }

        showToast(L("Torrent aggiunto"), kind: .success, detail: url.deletingPathExtension().lastPathComponent)
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
            showToast(L("Annuncio inviato ai tracker"), kind: .info)
        }
    }

    func toggleSequential(_ torrent: Torrent) {
        _ = control(torrent.sequential ? "sequential_off" : "sequential_on", id: torrent.id)
    }

    func remove(_ torrent: Torrent, deleteFiles: Bool) {
        if control(deleteFiles ? "remove_files" : "remove", id: torrent.id) {
            if selectedID == torrent.id {
                select(nil)
            }
            showToast(
                L(deleteFiles ? "Torrent e file rimossi" : "Torrent rimosso"),
                kind: .info,
                detail: torrent.name
            )
        }
    }

    func select(_ id: String?) {
        selectedID = id
        detailTick = 0
        detail = nil
        if let id {
            loadDetail(id)
        }
    }

    func setFilePriority(_ file: TorrentFile, wanted: Bool, torrentID: String) {
        guard session != nil else { return }
        let result = withSession { session in
            torrentID.withCString { idPointer in
                vt_set_file_priority(session, idPointer, Int32(file.index), wanted ? 4 : 0)
            }
        }
        guard let result else { return }
        if result != 0 {
            showToast(localizedError(takeLastError()), kind: .error)
        }
        forceDetailRefresh = true
        poll()
    }

    func magnetURI(for torrent: Torrent) -> String {
        withSession { session in
            let pointer = torrent.id.withCString { vt_magnet_uri(session, $0) }
            guard let pointer else { return "" }
            defer { vt_free_string(pointer) }
            return String(cString: pointer)
        } ?? ""
    }

    func copyMagnet(for torrent: Torrent) {
        let uri = magnetURI(for: torrent)
        guard !uri.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uri, forType: .string)
        showToast(L("Link magnet copiato"), kind: .info)
    }

    func reveal(_ torrent: Torrent) {
        let direct = URL(fileURLWithPath: torrent.savePath).appendingPathComponent(torrent.name)
        if FileManager.default.fileExists(atPath: direct.path) {
            NSWorkspace.shared.activateFileViewerSelecting([direct])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: torrent.savePath))
        }
    }

    /// Coalesces the edits of a settings field: applying on every keystroke
    /// rebinds the listening port (and resets the port mapping) for partial
    /// values like `6` or `68`. Closing the sheet still flushes immediately.
    func applySettingsSoon() {
        settingsApplyTask?.cancel()
        settingsApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.settingsApplyTask = nil
            self.applySettings()
        }
    }

    /// Cancels a pending debounced update and applies the current preferences
    /// immediately.
    func applySettingsNow() {
        settingsApplyTask?.cancel()
        settingsApplyTask = nil
        applySettings()
    }

    func applySettings() {
        guard !isShuttingDown, !isRestartingSession, session != nil else { return }

        let configuration: SessionConfiguration
        if let configurationOverride {
            configuration = configurationOverride
        } else {
            let defaults = UserDefaults.standard
            let rawPort = defaults.integer(forKey: PrefKey.listenPort)
            guard Preferences.isValidPort(rawPort) else {
                showToast(
                    L("Porta non valida"),
                    kind: .error,
                    detail: L("Inserisci un valore tra 1 e 65535.")
                )
                return
            }
            guard Preferences.isValidLimitKB(defaults.integer(forKey: PrefKey.downloadLimitKB)),
                  Preferences.isValidLimitKB(defaults.integer(forKey: PrefKey.uploadLimitKB)) else {
                showToast(
                    L("Limite non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 o un valore positivo entro il massimo consentito.")
                )
                return
            }
            configuration = Self.currentConfiguration()
        }

        if configuration.pex != sessionPexEnabled {
            restartSessionForPeerExchange(configuration: configuration, oldPex: sessionPexEnabled)
            return
        }

        // Keep the C++ fallback destination in sync with the preferences. It is
        // used by resume-data loading and by callers that omit a save path.
        let result = withSession { session -> Int32 in
            _ = configuration.downloadPath.withCString {
                vt_set_default_save_path(session, $0)
            }
            return configuration.bindAddress.withCString { bindAddress in
                vt_apply_settings_ex(
                    session,
                    configuration.port,
                    configuration.downloadLimit,
                    configuration.uploadLimit,
                    configuration.dht ? 1 : 0,
                    configuration.upnp ? 1 : 0,
                    configuration.lsd ? 1 : 0,
                    bindAddress
                )
            }
        }
        guard let result else { return }
        if result != 0 {
            showToast(
                L("Impostazioni non applicate"),
                kind: .error,
                detail: localizedError(takeLastError())
            )
        }
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

    package func shutdown(completion: (() -> Void)? = nil) {
        if isShuttingDown {
            if isShutdownComplete {
                completion?()
            } else if let completion {
                shutdownCompletion = completion
            }
            return
        }

        isShuttingDown = true
        sessionGeneration += 1
        isPollInFlight = false
        shutdownCompletion = completion
        pollTask?.cancel()
        pollTask = nil
        toastTask?.cancel()
        settingsApplyTask?.cancel()
        settingsApplyTask = nil

        if isRestartingSession {
            return
        }

        let previousSession = SessionPointerBox(session)
        session = nil
        isReady = false
        sessionQueue.async { [self] in
            previousSession.destroy()
            DispatchQueue.main.async { self.completeShutdown() }
        }
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

    private func finishPoll(_ snapshot: VertexSnapshot?, id: Int, generation: Int) {
        isPollInFlight = false
        guard generation == sessionGeneration, id >= lastAppliedPollID, !isShuttingDown else {
            return
        }
        lastAppliedPollID = id
        guard let snapshot else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: VertexSnapshot) {
        // Notify only for torrents we have seen actively unfinished (not while verifying),
        // so resumed torrents settling after launch don't trigger a false "completed" toast.
        let finished = Set(snapshot.torrents.filter { $0.finished }.map(\.id))
        // stateCode 1 = checking files, 7 = checking resume data. `phase` can't be used here
        // because it reports .paused before .checking.
        let unfinished = Set(snapshot.torrents.filter {
            !$0.finished && $0.stateCode != 1 && $0.stateCode != 7
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
        next.downloadHistory.append(Double(snapshot.downloadRate))
        next.uploadHistory.append(Double(snapshot.uploadRate))
        if next.downloadHistory.count > 80 {
            next.downloadHistory.removeFirst(next.downloadHistory.count - 80)
        }
        if next.uploadHistory.count > 80 {
            next.uploadHistory.removeFirst(next.uploadHistory.count - 80)
        }
        pollState = next

        if let id = selectedID {
            if next.torrentsByID[id] != nil {
                detailTick += 1
                if forceDetailRefresh || detailTick % 3 == 0 {
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
    private func applyDemoSnapshot() {
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

    private func loadDetail(_ id: String) {
        guard selectedID == id, !isShuttingDown, let session else {
            if selectedID == id {
                detail = nil
            }
            return
        }
        let generation = sessionGeneration
        let json = sessionQueue.sync { Self.readDetailJSON(session, id: id) }
        applyDetailJSON(json, id: id, generation: generation)
    }

    private func applyDetailJSON(_ json: String?, id: String, generation: Int? = nil) {
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

    #if DEBUG
    package func pollNowForTesting() {
        guard !isShuttingDown, let session else { return }
        nextPollID += 1
        let pollID = nextPollID
        let generation = sessionGeneration
        let snapshot = sessionQueue.sync { Self.readSnapshot(session) }
        finishPoll(snapshot, id: pollID, generation: generation)
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

    // MARK: - Helpers

    /// Serializes a synchronous bridge call with the background poll.
    private func withSession<T>(_ body: (OpaquePointer) -> T) -> T? {
        guard let session else { return nil }
        return sessionQueue.sync {
            body(session)
        }
    }

    nonisolated private static func readSnapshot(_ session: OpaquePointer) -> VertexSnapshot? {
        vt_session_poll(session)
        guard let pointer = vt_snapshot_json(session) else { return nil }
        let json = String(cString: pointer)
        vt_free_string(pointer)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VertexSnapshot.self, from: data)
    }

    nonisolated private static func readDetailJSON(
        _ session: OpaquePointer,
        id: String
    ) -> String? {
        let pointer = id.withCString { vt_detail_json(session, $0) }
        guard let pointer else { return nil }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    @discardableResult
    private func control(_ action: String, id: String) -> Bool {
        guard session != nil else { return false }
        let result = withSession { session in
            id.withCString { idPointer in
                action.withCString { actionPointer in
                    vt_control(session, idPointer, actionPointer)
                }
            }
        }
        guard let result else { return false }
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
            return (nil, L("Impossibile creare la cartella di destinazione."))
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (nil, L("La destinazione non è una cartella."))
        }
        guard fileManager.isWritableFile(atPath: path) else {
            return (nil, L("La cartella di destinazione non è scrivibile."))
        }

        return (path, nil)
    }

    private func takeLastError() -> String {
        let raw = withSession { session -> String in
            guard let pointer = vt_last_error(session) else { return "" }
            defer { vt_free_string(pointer) }
            return String(cString: pointer)
        } ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("Errore sconosciuto.")
            : raw
    }

    private func localizedError(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return L("Operazione non riuscita.") }
        let lower = value.lowercased()
        if lower.contains("already exists") || lower.contains("duplicate") { return L("Questo torrent è già presente.") }
        if lower.contains("no such file") { return L("File non trovato.") }
        if lower.contains("permission") { return L("Permesso negato.") }
        if lower.contains("invalid") || lower.contains("parse") { return L("Link o file non valido.") }
        switch value {
        case "Torrent non trovato": return L("Torrent non trovato")
        case "Comando non supportato": return L("Comando non supportato")
        case "Errore sconosciuto": return L("Errore sconosciuto")
        default: return value
        }
    }
}
