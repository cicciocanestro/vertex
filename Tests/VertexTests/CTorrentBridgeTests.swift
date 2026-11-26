import CTorrent
import Foundation
import VertexKit

/// Small thread-safe probe: the concurrent test must report a corrupted
/// snapshot from a background queue without trapping.
private final class ConcurrentProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var corrupted = false

    func markCorrupted() {
        lock.lock()
        corrupted = true
        lock.unlock()
    }

    var isCorrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return corrupted
    }
}

private final class SessionPointer: @unchecked Sendable {
    let value: OpaquePointer

    init(_ value: OpaquePointer) {
        self.value = value
    }
}

enum CTorrentBridgeTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: CTorrentBridgeTests]\u{001B}[0m")

        TestRunner.run("Session lifecycle: create, poll, settings, snapshot, destroy") {
            let initialPort = Int32(try TestsSupport.freeTCPPort())
            let updatedPort = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: initialPort) { session, _, downloadDir, _ in
                // Poll
                vt_session_poll(session)

                // Apply settings
                let settingsResult = vt_apply_settings_ex(
                    session,
                    updatedPort,
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

                    try TestRunner.assertTrue(
                        jsonString.contains("download_rate"), "Lo snapshot deve contenere download_rate")
                    try TestRunner.assertTrue(
                        jsonString.contains("torrents"), "Lo snapshot deve contenere l'array torrents")
                    try TestRunner.assertTrue(
                        jsonString.contains("listening"), "Lo snapshot deve contenere il flag listening")
                    try TestRunner.assertTrue(
                        jsonString.contains("alert_error"), "Lo snapshot deve esporre alert_error")

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
                try TestRunner.assertTrue(
                    addResult != 0, "Aggiungere un magnet non valido deve fallire con codice diverso da 0")

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
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port) { session, workspace, _, _ in
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

                // The normalization used by Swift and by the engine is the same C helper.
                try TestRunner.assertEqual(
                    normalizedPath(filePath.path, fallback: workspace.root.path) ?? "",
                    workspace.root.path,
                    "Un file deve usare la cartella che lo contiene"
                )
                try TestRunner.assertEqual(
                    normalizedPath("", fallback: workspace.root.path) ?? "",
                    workspace.root.path,
                    "Un percorso vuoto deve usare il fallback"
                )
                try TestRunner.assertEqual(
                    normalizedPath(
                        workspace.root.appendingPathComponent("missing.torrent").path,
                        fallback: workspace.root.path
                    ) ?? "",
                    workspace.root.path,
                    "Un .torrent inesistente deve usare la cartella che lo contiene"
                )
                try TestRunner.assertEqual(
                    normalizedPath("~otheruser/Downloads", fallback: workspace.root.path) ?? "",
                    "~otheruser/Downloads",
                    "~utente non deve essere espanso usando $HOME dell'utente corrente"
                )
                let fallbackExpanded = normalizedPath("   ", fallback: "~/Downloads") ?? ""
                try TestRunner.assertFalse(
                    fallbackExpanded.hasPrefix("~"),
                    "Una richiesta solo spazi deve normalizzare ed espandere anche il fallback"
                )
            }
        }
        TestRunner.run("Session lifecycle: errore di creazione con percorso non valido") {
            let workspace = try IntegrationWorkspace()
            defer { workspace.cleanup() }
            let resume = try workspace.directory("resume")
            let invalidDownload = workspace.root.appendingPathComponent("downloads")
            try Data("x".utf8).write(to: invalidDownload)
            let port = Int32(try TestsSupport.freeTCPPort())

            var errorPointer: UnsafeMutablePointer<CChar>?
            let session = invalidDownload.path.withCString { downloadPath in
                resume.path.withCString { resumePath in
                    vt_session_create_full(
                        downloadPath,
                        resumePath,
                        port,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        nil,
                        &errorPointer
                    )
                }
            }

            try TestRunner.assertNil(
                session,
                "vt_session_create_full deve fallire se la cartella è un file"
            )
            guard let errorPointer else {
                throw TestFailure(
                    message: "vt_session_create_full deve restituire il messaggio d'errore",
                    file: #file,
                    line: #line
                )
            }
            let message = String(cString: errorPointer)
            vt_free_string(errorPointer)
            try TestRunner.assertTrue(
                message.contains(invalidDownload.path),
                "Il messaggio d'errore deve indicare il percorso non valido: \(message)"
            )
        }

        TestRunner.run("Binding: ascolto limitato a un indirizzo locale") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "127.0.0.1") { session, _, _, _ in
                try TestsSupport.waitFor("ascolto su 127.0.0.1", timeout: 5) {
                    try sessionSnapshot(of: session).listening
                }
                let state = try sessionSnapshot(of: session)
                try TestRunner.assertEqual(state.bindAddress, "127.0.0.1")
                try TestRunner.assertEqual(state.listenError, "")
                try TestRunner.assertEqual(state.listenActualPort, Int(port))
            }
        }

        TestRunner.run("Binding: indirizzo non locale segnala l'errore di ascolto") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "203.0.113.9") { session, _, _, _ in
                try TestsSupport.waitFor("errore di ascolto", timeout: 5) {
                    try !sessionSnapshot(of: session).listenError.isEmpty
                }
                let state = try sessionSnapshot(of: session)
                try TestRunner.assertEqual(state.bindAddress, "203.0.113.9")
                try TestRunner.assertFalse(
                    state.listening,
                    "Un indirizzo non locale non deve aprire il socket"
                )
                try TestRunner.assertTrue(
                    state.listenError.contains("203.0.113.9"),
                    "L'errore deve citare l'indirizzo non disponibile: \(state.listenError)"
                )
            }
        }

        TestRunner.run("Binding: rimozione dell'associazione riapre tutte le interfacce") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port, bindAddress: "127.0.0.1") { session, _, _, _ in
                try TestsSupport.waitFor("ascolto associato", timeout: 5) {
                    try sessionSnapshot(of: session).listening
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
                    let inner = try sessionSnapshot(of: session)
                    return inner.bindAddress.isEmpty && inner.listening
                }
                let state = try sessionSnapshot(of: session)
                try TestRunner.assertEqual(state.bindAddress, "")
                try TestRunner.assertFalse(state.stats.isBoundToAddress)
            }
        }

        TestRunner.run("Bridge: configurazione SOCKS5 proxy") {
            let port = Int32(try TestsSupport.freeTCPPort())
            try withRawSession(port: port) { session, _, _, _ in
                // Initially proxy is disabled
                vt_session_poll(session)
                guard let cInit = vt_snapshot_json(session) else {
                    try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                    return
                }
                let initSnap = try JSONDecoder().decode(VertexSnapshot.self, from: Data(String(cString: cInit).utf8))
                vt_free_string(cInit)
                try TestRunner.assertFalse(initSnap.stats.isProxyActive)
                try TestRunner.assertEqual(initSnap.proxy.type, "None")

                // Apply SOCKS5 proxy with authentication (RFC 1929)
                let proxyHost = "127.0.0.1"
                let applyResult = proxyHost.withCString { hostPtr in
                    vt_apply_proxy_settings(session, 1, hostPtr, 1080, "testuser", "testpass")
                }
                try TestRunner.assertEqual(applyResult, 0, "vt_apply_proxy_settings deve restituire 0")

                vt_session_poll(session)
                guard let cActive = vt_snapshot_json(session) else {
                    try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                    return
                }
                let activeSnap = try JSONDecoder().decode(
                    VertexSnapshot.self, from: Data(String(cString: cActive).utf8))
                vt_free_string(cActive)
                try TestRunner.assertTrue(activeSnap.stats.isProxyActive)
                try TestRunner.assertEqual(activeSnap.proxy.type, "SOCKS5")
                try TestRunner.assertEqual(activeSnap.proxy.hostname, "127.0.0.1")
                try TestRunner.assertEqual(activeSnap.proxy.port, 1080)
                try TestRunner.assertTrue(
                    activeSnap.proxy.auth,
                    "Con un utente configurato il bridge deve usare socks5_pw (RFC 1929)"
                )
                try TestRunner.assertFalse(activeSnap.portmap.tcp.mapped)
                try TestRunner.assertFalse(activeSnap.portmap.udp.mapped)

                // Verify runtime settings update preserves UPnP disabled when proxy is active
                let settingsUpdate = vt_apply_settings_ex(
                    session,
                    port,
                    0,
                    0,
                    1,  // enable_dht
                    1,  // enable_upnp requested
                    1,  // enable_lsd
                    nil
                )
                try TestRunner.assertEqual(settingsUpdate, 0)
                vt_session_poll(session)
                guard let cStillProxy = vt_snapshot_json(session) else {
                    try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                    return
                }
                let stillProxySnap = try JSONDecoder().decode(
                    VertexSnapshot.self, from: Data(String(cString: cStillProxy).utf8))
                vt_free_string(cStillProxy)
                try TestRunner.assertTrue(stillProxySnap.stats.isProxyActive)
                try TestRunner.assertTrue(
                    stillProxySnap.proxy.auth,
                    "Un aggiornamento delle impostazioni non deve perdere l'autenticazione proxy"
                )
                try TestRunner.assertFalse(stillProxySnap.portmap.tcp.mapped)
                try TestRunner.assertFalse(stillProxySnap.portmap.udp.mapped)

                // Re-applying without a username must fall back to plain socks5:
                // libtorrent cannot authenticate with an empty username.
                let noAuthApply = proxyHost.withCString { hostPtr in
                    vt_apply_proxy_settings(session, 1, hostPtr, 1080, nil, nil)
                }
                try TestRunner.assertEqual(noAuthApply, 0)
                vt_session_poll(session)
                guard let cNoAuth = vt_snapshot_json(session) else {
                    try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                    return
                }
                let noAuthSnap = try JSONDecoder().decode(
                    VertexSnapshot.self, from: Data(String(cString: cNoAuth).utf8))
                vt_free_string(cNoAuth)
                try TestRunner.assertFalse(
                    noAuthSnap.proxy.auth,
                    "Senza username il proxy deve usare socks5 senza autenticazione"
                )

                // Disable proxy
                let disableResult = vt_apply_proxy_settings(session, 0, nil, 0, nil, nil)
                try TestRunner.assertEqual(disableResult, 0, "Disabilitare proxy deve restituire 0")

                vt_session_poll(session)
                guard let cDisabled = vt_snapshot_json(session) else {
                    try TestRunner.assertTrue(false, "vt_snapshot_json deve restituire un puntatore non nullo")
                    return
                }
                let disabledSnap = try JSONDecoder().decode(
                    VertexSnapshot.self, from: Data(String(cString: cDisabled).utf8))
                vt_free_string(cDisabled)
                try TestRunner.assertFalse(disabledSnap.stats.isProxyActive)
                try TestRunner.assertEqual(disabledSnap.proxy.type, "None")
                try TestRunner.assertFalse(disabledSnap.proxy.auth)
            }
        }

        TestRunner.run("Bridge: sanitizzazione UTF-8 e json_escape") {
            let validASCII = "Hello \"World\" \\ \n \t"
            try validASCII.withCString { cStr in
                try TestRunner.assertEqual(vt_is_valid_utf8(cStr), 1)
                guard let escaped = vt_json_escape(cStr) else {
                    try TestRunner.assertTrue(false, "vt_json_escape non deve restituire nil")
                    return
                }
                let swiftEscaped = String(cString: escaped)
                vt_free_string(escaped)
                try TestRunner.assertEqual(swiftEscaped, "Hello \\\"World\\\" \\\\ \\n \\t")
            }

            let validUTF8 = "Vertex client torrente: caffè e 🚀"
            try validUTF8.withCString { cStr in
                try TestRunner.assertEqual(vt_is_valid_utf8(cStr), 1)
                guard let escaped = vt_json_escape(cStr) else {
                    try TestRunner.assertTrue(false, "vt_json_escape non deve restituire nil")
                    return
                }
                let swiftEscaped = String(cString: escaped)
                vt_free_string(escaped)
                try TestRunner.assertEqual(swiftEscaped, validUTF8)
            }

            let validBoundaries = ["\u{80}", "\u{7FF}", "\u{800}", "\u{FFFF}", "\u{10000}", "\u{10FFFF}"]
            for value in validBoundaries {
                try value.withCString { cStr in
                    try TestRunner.assertEqual(vt_is_valid_utf8(cStr), 1, "UTF-8 valido rifiutato: \(value)")
                    guard let escaped = vt_json_escape(cStr) else {
                        try TestRunner.assertTrue(false, "vt_json_escape non deve restituire nil")
                        return
                    }
                    let swiftEscaped = String(cString: escaped)
                    vt_free_string(escaped)
                    try TestRunner.assertEqual(swiftEscaped, value)
                }
            }

            let invalidSequences: [[UInt8]] = [
                [0xC1, 0xBF],  // overlong 2-byte
                [0xE0, 0x80, 0x80],  // overlong 3-byte
                [0xED, 0xA0, 0x80],  // UTF-16 surrogate
                [0xF0, 0x80, 0x80, 0x80],  // overlong 4-byte
                [0xF4, 0x90, 0x80, 0x80],  // > U+10FFFF
                [0x80],  // continuation alone
                [0xE2, 0x82],  // truncated 3-byte
            ]
            for bytes in invalidSequences {
                var terminated = bytes
                terminated.append(0x00)
                try terminated.withUnsafeBufferPointer { ntBuf in
                    let cStr = UnsafeRawPointer(ntBuf.baseAddress!).assumingMemoryBound(to: CChar.self)
                    try TestRunner.assertEqual(vt_is_valid_utf8(cStr), 0, "UTF-8 non valido accettato")
                    guard let escaped = vt_json_escape(cStr) else {
                        try TestRunner.assertTrue(false, "vt_json_escape non deve restituire nil")
                        return
                    }
                    let swiftEscaped = String(cString: escaped)
                    vt_free_string(escaped)
                    try TestRunner.assertTrue(
                        swiftEscaped.contains("\\ufffd"),
                        "La sequenza corrotta deve produrre \\ufffd"
                    )
                }
            }

            let invalidBytes: [UInt8] = [
                0x41,  // 'A'
                0xC0, 0xAF,  // Overlong UTF-8
                0x42,  // 'B'
                0xED, 0xA0, 0x80,  // UTF-16 surrogate (U+D800)
                0x43,  // 'C'
                0xFF,  // Byte non valido
                0x44,  // 'D'
                0x00,  // Null terminator
            ]
            try invalidBytes.withUnsafeBufferPointer { ntBuf in
                let cStr = UnsafeRawPointer(ntBuf.baseAddress!).assumingMemoryBound(to: CChar.self)
                try TestRunner.assertEqual(vt_is_valid_utf8(cStr), 0)
                guard let escaped = vt_json_escape(cStr) else {
                    try TestRunner.assertTrue(false, "vt_json_escape non deve restituire nil")
                    return
                }
                let swiftEscaped = String(cString: escaped)
                vt_free_string(escaped)
                try TestRunner.assertTrue(
                    swiftEscaped.contains("\\ufffd"), "I byte corrotti devono essere sostituiti con \\ufffd")
                try TestRunner.assertEqual(swiftEscaped, "A\\ufffd\\ufffdB\\ufffd\\ufffd\\ufffdC\\ufffdD")
            }
        }

        TestRunner.run("Bridge: avvio sessione con proxy SOCKS5 preconfigurato e flush resume immediato") {
            let workspace = try IntegrationWorkspace()
            defer { workspace.cleanup() }
            let download = try workspace.directory("downloads")
            let resume = try workspace.directory("resume")
            let port = Int32(try TestsSupport.freeTCPPort())

            // Create session with SOCKS5 proxy already configured at startup
            let session = download.path.withCString { dlPath in
                resume.path.withCString { resPath in
                    "127.0.0.1".withCString { hostPtr in
                        "user".withCString { userPtr in
                            "pass".withCString { passPtr in
                                "1.14.2".withCString { verPtr in
                                    vt_session_create_configured(
                                        dlPath, resPath, port, 0, 0, 0, 0, 0, 1, nil,
                                        1, hostPtr, 9050, userPtr, passPtr, verPtr, nil
                                    )
                                }
                            }
                        }
                    }
                }
            }
            let validSession = try TestRunner.assertNotNil(session)
            let snap = try sessionSnapshot(of: validSession)
            try TestRunner.assertTrue(snap.stats.isProxyActive, "Il proxy deve essere già attivo dalla creazione")
            try TestRunner.assertEqual(snap.proxy.port, 9050)
            try TestRunner.assertTrue(snap.proxy.auth)
            try TestRunner.assertFalse(snap.portmap.tcp.mapped)

            // Add fixture torrent, create initial resume file via destroy, reload,
            // change file priority and immediately destroy WITHOUT polling in between
            // to verify vt_session_destroy drains pre-queued save_resume_data_alert.
            let fixture = IntegrationFixture.v1
            let added = fixture.torrentURL.path.withCString { pathPtr in
                download.path.withCString { dlPtr in
                    vt_add_torrent_file(validSession, pathPtr, dlPtr, 1, 0)
                }
            }
            try TestRunner.assertEqual(added, 0)
            let addedSnap = try sessionSnapshot(of: validSession)
            let torrentID = try TestRunner.assertNotNil(addedSnap.torrents.first?.id)
            vt_session_destroy(validSession)

            // Second session: priority change followed immediately by destroy (no poll!)
            let second = download.path.withCString { dlPath in
                resume.path.withCString { resPath in
                    vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, nil)
                }
            }
            let validSecond = try TestRunner.assertNotNil(second)
            let prioSet = torrentID.withCString { idPtr in
                vt_set_file_priority(validSecond, idPtr, 0, 0)
            }
            try TestRunner.assertEqual(prioSet, 0)
            // Wait a few milliseconds so libtorrent posts save_resume_data_alert and
            // clears need_save_resume_data() BEFORE vt_session_destroy runs.
            Thread.sleep(forTimeInterval: 0.05)
            vt_session_destroy(validSecond)

            // Third session: verify priority 0 was persisted despite no poll before destroy
            let third = download.path.withCString { dlPath in
                resume.path.withCString { resPath in
                    vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, nil)
                }
            }
            let validThird = try TestRunner.assertNotNil(third)
            defer { vt_session_destroy(validThird) }
            guard let detailPtr = torrentID.withCString({ vt_detail_json(validThird, $0) }) else {
                try TestRunner.assertTrue(false, "vt_detail_json non deve restituire nil")
                return
            }
            let detailJSON = String(cString: detailPtr)
            vt_free_string(detailPtr)
            let detail = try JSONDecoder().decode(TorrentDetail.self, from: Data(detailJSON.utf8))
            try TestRunner.assertEqual(
                detail.files.first?.priority,
                0,
                "La priorità modificata subito prima di vt_session_destroy deve sopravvivere al riavvio"
            )
        }

        TestRunner.run("Resume: un symlink .resume non viene caricato") {
            let workspace = try IntegrationWorkspace()
            defer { workspace.cleanup() }
            let download = try workspace.directory("downloads")
            let resume = try workspace.directory("resume")
            let elsewhere = try workspace.directory("elsewhere")
            let port = Int32(try TestsSupport.freeTCPPort())

            func openSession() -> OpaquePointer? {
                download.path.withCString { dlPath in
                    resume.path.withCString { resPath in
                        vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, nil)
                    }
                }
            }

            let first = try TestRunner.assertNotNil(openSession())
            let added = IntegrationFixture.v1.torrentURL.path.withCString { pathPtr in
                download.path.withCString { dlPtr in
                    vt_add_torrent_file(first, pathPtr, dlPtr, 1, 0)
                }
            }
            try TestRunner.assertEqual(added, 0)
            vt_session_destroy(first)

            let files = try FileManager.default.contentsOfDirectory(atPath: resume.path)
                .filter { $0.hasSuffix(".resume") }
            let name = try TestRunner.assertNotNil(files.first, "Il resume deve essere stato scritto")
            let original = resume.appendingPathComponent(name)
            let moved = elsewhere.appendingPathComponent(name)
            try FileManager.default.moveItem(at: original, to: moved)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: moved)

            let second = try TestRunner.assertNotNil(openSession())
            let snapshot = try sessionSnapshot(of: second)
            vt_session_destroy(second)
            try TestRunner.assertEqual(
                snapshot.torrents.count,
                0,
                "Un symlink .resume non deve essere seguito"
            )

            try FileManager.default.removeItem(at: original)
            try FileManager.default.moveItem(at: moved, to: original)
            let third = try TestRunner.assertNotNil(openSession())
            defer { vt_session_destroy(third) }
            try TestRunner.assertEqual(
                try sessionSnapshot(of: third).torrents.count,
                1,
                "Lo stesso file, regolare, deve essere caricato"
            )
        }

        TestRunner.run("Session: smoke UPnP/NAT-PMP (solo con VERTEX_TEST_UPNP=1)") {
            try upnpSmoke()
        }

        TestRunner.run("Bridge: chiamate concorrenti sulla stessa sessione") {
            try concurrentCalls()
        }

        TestRunner.run("Snapshot: 300 torrent e cache degli aggiornamenti") {
            try snapshotBenchmark()
        }

        TestRunner.run("Bridge: input malevoli o malformati") {
            try malformedInputs()
        }

        TestRunner.run("Bridge: guardie su priorità file, rimozione uppercase e bind+proxy fail-closed") {
            try bridgeSecurityAndBoundsGuards()
        }

        TestRunner.run("Bridge: vt_fail_close_proxy, vt_session_create_configured_ex e validazioni confine C") {
            try failCloseProxyAndBoundaryValidations()
        }

        TestRunner.run("Bridge: esclusione di tutti i file, invalidazione immediata cache e rimozione/riaggiunta") {
            try allSkippedCacheInvalidationAndReadd()
        }
    }

    /// Decodes the session snapshot through the same model the UI uses, so the
    /// binding tests also cover the JSON contract.
    private static func sessionSnapshot(of session: OpaquePointer) throws -> VertexSnapshot {
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
                    let snapshot = try? JSONDecoder().decode(VertexSnapshot.self, from: data)
                else {
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

    /// The bridge promises to serialize every entry point: hammer one session
    /// from several threads and require valid JSON throughout.
    private static func concurrentCalls() throws {
        let port = Int32(try TestsSupport.freeTCPPort())
        try withRawSession(port: port) { session, _, _, _ in
            let pointer = SessionPointer(session)
            let probe = ConcurrentProbe()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "vertex.bridge.concurrent", attributes: .concurrent)

            for _ in 0..<4 {
                queue.async(group: group) {
                    for _ in 0..<40 {
                        vt_session_poll(pointer.value)
                        if let json = vt_snapshot_json(pointer.value) {
                            let text = String(cString: json)
                            vt_free_string(json)
                            guard let data = text.data(using: .utf8),
                                (try? JSONDecoder().decode(VertexSnapshot.self, from: data)) != nil
                            else {
                                probe.markCorrupted()
                                continue
                            }
                        }
                        if let error = vt_last_error(pointer.value) {
                            vt_free_string(error)
                        }
                        _ = vt_set_active_limit(pointer.value, 0)
                    }
                }
            }
            group.wait()
            try TestRunner.assertFalse(
                probe.isCorrupted,
                "Uno snapshot concorrente non è un JSON valido"
            )
        }
    }

    private static func malformedInputs() throws {
        let port = Int32(try TestsSupport.freeTCPPort())
        try withRawSession(port: port) { session, _, download, _ in
            let rejected = [
                "",
                "magnet:",
                "magnet:?xt=urn:btih:",
                "magnet:?xt=urn:btih:zzzz",
                "magnet:?xt=urn:btih:" + String(repeating: "g", count: 40),
                String(repeating: "m", count: 100_000),
            ]
            for raw in rejected {
                let rc = raw.withCString { uri in
                    download.path.withCString { path in
                        vt_add_magnet(session, uri, path, 1, 0)
                    }
                }
                try TestRunner.assertTrue(
                    rc != 0,
                    "input accettato: \(raw.prefix(40))"
                )
                if let error = vt_last_error(session) { vt_free_string(error) }
            }

            // A valid infohash with a huge non-ASCII name may be accepted;
            // what matters is that it cannot crash or corrupt the snapshot.
            let hugeName =
                "magnet:?xt=urn:btih:"
                + String(repeating: "0", count: 40)
                + "&dn=" + String(repeating: "é", count: 4096)
            _ = hugeName.withCString { uri in
                download.path.withCString { path in
                    vt_add_magnet(session, uri, path, 1, 0)
                }
            }
            if let error = vt_last_error(session) { vt_free_string(error) }

            let detail = "no-such-id".withCString { vt_detail_json(session, $0) }
            if let detail {
                defer { vt_free_string(detail) }
                let decoded = try JSONDecoder().decode(
                    TorrentDetail.self,
                    from: Data(String(cString: detail).utf8)
                )
                try TestRunner.assertTrue(
                    decoded.files.isEmpty,
                    "Un id inesistente non deve produrre file"
                )
            }
            _ = try Self.decodeSnapshot(session)
        }
    }

    private static func bridgeSecurityAndBoundsGuards() throws {
        let port = Int32(try TestsSupport.freeTCPPort())
        try withRawSession(port: port) { session, _, download, _ in
            let magnetID = "abcdef0123456789abcdef0123456789abcdef01"
            let magnet = "magnet:?xt=urn:btih:\(magnetID)"
            let magnetAdded = magnet.withCString { uri in
                download.path.withCString { path in
                    vt_add_magnet(session, uri, path, 1, 0)
                }
            }
            try TestRunner.assertEqual(magnetAdded, 0)

            let noMetadataPrio = magnetID.withCString { id in
                vt_set_file_priority(session, id, 0, 4)
            }
            try TestRunner.assertEqual(
                noMetadataPrio,
                -1,
                "vt_set_file_priority deve rifiutare un magnet senza metadati"
            )

            let uppercaseRemoved = magnetID.uppercased().withCString { id in
                vt_control(session, id, "remove")
            }
            try TestRunner.assertEqual(
                uppercaseRemoved,
                0,
                "vt_control deve accettare e canonicalizzare anche info-hash uppercase"
            )
            try TestsSupport.waitFor("rimozione magnet uppercase", timeout: 5) {
                try Self.decodeSnapshot(session).torrents.isEmpty
            }

            let fixture = IntegrationFixture.v1
            let fileAdded = fixture.torrentURL.path.withCString { torrentPath in
                download.path.withCString { path in
                    vt_add_torrent_file(session, torrentPath, path, 1, 0)
                }
            }
            try TestRunner.assertEqual(fileAdded, 0)
            let snap = try Self.decodeSnapshot(session)
            let fixtureID = try TestRunner.assertNotNil(snap.torrents.first?.id)

            let outOfBoundsFileIndex = fixtureID.withCString { id in
                vt_set_file_priority(session, id, 99, 4)
            }
            try TestRunner.assertEqual(
                outOfBoundsFileIndex,
                -1,
                "vt_set_file_priority deve rifiutare un file_index >= num_files()"
            )

            // H-03: bind_address + SOCKS5 proxy must fail closed if the bound local interface is absent.
            let proxyApplied = "127.0.0.1".withCString { host in
                vt_apply_proxy_settings(session, 1, host, 1080, nil, nil)
            }
            try TestRunner.assertEqual(proxyApplied, 0)
            let downBind = "203.0.113.9".withCString { bind in
                vt_apply_settings_ex(session, port, 0, 0, 1, 0, 0, bind)
            }
            try TestRunner.assertEqual(downBind, 0)
            let guardedSnap = try Self.decodeSnapshot(session)
            try TestRunner.assertFalse(
                guardedSnap.listening, "Con bind non locale + proxy non deve risultare in ascolto")
            try TestRunner.assertTrue(
                guardedSnap.listenError.contains("203.0.113.9"),
                "listenError deve segnalare l'interfaccia assente: \(guardedSnap.listenError)"
            )

            let recoveredBind = "127.0.0.1".withCString { bind in
                vt_apply_settings_ex(session, port, 0, 0, 1, 0, 0, bind)
            }
            try TestRunner.assertEqual(recoveredBind, 0)
            try TestsSupport.waitFor("ripristino guardia bind+proxy su 127.0.0.1", timeout: 5) {
                try Self.decodeSnapshot(session).listenError.isEmpty
            }
        }
    }

    /// Guards the state_update_alert cache: 300 idle torrents must not turn the
    /// poll into 300 `status()` queries. The budget is deliberately generous
    /// (debug bridge build, shared CI runner); the printed numbers are the
    /// measurement, the assertion only catches a return to the O(N) path.
    static func snapshotBenchmark() throws {
        let count = 300
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }
        let download = try workspace.directory("downloads")
        let resume = try workspace.directory("resume")

        let port = Int32(try TestsSupport.freeTCPPort())
        let session = download.path.withCString { dlPath in
            resume.path.withCString { resPath in
                vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, nil)
            }
        }
        guard let session else {
            throw TestFailure(message: "sessione non creata", file: #file, line: #line)
        }
        defer { vt_session_destroy(session) }

        for index in 0..<count {
            let hash = String(format: "%040x", index + 1)
            let magnet = "magnet:?xt=urn:btih:\(hash)&dn=bench-\(index)"
            let rc = magnet.withCString { uri in
                download.path.withCString { path in
                    vt_add_magnet(session, uri, path, 1, 0)
                }
            }
            if rc != 0 {
                let errPtr = vt_last_error(session)
                let errMsg = errPtr.map { String(cString: $0) } ?? ""
                if let errPtr { vt_free_string(errPtr) }
                throw TestFailure(
                    message: "add magnet \(index) fallita: \(errMsg)",
                    file: #file,
                    line: #line
                )
            }
        }

        // Warm-up: the first poll fills the cache and pays the cold path.
        _ = Self.drainSnapshot(session)

        var samples: [Double] = []
        for _ in 0..<20 {
            let start = DispatchTime.now().uptimeNanoseconds
            vt_session_poll(session)
            let json = vt_snapshot_json(session)
            if let json { vt_free_string(json) }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            samples.append(elapsed)
        }
        samples.sort()
        let p50 = samples[samples.count / 2]
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        print(String(format: "  Snapshot: %d torrent, p50 %.2f ms, p95 %.2f ms", count, p50, p95))

        let snapshot = try Self.decodeSnapshot(session)
        try TestRunner.assertEqual(snapshot.torrents.count, count, "Lo snapshot deve elencare tutti i torrent")
        try TestRunner.assertTrue(
            snapshot.torrents.allSatisfy { $0.paused }, "I torrent aggiunti in pausa devono risultare in pausa")

        // Change one torrent through the bridge: the alert must refresh the
        // cache, so the next snapshot cannot keep reporting it as paused.
        let firstID = snapshot.torrents[0].id
        try TestRunner.assertEqual(
            firstID.withCString { vt_control(session, $0, "resume") },
            0,
            "resume deve riuscire"
        )
        _ = Self.drainSnapshot(session)
        let refreshed = try Self.decodeSnapshot(session)
        let resumed = refreshed.torrents.first { $0.id == firstID }
        try TestRunner.assertNotNil(resumed, "Il torrent ripreso deve restare nello snapshot")
        try TestRunner.assertFalse(resumed?.paused ?? true, "La cache deve riflettere il resume")

        // Sanitizers instrument every access: the absolute timing is not
        // comparable, so the budget only guards normal runs. The measurement is
        // printed either way.
        if ProcessInfo.processInfo.environment["VERTEX_SANITIZER"] == nil {
            try TestRunner.assertTrue(p95 < 50, "p95 dello snapshot troppo alto: \(p95) ms")
        } else {
            print("  (budget non applicato: esecuzione sotto sanitizer)")
        }
    }

    private static func drainSnapshot(_ session: OpaquePointer) -> String? {
        vt_session_poll(session)
        guard let pointer = vt_snapshot_json(session) else { return nil }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    private static func decodeSnapshot(_ session: OpaquePointer) throws -> VertexSnapshot {
        guard let json = drainSnapshot(session) else {
            throw TestFailure(message: "snapshot nil", file: #file, line: #line)
        }
        return try JSONDecoder().decode(VertexSnapshot.self, from: Data(json.utf8))
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
                        vt_session_create_full(
                            dlPath, resPath, port, 0, 0, 0, 0, 0,
                            upnp ? 1 : 0, bindPath, nil)
                    }
                }
                return vt_session_create_full(
                    dlPath, resPath, port, 0, 0, 0, 0, 0,
                    upnp ? 1 : 0, nil, nil)
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

    private static func normalizedPath(_ requested: String, fallback: String) -> String? {
        let pointer = requested.withCString { requestedPointer in
            fallback.withCString { fallbackPointer in
                vt_normalize_save_path(requestedPointer, fallbackPointer)
            }
        }
        guard let pointer else { return nil }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    private static func failCloseProxyAndBoundaryValidations() throws {
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }
        let download = try workspace.directory("downloads")
        let resume = try workspace.directory("resume")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resume.path)
        let port = Int32(try TestsSupport.freeTCPPort())

        // Pre-existing read-only download directory must be rejected at session creation.
        let readonlyDownload = try workspace.directory("readonly-downloads")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readonlyDownload.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readonlyDownload.path)
        }
        var roError: UnsafeMutablePointer<CChar>?
        let roSession = readonlyDownload.path.withCString { dlPath in
            resume.path.withCString { resPath in
                vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, &roError)
            }
        }
        if let roError { vt_free_string(roError) }
        if let roSession { vt_session_destroy(roSession) }
        try TestRunner.assertNil(roSession, "Una cartella download non scrivibile deve essere rifiutata")

        // Out-of-domain proxy_type or out-of-range proxy_port at creation must fail closed instead of starting clearnet/:1080.
        var badProxyTypeError: UnsafeMutablePointer<CChar>?
        let badProxySession = download.path.withCString { dlPath in
            resume.path.withCString { resPath in
                "127.0.0.1".withCString { host in
                    vt_session_create_configured_ex(
                        dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil,
                        2, host, 1080, nil, nil, 1, "1.17.14", &badProxyTypeError
                    )
                }
            }
        }
        if let badProxyTypeError { vt_free_string(badProxyTypeError) }
        if let badProxySession { vt_session_destroy(badProxySession) }
        try TestRunner.assertNil(badProxySession, "proxy_type fuori dominio deve fallire in creazione")

        var badProxyPortError: UnsafeMutablePointer<CChar>?
        let badPortSession = download.path.withCString { dlPath in
            resume.path.withCString { resPath in
                "127.0.0.1".withCString { host in
                    vt_session_create_configured_ex(
                        dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil,
                        1, host, 70_000, nil, nil, 1, "1.17.14", &badProxyPortError
                    )
                }
            }
        }
        let badPortMessage = badProxyPortError.map { ptr -> String in
            defer { vt_free_string(ptr) }
            return String(cString: ptr)
        }
        if let badPortSession { vt_session_destroy(badPortSession) }
        try TestRunner.assertNil(badPortSession, "proxy_port fuori range deve fallire in creazione")
        try TestRunner.assertEqual(badPortMessage, "Porta proxy fuori intervallo (1–65535).")

        // Create session via vt_session_create_configured_ex with max_active = 1 and check 0700 on resume_dir.
        let created = download.path.withCString { dlPath in
            resume.path.withCString { resPath in
                vt_session_create_configured_ex(
                    dlPath, resPath, port, 0, 0, 1, 0, 0, 0, nil,
                    0, nil, 0, nil, nil, 1, "1.17.14", nil
                )
            }
        }
        let session = try TestRunner.assertNotNil(created)
        defer { vt_session_destroy(session) }

        let resumePerms =
            (try FileManager.default.attributesOfItem(atPath: resume.path)[.posixPermissions] as? NSNumber)?.intValue
            ?? 0
        try TestRunner.assertEqual(resumePerms & 0o777, 0o700, "resume_dir deve essere forzata a permessi 0700")

        // vt_fail_close_proxy halts listening, sets proxy error, resists vt_clear_proxy_error,
        // and recovers once valid proxy settings or proxy_type = 0 are applied.
        "Host proxy non valido".withCString { reason in
            vt_fail_close_proxy(session, reason)
        }
        let failClosedSnap = try Self.decodeSnapshot(session)
        try TestRunner.assertTrue(failClosedSnap.proxy.enabled, "Il proxy deve risultare abilitato in fail-close")
        try TestRunner.assertEqual(failClosedSnap.proxy.error, "Host proxy non valido")
        try TestRunner.assertFalse(failClosedSnap.listening, "La sessione in fail-close non deve ascoltare")

        vt_clear_proxy_error(session)
        let afterClearAttempt = try Self.decodeSnapshot(session)
        try TestRunner.assertEqual(
            afterClearAttempt.proxy.error,
            "Host proxy non valido",
            "vt_clear_proxy_error non deve cancellare l'errore finché la guardia fail-close è attiva"
        )

        // Invalid proxy_type, whitespace-only hostname, and out-of-range ports must stay fail-closed.
        try TestRunner.assertEqual(vt_apply_proxy_settings(session, 99, "127.0.0.1", 1080, nil, nil), -1)
        if let err = vt_last_error(session) { vt_free_string(err) }
        try TestRunner.assertEqual(vt_apply_proxy_settings(session, 1, "   ", 1080, nil, nil), -1)
        if let err = vt_last_error(session) {
            defer { vt_free_string(err) }
            try TestRunner.assertEqual(String(cString: err), "Host proxy non valido")
        }
        for invalidPort: Int32 in [0, -1, 70_000] {
            try TestRunner.assertEqual(vt_apply_proxy_settings(session, 1, "127.0.0.1", invalidPort, nil, nil), -1)
            if let err = vt_last_error(session) {
                defer { vt_free_string(err) }
                try TestRunner.assertEqual(String(cString: err), "Porta proxy fuori intervallo (1–65535).")
            }
        }

        // Trimmed hostname with valid port is accepted and clears fail-closed state
        // (libtorrent may asynchronously report ECONNREFUSED/EPERM on 127.0.0.1:1080,
        // so verify that the fail-closed configuration error itself is gone).
        try TestRunner.assertEqual(vt_apply_proxy_settings(session, 1, "  127.0.0.1  ", 1080, "user", "pass"), 0)
        let validProxySnap = try Self.decodeSnapshot(session)
        try TestRunner.assertEqual(validProxySnap.proxy.hostname, "127.0.0.1")
        try TestRunner.assertEqual(validProxySnap.proxy.port, 1080)
        try TestRunner.assertTrue(validProxySnap.proxy.auth)
        try TestRunner.assertFalse(validProxySnap.proxy.error == "Host proxy non valido")
        try TestRunner.assertFalse(validProxySnap.proxy.error == "Porta proxy fuori intervallo (1–65535).")

        // Transitioning from an active proxy endpoint to vt_fail_close_proxy must clear stale
        // hostname/port/auth metadata so the TCP health probe stops hitting the old endpoint.
        "Porta proxy fuori intervallo (1–65535).".withCString { reason in
            vt_fail_close_proxy(session, reason)
        }
        let clearedEndpointSnap = try Self.decodeSnapshot(session)
        try TestRunner.assertTrue(clearedEndpointSnap.proxy.enabled)
        try TestRunner.assertEqual(clearedEndpointSnap.proxy.hostname, "")
        try TestRunner.assertEqual(clearedEndpointSnap.proxy.port, 0)
        try TestRunner.assertFalse(clearedEndpointSnap.proxy.auth)
        try TestRunner.assertEqual(clearedEndpointSnap.proxy.error, "Porta proxy fuori intervallo (1–65535).")

        // Disabling proxy restores clearnet cleanly.
        try TestRunner.assertEqual(vt_apply_proxy_settings(session, 0, nil, 0, nil, nil), 0)
        try TestsSupport.waitFor("ripristino ascolto dopo uscita da proxy", timeout: 5) {
            let snap = try Self.decodeSnapshot(session)
            return !snap.proxy.enabled && snap.listening
        }

        // Unspecified ("0.0.0.0", "::") and IPv6 link-local ("fe80::1") bind addresses must be rejected.
        for invalidBind in ["0.0.0.0", "::", "[::]", "fe80::1", "[fe80::1]"] {
            let rc = invalidBind.withCString { bindPtr in
                vt_apply_settings_ex(session, port, 0, 0, 0, 0, 0, bindPtr)
            }
            try TestRunner.assertEqual(rc, -1, "bind_address non valido accettato: \(invalidBind)")
            if let err = vt_last_error(session) { vt_free_string(err) }
        }

        // vt_set_default_save_path rejects whitespace-only input.
        try TestRunner.assertEqual(vt_set_default_save_path(session, "   "), -1)
        if let err = vt_last_error(session) { vt_free_string(err) }
    }

    private static func allSkippedCacheInvalidationAndReadd() throws {
        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }
        let download = try workspace.directory("downloads")
        let resume = try workspace.directory("resume")
        let port = Int32(try TestsSupport.freeTCPPort())

        func openSession() throws -> OpaquePointer {
            let ptr = download.path.withCString { dlPath in
                resume.path.withCString { resPath in
                    vt_session_create_full(dlPath, resPath, port, 0, 0, 0, 0, 0, 0, nil, nil)
                }
            }
            return try TestRunner.assertNotNil(ptr)
        }

        let first = try openSession()
        // Add v1 fixture paused, warm the snapshot cache, then verify single-poll updates (B-2).
        let addedV1 = IntegrationFixture.v1.torrentURL.path.withCString { pathPtr in
            download.path.withCString { dlPtr in
                vt_add_torrent_file(first, pathPtr, dlPtr, 1, 0)
            }
        }
        try TestRunner.assertEqual(addedV1, 0)
        let initialSnap = try Self.decodeSnapshot(first)
        let v1ID = try TestRunner.assertNotNil(initialSnap.torrents.first?.id)
        try TestRunner.assertTrue(initialSnap.torrents.first?.paused == true)

        try TestRunner.assertEqual(v1ID.withCString { vt_control(first, $0, "sequential_on") }, 0)
        let seqSnap = try Self.decodeSnapshot(first)
        try TestRunner.assertTrue(
            seqSnap.torrents.first?.sequential == true,
            "L'invalidazione di status_cache deve riflettere sequential_on al primo snapshot"
        )

        // M-1: setting all file priorities to 0 (Skip) on an incomplete torrent must NOT report finished/100%.
        try TestRunner.assertEqual(v1ID.withCString { vt_set_all_file_priorities(first, $0, 0) }, 0)
        try TestsSupport.waitFor("priorità 0 applicate su tutti i file") {
            guard let ptr = v1ID.withCString({ vt_detail_json(first, $0) }) else { return false }
            defer { vt_free_string(ptr) }
            let detail = try JSONDecoder().decode(TorrentDetail.self, from: Data(String(cString: ptr).utf8))
            return !detail.files.isEmpty && detail.files.allSatisfy { $0.priority == 0 }
        }
        let skippedSnap = try Self.decodeSnapshot(first)
        let skippedTorrent = try TestRunner.assertNotNil(skippedSnap.torrents.first { $0.id == v1ID })
        try TestRunner.assertFalse(
            skippedTorrent.finished,
            "Un torrent incompleto con tutti i file su Skip non deve risultare completato"
        )
        try TestRunner.assertFalse(skippedTorrent.seeding)
        try TestRunner.assertEqual(skippedTorrent.progress, 0.0)
        try TestRunner.assertEqual(skippedTorrent.eta, -1)

        // B-7: vt_set_trackers must reject malformed schemes/hosts and accept valid URLs.
        for badURL in [
            "://missing-scheme/announce", "1bad://tracker.example/announce", "http:///announce", "http://:80/a",
        ] {
            let rc = v1ID.withCString { idPtr in
                badURL.withCString { urlPtr in vt_set_trackers(first, idPtr, urlPtr) }
            }
            try TestRunner.assertEqual(rc, -1, "URL tracker malformato accettato: \(badURL)")
            if let err = vt_last_error(first) { vt_free_string(err) }
        }
        let validTracker = "https://[::1]:8443/announce"
        try TestRunner.assertEqual(
            v1ID.withCString { idPtr in
                validTracker.withCString { urlPtr in vt_set_trackers(first, idPtr, urlPtr) }
            },
            0
        )

        // B-7 & A-8: add v2 fixture, verify uppercase hex lookup, remove and re-add in same session,
        // and verify .resume is persisted across destroy (even if a symlink stood at <id>.resume).
        let addedV2 = IntegrationFixture.v2.torrentURL.path.withCString { pathPtr in
            download.path.withCString { dlPtr in
                vt_add_torrent_file(first, pathPtr, dlPtr, 1, 0)
            }
        }
        try TestRunner.assertEqual(addedV2, 0)
        let bothSnap = try Self.decodeSnapshot(first)
        let v2ID = try TestRunner.assertNotNil(bothSnap.torrents.first { $0.id != v1ID }?.id)

        try TestRunner.assertEqual(
            v2ID.uppercased().withCString { vt_control(first, $0, "remove") },
            0,
            "find_handle deve risolvere anche ID uppercase di torrent v2"
        )
        let readdedV2 = IntegrationFixture.v2.torrentURL.path.withCString { pathPtr in
            download.path.withCString { dlPtr in
                vt_add_torrent_file(first, pathPtr, dlPtr, 1, 0)
            }
        }
        try TestRunner.assertEqual(readdedV2, 0)

        // B-1: place a symlink at <v1ID>.resume after flushing resume state, then destroy:
        // vt_session_destroy must use symlink_status, see that no regular .resume exists, and write a real 0600 file.
        let dummyTarget = workspace.root.appendingPathComponent("dummy-target")
        try Data("placeholder".utf8).write(to: dummyTarget)
        let v1ResumeURL = resume.appendingPathComponent("\(v1ID).resume")
        try? FileManager.default.removeItem(at: v1ResumeURL)
        try FileManager.default.createSymbolicLink(at: v1ResumeURL, withDestinationURL: dummyTarget)

        vt_session_destroy(first)

        let v2ResumeURL = resume.appendingPathComponent("\(v2ID).resume")
        try TestRunner.assertTrue(
            FileManager.default.fileExists(atPath: v2ResumeURL.path),
            "Il .resume di un torrent rimosso e riaggiunto nella stessa sessione deve essere salvato"
        )
        let v1Attrs = try FileManager.default.attributesOfItem(atPath: v1ResumeURL.path)
        try TestRunner.assertEqual(
            v1Attrs[.type] as? FileAttributeType,
            .typeRegular,
            "vt_session_destroy deve sostituire un symlink .resume con un file regolare"
        )

        let reopened = try openSession()
        defer { vt_session_destroy(reopened) }
        let reopenedSnap = try Self.decodeSnapshot(reopened)
        try TestRunner.assertEqual(
            reopenedSnap.torrents.count,
            2,
            "Entrambi i torrent devono essere ricaricati al riavvio"
        )
    }
}
