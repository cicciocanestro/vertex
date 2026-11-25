import CTorrent
import Darwin
import Foundation

/// Minimal loopback listeners used by the leak test. They count TCP accepts,
/// which is enough to prove where libtorrent tried to connect: a direct tracker
/// connection and a SOCKS5 connection are distinguishable without pcap.
final class LocalTCPListener: @unchecked Sendable {
    private let listenFD: Int32
    private let lock = NSLock()
    private var accepted = 0
    private var stopping = false
    private var handler: ((Int32) -> Void)?
    private(set) var port: Int = 0

    init() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw IntegrationTestError.io("socket() fallita")
        }
        var reuse: Int32 = 1
        setsockopt(
            listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listenFD, 32) == 0 else {
            close(listenFD)
            throw IntegrationTestError.io("bind/listen fallita")
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listenFD, $0, &length)
            }
        }
        guard named == 0 else {
            close(listenFD)
            throw IntegrationTestError.io("getsockname fallita")
        }
        port = Int(UInt16(bigEndian: actual.sin_port))
    }

    func start(handler: @escaping (Int32) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "vertex-test-listener"
        thread.start()
    }

    var acceptedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return accepted
    }

    func stop() {
        lock.lock()
        stopping = true
        lock.unlock()
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                lock.lock()
                let done = stopping
                lock.unlock()
                if done { return }
                continue
            }
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(
                client, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            lock.lock()
            accepted += 1
            let handler = self.handler
            lock.unlock()
            handler?(client)
            close(client)
        }
    }
}

private enum Loopback {
    static func readExact(_ fd: Int32, count: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let read = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            if read <= 0 { return nil }
            offset += read
        }
        return buffer
    }

    /// Completes the SOCKS5 greeting, records the requested host, then fails the
    /// CONNECT: the tracker announce cannot succeed, but the attempt is visible.
    static func handleSOCKS5(_ fd: Int32) {
        guard let greeting = readExact(fd, count: 2), greeting[0] == 0x05 else { return }
        let methods = Int(greeting[1])
        guard readExact(fd, count: methods) != nil else { return }
        _ = [UInt8]([0x05, 0x00]).withUnsafeBytes { send(fd, $0.baseAddress, 2, 0) }

        guard let header = readExact(fd, count: 4), header[0] == 0x05 else { return }
        switch header[3] {
        case 0x01:
            _ = readExact(fd, count: 4)
        case 0x03:
            guard let length = readExact(fd, count: 1) else { return }
            _ = readExact(fd, count: Int(length[0]))
        case 0x04:
            _ = readExact(fd, count: 16)
        default:
            return
        }
        _ = readExact(fd, count: 2)
        _ = [UInt8]([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).withUnsafeBytes {
            send(fd, $0.baseAddress, 10, 0)
        }
    }
}

enum NetworkLeakTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: NetworkLeakTests]\u{001B}[0m")

        TestRunner.run("Rete: con il proxy attivo non c'è traffico diretto verso il tracker") {
            try assertNoDirectTrackerTraffic(proxyEnabled: true)
        }

        TestRunner.run("Rete: senza proxy il tracker diretto viene contattato (controllo)") {
            try assertNoDirectTrackerTraffic(proxyEnabled: false)
        }
    }

    /// Runs a direct tracker stub and a SOCKS5 stub, then adds a magnet whose
    /// only tracker is the direct stub.
    ///
    /// - proxy enabled: libtorrent must reach the SOCKS5 stub and never open a
    ///   TCP connection to the tracker.
    /// - proxy disabled: the tracker must receive a connection, otherwise the
    ///   negative assertion above would be vacuous.
    private static func assertNoDirectTrackerTraffic(proxyEnabled: Bool) throws {
        let direct = try LocalTCPListener()
        let proxy = try LocalTCPListener()
        defer {
            direct.stop()
            proxy.stop()
        }

        direct.start { _ in
            // Close immediately: the accept itself is the measurement.
        }
        proxy.start { fd in
            Loopback.handleSOCKS5(fd)
        }

        let workspace = try IntegrationWorkspace()
        defer { workspace.cleanup() }
        let download = try workspace.directory("downloads")
        let resume = try workspace.directory("resume")

        let session = try createSession(
            download: download,
            resume: resume,
            port: try TestsSupport.freeTCPPort(),
            proxyPort: proxyEnabled ? proxy.port : nil
        )
        defer { vt_session_destroy(session) }

        let id = String(repeating: "a", count: 40)
        let magnet = "magnet:?xt=urn:btih:\(id)&dn=leak-test"
        let added = magnet.withCString { uri in
            download.path.withCString { path in
                vt_add_magnet(session, uri, path, 0, 0)
            }
        }
        guard added == 0 else {
            throw IntegrationTestError.bridge(
                "add magnet: \(lastError(session))"
            )
        }

        let trackerURL = "http://127.0.0.1:\(direct.port)/announce"
        guard id.withCString({ idPtr in trackerURL.withCString { vt_set_trackers(session, idPtr, $0) } }) == 0 else {
            throw IntegrationTestError.bridge("set trackers: \(lastError(session))")
        }
        _ = id.withCString { vt_control(session, $0, "reannounce") }

        if proxyEnabled {
            try waitUntil("connessione al proxy", timeout: 10) {
                vt_session_poll(session)
                return proxy.acceptedCount > 0
            }
            try TestsSupport.waitUntilStable(
                "nessuna connessione diretta al tracker con il proxy attivo",
                duration: 2.0
            ) {
                vt_session_poll(session)
                return direct.acceptedCount == 0
            }
            try TestRunner.assertEqual(
                direct.acceptedCount, 0,
                "Con il proxy attivo il tracker ha ricevuto \(direct.acceptedCount) connessioni dirette"
            )
        } else {
            try waitUntil("connessione diretta al tracker", timeout: 10) {
                vt_session_poll(session)
                return direct.acceptedCount > 0
            }
            try TestRunner.assertTrue(
                direct.acceptedCount > 0,
                "Senza proxy il tracker diretto deve essere contattato"
            )
        }
    }

    private static func createSession(
        download: URL,
        resume: URL,
        port: Int,
        proxyPort: Int?
    ) throws -> OpaquePointer {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let host = proxyPort == nil ? "" : "127.0.0.1"
        let session = download.path.withCString { downloadPath in
            resume.path.withCString { resumePath in
                host.withCString { hostPointer in
                    "".withCString { userPointer in
                        "".withCString { passPointer in
                            "test".withCString { versionPointer in
                                vt_session_create_configured(
                                    downloadPath,
                                    resumePath,
                                    Int32(port),
                                    0, 0,
                                    0,  // DHT
                                    0,  // PEX
                                    0,  // LSD
                                    0,  // UPnP
                                    "",
                                    proxyPort == nil ? 0 : 1,
                                    hostPointer,
                                    Int32(proxyPort ?? 0),
                                    userPointer,
                                    passPointer,
                                    versionPointer,
                                    &errorPointer
                                )
                            }
                        }
                    }
                }
            }
        }
        if let errorPointer {
            let message = String(cString: errorPointer)
            vt_free_string(errorPointer)
            if session == nil {
                throw IntegrationTestError.bridge("create: \(message)")
            }
        }
        guard let session else {
            throw IntegrationTestError.bridge("create: nil")
        }
        return session
    }

    private static func lastError(_ session: OpaquePointer) -> String {
        guard let pointer = vt_last_error(session) else { return "sconosciuto" }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    private static func waitUntil(
        _ label: String,
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw IntegrationTestError.timeout(label)
    }
}
