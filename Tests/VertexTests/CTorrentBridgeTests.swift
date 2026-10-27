import Foundation
import CTorrent
import VertexKit

enum CTorrentBridgeTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: CTorrentBridgeTests]\u{001B}[0m")

        TestRunner.run("Session lifecycle: create, poll, settings, snapshot, destroy") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("vertex_test_\(UUID().uuidString)")
            let downloadDir = tempDir.appendingPathComponent("downloads")
            let resumeDir = tempDir.appendingPathComponent("resume")

            try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)

            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            // Create session through the full entry point, also covering the
            // explicit UPnP/NAT-PMP switch used by the app.
            let session = downloadDir.path.withCString { dlPath in
                resumeDir.path.withCString { resPath in
                    vt_session_create_full(dlPath, resPath, 6882, 0, 0, 0, 0, 0, 0)
                }
            }

            try TestRunner.assertNotNil(session, "vt_session_create_full deve restituire un puntatore valido")
            guard let session else { return }

            // Poll
            vt_session_poll(session)

            // Apply settings
            let settingsResult = vt_apply_settings_ex(
                session,
                6883,
                1024 * 1024,
                512 * 1024,
                0,
                0,
                0
            )
            try TestRunner.assertEqual(settingsResult, 0, "vt_apply_settings_ex deve restituire 0 per successo")

            // Snapshot JSON
            let cSnapshot = vt_snapshot_json(session)
            try TestRunner.assertNotNil(cSnapshot, "vt_snapshot_json deve restituire un puntatore non nullo")

            if let cSnapshot {
                let jsonString = String(cString: cSnapshot)
                vt_free_string(cSnapshot)

                try TestRunner.assertTrue(jsonString.contains("download_rate"), "Lo snapshot deve contenere download_rate")
                try TestRunner.assertTrue(jsonString.contains("torrents"), "Lo snapshot deve contenere l'array torrents")
                try TestRunner.assertTrue(jsonString.contains("listening"), "Lo snapshot deve contenere il flag listening")

                let snapshotData = Data(jsonString.utf8)
                let decoded = try JSONDecoder().decode(VertexSnapshot.self, from: snapshotData)
                try TestRunner.assertEqual(decoded.torrents.count, 0, "La sessione di test non deve avere torrent")
                try TestRunner.assertTrue(decoded.port > 0, "Lo snapshot deve esporre la porta di ascolto")
            }

            // Test add invalid magnet - should gracefully fail without crashing
            let invalidMagnet = "invalid_uri_string"
            let addResult = invalidMagnet.withCString { uriPtr in
                downloadDir.path.withCString { dlPtr in
                    vt_add_magnet(session, uriPtr, dlPtr, 0, 0)
                }
            }
            try TestRunner.assertTrue(addResult != 0, "Aggiungere un magnet non valido deve fallire con codice diverso da 0")

            // Verify last error is available
            let cError = vt_last_error(session)
            if let cError {
                let err = String(cString: cError)
                vt_free_string(cError)
                try TestRunner.assertFalse(err.isEmpty, "vt_last_error deve contenere il messaggio di errore")
            }

            // Destroy session
            vt_session_destroy(session)
        }

        TestRunner.run("Default save path: aggiornamento usato dai torrent senza destinazione") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("vertex_default_path_\(UUID().uuidString)")
            let firstDownloadDir = tempDir.appendingPathComponent("downloads-1")
            let secondDownloadDir = tempDir.appendingPathComponent("downloads-2")
            let resumeDir = tempDir.appendingPathComponent("resume")

            try FileManager.default.createDirectory(at: firstDownloadDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let session = firstDownloadDir.path.withCString { dlPath in
                resumeDir.path.withCString { resPath in
                    vt_session_create_full(dlPath, resPath, 6884, 0, 0, 0, 0, 0, 0)
                }
            }
            guard let session else {
                try TestRunner.assertTrue(false, "vt_session_create_full deve restituire un puntatore valido")
                return
            }
            defer { vt_session_destroy(session) }

            let updated = secondDownloadDir.path.withCString {
                vt_set_default_save_path(session, $0)
            }
            try TestRunner.assertEqual(updated, 0, "vt_set_default_save_path deve accettare una cartella valida")
            try TestRunner.assertTrue(
                FileManager.default.fileExists(atPath: secondDownloadDir.path),
                "La nuova cartella predefinita deve essere creata"
            )

            let magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
            let addResult = magnet.withCString {
                vt_add_magnet(session, $0, nil, 1, 0)
            }
            try TestRunner.assertEqual(addResult, 0, "Il magnet valido deve essere aggiunto")

            vt_session_poll(session)
            guard let cSnapshot = vt_snapshot_json(session) else {
                try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                return
            }
            let json = String(cString: cSnapshot)
            vt_free_string(cSnapshot)
            let snapshot = try JSONDecoder().decode(VertexSnapshot.self, from: Data(json.utf8))
            guard let torrent = snapshot.torrents.first else {
                try TestRunner.assertTrue(false, "Lo snapshot deve contenere il torrent aggiunto")
                return
            }
            try TestRunner.assertEqual(
                torrent.savePath,
                secondDownloadDir.path,
                "Il torrent senza save path deve usare la nuova cartella predefinita"
            )

            let filePath = tempDir.appendingPathComponent("not-a-directory")
            try Data("x".utf8).write(to: filePath)
            let rejectedFile = filePath.path.withCString {
                vt_set_default_save_path(session, $0)
            }
            try TestRunner.assertTrue(
                rejectedFile != 0,
                "Un file non può essere usato come cartella predefinita"
            )
            try TestRunner.assertTrue(
                vt_set_default_save_path(session, nil) != 0,
                "Un percorso nullo deve essere rifiutato"
            )
        }
    }
}
