import Foundation
import CTorrent
import VertexKit

enum CTorrentBridgeTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: CTorrentBridgeTests]\u{001B}[0m")

        TestRunner.run("Session lifecycle: create, poll, settings, snapshot, destroy") {
            try withRawSession(port: 6882) { session, _, downloadDir, _ in
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
                    0,
                    nil
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
            }
        }

        TestRunner.run("Default save path: aggiornamento usato dai torrent senza destinazione") {
            try withRawSession(port: 6884) { session, workspace, _, _ in
                let secondDownloadDir = workspace.root.appendingPathComponent("downloads-2")

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

                let filePath = workspace.root.appendingPathComponent("not-a-directory")
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
        TestRunner.run("Binding: ascolto limitato a un indirizzo locale") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "127.0.0.1") { session, _, _, _ in
                try TestsSupport.waitFor("ascolto su 127.0.0.1", timeout: 5) {
                    try snapshot(of: session).listening
                }
                let snapshot = try snapshot(of: session)
                try TestRunner.assertEqual(snapshot.bindAddress, "127.0.0.1")
                try TestRunner.assertEqual(snapshot.listenError, "")
                try TestRunner.assertEqual(snapshot.listenActualPort, Int(port))
            }
        }

        TestRunner.run("Binding: indirizzo non locale segnala l'errore di ascolto") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "203.0.113.9") { session, _, _, _ in
                try TestsSupport.waitFor("errore di ascolto", timeout: 5) {
                    try !snapshot(of: session).listenError.isEmpty
                }
                let snapshot = try snapshot(of: session)
                try TestRunner.assertEqual(snapshot.bindAddress, "203.0.113.9")
                try TestRunner.assertFalse(
                    snapshot.listening,
                    "Un indirizzo non locale non deve aprire il socket"
                )
                try TestRunner.assertTrue(
                    snapshot.listenError.contains("203.0.113.9"),
                    "L'errore deve citare l'indirizzo non disponibile: \(snapshot.listenError)"
                )
            }
        }

        TestRunner.run("Binding: rimozione dell'associazione riapre tutte le interfacce") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "127.0.0.1") { session, _, _, _ in
                try TestsSupport.waitFor("ascolto associato", timeout: 5) {
                    try snapshot(of: session).listening
                }

                let reopened = vt_apply_settings_ex(
                    session,
                    port,
                    0,
                    0,
                    0,
                    0,
                    0,
                    nil
                )
                try TestRunner.assertEqual(reopened, 0)

                try TestsSupport.waitFor("ascolto su tutte le interfacce", timeout: 5) {
                    let snapshot = try snapshot(of: session)
                    return snapshot.bindAddress.isEmpty && snapshot.listening
                }
                let snapshot = try snapshot(of: session)
                try TestRunner.assertEqual(snapshot.bindAddress, "")
                try TestRunner.assertFalse(snapshot.stats.isBoundToAddress)
            }
        }

        TestRunner.run("Session: smoke UPnP/NAT-PMP (solo con VERTEX_TEST_UPNP=1)") {
            try upnpSmoke()
        }
    }

    /// Decodes the session snapshot through the same model the UI uses, so the
    /// binding tests also cover the JSON contract.
    private static func snapshot(of session: OpaquePointer) throws -> VertexSnapshot {
        vt_session_poll(session)
        guard let pointer = vt_snapshot_json(session) else {
            throw TestFailure(
                message: "vt_snapshot_json ha restituito un puntatore nullo",
                file: #file,
                line: #line
            )
        }
        let json = String(cString: pointer)
        vt_free_string(pointer)
        return try JSONDecoder().decode(VertexSnapshot.self, from: Data(json.utf8))
    }

    /// Best-effort router test. It never requires a successful mapping: the
    /// runner has no UPnP gateway, so it only checks that every reported state
    /// is internally consistent. It is disabled unless explicitly requested.
    private static func upnpSmoke() throws {
        guard ProcessInfo.processInfo.environment["VERTEX_TEST_UPNP"] == "1" else {
            print("(gate disattivato) ", terminator: "")
            return
        }

        let port = try TestsSupport.freeTCPPort()
        try withRawSession(port: Int32(port), upnp: true) { session, _, _, _ in
            var lastSnapshot: VertexSnapshot?
            let deadline = Date().addingTimeInterval(8)
            repeat {
                vt_session_poll(session)
                guard let pointer = vt_snapshot_json(session) else { break }
                let json = String(cString: pointer)
                vt_free_string(pointer)
                guard let data = json.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(VertexSnapshot.self, from: data) else {
                    break
                }
                lastSnapshot = snapshot
                let mapping = snapshot.portmap
                if mapping.tcp.mapped || mapping.udp.mapped || mapping.hasError {
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            } while Date() < deadline

            guard let snapshot = lastSnapshot else {
                throw TestFailure(
                    message: "Lo snapshot della sessione UPnP non è decodificabile",
                    file: #file,
                    line: #line
                )
            }

            try TestRunner.assertEqual(snapshot.port, port)
            try validateMapping(snapshot.portmap.tcp, label: "TCP")
            try validateMapping(snapshot.portmap.udp, label: "UDP")
            if !snapshot.portmap.error.isEmpty {
                try TestRunner.assertTrue(
                    hasTransportPrefix(snapshot.portmap.error),
                    "L'errore di mapping non identifica il trasporto: \(snapshot.portmap.error)"
                )
            }
        }
    }

    /// Creates a raw C session in a temporary workspace and destroys it at the
    /// end, so each test only contains its own assertions.
    private static func withRawSession(
        port: Int32,
        upnp: Bool = false,
        bindAddress: String? = nil,
        _ body: (OpaquePointer, IntegrationWorkspace, URL, URL) throws -> Void
    ) throws {
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }
        let download = try workspace.directory("downloads")
        let resume = try workspace.directory("resume")

        let session = download.path.withCString { dlPath in
            resume.path.withCString { resPath in
                if let bindAddress {
                    return bindAddress.withCString { bindPath in
                        vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0,
                                               upnp ? 1 : 0, bindPath)
                    }
                }
                return vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0,
                                              upnp ? 1 : 0, nil)
            }
        }
        guard let session else {
            throw TestFailure(
                message: "vt_session_create_full deve restituire un puntatore valido",
                file: #file,
                line: #line
            )
        }
        defer { vt_session_destroy(session) }
        try body(session, workspace, download, resume)
    }

    private static func validateMapping(_ info: PortMapInfo, label: String) throws {
        if info.mapped {
            try TestRunner.assertTrue(
                info.externalPort > 0,
                "\(label) mappata senza porta esterna"
            )
            try TestRunner.assertTrue(
                info.transport == "UPnP" || info.transport == "NAT-PMP",
                "\(label) mappata con trasporto inatteso: \(info.transport)"
            )
        } else {
            try TestRunner.assertEqual(info.externalPort, 0, "\(label) non mappata con porta esterna")
            try TestRunner.assertEqual(info.transport, "", "\(label) non mappata con trasporto")
        }

        if !info.error.isEmpty {
            try TestRunner.assertTrue(
                hasTransportPrefix(info.error),
                "L'errore \(label) non identifica il trasporto: \(info.error)"
            )
        }
    }

    private static func hasTransportPrefix(_ error: String) -> Bool {
        error.hasPrefix("UPnP: ") || error.hasPrefix("NAT-PMP: ")
    }
}
