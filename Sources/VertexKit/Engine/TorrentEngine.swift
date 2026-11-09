import AppKit
import CTorrent
import Foundation

/// A session pointer is only handed to one lifecycle queue at a time. The box
/// makes that ownership explicit to the compiler; libtorrent itself is
/// thread-safe and the pointer is not used by the UI while it is in flight.
final class SessionPointerBox: @unchecked Sendable {
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

private struct SessionCreationResult {
    let pointer: OpaquePointer?
    let error: String?
}

@MainActor
package final class TorrentEngine: ObservableObject {
    package static let shared = TorrentEngine()

    @Published var pollState = PollState()
    @Published var detail: TorrentDetail?

    package var torrents: [Torrent] { pollState.torrents }
    package var stats: SessionStats { pollState.stats }
    package var downloadHistory: [Double] { pollState.downloadHistory }
    package var uploadHistory: [Double] { pollState.uploadHistory }

    package func torrent(withID id: String) -> Torrent? {
        pollState.torrentsByID[id]
    }

    @Published var toast: ToastMessage?
    @Published var isReady = false
    /// Readiness exposed to the `Vertex` executable target (AppDelegate waits
    /// for the session before consuming files opened from Finder).
    package var isEngineReady: Bool { isReady }
    package var engineStartupError: String? { startupError }
    @Published var isStarting = false
    @Published var startupError: String?
    @Published var isRestartingSession = false
    /// Torrent shown in the inspector. It is the single source of truth for
    /// the selection: `RootView` reads it instead of keeping a parallel copy.
    @Published var selectedID: String?

    var session: OpaquePointer?
    var pollTask: Task<Void, Never>?
    var toastTask: Task<Void, Never>?
    var settingsApplyTask: Task<Void, Never>?
    var unfinishedIDs: Set<String> = []
    var detailTick = 0
    var forceDetailRefresh = false
    /// True after the first snapshot has been applied. Published so the list
    /// can show a loading placeholder instead of flashing the empty state.
    @Published var hasLoadedSnapshot = false
    var isShuttingDown = false
    var sessionPexEnabled = true
    var shutdownCompletions: [() -> Void] = []
    var isShutdownComplete = false
    /// All `vt_*` calls run on this serial queue. Creating, polling, reading
    /// details and destroying a session are therefore ordered, and the poll no
    /// longer blocks the main actor.
    let sessionQueue = DispatchQueue(
        label: "com.vertex.session",
        qos: .userInitiated
    )
    let decoder = JSONDecoder()
    var isPollInFlight = false
    var sessionGeneration = 0
    var nextPollID = 0
    var lastAppliedPollID = 0
    var configurationOverride: SessionConfiguration?
    var lastAppliedConfiguration: SessionConfiguration?
    var proxyCheckTick = 0
    var proxyHealthError: String?
    var isProxyProbeInFlight = false
    /// Errors shown in the last few seconds. libtorrent reports an add failure
    /// twice (synchronously and through add_torrent_alert); the alert path uses
    /// this to avoid showing the same message again.
    /// Called when a download completes while Vertex is not the active app.
    /// Injected so the engine stays testable: the default bounces the Dock icon,
    /// which needs no notification authorization (unlike UNUserNotificationCenter,
    /// which also requires a Developer ID signed bundle).
    var completionAttention: () -> Void = {
        // `NSApp` is nil until the application object exists (never the case in
        // the headless test runner), and `isRunning` keeps the request out of
        // processes without a run loop.
        guard let app = NSApp, app.isRunning, !app.isActive else { return }
        app.requestUserAttention(.informationalRequest)
    }

    var recentErrorToasts: [String: Date] = [:]
    private static let errorToastDedupWindow: TimeInterval = 8

    private init() {
        Preferences.registerDefaults()

        #if DEBUG
        if DemoData.isEnabled {
            isReady = true
            applyDemoSnapshot()
            startPolling()
            return
        }
        #endif

        startSession()
    }

    /// Starts the libtorrent session on the serial session queue. Loading the
    /// resume directory and creating a session can take seconds with a large
    /// library, so it must not run on the main actor.
    ///
    /// The preference validation and the configuration snapshot are part of the
    /// same block: `validateAllPreferences` reads the Keychain (proxy password)
    /// and `currentConfiguration` must see the warmed cache, so both belong off
    /// the main thread.
    private func startSession(configuration: SessionConfiguration? = nil) {
        isStarting = true
        startupError = nil
        sessionQueue.async { [self] in
            Self.validateAllPreferences()
            let configuration = configuration ?? Self.currentConfiguration()
            let creation = Self.makeSession(configuration)
            DispatchQueue.main.async {
                self.finishStartup(creation, configuration: configuration)
            }
        }
    }

    private func finishStartup(
        _ creation: SessionCreationResult,
        configuration: SessionConfiguration
    ) {
        isStarting = false

        if isShuttingDown {
            let pointer = SessionPointerBox(creation.pointer)
            sessionQueue.async { pointer.destroy() }
            return
        }

        guard let newSession = creation.pointer else {
            startupError = Self.sessionFailureDetail(
                creation.error,
                fallback: L("Il motore incluso nell'app non è riuscito ad avviarsi. Riavvia Vertex; se il problema persiste, reinstalla l'app.")
            )
            isReady = false
            return
        }

        session = newSession
        sessionPexEnabled = configuration.pex
        isReady = true
        startupError = nil
        lastAppliedConfiguration = configuration
        startPolling()
    }

    /// Retries the initial session creation after a failure. The persistent
    /// error view calls this; it is a no-op while a session or a startup is in
    /// flight.
    package func retryStartup() {
        guard !isStarting, !isShuttingDown, session == nil else { return }
        startSession(configuration: configurationOverride)
    }

    #if DEBUG
    /// Test-only initializer: it uses an explicit configuration instead of the
    /// user's preferences and never starts a polling task unless asked to.
    package init(configuration: SessionConfiguration, startPollingImmediately: Bool = false) {
        Preferences.registerDefaults()
        configurationOverride = configuration
        sessionPexEnabled = configuration.pex
        session = Self.makeSession(configuration).pointer
        isReady = session != nil
        if isReady {
            lastAppliedConfiguration = configuration
        }
        if isReady && startPollingImmediately {
            startPolling()
        }
    }
    #endif

    // MARK: - Session Lifecycle

    /// Creates and configures a session. This runs off the main actor when
    /// called by the lifecycle queue, so libtorrent I/O cannot block the UI.
    nonisolated private static func makeSession(
        _ configuration: SessionConfiguration
    ) -> SessionCreationResult {
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
            return SessionCreationResult(pointer: nil, error: error.localizedDescription)
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let pointer = configuration.downloadPath.withCString { downloadPath in
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
                        bindAddress,
                        &errorPointer
                    )
                }
            }
        }

        let error = errorPointer.map { String(cString: $0) }
        if let errorPointer {
            vt_free_string(errorPointer)
        }

        if let pointer, configuration.proxyEnabled {
            configuration.proxyHost.withCString { hostPointer in
                configuration.proxyUser.withCString { userPointer in
                    configuration.proxyPassword.withCString { passPointer in
                        _ = vt_apply_proxy_settings(
                            pointer,
                            1,
                            hostPointer,
                            configuration.proxyPort,
                            userPointer,
                            passPointer
                        )
                    }
                }
            }
        }

        return SessionCreationResult(pointer: pointer, error: error)
    }

    func recordErrorToast(_ text: String) {
        let now = Date()
        recentErrorToasts = recentErrorToasts.filter {
            now.timeIntervalSince($0.value) < Self.errorToastDedupWindow
        }
        recentErrorToasts[text] = now
    }

    func hasRecentErrorToast(_ text: String) -> Bool {
        guard let shown = recentErrorToasts[text] else { return false }
        return Date().timeIntervalSince(shown) < Self.errorToastDedupWindow
    }

    private static func sessionFailureDetail(_ error: String?, fallback: String) -> String {
        guard let error,
              !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return fallback + "\n" + error
    }

    /// PEX is a session plugin in libtorrent: changing it requires recreating
    /// the session. Destruction and creation run off the main thread, and the
    /// previous PEX value is used as a fallback if the new session cannot start.
    func restartSessionForPeerExchange(
        configuration: SessionConfiguration,
        oldPex: Bool
    ) {
        guard !isRestartingSession, !isShuttingDown else { return }
        isRestartingSession = true
        sessionGeneration += 1
        isPollInFlight = false
        // The new session is a different libtorrent instance: poll IDs from
        // before the restart are stale. Resetting here keeps the guard in
        // `finishPoll` meaningful instead of relying on the monotonic counter
        // to outlive the restart by accident.
        lastAppliedPollID = 0

        let previousSession = SessionPointerBox(session)
        session = nil
        lastAppliedConfiguration = nil
        isReady = false
        hasLoadedSnapshot = false
        unfinishedIDs.removeAll()
        pollTask?.cancel()
        pollTask = nil

        showToast(L("Riavvio del motore BitTorrent…"), kind: .info)

        sessionQueue.async { [self] in
            previousSession.destroy()

            let creation = Self.makeSession(configuration)
            let newSession = SessionPointerBox(creation.pointer)
            let fallbackSession: SessionPointerBox?
            if newSession.value == nil, configuration.pex != oldPex {
                var fallbackConfiguration = configuration
                fallbackConfiguration.pex = oldPex
                fallbackSession = SessionPointerBox(Self.makeSession(fallbackConfiguration).pointer)
            } else {
                fallbackSession = nil
            }

            DispatchQueue.main.async {
                self.finishSessionRestart(
                    newSession: newSession.value,
                    fallbackSession: fallbackSession?.value,
                    configuration: configuration,
                    oldPex: oldPex,
                    creationError: creation.error
                )
            }
        }
    }

    private func finishSessionRestart(
        newSession: OpaquePointer?,
        fallbackSession: OpaquePointer?,
        configuration: SessionConfiguration,
        oldPex: Bool,
        creationError: String?
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
                detail: Self.sessionFailureDetail(
                    creationError,
                    fallback: L("La sessione precedente è stata ripristinata.")
                )
            )
        } else {
            session = nil
            lastAppliedConfiguration = nil
            isReady = false
            pollState = PollState()
            detail = nil
            selectedID = nil
            showToast(
                L("Impossibile riavviare il motore BitTorrent"),
                kind: .error,
                detail: Self.sessionFailureDetail(
                    creationError,
                    fallback: L("La modifica a Peer Exchange non è stata applicata. Riavvia Vertex.")
                )
            )
        }
    }

    package func shutdown(completion: (() -> Void)? = nil) {
        if isShuttingDown {
            if isShutdownComplete {
                completion?()
            } else if let completion {
                shutdownCompletions.append(completion)
            }
            return
        }

        isShuttingDown = true
        sessionGeneration += 1
        isPollInFlight = false
        shutdownCompletions = completion.map { [$0] } ?? []
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
        lastAppliedConfiguration = nil
        isReady = false
        sessionQueue.async { [self] in
            previousSession.destroy()
            DispatchQueue.main.async { self.completeShutdown() }
        }
    }

    private func completeShutdown() {
        guard !isShutdownComplete else { return }
        isShutdownComplete = true
        let completions = shutdownCompletions
        shutdownCompletions.removeAll()
        for completion in completions {
            completion()
        }
    }

    // MARK: - Queue Primitives

    /// Serializes a synchronous bridge call with the background poll.
    func withSession<T>(_ body: (OpaquePointer) -> T) -> T? {
        guard let session else { return nil }
        return sessionQueue.sync {
            body(session)
        }
    }

    nonisolated static func readLastError(_ session: OpaquePointer) -> String {
        guard let pointer = vt_last_error(session) else { return "" }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    /// Runs `operation` on the session queue and reports the outcome on the
    /// main actor. Returns false when the command cannot be queued at all (no
    /// session, or the engine is shutting down), so callers that need to answer
    /// the user immediately can do it without waiting for a callback.
    @discardableResult
    func enqueueSessionOperation(
        errorTitle: String? = nil,
        operation: @escaping @Sendable (OpaquePointer) -> Int32,
        onSuccess: (@MainActor () -> Void)? = nil,
        onFailure: (@MainActor (String) -> Void)? = nil
    ) -> Bool {
        guard !isShuttingDown, let session else { return false }
        let generation = sessionGeneration
        let pointer = SessionPointerBox(session)
        sessionQueue.async { [weak self] in
            guard let s = pointer.value else { return }
            let code = operation(s)
            let rawError = code != 0 ? Self.readLastError(s) : ""
            DispatchQueue.main.async {
                guard let self else { return }
                guard !self.isShuttingDown, self.sessionGeneration == generation else {
                    // The engine was shut down or restarted while the command
                    // was in flight: the caller must not wait forever for an
                    // outcome that no longer exists.
                    if !self.isShuttingDown {
                        onFailure?(L("Motore non disponibile."))
                    }
                    return
                }
                if code != 0 {
                    let message = self.localizedError(
                        rawError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? L("Errore sconosciuto.")
                            : rawError
                    )
                    if let onFailure {
                        onFailure(message)
                    } else if let errorTitle {
                        self.showToast(errorTitle, kind: .error, detail: message)
                    } else {
                        self.showToast(message, kind: .error)
                    }
                    return
                }
                onSuccess?()
            }
        }
        return true
    }
}
