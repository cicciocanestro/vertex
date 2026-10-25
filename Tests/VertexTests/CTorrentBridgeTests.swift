import Foundation
import CTorrent

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

            // Create session
            let session = downloadDir.path.withCString { dlPath in
                resumeDir.path.withCString { resPath in
                    vt_session_create(dlPath, resPath, 6882, 0, 0, 0)
                }
            }

            try TestRunner.assertNotNil(session, "vt_session_create deve restituire un puntatore valido")
            guard let session else { return }

            // Poll
            vt_session_poll(session)

            // Apply settings
            let settingsResult = vt_apply_settings(session, 6883, 1024 * 1024, 512 * 1024, 0, 0)
            try TestRunner.assertEqual(settingsResult, 0, "vt_apply_settings deve restituire 0 per successo")

            // Snapshot JSON
            let cSnapshot = vt_snapshot_json(session)
            try TestRunner.assertNotNil(cSnapshot, "vt_snapshot_json deve restituire un puntatore non nullo")

            if let cSnapshot {
                let jsonString = String(cString: cSnapshot)
                vt_free_string(cSnapshot)

                try TestRunner.assertTrue(jsonString.contains("download_rate"), "Lo snapshot deve contenere download_rate")
                try TestRunner.assertTrue(jsonString.contains("torrents"), "Lo snapshot deve contenere l'array torrents")
                try TestRunner.assertTrue(jsonString.contains("listening"), "Lo snapshot deve contenere il flag listening")
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
    }
}
