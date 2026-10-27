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
                torrents: torrents
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
