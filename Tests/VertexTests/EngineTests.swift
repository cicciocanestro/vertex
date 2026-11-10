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
            let destination = engineDownloadPath(workspace, "magnet")
            let addError = onMain {
                engine.addMagnet(
                    magnet,
                    destination: destination,
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
            try waitUntil("dettaglio del torrent selezionato caricato") {
                onMain { engine.detail != nil }
            }
            let detail = onMain { engine.detail }
            try TestRunner.assertNotNil(detail, "Il dettaglio del torrent selezionato deve essere caricato")
            try TestRunner.assertEqual(detail?.metadata, false)

            onMain { engine.select(nil) }
            try TestRunner.assertNil(onMain { engine.detail })

            // Load smoke test for the serialized snapshot path.
            for _ in 0..<100 {
                onMain { engine.pollNowForTesting() }
            }
            try TestRunner.assertEqual(onMain { engine.torrents.count }, 1)

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

        TestRunner.run("Engine: aggiunta asincrona e callback di esito") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "async-add")
            defer { shutdown(engine) }

            let destination = engineDownloadPath(workspace, "async-add")
            let magnet = "magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

            // The bridge call runs off the main thread, so a valid request is
            // accepted synchronously and reports its outcome through the
            // callback. The sheet closes only on that outcome.
            let firstBox = onMain { AsyncBox<String>() }
            let accepted = onMain {
                engine.addMagnet(
                    magnet,
                    destination: destination,
                    startPaused: true,
                    sequential: false,
                    completion: { failure in
                        firstBox.value = failure
                        firstBox.isDone = true
                    }
                )
            }
            try TestRunner.assertNil(accepted, "Un magnet valido deve essere accettato senza errori sincroni")
            try waitUntil("callback della prima aggiunta") { onMain { firstBox.isDone } }
            try TestRunner.assertNil(onMain { firstBox.value }, "La prima aggiunta non deve riportare errori")

            try waitForTorrent(engine)
            try TestRunner.assertEqual(onMain { engine.torrents.count }, 1)

            // A duplicate must surface through the callback: it is the only
            // signal the add sheet has to keep itself open.
            let duplicateBox = onMain { AsyncBox<String>() }
            _ = onMain {
                engine.addMagnet(
                    magnet,
                    destination: destination,
                    startPaused: true,
                    sequential: false,
                    completion: { failure in
                        duplicateBox.value = failure
                        duplicateBox.isDone = true
                    }
                )
            }
            try waitUntil("errore dell'aggiunta duplicata") { onMain { duplicateBox.isDone } }
            let duplicateOutcome = onMain { duplicateBox.value }
            try TestRunner.assertNotNil(duplicateOutcome, "Un torrent duplicato deve riportare un errore")
            try TestRunner.assertEqual(onMain { engine.torrents.count }, 1)
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
            try waitUntil("dettaglio del torrent fixture caricato") {
                onMain { engine.detail != nil }
            }
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
                engine.detail?.files.first(where: { $0.index == second.index })?.isWanted == false
            }

            // Bulk file priorities: deselect all, then select all.
            onMain { engine.setAllFilePriorities(wanted: false, torrentID: torrent.id) }
            try waitFor(engine) {
                let files = engine.detail?.files ?? []
                return files.count == 2 && files.allSatisfy { !$0.isWanted }
            }
            onMain { engine.setAllFilePriorities(wanted: true, torrentID: torrent.id) }
            try waitFor(engine) {
                let files = engine.detail?.files ?? []
                return files.count == 2 && files.allSatisfy(\.isWanted)
            }

            onMain { engine.togglePause(torrent) }
            try waitFor(engine) {
                engine.torrents.first?.paused == false
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
            try waitUntil("rimozione asincrona del torrent") {
                onMain {
                    engine.pollNowForTesting()
                    return engine.torrents.isEmpty && engine.detail == nil
                }
            }
            try TestRunner.assertEqual(onMain { engine.torrents.count }, 0)
            try TestRunner.assertNil(onMain { engine.detail })

            onMain { engine.dismissToast() }
            try TestRunner.assertNil(onMain { engine.toast })

            // Commands that target a removed torrent must surface an error and
            // must not crash the engine.
            onMain { engine.togglePause(torrent) }
            try waitUntil("errore comando su torrent rimosso") {
                onMain { engine.toast != nil }
            }
            onMain { engine.dismissToast() }
            onMain { engine.setFilePriority(second, wanted: true, torrentID: torrent.id) }
            try waitUntil("errore priorità su torrent rimosso") {
                onMain { engine.toast != nil }
            }
            onMain { engine.dismissToast() }
            onMain { engine.setAllFilePriorities(wanted: false, torrentID: torrent.id) }
            try waitUntil("errore priorità bulk su torrent rimosso") {
                onMain { engine.toast != nil }
            }
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
            try waitUntil("dettaglio iniziale presente") {
                onMain { engine.detail != nil }
            }
            try TestRunner.assertNotNil(onMain { engine.detail })

            // A failed fetch must not leave the previous detail visible.
            onMain { engine.applyDetailJSONForTesting(nil, id: torrent.id) }
            try TestRunner.assertNil(onMain { engine.detail })

            onMain { engine.select(torrent.id) }
            try waitUntil("dettaglio ripristinato") {
                onMain { engine.detail != nil }
            }
            try TestRunner.assertNotNil(onMain { engine.detail })
            onMain { engine.applyDetailJSONForTesting("not-json", id: torrent.id) }
            try TestRunner.assertNil(onMain { engine.detail })

            // A stale response for another selection must be ignored.
            onMain { engine.select(torrent.id) }
            try waitUntil("dettaglio ripristinato per stale check") {
                onMain { engine.detail != nil }
            }
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

            // Rate history must keep appending zeros after a transfer stops so
            // the sparkline decays back to flat zero instead of freezing, then
            // stop publishing once all 80 samples are 0.
            let activeJSON = """
            {
                "download_rate": 524288,
                "upload_rate": 0,
                "active": 1,
                "paused_count": 0,
                "dht_nodes": 0,
                "alert_error": "",
                "listen_actual_port": 6881,
                "listening": true,
                "bind_address": "",
                "listen_error": "",
                "portmap": {
                    "tcp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "udp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "error": ""
                },
                "port": 6881,
                "torrents": []
            }
            """
            let idleJSON = activeJSON.replacingOccurrences(
                of: "\"download_rate\": 524288",
                with: "\"download_rate\": 0"
            )
            let activeSnapshot = try JSONDecoder().decode(
                VertexSnapshot.self,
                from: Data(activeJSON.utf8)
            )
            let idleSnapshot = try JSONDecoder().decode(
                VertexSnapshot.self,
                from: Data(idleJSON.utf8)
            )
            onMain { engine.applySnapshotForTesting(activeSnapshot) }
            try TestRunner.assertEqual(onMain { engine.downloadHistory.last }, 524288)
            for _ in 0..<80 {
                onMain { engine.applySnapshotForTesting(idleSnapshot) }
            }
            try TestRunner.assertTrue(
                onMain { engine.downloadHistory.allSatisfy { $0 == 0 } },
                "La history deve scorrere a zero quando il traffico si ferma"
            )
        }

        TestRunner.run("Engine: impostazioni, riavvio PEX e shutdown con completion concorrenti") {
            let workspace = try IntegrationWorkspace()
            let (engine, configuration) = try makeEngineWithConfiguration(in: workspace, name: "settings")
            defer { shutdown(engine) }

            onMain { engine.applySettings() }
            try TestRunner.assertNil(onMain { engine.toast }, "Le impostazioni valide non devono produrre errori")

            // Dynamic bindAddress switch: simulate binding to a downed tunnel IP
            // (203.0.113.9), verify listenError is surfaced and socket stops
            // listening, then restore automatic binding ("") and verify recovery.
            var tunnelDown = configuration
            tunnelDown.bindAddress = "203.0.113.9"
            onMain {
                engine.setConfigurationForTesting(tunnelDown)
                engine.applySettings()
            }
            try waitFor(engine) {
                onMain {
                    engine.stats.bindAddress == "203.0.113.9"
                        && !engine.stats.isListening
                        && !engine.stats.listenError.isEmpty
                }
            }
            try TestRunner.assertTrue(onMain { engine.stats.isBoundToAddress })

            var automaticBind = configuration
            automaticBind.bindAddress = ""
            onMain {
                engine.setConfigurationForTesting(automaticBind)
                engine.applySettings()
            }
            try waitFor(engine) {
                onMain {
                    !engine.stats.isBoundToAddress
                        && engine.stats.isListening
                        && engine.stats.listenError.isEmpty
                }
            }

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

            let firstCompleted = onMain { AsyncBox<Void>() }
            let secondCompleted = onMain { AsyncBox<Void>() }
            var pausedAgain = configuration
            pausedAgain.pex = false
            onMain {
                engine.setConfigurationForTesting(pausedAgain)
                engine.applySettings()
                engine.shutdown { firstCompleted.isDone = true }
                engine.shutdown { secondCompleted.isDone = true }
            }
            try waitUntil("shutdown con completion concorrenti") {
                onMain { firstCompleted.isDone && secondCompleted.isDone }
            }
            try TestRunner.assertFalse(onMain { engine.isReady })
        }

        TestRunner.run("Views: rendering headless delle viste critiche") {
            let workspace = try IntegrationWorkspace()
            let engine = try makeEngine(in: workspace, name: "views")
            defer { shutdown(engine) }

            let fixture = IntegrationFixture.v1
            let downloadPath = engineDownloadPath(workspace, "views")
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
                try TestRunner.assertTrue(false, "Serve un torrent per renderizzare le viste")
                return
            }
            onMain { engine.select(torrent.id) }

            let rendered = onMain {
                ViewRenderingSupport.renderCriticalViews(engine: engine, torrents: engine.torrents)
            }
            try TestRunner.assertEqual(rendered.count, 13)
            for (name, area) in rendered {
                try TestRunner.assertTrue(area > 0, "La vista \(name) non ha prodotto un'immagine")
            }

            let variants = onMain {
                ViewRenderingSupport.renderStateVariants(engine: engine, torrents: engine.torrents)
            }
            try TestRunner.assertEqual(variants.count, 13)
            for (name, area) in variants {
                try TestRunner.assertTrue(
                    area > 0,
                    "La variante \(name) non ha prodotto un'immagine"
                )
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
        _ condition: @escaping @Sendable @MainActor () -> Bool
    ) throws {
        try TestsSupport.waitFor("condizione dell'engine", timeout: timeout) {
            onMain {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
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
        let box = onMain { AsyncBox<Void>() }
        onMain { engine.shutdown { box.isDone = true } }
        let deadline = Date().addingTimeInterval(5)
        while !onMain({ box.isDone }) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

@MainActor
private final class AsyncBox<T> {
    var value: T?
    var isDone = false

    init(_ value: T? = nil) {
        self.value = value
    }
}
#endif
