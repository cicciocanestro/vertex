import Foundation
import CTorrent
import VertexKit

enum TorrentIntegrationTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: TorrentIntegrationTests]\u{001B}[0m")

        TestRunner.run("Loopback seed/download: torrent v1") {
            try transfer(.v1)
        }

        TestRunner.run("Loopback seed/download: torrent v2") {
            try transfer(.v2)
        }

        TestRunner.run("Pausa e ripresa tramite vt_control") {
            try pauseAndResume()
        }

        TestRunner.run("Resume: ricaricamento dopo riavvio della sessione") {
            try resumeAfterRestart()
        }

        TestRunner.run("Resume: cambio PEX con sessione ricreata") {
            try resumeAfterPexChange()
        }

        TestRunner.run("Priorità file: esclusione del secondo file") {
            try filePriority()
        }

        TestRunner.run("Rimozione: senza file e con delete_files") {
            try removeAndDeleteFiles()
        }

        TestRunner.run("Due torrent contemporanei in un solo swarm locale") {
            try multipleTorrents()
        }

        TestRunner.run("Fallimenti: torrent, peer e percorso non scrivibile") {
            try failurePaths()
        }
    }

    private static func transfer(_ fixture: IntegrationFixture) throws {
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port
        )
        defer { leech.session.close() }

        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)

        for file in fixture.files {
            try fixture.assertDownloaded(in: leech.session.downloadDirectory, path: file.path)
        }

        // The v2 fixture also exercises the detail JSON path for a v2-only
        // torrent, including the tracker-stats selection in the bridge.
        let detail = try leech.session.detail(torrentID: leech.torrentID)
        try TestRunner.assertEqual(detail.metadata, true)
        try TestRunner.assertEqual(detail.files.count, 2)
        try TestRunner.assertTrue(detail.trackers.isEmpty, "I fixture non hanno tracker")
    }

    private static func pauseAndResume() throws {
        let fixture = IntegrationFixture.v1
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port
        )
        defer { leech.session.close() }

        try leech.session.control(torrentID: leech.torrentID, action: "pause")
        try TestsSupport.waitFor("pausa del torrent") {
            try leech.session.snapshot().torrents.first?.paused == true
        }

        try leech.session.control(torrentID: leech.torrentID, action: "resume")
        try TestsSupport.waitFor("ripresa del torrent") {
            try leech.session.snapshot().torrents.first?.paused == false
        }

        // The transfer itself is covered by the v1/v2 tests. Do not make this
        // state-transition test depend on a peer reconnection after resume.
        let resumed = try leech.session.snapshot()
        try TestRunner.assertEqual(
            resumed.torrents.first?.paused,
            false,
            "Il torrent deve risultare in ripresa"
        )
    }

    private static func resumeAfterRestart() throws {
        let fixture = IntegrationFixture.v1
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port
        )
        defer { leech.session.close() }

        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)
        try fixture.assertDownloaded(in: leech.session.downloadDirectory, path: "data.bin")

        let downloadDirectory = leech.session.downloadDirectory
        let resumeDirectory = leech.session.resumeDirectory
        let torrentID = leech.torrentID
        let resumeFile = resumeDirectory.appendingPathComponent("\(torrentID).resume")
        leech.session.close()

        try TestRunner.assertTrue(
            FileManager.default.fileExists(atPath: resumeFile.path),
            "Il resume data non è stato scritto in \(resumeFile.path)"
        )

        let restarted = try BridgeSession(
            downloadDirectory: downloadDirectory,
            resumeDirectory: resumeDirectory,
            port: try TestsSupport.freeTCPPort()
        )
        defer { restarted.close() }

        try TestsSupport.waitFor("ricaricamento del resume") {
            try restarted.snapshot().torrents.contains {
                $0.name == fixture.rootName && $0.hasMetadata
            }
        }

        let restored = try restarted.waitForTorrent(fixture.rootName)
        try TestRunner.assertTrue(restored.hasMetadata, "Il torrent ricaricato non ha metadati")
        try TestRunner.assertEqual(
            restored.savePath,
            downloadDirectory.path,
            "Il save_path non è stato preservato dal resume"
        )
        try fixture.assertDownloaded(in: downloadDirectory, path: "data.bin")
    }

    private static func resumeAfterPexChange() throws {
        let fixture = IntegrationFixture.v1
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port,
            enablePEX: true
        )
        defer { leech.session.close() }

        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)
        try fixture.assertDownloaded(in: leech.session.downloadDirectory, path: "data.bin")

        let downloadDirectory = leech.session.downloadDirectory
        let resumeDirectory = leech.session.resumeDirectory
        let torrentID = leech.torrentID
        let resumeFile = resumeDirectory.appendingPathComponent("\(torrentID).resume")
        leech.session.close()

        try TestRunner.assertTrue(
            FileManager.default.fileExists(atPath: resumeFile.path),
            "Il resume data non è stato scritto in \(resumeFile.path)"
        )

        // This is the same recreate-and-reload path used when the PEX toggle
        // changes, with the plugin disabled on the new session.
        let restarted = try BridgeSession(
            downloadDirectory: downloadDirectory,
            resumeDirectory: resumeDirectory,
            port: try TestsSupport.freeTCPPort(),
            enablePEX: false
        )
        defer { restarted.close() }

        try TestsSupport.waitFor("ricaricamento del resume dopo cambio PEX") {
            try restarted.snapshot().torrents.contains {
                $0.name == fixture.rootName && $0.hasMetadata
            }
        }

        let restored = try restarted.waitForTorrent(fixture.rootName)
        try TestRunner.assertEqual(
            restored.savePath,
            downloadDirectory.path,
            "Il save_path non è stato preservato dopo il cambio PEX"
        )
        try fixture.assertDownloaded(in: downloadDirectory, path: "data.bin")
    }

    private static func filePriority() throws {
        let fixture = IntegrationFixture.v1
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port,
            configureBeforeConnect: { session, torrentID in
                try session.setFilePriority(torrentID: torrentID, fileIndex: 1, priority: 0)
                try TestsSupport.waitFor("applicazione della priorità") {
                    let detail = try session.detail(torrentID: torrentID)
                    return detail.files.count == 2 && detail.files[1].priority == 0
                }
            }
        )
        defer { leech.session.close() }

        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)
        try fixture.assertDownloaded(in: leech.session.downloadDirectory, path: "data.bin")

        let skipped = leech.session.downloadDirectory
            .appendingPathComponent(fixture.rootName, isDirectory: true)
            .appendingPathComponent("second.bin")
        if FileManager.default.fileExists(atPath: skipped.path) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: skipped.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(size, 0, "Il file con priorità 0 è stato scritto")
        }
    }

    private static func removeAndDeleteFiles() throws {
        let fixture = IntegrationFixture.v1
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let seed = try IntegrationSwarm.makeSeed(fixture, workspace: workspace)
        defer { seed.session.close() }

        let leech = try IntegrationSwarm.makeLeech(
            fixture,
            workspace: workspace,
            seedPort: seed.port
        )
        defer { leech.session.close() }

        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)
        let dataURL = leech.session.downloadDirectory
            .appendingPathComponent(fixture.rootName, isDirectory: true)
            .appendingPathComponent("data.bin")
        try TestRunner.assertTrue(
            FileManager.default.fileExists(atPath: dataURL.path),
            "Il file scaricato non esiste"
        )

        try leech.session.control(torrentID: leech.torrentID, action: "remove")
        try TestsSupport.waitFor("rimozione senza delete_files") {
            try leech.session.snapshot().torrents.isEmpty
        }
        try TestRunner.assertTrue(
            FileManager.default.fileExists(atPath: dataURL.path),
            "remove non deve cancellare i file"
        )

        try leech.session.addTorrentFile(
            fixture.torrentURL.path,
            savePath: leech.session.downloadDirectory.path
        )
        let readded = try leech.session.waitForTorrent(fixture.rootName)
        try leech.session.addPeer(torrentID: readded.id, port: seed.port)
        try IntegrationSwarm.waitForCompletion(leech.session, name: fixture.rootName)

        try leech.session.control(torrentID: readded.id, action: "remove_files")
        try TestsSupport.waitFor("rimozione con delete_files") {
            try leech.session.snapshot().torrents.isEmpty
        }
        for file in fixture.files {
            let url = leech.session.downloadDirectory
                .appendingPathComponent(fixture.rootName, isDirectory: true)
                .appendingPathComponent(file.path)
            try TestsSupport.waitFor("cancellazione di \(url.lastPathComponent)") {
                !FileManager.default.fileExists(atPath: url.path)
            }
        }
    }

    private static func multipleTorrents() throws {
        let fixtures: [IntegrationFixture] = [.v1, .v2]
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let sourceRoot = try workspace.directory("seed")
        for fixture in fixtures {
            try fixture.writeSource(in: sourceRoot)
        }
        let seedPort = try TestsSupport.freeTCPPort()
        let seed = try BridgeSession(
            downloadDirectory: sourceRoot,
            resumeDirectory: try workspace.directory("seed-resume"),
            port: seedPort
        )
        defer { seed.close() }

        for fixture in fixtures {
            try seed.addTorrentFile(
                fixture.torrentURL.path,
                savePath: sourceRoot.path
            )
        }
        try TestsSupport.waitFor("seed multiplo in ascolto") {
            let snapshot = try seed.snapshot()
            return snapshot.torrents.count == 2
                && snapshot.listenActualPort > 0
                && snapshot.torrents.allSatisfy { $0.hasMetadata }
        }
        try TestsSupport.waitFor("seed multiplo in seeding") {
            let snapshot = try seed.snapshot()
            return snapshot.torrents.count == 2
                && snapshot.torrents.allSatisfy { $0.seeding || $0.finished }
        }

        let downloadRoot = try workspace.directory("download")
        let leech = try BridgeSession(
            downloadDirectory: downloadRoot,
            resumeDirectory: try workspace.directory("download-resume"),
            port: try TestsSupport.freeTCPPort()
        )
        defer { leech.close() }

        for fixture in fixtures {
            try leech.addTorrentFile(
                fixture.torrentURL.path,
                savePath: downloadRoot.path
            )
        }
        try TestsSupport.waitFor("metadata dei due torrent") {
            let snapshot = try leech.snapshot()
            return snapshot.torrents.count == 2
                && snapshot.torrents.allSatisfy { $0.hasMetadata }
        }

        let actualSeedPort = try seed.snapshot().listenActualPort
        for fixture in fixtures {
            let torrent = try leech.waitForTorrent(fixture.rootName)
            try leech.addPeer(
                torrentID: torrent.id,
                port: actualSeedPort > 0 ? actualSeedPort : seedPort
            )
        }
        try TestsSupport.waitFor("completamento dei due torrent") {
            let snapshot = try leech.snapshot()
            return snapshot.torrents.count == 2
                && snapshot.torrents.allSatisfy { $0.finished }
        }

        for fixture in fixtures {
            for file in fixture.files {
                try fixture.assertDownloaded(in: downloadRoot, path: file.path)
            }
        }
    }

    private static func failurePaths() throws {
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }

        let defaultRoot = try workspace.directory("default")
        let session = try BridgeSession(
            downloadDirectory: defaultRoot,
            resumeDirectory: try workspace.directory("resume"),
            port: try TestsSupport.freeTCPPort()
        )
        defer { session.close() }

        let missingTorrent = workspace.root.appendingPathComponent("missing.torrent").path
        let addResult = missingTorrent.withCString { path in
            defaultRoot.path.withCString { destination in
                vt_add_torrent_file(session.pointer, path, destination, 0, 0)
            }
        }
        try TestRunner.assertTrue(addResult != 0, "Un torrent inesistente deve fallire")
        try TestRunner.assertFalse(
            session.lastError().isEmpty,
            "Un torrent inesistente deve produrre un errore"
        )

        let invalidPeer = "missing-torrent-id".withCString { id in
            "127.0.0.1".withCString { host in
                vt_add_peer(session.pointer, id, host, 1)
            }
        }
        try TestRunner.assertTrue(invalidPeer != 0, "Un peer su un torrent inesistente deve fallire")

        let invalidPriority = "missing-torrent-id".withCString { id in
            vt_set_file_priority(session.pointer, id, 0, 0)
        }
        try TestRunner.assertTrue(invalidPriority != 0, "Una priorità su un torrent inesistente deve fallire")

        let outOfRangePriority = "missing-torrent-id".withCString { id in
            vt_set_file_priority(session.pointer, id, 0, 8)
        }
        try TestRunner.assertTrue(outOfRangePriority != 0, "Una priorità fuori range deve fallire")
        try TestRunner.assertTrue(
            session.lastError().contains("Parametri non validi"),
            "Una priorità fuori range deve produrre un errore esplicito"
        )

        let readonly = try workspace.directory("readonly")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: readonly.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: readonly.path
            )
        }

        // The C bridge must repair an unusable destination to the session default.
        try session.addTorrentFile(
            IntegrationFixture.v1.torrentURL.path,
            savePath: readonly.path,
            paused: true
        )
        let added = try session.waitForTorrent(IntegrationFixture.v1.rootName)
        try TestRunner.assertEqual(
            added.savePath,
            defaultRoot.path,
            "La destinazione non scrivibile non è stata riparata"
        )
    }
}
