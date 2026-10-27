#if DEBUG
import Foundation
@testable import VertexKit

enum EngineTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: EngineTests]\u{001B}[0m")

        TestRunner.run("Engine: magnet, selezione e dettaglio") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "magnet")
            defer { shutdown(engine) }

            try onMain {
                try TestRunner.assertTrue(engine.isReady, "La sessione di test deve essere pronta")
                try TestRunner.assertEqual(engine.torrents.count, 0)
            }

            let magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
            let addError = onMain {
                engine.addMagnet(
                    magnet,
                    destination: engineDownloadPath(workspace, "magnet"),
                    startPaused: true,
                    sequential: false
                )
            }
            try TestRunner.assertNil(addError)

            try waitForTorrent(engine)
            guard let torrent = onMain({ engine.torrents.first }) else {
                try TestRunner.assertTrue(false, "Il torrent aggiunto deve comparire nello snapshot")
                return
            }

            onMain { engine.select(torrent.id) }
            let detail = onMain { engine.detail }
            try TestRunner.assertNotNil(detail, "Il dettaglio del torrent selezionato deve essere caricato")
            try TestRunner.assertEqual(detail?.metadata, false)

            onMain { engine.select(nil) }
            try TestRunner.assertNil(onMain { engine.detail })

            let invalidError = onMain {
                engine.addMagnet(
                    "https://example.com/not-a-magnet",
                    destination: engineDownloadPath(workspace, "magnet"),
                    startPaused: true,
                    sequential: false
                )
            }
            try TestRunner.assertNotNil(invalidError, "Un URI non magnet deve essere rifiutato")
            try TestRunner.assertNotNil(onMain { engine.toast })
        }

        TestRunner.run("Engine: file, priorità, controlli e rimozione") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "file")
            defer { shutdown(engine) }

            let fixture = IntegrationFixture.v1
            let downloadPath = engineDownloadPath(workspace, "file")
            let addError = onMain {
                engine.addTorrentFile(
                    fixture.torrentURL,
                    destination: downloadPath,
                    startPaused: true,
                    sequential: false
                )
            }
            try TestRunner.assertNil(addError)

            try waitForTorrent(engine)
            guard let torrent = onMain({ engine.torrents.first }) else {
                try TestRunner.assertTrue(false, "Il torrent fixture deve comparire nello snapshot")
                return
            }
            try TestRunner.assertEqual(torrent.name, fixture.rootName)

            onMain { engine.select(torrent.id) }
            guard let detail = onMain({ engine.detail }) else {
                try TestRunner.assertTrue(false, "Il dettaglio del torrent fixture deve essere disponibile")
                return
            }
            try TestRunner.assertEqual(detail.files.count, 2)

            guard let second = detail.files.first(where: { $0.path.contains("second.bin") }) else {
                try TestRunner.assertTrue(false, "Il torrent fixture deve contenere second.bin")
                return
            }
            onMain { engine.setFilePriority(second, wanted: false, torrentID: torrent.id) }
            // libtorrent applies file priorities asynchronously, so the refreshed
            // detail converges a few polls later instead of immediately.
            try waitFor(engine) {
                onMain {
                    engine.detail?.files.first(where: { $0.index == second.index })?.isWanted == false
                }
            }

            onMain { engine.togglePause(torrent) }
            try waitFor(engine) {
                onMain { engine.torrents.first?.paused == false }
            }
            guard let resumed = onMain({ engine.torrents.first }) else {
                try TestRunner.assertTrue(false, "Lo snapshot del torrent deve essere disponibile")
                return
            }
            onMain { engine.togglePause(resumed) }
            try waitFor(engine) {
                onMain { engine.torrents.first?.paused == true }
            }

            onMain { engine.toggleSequential(torrent) }
            try waitFor(engine) {
                onMain { engine.torrents.first?.sequential == true }
            }

            onMain { engine.pause(torrent) }
            try waitFor(engine) {
                onMain { engine.torrents.first?.paused == true }
            }

            onMain { engine.resume(torrent) }
            try waitFor(engine) {
                onMain { engine.torrents.first?.paused == false }
            }

            onMain { engine.reannounce(torrent) }
            try TestRunner.assertTrue(
                onMain { !engine.magnetURI(for: torrent).isEmpty },
                "Il magnet URI deve essere disponibile per un torrent con metadati"
            )

            onMain { engine.remove(torrent, deleteFiles: false) }
            onMain { engine.pollNowForTesting() }
            try TestRunner.assertEqual(onMain { engine.torrents.count }, 0)
            try TestRunner.assertNil(onMain { engine.detail })

            onMain { engine.dismissToast() }
            try TestRunner.assertNil(onMain { engine.toast })

            // Commands that target a removed torrent must surface an error and
            // must not crash the engine.
            onMain { engine.togglePause(torrent) }
            try TestRunner.assertNotNil(
                onMain { engine.toast },
                "Un comando su un torrent rimosso deve produrre un errore"
            )
            onMain { engine.dismissToast() }
            onMain { engine.setFilePriority(second, wanted: true, torrentID: torrent.id) }
            try TestRunner.assertNotNil(
                onMain { engine.toast },
                "La priorità di un torrent rimosso deve produrre un errore"
            )
        }

        TestRunner.run("Engine: dettaglio fallito e stato non selezionato") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "detail")
            defer { shutdown(engine) }

            let magnet = "magnet:?xt=urn:btih:fedcba9876543210fedcba9876543210fedcba98"
            let addError = onMain {
                engine.addMagnet(
                    magnet,
                    destination: engineDownloadPath(workspace, "detail"),
                    startPaused: true,
                    sequential: false
                )
            }
            try TestRunner.assertNil(addError)

            try waitForTorrent(engine)
            guard let torrent = onMain({ engine.torrents.first }) else {
                try TestRunner.assertTrue(false, "Il torrent magnet deve comparire nello snapshot")
                return
            }
            onMain { engine.select(torrent.id) }
            try TestRunner.assertNotNil(onMain { engine.detail })

            // A failed fetch must not leave the previous detail visible.
            onMain { engine.applyDetailJSONForTesting(nil, id: torrent.id) }
            try TestRunner.assertNil(onMain { engine.detail })

            onMain { engine.select(torrent.id) }
            try TestRunner.assertNotNil(onMain { engine.detail })
            onMain { engine.applyDetailJSONForTesting("not-json", id: torrent.id) }
            try TestRunner.assertNil(onMain { engine.detail })

            // A stale response for another selection must be ignored.
            onMain { engine.select(torrent.id) }
            onMain { engine.applyDetailJSONForTesting(nil, id: "another-torrent") }
            try TestRunner.assertNotNil(onMain { engine.detail })

            let valid = """
            {
                "files": [
                    {"index": 0, "path": "data.bin", "size": 1024, "progress": 1.0, "priority": 4}
                ],
                "trackers": [],
                "metadata": true
            }
            """
            onMain { engine.applyDetailJSONForTesting(valid, id: torrent.id) }
            let decoded = onMain { engine.detail }
            try TestRunner.assertEqual(decoded?.files.count, 1)
            try TestRunner.assertEqual(decoded?.metadata, true)
        }

        TestRunner.run("Engine: impostazioni, riavvio PEX e shutdown asincrono") {
            let workspace = try IntegrationWorkspace()
            let (engine, configuration) = try makeEngineWithConfiguration(in: workspace, name: "settings")
            defer { shutdown(engine) }

            onMain { engine.applySettings() }
            try TestRunner.assertNil(onMain { engine.toast }, "Le impostazioni valide non devono produrre errori")

            // Changing PEX requires recreating the libtorrent session.
            var restarted = configuration
            restarted.pex = true
            onMain { engine.setConfigurationForTesting(restarted) }
            onMain { engine.applySettings() }
            try waitUntil("riavvio della sessione per PEX") {
                onMain { engine.isReady && !engine.isRestartingSession }
            }
            try TestRunner.assertTrue(
                onMain { engine.isReady },
                "La sessione deve essere pronta dopo il riavvio per PEX"
            )

            var completed = false
            onMain { engine.shutdown { completed = true } }
            try waitUntil("shutdown dell'engine") { completed }
            try TestRunner.assertFalse(onMain { engine.isReady })
        }

        TestRunner.run("Views: rendering headless delle viste critiche") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "views")
            defer { shutdown(engine) }

            let fixture = IntegrationFixture.v1
            let addError = onMain {
                engine.addTorrentFile(
                    fixture.torrentURL,
                    destination: engineDownloadPath(workspace, "views"),
                    startPaused: true,
                    sequential: false
                )
            }
            try TestRunner.assertNil(addError)

            try waitForTorrent(engine)
            guard let torrent = onMain({ engine.torrents.first }) else {
                try TestRunner.assertTrue(false, "Serve un torrent per renderizzare le viste")
                return
            }
            onMain { engine.select(torrent.id) }

            let rendered = onMain {
                ViewRenderingSupport.renderCriticalViews(engine: engine, torrents: engine.torrents)
            }
            try TestRunner.assertEqual(rendered.count, 6)
            for (name, area) in rendered {
                try TestRunner.assertTrue(area > 0, "La vista \(name) non ha prodotto un'immagine")
            }
        }
    }

    // MARK: - Helpers

    private static func makeEngine(
        in workspace: IntegrationWorkspace,
        name: String
    ) throws -> TorrentEngine {
        try makeEngineWithConfiguration(in: workspace, name: name).engine
    }

    private static func makeEngineWithConfiguration(
        in workspace: IntegrationWorkspace,
        name: String
    ) throws -> (engine: TorrentEngine, configuration: SessionConfiguration) {
        let download = try workspace.directory("\(name)-download")
        let resume = try workspace.directory("\(name)-resume")
        let port = try TestsSupport.freeTCPPort()
        let configuration = SessionConfiguration(
            downloadPath: download.path,
            resumePath: resume.path,
            port: Int32(port)
        )
        let engine = onMain { TorrentEngine(configuration: configuration) }
        try onMain {
            try TestRunner.assertTrue(engine.isReady, "L'engine di test non è riuscito ad avviare la sessione")
        }
        return (engine, configuration)
    }

    private static func engineDownloadPath(
        _ workspace: IntegrationWorkspace,
        _ name: String
    ) -> String {
        workspace.root.appendingPathComponent("\(name)-download", isDirectory: true).path
    }

    private static func waitForTorrent(_ engine: TorrentEngine, timeout: TimeInterval = 10) throws {
        try TestsSupport.waitFor("torrent nell'engine", timeout: timeout) {
            onMain {
                engine.pollNowForTesting()
                return !engine.torrents.isEmpty
            }
        }
    }

    private static func waitFor(
        _ engine: TorrentEngine,
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) throws {
        try TestsSupport.waitFor("condizione dell'engine", timeout: timeout) {
            onMain {
                engine.pollNowForTesting()
                return condition()
            }
        }
    }

    private static func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) throws {
        try TestsSupport.waitFor(description, timeout: timeout) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            return condition()
        }
    }

    private static func shutdown(_ engine: TorrentEngine) {
        var completed = false
        onMain { engine.shutdown { completed = true } }
        let deadline = Date().addingTimeInterval(5)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private static func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        try MainActor.assumeIsolated(body)
    }
}
#endif
