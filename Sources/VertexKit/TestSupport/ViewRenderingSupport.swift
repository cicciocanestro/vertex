#if DEBUG
    import AppKit
    import SwiftUI

    /// Headless rendering helpers used by the test runner. They live in VertexKit
    /// so the views can stay internal; they are compiled only in DEBUG builds.
    package enum ViewRenderingSupport {
        @MainActor
        package static func renderCriticalViews(
            engine: TorrentEngine,
            torrents: [Torrent]
        ) -> [String: Int] {
            // Avoid touching AppKit's global state more than once per process.
            _ = NSApplication.shared

            var results: [String: Int] = [:]
            results["NetworkDiagnosticsView"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )
            results["StatusBarView"] = render(
                StatusBarView(engine: engine),
                width: 900,
                height: 44
            )
            results["SettingsSheet"] = render(
                SettingsSheet(engine: engine, onClose: {}, onOpenDiagnostics: {}),
                width: 700,
                height: 540
            )
            results["AddTorrentSheet"] = render(
                AddTorrentSheet(engine: engine, initialMode: .magnet, onClose: {}),
                width: 580,
                height: 560
            )
            results["FilterBar"] = render(
                FilterBar(
                    filter: .constant(.all),
                    sort: .constant(.recent),
                    sortAscending: .constant(false),
                    counts: TorrentListPipeline.applyWithCounts(
                        to: torrents,
                        filter: .all,
                        search: "",
                        sort: .recent
                    ).counts
                ),
                width: 900,
                height: 44
            )
            results["EmptyStateView"] = render(
                EmptyStateView(onAdd: {}, onPasteMagnet: {}),
                width: 760,
                height: 520
            )
            results["EngineUnavailableView"] = render(
                EngineUnavailableView(message: "Errore di avvio del motore", onRetry: {}),
                width: 760,
                height: 520
            )
            results["ToastViewAction"] = render(
                ToastView(
                    toast: ToastMessage(
                        kind: .success,
                        text: "Download completato",
                        detail: "file.mkv",
                        actionTitle: "Mostra nel Finder",
                        action: .reveal(path: "/tmp")
                    ),
                    onDismiss: {},
                    onAction: { _ in }
                ),
                width: 520,
                height: 90
            )
            results["NoResultsView"] = render(
                NoResultsView(query: "ubuntu", onReset: {}),
                width: 760,
                height: 520
            )
            results["DropOverlay"] = render(
                DropOverlay(),
                width: 760,
                height: 520
            )
            results["RootView"] = render(
                RootView(engine: engine),
                width: 1180,
                height: 760
            )

            if let torrent = torrents.first {
                results["InspectorView"] = render(
                    InspectorView(
                        engine: engine,
                        torrent: torrent,
                        onClose: {},
                        onDeleteWithFiles: { _ in }
                    ),
                    width: 360,
                    height: 700
                )
                results["TorrentListView"] = render(
                    TorrentListView(
                        engine: engine,
                        torrents: torrents,
                        selectedIDs: [torrent.id],
                        onSelectClick: { _, _, _ in },
                        onSelectAll: {},
                        onDeleteSelection: { _ in }
                    ),
                    width: 640,
                    height: 420
                )
            }

            return results
        }

        /// Renders the states that are otherwise only reachable by interacting with
        /// the window: settings/diagnostics modals, add sheet, delete confirmation,
        /// inspector, drop overlay, filtered search and the UPnP/NAT-PMP cards.
        @MainActor
        package static func renderStateVariants(
            engine: TorrentEngine,
            torrents: [Torrent]
        ) -> [String: Int] {
            _ = NSApplication.shared

            var results: [String: Int] = [
                "RootViewSettings": render(
                    RootView(engine: engine, showSettings: true),
                    width: 1180,
                    height: 760
                ),
                "RootViewDiagnostics": render(
                    RootView(engine: engine, showDiagnostics: true),
                    width: 1180,
                    height: 760
                ),
                "RootViewAddSheet": render(
                    RootView(engine: engine, showAddSheet: true, addMode: .file),
                    width: 1180,
                    height: 760
                ),
                "RootViewNoResults": render(
                    RootView(engine: engine, search: "nessun-risultato-possibile"),
                    width: 1180,
                    height: 760
                ),
                "RootViewFiltered": render(
                    RootView(engine: engine, filter: .downloading, sort: .name),
                    width: 1180,
                    height: 760
                ),
                "RootViewDropOverlay": render(
                    RootView(engine: engine, dropTargeted: true),
                    width: 1180,
                    height: 760
                ),
                "RootViewMinWidthLarge": render(
                    RootView(engine: engine).dynamicTypeSize(.large),
                    width: WindowMetrics.minimumWidth,
                    height: WindowMetrics.minimumHeight
                ),
                "RootViewMinWidthXXLarge": render(
                    RootView(engine: engine).dynamicTypeSize(.xxLarge),
                    width: WindowMetrics.minimumWidth,
                    height: WindowMetrics.minimumHeight
                ),
                "SettingsSheetXXLarge": render(
                    SettingsSheet(engine: engine, onClose: {}, onOpenDiagnostics: {})
                        .dynamicTypeSize(.xxLarge),
                    width: 700,
                    height: 540
                ),
            ]

            if let torrent = torrents.first {
                let synthetic = Torrent(
                    id: "synthetic-second-id",
                    name: "Second.mkv",
                    stateCode: 3,
                    progress: 0.4,
                    size: 1024,
                    downloaded: 400,
                    uploaded: 0,
                    downloadRate: 0,
                    uploadRate: 0,
                    peers: 1,
                    seeds: 1,
                    eta: 10,
                    finished: false,
                    seeding: false,
                    paused: false,
                    sequential: false,
                    hasMetadata: true,
                    savePath: torrent.savePath,
                    ratio: 0,
                    added: 0,
                    error: ""
                )
                var state = engine.pollState
                state.torrents = [torrent, synthetic]
                state.torrentsByID[synthetic.id] = synthetic
                engine.pollState = state
                engine.setSelection(
                    TorrentListSelection.State(selectedIDs: [torrent.id, synthetic.id], anchorID: torrent.id))
                results["RootViewMultiSelection"] = render(
                    RootView(engine: engine),
                    width: 1180,
                    height: 760
                )
                state.torrents = torrents
                state.torrentsByID = Dictionary(torrents.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                engine.pollState = state
                engine.select(torrent.id)

                results["RootViewInspector"] = render(
                    RootView(engine: engine, selectedID: torrent.id),
                    width: 1180,
                    height: 760
                )
                results["RootViewDeleteConfirmation"] = render(
                    RootView(
                        engine: engine,
                        pendingDeletion: torrent,
                        showDeleteConfirmation: true
                    ),
                    width: 1180,
                    height: 760
                )
            }

            let original = engine.stats
            defer { engine.setStatsForTesting(original) }

            let base = SessionStats(
                downloadRate: 1_200_000,
                uploadRate: 240_000,
                active: 2,
                paused: 1,
                dhtNodes: 42,
                port: 6881,
                actualPort: 6881,
                isListening: true
            )

            var mapped = base
            mapped.portmap = PortMapSnapshot(
                tcp: PortMapInfo(mapped: true, externalPort: 6881, transport: "UPnP"),
                udp: PortMapInfo(mapped: true, externalPort: 6881, transport: "NAT-PMP")
            )
            engine.setStatsForTesting(mapped)
            results["DiagnosticsMapped"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )

            var partialError = base
            partialError.portmap = PortMapSnapshot(
                tcp: PortMapInfo(error: "UPnP: timeout"),
                udp: PortMapInfo(mapped: true, externalPort: 6881, transport: "NAT-PMP")
            )
            engine.setStatsForTesting(partialError)
            results["DiagnosticsPartialError"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )

            engine.setStatsForTesting(base)
            results["DiagnosticsUnmapped"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )

            var globalError = base
            globalError.portmap = PortMapSnapshot(error: "NAT-PMP: no gateway")
            engine.setStatsForTesting(globalError)
            results["DiagnosticsGlobalError"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )

            // Pinned to a tunnel address that is no longer available: this is the
            // state the client shows when the VPN is down and the engine refuses to
            // fall back to the physical interface.
            var bound = base
            bound.bindAddress = "10.8.0.2"
            bound.listenError = "listening on 10.8.0.2:6881 failed: Can't assign requested address"
            engine.setStatsForTesting(bound)
            results["DiagnosticsBound"] = render(
                NetworkDiagnosticsView(engine: engine, onClose: {}, onOpenSettings: {}),
                width: 760,
                height: 640
            )

            return results
        }

        /// Renders every settings section, the inspector tabs with real data, the
        /// row states and an empty status bar. These paths are otherwise reachable
        /// only by clicking through the window, and they are where most of the view
        /// code lives.
        @MainActor
        package static func renderExtendedViews(
            engine: TorrentEngine,
            torrents: [Torrent]
        ) -> [String: Int] {
            _ = NSApplication.shared

            var results: [String: Int] = [:]
            for section in SettingsSection.allCases {
                results["SettingsSheet.\(section.rawValue)"] = render(
                    SettingsSheet(
                        engine: engine,
                        initialSection: section,
                        onClose: {},
                        onOpenDiagnostics: {}
                    ),
                    width: 700,
                    height: 540
                )
            }

            results["SettingsSheet.searchProxy"] = render(
                SettingsSheet(
                    engine: engine,
                    initialQuery: "proxy",
                    onClose: {},
                    onOpenDiagnostics: {}
                ),
                width: 700,
                height: 540
            )
            results["SettingsSheet.searchNone"] = render(
                SettingsSheet(
                    engine: engine,
                    initialQuery: "zzz",
                    onClose: {},
                    onOpenDiagnostics: {}
                ),
                width: 700,
                height: 540
            )

            results["AddTorrentSheetFile"] = render(
                AddTorrentSheet(engine: engine, initialMode: .file, onClose: {}),
                width: 580,
                height: 560
            )

            let rowStates: [Torrent] = [
                Torrent(
                    id: "ext-download", name: "Ubuntu-24.04-desktop-amd64.iso",
                    stateCode: 3, progress: 0.42, size: 5_000_000_000,
                    downloaded: 2_100_000_000, uploaded: 10_000_000,
                    downloadRate: 4_500_000, uploadRate: 120_000,
                    peers: 12, seeds: 30, eta: 640,
                    finished: false, seeding: false, paused: false,
                    sequential: true, hasMetadata: true,
                    savePath: "/tmp", ratio: 0.1, added: 0, error: ""
                ),
                Torrent(
                    id: "ext-seed", name: "Debian-13-netinst.iso",
                    stateCode: 5, progress: 1, size: 800_000_000,
                    downloaded: 800_000_000, uploaded: 1_600_000_000,
                    downloadRate: 0, uploadRate: 900_000,
                    peers: 4, seeds: 9, eta: -1,
                    finished: true, seeding: true, paused: false,
                    sequential: false, hasMetadata: true,
                    savePath: "/tmp", ratio: 2.0, added: 0, error: ""
                ),
                Torrent(
                    id: "ext-queued", name: "Queued.mkv",
                    stateCode: 1, progress: 0.2, size: 10_000_000,
                    downloaded: 2_000_000, uploaded: 0,
                    downloadRate: 0, uploadRate: 0,
                    peers: 0, seeds: 0, eta: -1,
                    finished: false, seeding: false, paused: true,
                    autoManaged: true, sequential: false, hasMetadata: false,
                    savePath: "/tmp", ratio: 0, added: 0, error: ""
                ),
                Torrent(
                    id: "ext-error", name: "Broken.iso",
                    stateCode: 3, progress: 0, size: 50_000_000,
                    downloaded: 0, uploaded: 0,
                    downloadRate: 0, uploadRate: 0,
                    peers: 0, seeds: 0, eta: -1,
                    finished: false, seeding: false, paused: false,
                    sequential: false, hasMetadata: true,
                    savePath: "/tmp", ratio: 0, added: 0,
                    error: "tracker timeout"
                ),
            ]
            results["TorrentListViewStates"] = render(
                TorrentListView(
                    engine: engine,
                    torrents: rowStates,
                    selectedIDs: ["ext-download"],
                    onSelectClick: { _, _, _ in },
                    onSelectAll: {},
                    onDeleteSelection: { _ in }
                ),
                width: 900,
                height: 460
            )

            if let torrent = torrents.first {
                let originalDetail = engine.detail
                defer { engine.detail = originalDetail }
                engine.detail = TorrentDetail(
                    files: [
                        TorrentFile(index: 0, path: "video.mkv", size: 1_000_000, progress: 0.5, priority: 4),
                        TorrentFile(index: 1, path: "sample.mkv", size: 10_000, progress: 0, priority: 0),
                    ],
                    trackers: [
                        TorrentTracker(
                            url: "udp://tracker.example:1337", verified: true, fails: 0,
                            message: "", peers: 12, seeds: 30
                        ),
                        TorrentTracker(
                            url: "https://tracker.invalid/announce", verified: false, fails: 3,
                            message: "timeout", peers: 0, seeds: 0
                        ),
                    ],
                    peers: [
                        TorrentPeer(
                            endpoint: "203.0.113.10:51413", client: "qBittorrent 4.6",
                            progress: 0.8, downloadRate: 1_000, uploadRate: 0,
                            flags: "DUEPIS", source: "tracker"
                        ),
                        TorrentPeer(
                            endpoint: "198.51.100.7:6881", client: "Unknown",
                            progress: 0.3, downloadRate: 0, uploadRate: 500,
                            flags: "D", source: "dht"
                        ),
                    ],
                    metadata: true
                )

                for tab in DetailTab.allCases {
                    results["InspectorView.\(tab.rawValue)"] = render(
                        InspectorView(
                            engine: engine,
                            torrent: torrent,
                            initialTab: tab,
                            onClose: {},
                            onDeleteWithFiles: { _ in }
                        ),
                        width: 360,
                        height: 700
                    )
                }
            }

            let originalState = engine.pollState
            engine.pollState = TorrentEngine.PollState()
            results["StatusBarEmpty"] = render(
                StatusBarView(engine: engine),
                width: 900,
                height: 44
            )
            let originalReady = engine.isReady
            let originalStartup = engine.startupError
            let originalLoaded = engine.hasLoadedSnapshot
            let originalToast = engine.toast
            defer {
                engine.pollState = originalState
                engine.isReady = originalReady
                engine.startupError = originalStartup
                engine.hasLoadedSnapshot = originalLoaded
                engine.toast = originalToast
            }

            engine.pollState = TorrentEngine.PollState()
            engine.hasLoadedSnapshot = true
            results["RootView.empty"] = render(
                RootView(engine: engine), width: 1180, height: 760
            )

            engine.hasLoadedSnapshot = false
            results["RootView.loading"] = render(
                RootView(engine: engine), width: 1180, height: 760
            )

            engine.isReady = false
            engine.startupError = "Errore di avvio"
            results["RootView.unavailable"] = render(
                RootView(engine: engine), width: 1180, height: 760
            )

            engine.isReady = originalReady
            engine.startupError = nil
            engine.hasLoadedSnapshot = true
            engine.pollState = originalState

            engine.toast = ToastMessage(kind: .success, text: L("Download completato"))
            results["RootView.toastSuccess"] = render(
                RootView(engine: engine), width: 1180, height: 760
            )
            engine.toast = ToastMessage(
                kind: .error,
                text: L("Errore sconosciuto"),
                detail: L("Errore sconosciuto")
            )
            results["RootView.toastError"] = render(
                RootView(engine: engine), width: 1180, height: 760
            )

            return results
        }

        @MainActor
        private static func render<V: View>(
            _ view: V,
            width: CGFloat,
            height: CGFloat
        ) -> Int {
            let renderer = ImageRenderer(
                content: view.frame(width: width, height: height)
            )
            renderer.scale = 1
            guard let image = renderer.cgImage else { return 0 }
            return image.width * image.height
        }
    }
#endif
