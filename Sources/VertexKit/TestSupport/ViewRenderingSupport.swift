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
            height: 780
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
                    selectedID: torrent.id,
                    onSelect: { _ in },
                    onDeleteWithFiles: { _ in }
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
            )
        ]

        if let torrent = torrents.first {
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
