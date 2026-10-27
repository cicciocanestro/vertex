import Darwin
import Foundation
import CTorrent
import VertexKit

enum IntegrationTestError: Error, CustomStringConvertible {
    case bridge(String)
    case fixture(String)
    case io(String)
    case timeout(String)

    var description: String {
        switch self {
        case .bridge(let message): return "bridge: \(message)"
        case .fixture(let message): return "fixture: \(message)"
        case .io(let message): return "io: \(message)"
        case .timeout(let message): return "timeout: \(message)"
        }
    }
}

// Tiny deterministic torrent fixtures. Keep these values in sync with
// Tests/Fixtures/README.md.
enum IntegrationFixture {
    case v1
    case v2

    var rootName: String {
        switch self {
        case .v1: return "vertex-fixture-v1"
        case .v2: return "vertex-fixture-v2"
        }
    }

    var torrentURL: URL {
        TestsSupport.fixturesDirectory.appendingPathComponent("\(name).torrent")
    }

    var name: String {
        switch self {
        case .v1: return "fixture-v1"
        case .v2: return "fixture-v2"
        }
    }

    var files: [(path: String, size: Int)] {
        switch self {
        case .v1:
            return [("data.bin", 32_768), ("second.bin", 16_384)]
        case .v2:
            return [("data.bin", 32_768), ("second.bin", 16_384)]
        }
    }

    func bytes(for path: String) throws -> Data {
        guard let file = files.first(where: { $0.path == path }) else {
            throw IntegrationTestError.fixture("File sconosciuto in \(name): \(path)")
        }
        return Data((0..<file.size).map { UInt8($0 % 251) })
    }

    func writeSource(in root: URL) throws {
        for file in files {
            let url = root
                .appendingPathComponent(rootName, isDirectory: true)
                .appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes(for: file.path).write(to: url)
        }
    }

    func assertDownloaded(in root: URL, path: String) throws {
        let url = root
            .appendingPathComponent(rootName, isDirectory: true)
            .appendingPathComponent(path)
        guard let actual = try? Data(contentsOf: url) else {
            throw IntegrationTestError.fixture("File scaricato assente: \(url.path)")
        }
        let expected = try bytes(for: path)
        try TestRunner.assertEqual(
            actual,
            expected,
            "Contenuto diverso per \(url.path)"
        )
    }
}

enum TestsSupport {
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func freeTCPPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw IntegrationTestError.io("socket() fallita")
        }
        defer { _ = Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw IntegrationTestError.io("bind() su una porta libera fallita")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw IntegrationTestError.io("getsockname() fallita")
        }

        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func waitFor(
        _ description: String,
        timeout: TimeInterval = 30,
        _ condition: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw IntegrationTestError.timeout(description)
    }
}

final class IntegrationWorkspace {
    let root: URL
    private var cleaned = false

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vertex-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.path
        )
        try? FileManager.default.removeItem(at: root)
    }

    deinit {
        cleanup()
    }
}

final class BridgeSession {
    let pointer: OpaquePointer
    let downloadDirectory: URL
    let resumeDirectory: URL
    let requestedPort: Int
    private var closed = false

    init(
        downloadDirectory: URL,
        resumeDirectory: URL,
        port: Int,
        enableDHT: Bool = false,
        enablePEX: Bool = false,
        enableLSD: Bool = false
    ) throws {
        self.downloadDirectory = downloadDirectory
        self.resumeDirectory = resumeDirectory
        self.requestedPort = port

        try FileManager.default.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: resumeDirectory,
            withIntermediateDirectories: true
        )

        let created = downloadDirectory.path.withCString { downloadPath in
            resumeDirectory.path.withCString { resumePath in
                vt_session_create_ex(
                    downloadPath,
                    resumePath,
                    Int32(port),
                    0,
                    0,
                    enableDHT ? 1 : 0,
                    enablePEX ? 1 : 0,
                    enableLSD ? 1 : 0
                )
            }
        }
        guard let created else {
            throw IntegrationTestError.bridge("vt_session_create ha restituito nil")
        }
        self.pointer = created

        // Keep tests hermetic even if the caller requests discovery features.
        _ = vt_apply_settings_ex(
            pointer,
            Int32(port),
            0,
            0,
            enableDHT ? 1 : 0,
            0,
            enableLSD ? 1 : 0
        )
    }

    deinit {
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        vt_session_destroy(pointer)
    }

    func snapshot() throws -> VertexSnapshot {
        vt_session_poll(pointer)
        guard let cSnapshot = vt_snapshot_json(pointer) else {
            throw IntegrationTestError.bridge("vt_snapshot_json ha restituito nil")
        }
        let json = String(cString: cSnapshot)
        vt_free_string(cSnapshot)
        guard let data = json.data(using: .utf8) else {
            throw IntegrationTestError.bridge("snapshot JSON non UTF-8")
        }
        do {
            return try JSONDecoder().decode(VertexSnapshot.self, from: data)
        } catch {
            throw IntegrationTestError.bridge("snapshot JSON non decodificabile: \(error)")
        }
    }

    func detail(torrentID: String) throws -> TorrentDetail {
        guard let cDetail = torrentID.withCString({
            vt_detail_json(pointer, $0)
        }) else {
            throw IntegrationTestError.bridge("vt_detail_json ha restituito nil")
        }
        let json = String(cString: cDetail)
        vt_free_string(cDetail)
        guard let data = json.data(using: .utf8) else {
            throw IntegrationTestError.bridge("detail JSON non UTF-8")
        }
        return try JSONDecoder().decode(TorrentDetail.self, from: data)
    }

    func addTorrentFile(_ path: String, savePath: String, paused: Bool = false) throws {
        let result = path.withCString { filePath in
            savePath.withCString { destination in
                vt_add_torrent_file(
                    pointer,
                    filePath,
                    destination,
                    paused ? 1 : 0,
                    0
                )
            }
        }
        if result != 0 {
            throw IntegrationTestError.bridge(lastError())
        }
    }

    func addPeer(torrentID: String, host: String = "127.0.0.1", port: Int) throws {
        let result = torrentID.withCString { id in
            host.withCString { hostPointer in
                vt_add_peer(pointer, id, hostPointer, Int32(port))
            }
        }
        if result != 0 {
            throw IntegrationTestError.bridge(lastError())
        }
    }

    func control(torrentID: String, action: String) throws {
        let result = torrentID.withCString { id in
            action.withCString { actionPointer in
                vt_control(pointer, id, actionPointer)
            }
        }
        if result != 0 {
            throw IntegrationTestError.bridge(lastError())
        }
    }

    func setFilePriority(torrentID: String, fileIndex: Int, priority: Int) throws {
        let result = torrentID.withCString { id in
            vt_set_file_priority(pointer, id, Int32(fileIndex), Int32(priority))
        }
        if result != 0 {
            throw IntegrationTestError.bridge(lastError())
        }
    }

    func lastError() -> String {
        guard let cError = vt_last_error(pointer) else {
            return "errore sconosciuto"
        }
        let message = String(cString: cError)
        vt_free_string(cError)
        return message
    }

    func waitForTorrent(_ name: String, timeout: TimeInterval = 30) throws -> Torrent {
        try TestsSupport.waitFor("torrent \(name)", timeout: timeout) {
            try snapshot().torrents.first(where: { $0.name == name }) != nil
        }
        guard let torrent = try snapshot().torrents.first(where: { $0.name == name }) else {
            throw IntegrationTestError.bridge("Torrent \(name) assente")
        }
        return torrent
    }
}

// Helpers shared by the integration tests.
enum IntegrationSwarm {
    static func makeSeed(
        _ fixture: IntegrationFixture,
        workspace: IntegrationWorkspace
    ) throws -> (session: BridgeSession, port: Int) {
        let sourceRoot = try workspace.directory("seed")
        try fixture.writeSource(in: sourceRoot)
        let resumeRoot = try workspace.directory("seed-resume")
        let port = try TestsSupport.freeTCPPort()
        let seed = try BridgeSession(
            downloadDirectory: sourceRoot,
            resumeDirectory: resumeRoot,
            port: port
        )
        do {
            try seed.addTorrentFile(
                fixture.torrentURL.path,
                savePath: sourceRoot.path
            )
            try TestsSupport.waitFor("seed \(fixture.name) in ascolto") {
                let snapshot = try seed.snapshot()
                return snapshot.torrents.contains { $0.name == fixture.rootName && $0.hasMetadata }
                    && snapshot.listenActualPort > 0
            }
            try TestsSupport.waitFor("seed \(fixture.name) in seeding") {
                try seed.snapshot().torrents.contains {
                    $0.name == fixture.rootName && ($0.seeding || $0.finished)
                }
            }
            let actualPort = try seed.snapshot().listenActualPort
            return (seed, actualPort > 0 ? actualPort : port)
        } catch {
            seed.close()
            throw error
        }
    }

    static func makeLeech(
        _ fixture: IntegrationFixture,
        workspace: IntegrationWorkspace,
        seedPort: Int,
        name: String = "leech",
        enablePEX: Bool = false,
        configureBeforeConnect: ((BridgeSession, String) throws -> Void)? = nil
    ) throws -> (session: BridgeSession, torrentID: String) {
        let downloadRoot = try workspace.directory(name)
        let resumeRoot = try workspace.directory("\(name)-resume")
        let port = try TestsSupport.freeTCPPort()
        let leech = try BridgeSession(
            downloadDirectory: downloadRoot,
            resumeDirectory: resumeRoot,
            port: port,
            enablePEX: enablePEX
        )
        do {
            try leech.addTorrentFile(
                fixture.torrentURL.path,
                savePath: downloadRoot.path
            )
            try TestsSupport.waitFor("metadata \(fixture.name) nel leech") {
                try leech.snapshot().torrents.first(where: {
                    $0.name == fixture.rootName && $0.hasMetadata
                }) != nil
            }
            let torrent = try leech.waitForTorrent(fixture.rootName)
            try configureBeforeConnect?(leech, torrent.id)
            try leech.addPeer(torrentID: torrent.id, port: seedPort)
            return (leech, torrent.id)
        } catch {
            leech.close()
            throw error
        }
    }

    static func waitForCompletion(
        _ session: BridgeSession,
        name: String,
        timeout: TimeInterval = 30
    ) throws {
        try TestsSupport.waitFor("completamento \(name)", timeout: timeout) {
            let torrent = try session.snapshot().torrents.first(where: { $0.name == name })
            return torrent?.finished == true
        }
    }
}
