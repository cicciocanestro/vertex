import AppKit
import CTorrent
import Foundation

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
    /// Torrent shown in the inspector (non-nil iff exactly one row is selected).
    @Published var selectedID: String?
    /// Full set of selected torrent IDs (`⌘-Click`, `⇧-Click`, `⌘A`).
    @Published package var selectedIDs: Set<String> = []
    var selectionAnchorID: String?

    /// Owns the libtorrent pointer: see `SessionController`. Internal so the
    /// engine extensions (polling, actions) can route calls through the actor.
    let sessionController: SessionController
    /// Mirror of the actor's state for synchronous decisions (command gating,
    /// UI state). The pointer itself never leaves the actor.
    private(set) var hasSession = false
    var pollTask: Task<Void, Never>?
    var toastTask: Task<Void, Never>?
    var settingsApplyTask: Task<Void, Never>?
    var unfinishedIDs: Set<String> = []
    /// Finished torrents that have already been auto-paused by the seed ratio
    /// limit (or manually resumed by the user while already >= the limit), so
    /// the poll does not immediately pause a torrent the user just resumed.
    var ratioLimitSatisfiedIDs: Set<String> = []
    var detailTick = 0
    var forceDetailRefresh = false
    /// True after the first snapshot has been applied. Published so the list
    /// can show a loading placeholder instead of flashing the empty state.
    @Published var hasLoadedSnapshot = false
    var isShuttingDown = false
    var sessionPexEnabled = true
    var shutdownCompletions: [() -> Void] = []
    var isShutdownComplete = false
    let decoder = JSONDecoder()
    var isPollInFlight = false
    /// Bumped on every restart/shutdown: async results from the previous
    /// session must not be applied to the new one.
    var sessionGeneration = 0
    var configurationOverride: SessionConfiguration?
    var lastAppliedConfiguration: SessionConfiguration?
    var proxyCheckTick = 0
    var proxyHealthError: String?
    var isProxyProbeInFlight = false
    var isWarmingProxyPassword = false
    var lastProxyPasswordWarmAttempt: Date?
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

    /// Dispatches an optional native macOS notification when downloads finish.
    /// Injected so tests can observe completion events without touching
    /// `UNUserNotificationCenter`.
    var completionNotification: ([String]) -> Void = { names in
        guard UserDefaults.standard.bool(forKey: PrefKey.notificationsEnabled) else { return }
        SystemNotifications.postDownloadCompleted(names: names)
    }

    var recentErrorToasts: [String: Date] = [:]
    private static let errorToastDedupWindow: TimeInterval = 8

    private init() {
        sessionController = SessionController()
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

    /// Starts the libtorrent session on the session actor. Loading the resume
    /// directory and creating a session can take seconds with a large library,
    /// so it must not run on the main actor; the actor validates the preferences
    /// (Keychain read included) before building the configuration.
    private func startSession(configuration: SessionConfiguration? = nil) {
        isStarting = true
        startupError = nil
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.sessionController.create(configuration: configuration)
            self.finishStartup(outcome)
        }
    }

    private func finishStartup(_ outcome: SessionCreationOutcome) {
        isStarting = false

        if isShuttingDown {
            Task { await sessionController.destroy() }
            return
        }

        guard outcome.started else {
            hasSession = false
            startupError = Self.sessionFailureDetail(
                outcome.error,
                fallback: L("Il motore incluso nell'app non è riuscito ad avviarsi. Riavvia Vertex; se il problema persiste, reinstalla l'app.")
            )
            isReady = false
            return
        }

        hasSession = true
        sessionPexEnabled = outcome.configuration.pex
        isReady = true
        startupError = nil
        lastAppliedConfiguration = outcome.configuration
        startPolling()
    }

    /// Retries the initial session creation after a failure. The persistent
    /// error view calls this; it is a no-op while a session or a startup is in
    /// flight.
    package func retryStartup() {
        guard !isStarting, !isShuttingDown, !hasSession else { return }
        startSession(configuration: configurationOverride)
    }

    #if DEBUG
    /// Test-only initializer: it uses an explicit configuration instead of the
    /// user's preferences and never starts a polling task unless asked to.
    package init(configuration: SessionConfiguration, startPollingImmediately: Bool = false) {
        Preferences.registerDefaults()
        configurationOverride = configuration
        sessionPexEnabled = configuration.pex
        // Tests need a session synchronously: the controller creates it in its
        // initializer, so the pointer never crosses an isolation boundary.
        let controller = SessionController(configuration: configuration)
        sessionController = controller
        hasSession = controller.started
        isReady = hasSession
        if isReady {
            lastAppliedConfiguration = configuration
        }
        if isReady && startPollingImmediately {
            startPolling()
        }
    }
    #endif

    // MARK: - Session Lifecycle

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
    /// the session. Both destruction and creation run on the session actor, and
    /// the previous PEX value is used as a fallback if the new session cannot start.
    func restartSessionForPeerExchange(
        configuration: SessionConfiguration,
        oldPex: Bool
    ) {
        guard !isRestartingSession, !isShuttingDown else { return }
        isRestartingSession = true
        sessionGeneration += 1
        isPollInFlight = false
        hasSession = false
        lastAppliedConfiguration = nil
        isReady = false
        hasLoadedSnapshot = false
        unfinishedIDs.removeAll()
        ratioLimitSatisfiedIDs.removeAll()
        pollTask?.cancel()
        pollTask = nil

        showToast(L("Riavvio del motore BitTorrent…"), kind: .info)

        Task { [weak self] in
            guard let self else { return }
            await self.sessionController.destroy()

            var outcome = await self.sessionController.create(configuration: configuration)
            var restoredPreviousPex = false
            if !outcome.started, configuration.pex != oldPex {
                var fallbackConfiguration = configuration
                fallbackConfiguration.pex = oldPex
                let fallback = await self.sessionController.create(configuration: fallbackConfiguration)
                if fallback.started {
                    outcome = fallback
                    restoredPreviousPex = true
                }
            }

            self.finishSessionRestart(
                outcome,
                requested: configuration,
                oldPex: oldPex,
                restoredPreviousPex: restoredPreviousPex
            )
        }
    }

    private func finishSessionRestart(
        _ outcome: SessionCreationOutcome,
        requested: SessionConfiguration,
        oldPex: Bool,
        restoredPreviousPex: Bool
    ) {
        isRestartingSession = false

        if isShuttingDown {
            // A shutdown arrived while the restart was in flight: it returned
            // early, so the completion must be delivered here.
            Task { [weak self] in
                guard let self else { return }
                await self.sessionController.destroy()
                self.completeShutdown()
            }
            return
        }

        if outcome.started {
            if restoredPreviousPex {
                // Put the preference back: the new PEX value could not start.
                UserDefaults.standard.set(oldPex, forKey: PrefKey.pexEnabled)
            }
            hasSession = true
            sessionPexEnabled = outcome.configuration.pex
            isReady = true
            startupError = nil
            // The session was created from this configuration: diffing the
            // current preferences against it applies only the edits made while
            // the restart was in progress, instead of rebinding the listening
            // port and remapping UPnP on every PEX toggle.
            lastAppliedConfiguration = outcome.configuration
            startPolling()
            poll()
            applySettings()
            if restoredPreviousPex {
                showToast(
                    L("La modifica a Peer Exchange non è stata applicata."),
                    kind: .error,
                    detail: Self.sessionFailureDetail(
                        outcome.error,
                        fallback: L("La sessione precedente è stata ripristinata.")
                    )
                )
            }
            return
        }

        // Both attempts failed: put the preference back and surface a retry view.
        UserDefaults.standard.set(oldPex, forKey: PrefKey.pexEnabled)
        sessionPexEnabled = oldPex
        hasSession = false
        lastAppliedConfiguration = nil
        isReady = false
        // Without this the empty library is indistinguishable from a dead
        // engine and the retry button never appears.
        startupError = Self.sessionFailureDetail(
            outcome.error,
            fallback: L("Il motore BitTorrent non è disponibile. Riavvia Vertex.")
        )
        pollState = PollState()
        detail = nil
        selectedID = nil
        selectedIDs = []
        selectionAnchorID = nil
        showToast(
            L("Impossibile riavviare il motore BitTorrent"),
            kind: .error,
            detail: Self.sessionFailureDetail(
                outcome.error,
                fallback: L("La modifica a Peer Exchange non è stata applicata. Riavvia Vertex.")
            )
        )
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

        hasSession = false
        lastAppliedConfiguration = nil
        isReady = false
        Task { [weak self] in
            guard let self else { return }
            await self.sessionController.destroy()
            self.completeShutdown()
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

    /// A Keychain read can fail transiently (locked keychain, denied prompt,
    /// different signing identity). The cache then stays cold and the session
    /// runs without proxy credentials, so retry off the main thread while the
    /// user asked for a proxy. Backed off, so a permanently unavailable
    /// Keychain does not prompt on every poll.
    func retryProxyPasswordWarmIfNeeded() {
        guard !Preferences.isProxyPasswordCacheLoaded,
              !isWarmingProxyPassword,
              !isShuttingDown,
              hasSession,
              UserDefaults.standard.bool(forKey: PrefKey.proxyEnabled) else {
            return
        }
        if let last = lastProxyPasswordWarmAttempt,
           Date().timeIntervalSince(last) < 30 {
            return
        }
        lastProxyPasswordWarmAttempt = Date()
        isWarmingProxyPassword = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Preferences.warmProxyPasswordCache()
            let loaded = Preferences.isProxyPasswordCacheLoaded
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWarmingProxyPassword = false
                // The password may have arrived: re-apply so libtorrent gets it.
                if loaded {
                    self.applySettings()
                }
            }
        }
    }

    /// Runs `operation` on the session actor and reports the outcome on the
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
        guard !isShuttingDown, hasSession else { return false }
        let generation = sessionGeneration
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.sessionController.perform(operation)
            guard !self.isShuttingDown, self.sessionGeneration == generation else {
                // The engine was shut down or restarted while the command was
                // in flight: the caller must not wait forever for an outcome
                // that no longer exists.
                if !self.isShuttingDown {
                    onFailure?(L("Motore non disponibile."))
                }
                return
            }
            if outcome.code != 0 {
                let message = self.localizedError(
                    outcome.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("Errore sconosciuto.")
                        : outcome.error
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
        return true
    }
}
