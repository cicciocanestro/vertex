#if DEBUG
    import Foundation
    @testable import VertexKit

    enum EngineTests {
        static func runAll() {
            print("\n\u{001B}[1m[Suite: EngineTests]\u{001B}[0m")

            TestRunner.run("Engine: intervallo di polling adattivo") {
                try onMain {
                    try TestRunner.assertEqual(
                        TorrentEngine.pollInterval(
                            downloadRate: 0, uploadRate: 0, hasUnfinished: false, isAppActive: true
                        ),
                        1.6,
                        "Una libreria inattiva deve diradare i poll"
                    )
                    try TestRunner.assertEqual(
                        TorrentEngine.pollInterval(
                            downloadRate: 1024, uploadRate: 0, hasUnfinished: false, isAppActive: true
                        ),
                        0.8,
                        "Il traffico in corso deve usare il ritmo rapido"
                    )
                    try TestRunner.assertEqual(
                        TorrentEngine.pollInterval(
                            downloadRate: 0, uploadRate: 0, hasUnfinished: true, isAppActive: true
                        ),
                        0.8,
                        "Un download incompleto deve usare il ritmo rapido"
                    )
                    try TestRunner.assertEqual(
                        TorrentEngine.pollInterval(
                            downloadRate: 1024, uploadRate: 1024, hasUnfinished: true, isAppActive: false
                        ),
                        2.5,
                        "In background il poll deve rallentare comunque"
                    )
                }
            }

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
                let magnetURI = onMain { AsyncBox<String>() }
                onMain { engine.magnetURI(for: torrent) { magnetURI.value = $0 } }
                try waitUntil("magnet URI disponibile") {
                    onMain { !(magnetURI.value ?? "").isEmpty }
                }

                // Test moveStorage through engine
                let targetMoved = try workspace.directory("engine-moved")
                let moveBox = onMain { AsyncBox<String>() }
                onMain {
                    engine.moveStorage(torrent, to: targetMoved.path) { failure in
                        moveBox.value = failure
                        moveBox.isDone = true
                    }
                }
                try waitUntil("callback spostamento storage") { onMain { moveBox.isDone } }
                try TestRunner.assertNil(onMain { moveBox.value })

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

                // Seed ratio limit: auto-pauses seeding torrent when ratio threshold is met.
                var ratioConfig = automaticBind
                ratioConfig.seedRatioLimit = 1.5
                onMain {
                    engine.setConfigurationForTesting(ratioConfig)
                    engine.applySettings()
                }
                let seedingFinished = Torrent.test(
                    id: "seed-ratio-test",
                    name: "SeedRatioTorrent",
                    stateCode: 5,
                    progress: 1.0,
                    finished: true,
                    seeding: true,
                    paused: false,
                    ratio: 1.8
                )
                onMain {
                    var testStats = engine.stats
                    testStats.active = 1
                    let testSnapshot = VertexSnapshot.test(
                        torrents: [seedingFinished],
                        stats: testStats
                    )
                    engine.applySnapshotForTesting(testSnapshot)
                }
                try TestRunner.assertTrue(
                    onMain { engine.ratioLimitSatisfiedIDs.contains("seed-ratio-test") },
                    "Il torrent con ratio >= limite deve essere registrato nei ratioLimitSatisfiedIDs"
                )

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
                try TestRunner.assertEqual(variants.count, 21)
                for (name, area) in variants {
                    try TestRunner.assertTrue(
                        area > 0,
                        "La variante \(name) non ha prodotto un'immagine"
                    )
                }

                let extended = onMain {
                    ViewRenderingSupport.renderExtendedViews(engine: engine, torrents: engine.torrents)
                }
                try TestRunner.assertEqual(extended.count, 27)
                for (name, area) in extended {
                    try TestRunner.assertTrue(
                        area > 0,
                        "La vista estesa \(name) non ha prodotto un'immagine"
                    )
                }

                // Verify libtorrent error localization and absence of false positives
                try TestRunner.assertEqual(
                    onMain { engine.localizedError("missing info-hash from URI") },
                    L("Link o file non valido.")
                )
                try TestRunner.assertEqual(
                    onMain { engine.localizedError("expected value (list, dict, int or string) in bencoded string") },
                    L("Link o file non valido.")
                )
                try TestRunner.assertEqual(
                    onMain { engine.localizedError("torrent file is not a dictionary") },
                    L("Link o file non valido.")
                )
                try TestRunner.assertEqual(
                    onMain { engine.localizedError("torrent already exists in session") },
                    L("Questo torrent è già presente.")
                )
                try TestRunner.assertFalse(
                    onMain { engine.localizedError("File already exists") } == L("Questo torrent è già presente."),
                    "Un errore generico di filesystem non deve essere segnalato come torrent duplicato"
                )
                try TestRunner.assertEqual(
                    onMain { engine.localizedError("Parametri non validi") },
                    L("Parametri non validi.")
                )
                try TestRunner.assertEqual(
                    onMain {
                        engine.localizedError("Esiste già un file con lo stesso nome nella cartella di destinazione.")
                    },
                    L("Esiste già un file con lo stesso nome nella cartella di destinazione.")
                )

                // Multi-selection and completion notification hook
                let notified = onMain { AsyncBox<[String]>() }
                onMain {
                    engine.completionNotification = { names in
                        notified.value = names
                    }
                    let t1 = Torrent.test(id: "m1", name: "Multi1.iso", stateCode: 3, progress: 0.5, finished: false)
                    let t2 = Torrent.test(id: "m2", name: "Multi2.iso", stateCode: 3, progress: 0.5, finished: false)
                    engine.applySnapshotForTesting(VertexSnapshot.test(torrents: [t1, t2]))
                    engine.selectClick("m1", visibleIDs: ["m1", "m2"], command: false, shift: false)
                    engine.selectClick("m2", visibleIDs: ["m1", "m2"], command: true, shift: false)
                }
                try TestRunner.assertEqual(onMain { engine.selectedIDs }, ["m1", "m2"])
                try TestRunner.assertNil(
                    onMain { engine.selectedID },
                    "L'inspector singolo deve chiudersi quando sono selezionati più torrent"
                )
                try TestRunner.assertEqual(onMain { engine.selectedTorrents.count }, 2)

                onMain {
                    let t1Done = Torrent.test(
                        id: "m1", name: "Multi1.iso", stateCode: 5, progress: 1.0,
                        size: 1024, downloaded: 1024, finished: true, seeding: true)
                    let t2 = Torrent.test(id: "m2", name: "Multi2.iso", stateCode: 3, progress: 0.6, finished: false)
                    let t3Zero = Torrent.test(
                        id: "m3", name: "Zero.iso", stateCode: 3, progress: 0, size: 0, downloaded: 0, finished: false)
                    engine.applySnapshotForTesting(VertexSnapshot.test(torrents: [t1Done, t2, t3Zero]))
                }
                try TestRunner.assertEqual(onMain { notified.value }, ["Multi1.iso"])

                // M-1: 0-byte or 0-downloaded (all files skipped) torrents must never fire completion notifications.
                onMain {
                    notified.value = nil
                    let t1Done = Torrent.test(
                        id: "m1", name: "Multi1.iso", stateCode: 5, progress: 1.0,
                        size: 1024, downloaded: 1024, finished: true, seeding: true)
                    let t2Skipped = Torrent.test(
                        id: "m2", name: "Multi2.iso", stateCode: 4, progress: 1.0,
                        size: 1024, downloaded: 0, finished: true)
                    let t3ZeroDone = Torrent.test(
                        id: "m3", name: "Zero.iso", stateCode: 4, progress: 1.0,
                        size: 0, downloaded: 0, finished: true)
                    engine.applySnapshotForTesting(VertexSnapshot.test(torrents: [t1Done, t2Skipped, t3ZeroDone]))
                }
                try TestRunner.assertNil(
                    onMain { notified.value },
                    "Un torrent con size <= 0 o downloaded <= 0 non deve emettere notifica di completamento"
                )
            }

            TestRunner.run("Engine: una richiesta durante lo shutdown risponde sempre") {
                let workspace = try IntegrationWorkspace()
                let engine = try makeEngine(in: workspace, name: "shutdown-add")
                defer { shutdown(engine) }

                let answered = onMain { AsyncBox<String>() }
                onMain { engine.shutdown() }

                let rejected = onMain {
                    engine.addMagnet(
                        "magnet:?xt=urn:btih:dddddddddddddddddddddddddddddddddddddddd",
                        destination: engineDownloadPath(workspace, "shutdown-add"),
                        startPaused: false,
                        sequential: false
                    ) { message in
                        answered.value = message
                    }
                }
                // A dropped completion used to leave the add sheet open forever.
                try TestRunner.assertEqual(rejected, L("Motore non disponibile."))
                let callback = onMain { answered.value }
                try TestRunner.assertEqual(callback ?? "", L("Motore non disponibile."))
            }

            TestRunner.run("Engine: serializzazione impostazioni, ratio in coda, URL pendenti e path traversal") {
                let workspace = try IntegrationWorkspace()
                let (engine, configuration) = try makeEngineWithConfiguration(in: workspace, name: "guards")
                defer { shutdown(engine) }

                // L-02: safeTorrentChildURL blocks ../ traversal outside savePath.
                try TestRunner.assertNil(
                    TorrentEngine.safeTorrentChildURL(savePath: "/tmp/downloads", name: "../escape")
                )
                try TestRunner.assertNil(
                    TorrentEngine.safeTorrentChildURL(savePath: "/tmp/downloads", name: "../../etc/passwd")
                )
                try TestRunner.assertEqual(
                    TorrentEngine.safeTorrentChildURL(savePath: "/tmp/downloads", name: "ubuntu.iso")?.path,
                    "/tmp/downloads/ubuntu.iso"
                )

                // H-01: two rapid applySettings() calls back-to-back must serialize and
                // converge on the second configuration instead of dropping the update.
                var firstEdit = configuration
                firstEdit.lsd = true
                var secondEdit = configuration
                secondEdit.lsd = false
                secondEdit.bindAddress = "127.0.0.1"
                onMain {
                    engine.setConfigurationForTesting(firstEdit)
                    engine.applySettings()
                    engine.setConfigurationForTesting(secondEdit)
                    engine.applySettings()
                }
                try waitFor(engine) {
                    onMain {
                        !engine.isApplyingSettings && engine.stats.bindAddress == "127.0.0.1"
                    }
                }

                // M-11: a finished torrent that is paused ONLY because it is queued
                // (paused && autoManaged) must NOT be marked satisfied prematurely.
                var ratioCfg = secondEdit
                ratioCfg.seedRatioLimit = 1.0
                onMain {
                    engine.setConfigurationForTesting(ratioCfg)
                    engine.applySettings()
                }
                try waitUntil("applicazione ratioCfg") {
                    onMain { !engine.isApplyingSettings }
                }
                let queuedSeeder = Torrent.test(
                    id: "queued-seeder",
                    name: "QueuedSeeder",
                    stateCode: 5,
                    progress: 1.0,
                    finished: true,
                    seeding: true,
                    paused: true,
                    autoManaged: true,
                    ratio: 2.0
                )
                onMain {
                    engine.applySnapshotForTesting(VertexSnapshot.test(torrents: [queuedSeeder]))
                }
                try TestRunner.assertFalse(
                    onMain { engine.ratioLimitSatisfiedIDs.contains("queued-seeder") },
                    "Un torrent in coda non deve essere marcato soddisfatto prima della pausa automatica"
                )

                // Pending external URLs queued during PEX session restart must drain once ready.
                var pexToggle = ratioCfg
                pexToggle.pex = !configuration.pex
                let externalMagnet = URL(
                    string: "magnet:?xt=urn:btih:1111222233334444555566667777888899990000"
                )!
                onMain {
                    engine.setConfigurationForTesting(pexToggle)
                    engine.applySettings()
                    engine.openExternalURLs([externalMagnet])
                }
                try waitUntil("riavvio PEX e drenaggio URL pendenti") {
                    onMain { engine.isReady && !engine.isRestartingSession }
                }
                try waitForTorrent(engine)
                try TestRunner.assertTrue(
                    onMain {
                        engine.torrents.contains { $0.id == "1111222233334444555566667777888899990000" }
                    },
                    "Il magnet ricevuto durante il riavvio PEX deve essere accodato e aggiunto"
                )
                let drained = onMain {
                    engine.torrents.first { $0.id == "1111222233334444555566667777888899990000" }
                }
                try TestRunner.assertEqual(
                    drained?.savePath,
                    configuration.downloadPath,
                    "openExternalURLs senza destination esplicita deve rispettare configurationOverride.downloadPath"
                )
            }

            TestRunner.run("Engine: validazione indipendente campi, fail-closed proxy, sonda SOCKS5 e alert multipli") {
                try TestRunner.assertTrue(TorrentEngine.isProxyProtocolOrAuthError("SOCKS authentication error"))
                try TestRunner.assertTrue(TorrentEngine.isProxyProtocolOrAuthError("SOCKS unsupported version"))
                try TestRunner.assertTrue(TorrentEngine.isProxyProtocolOrAuthError("SOCKS general failure"))
                try TestRunner.assertTrue(TorrentEngine.isProxyProtocolOrAuthError("Host proxy non valido"))
                try TestRunner.assertTrue(
                    TorrentEngine.isProxyProtocolOrAuthError("Porta proxy fuori intervallo (1–65535).")
                )
                try TestRunner.assertFalse(TorrentEngine.isProxyProtocolOrAuthError(""))
                try TestRunner.assertFalse(TorrentEngine.isProxyProtocolOrAuthError("Connection refused"))

                let workspace = try IntegrationWorkspace()
                let suiteName = "app.vertex.engine-c1.\(UUID().uuidString)"
                let dataDir = try workspace.directory("c1-data")
                let downloadsDir = try workspace.directory("c1-downloads")
                let prevSuite = getenv("VERTEX_DEFAULTS_SUITE").map { String(cString: $0) }
                let prevData = getenv("VERTEX_DATA_DIR").map { String(cString: $0) }
                let prevDownloads = getenv("VERTEX_DOWNLOADS_DIR").map { String(cString: $0) }
                suiteName.withCString { _ = setenv("VERTEX_DEFAULTS_SUITE", $0, 1) }
                dataDir.path.withCString { _ = setenv("VERTEX_DATA_DIR", $0, 1) }
                downloadsDir.path.withCString { _ = setenv("VERTEX_DOWNLOADS_DIR", $0, 1) }
                defer {
                    if let prevSuite {
                        prevSuite.withCString { _ = setenv("VERTEX_DEFAULTS_SUITE", $0, 1) }
                    } else {
                        unsetenv("VERTEX_DEFAULTS_SUITE")
                    }
                    if let prevData {
                        prevData.withCString { _ = setenv("VERTEX_DATA_DIR", $0, 1) }
                    } else {
                        unsetenv("VERTEX_DATA_DIR")
                    }
                    if let prevDownloads {
                        prevDownloads.withCString { _ = setenv("VERTEX_DOWNLOADS_DIR", $0, 1) }
                    } else {
                        unsetenv("VERTEX_DOWNLOADS_DIR")
                    }
                    UserDefaults().removePersistentDomain(forName: suiteName)
                    workspace.cleanup()
                }

                let (engine, configuration) = try makeEngineWithConfiguration(in: workspace, name: "c1")
                defer { shutdown(engine) }

                try TestRunner.assertEqual(
                    onMain { engine.localizedError("Invalid cross-device link") },
                    L("Errore di lettura o scrittura sul disco.")
                )

                // B-3: multiple alert_errors in a single poll must all reach the toast without loss.
                let multiAlertJSON = """
                    {
                        "download_rate": 0, "upload_rate": 0, "active": 0, "paused_count": 0,
                        "dht_nodes": 0, "alert_error": "Permission denied",
                        "alert_errors": ["No space left on device", "Permission denied"],
                        "listen_actual_port": 6881, "listening": true, "bind_address": "",
                        "listen_error": "",
                        "portmap": {
                            "tcp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                            "udp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                            "error": ""
                        },
                        "port": 6881, "torrents": []
                    }
                    """
                let multiAlertSnapshot = try JSONDecoder().decode(
                    VertexSnapshot.self, from: Data(multiAlertJSON.utf8)
                )
                onMain { engine.applySnapshotForTesting(multiAlertSnapshot) }
                try TestRunner.assertEqual(onMain { engine.toast?.text ?? "" }, L("Spazio su disco insufficiente."))
                try TestRunner.assertEqual(onMain { engine.toast?.detail ?? "" }, L("Permesso negato."))

                // C-1: an invalid listenPort in UserDefaults must fall back to the previous port
                // without blocking a valid bindAddress update in the same applySettings() pass.
                let defaults = Preferences.userDefaults
                defaults.set(configuration.downloadPath, forKey: PrefKey.downloadPath)
                defaults.set(configuration.pex, forKey: PrefKey.pexEnabled)
                defaults.set(0, forKey: PrefKey.listenPort)
                defaults.set("203.0.113.9", forKey: PrefKey.bindAddress)
                defaults.set(false, forKey: PrefKey.proxyEnabled)
                onMain {
                    engine.configurationOverride = nil
                    engine.applySettings()
                }
                try TestRunner.assertEqual(onMain { engine.toast?.text ?? "" }, L("Porta non valida"))
                try waitFor(engine) {
                    onMain {
                        !engine.isApplyingSettings
                            && engine.stats.bindAddress == "203.0.113.9"
                            && !engine.stats.isListening
                    }
                }

                // C-1: proxyEnabled with an empty host or out-of-range port must invoke vt_fail_close_proxy.
                defaults.set(Int(configuration.port), forKey: PrefKey.listenPort)
                defaults.set("", forKey: PrefKey.bindAddress)
                defaults.set(true, forKey: PrefKey.proxyEnabled)
                defaults.set("   ", forKey: PrefKey.proxyHost)
                defaults.set(1080, forKey: PrefKey.proxyPort)
                onMain { engine.applySettings() }
                try TestRunner.assertEqual(onMain { engine.toast?.text ?? "" }, L("Host proxy non valido"))
                try waitFor(engine) {
                    onMain { !engine.isApplyingSettings && engine.stats.proxy.hasError }
                }

                defaults.set("127.0.0.1", forKey: PrefKey.proxyHost)
                defaults.set(70_000, forKey: PrefKey.proxyPort)
                onMain { engine.applySettings() }
                try TestRunner.assertEqual(onMain { engine.toast?.text ?? "" }, L("Porta proxy non valida"))
                try waitFor(engine) {
                    onMain {
                        !engine.isApplyingSettings
                            && engine.stats.proxy.hasError
                            && engine.stats.proxy.hostname.isEmpty
                            && engine.stats.proxy.port == 0
                    }
                }

                // #1: an unwritable downloadPath must NEVER prevent vt_fail_close_proxy or
                // vt_apply_proxy_settings from running first and updating the proxy baseline.
                defaults.set(false, forKey: PrefKey.proxyEnabled)
                defaults.set("127.0.0.1", forKey: PrefKey.proxyHost)
                defaults.set(1080, forKey: PrefKey.proxyPort)
                onMain { engine.applySettings() }
                try waitFor(engine) {
                    onMain { !engine.isApplyingSettings && !engine.stats.proxy.enabled }
                }

                let readonlyParent = try workspace.directory("c1-readonly-parent")
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o555],
                    ofItemAtPath: readonlyParent.path
                )
                defer {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: readonlyParent.path
                    )
                }
                let unwritableTarget = readonlyParent.appendingPathComponent("blocked-downloads", isDirectory: true)
                defaults.set(unwritableTarget.path, forKey: PrefKey.downloadPath)
                defaults.set(true, forKey: PrefKey.proxyEnabled)
                defaults.set("   ", forKey: PrefKey.proxyHost)
                defaults.set(1080, forKey: PrefKey.proxyPort)
                onMain { engine.applySettings() }
                try waitFor(engine) {
                    onMain {
                        !engine.isApplyingSettings
                            && engine.stats.proxy.enabled
                            && engine.stats.proxy.hasError
                            && !engine.stats.isListening
                    }
                }

                // Fixing proxyHost/proxyPort while downloadPath is STILL unwritable must also
                // apply the SOCKS5 endpoint instead of aborting early on vt_set_default_save_path.
                defaults.set("127.0.0.1", forKey: PrefKey.proxyHost)
                defaults.set(1080, forKey: PrefKey.proxyPort)
                onMain { engine.applySettings() }
                try waitFor(engine) {
                    onMain {
                        !engine.isApplyingSettings
                            && engine.stats.proxy.enabled
                            && engine.stats.proxy.hostname == "127.0.0.1"
                            && engine.stats.proxy.port == 1080
                    }
                }

                // #5: finishPoll with a stale generation must not clear isPollInFlight.
                onMain {
                    engine.isPollInFlight = true
                    engine.finishPoll(nil, generation: engine.sessionGeneration &- 1)
                }
                try TestRunner.assertTrue(
                    onMain { engine.isPollInFlight },
                    "Un poll di una generazione precedente non deve azzerare isPollInFlight"
                )
                onMain {
                    engine.finishPoll(nil, generation: engine.sessionGeneration)
                }
                try TestRunner.assertFalse(onMain { engine.isPollInFlight })
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
                    // Adds are async: pump the run loop so the Task can run before
                    // polling the snapshot.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
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
