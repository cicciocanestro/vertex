import CTorrent
import Foundation

package struct SessionCreationOutcome: Sendable {
    package let started: Bool
    package let configuration: SessionConfiguration
    package let error: String?
}

package struct SessionOperationOutcome: Sendable {
    package let code: Int32
    package let error: String
}

/// Owns the libtorrent session pointer.
///
/// Every `vt_*` call goes through this actor: the pointer never leaves it, so
/// the engine needs no serial queue, no ownership box and no generation tokens.
/// Creation, destruction, polling and detail reads are therefore serialized by
/// the actor itself, and the heavy work (resume directory, Keychain validation,
/// JSON decoding) happens off the main actor.
#if DEBUG
    /// Sendable carrier for the test pointer: an `OpaquePointer` is not Sendable,
    /// and Swift 6.1 rejects reading one across isolation even with
    /// `nonisolated(unsafe)`. The box is safe because the bridge serializes every
    /// entry point with its own mutex.
    package final class TestSessionBox: @unchecked Sendable {
        package let value: OpaquePointer?

        package init(_ value: OpaquePointer?) {
            self.value = value
        }
    }
#endif

package actor SessionController {
    private var pointer: OpaquePointer?

    #if DEBUG
        /// Read-only alias for the synchronous test helpers.
        nonisolated let testPointerBox: TestSessionBox
    #endif

    /// Whether the initial session was created. Readable synchronously by the
    /// DEBUG initializer, before any async call.
    package nonisolated let started: Bool

    package init() {
        pointer = nil
        started = false
        #if DEBUG
            testPointerBox = TestSessionBox(nil)
        #endif
    }

    /// Synchronous variant used by the DEBUG test initializer: the heavy work
    /// must run on the caller's thread there, and no pointer crosses an
    /// isolation boundary.
    #if DEBUG
        package init(configuration: SessionConfiguration) {
            let creation = Self.makeSession(configuration)
            pointer = creation.pointer
            started = creation.pointer != nil
            testPointerBox = TestSessionBox(creation.pointer)
        }
    #endif

    package var isActive: Bool { pointer != nil }

    /// Validates the preferences, builds the configuration and starts libtorrent
    /// on the actor's executor (never on the main thread).
    package func create(configuration override: SessionConfiguration?) async -> SessionCreationOutcome {
        TorrentEngine.validateAllPreferences()
        let configuration = override ?? TorrentEngine.currentConfiguration()
        let creation = Self.makeSession(configuration)
        guard let created = creation.pointer else {
            Log.session.error("session creation failed: \(creation.error ?? "unknown", privacy: .private)")
            return SessionCreationOutcome(
                started: false,
                configuration: configuration,
                error: creation.error
            )
        }
        // A previous session must never leak: create is only called on a
        // controller whose previous session was destroyed (or never existed).
        if let pointer {
            vt_session_destroy(pointer)
        }
        pointer = created
        Log.session.notice("session created")
        return SessionCreationOutcome(started: true, configuration: configuration, error: nil)
    }

    package func destroy() {
        if let pointer {
            vt_session_destroy(pointer)
            self.pointer = nil
            Log.session.notice("session destroyed")
        }
    }

    package func poll() -> VertexSnapshot? {
        guard let pointer else { return nil }
        return Self.readSnapshot(pointer)
    }

    package func detail(id: String) -> TorrentDetail? {
        guard let pointer else { return nil }
        return Self.readDetail(pointer, id: id)
    }

    package func perform(
        _ operation: @Sendable (OpaquePointer) -> Int32
    ) -> SessionOperationOutcome {
        guard let pointer else {
            return SessionOperationOutcome(code: -1, error: "Motore non disponibile")
        }
        let code = operation(pointer)
        let error = code != 0 ? Self.readLastError(pointer) : ""
        if code != 0 {
            Log.session.debug("operation failed (\(code)): \(error, privacy: .private)")
        }
        return SessionOperationOutcome(code: code, error: error)
    }

    // MARK: - Bridge helpers (no actor state)

    nonisolated static func readLastError(_ session: OpaquePointer) -> String {
        guard let pointer = vt_last_error(session) else { return "" }
        defer { vt_free_string(pointer) }
        return String(cString: pointer)
    }

    nonisolated static func readSnapshot(_ session: OpaquePointer) -> VertexSnapshot? {
        vt_session_poll(session)
        guard let pointer = vt_snapshot_json(session) else { return nil }
        let json = String(cString: pointer)
        vt_free_string(pointer)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VertexSnapshot.self, from: data)
    }

    nonisolated static func readDetail(_ session: OpaquePointer, id: String) -> TorrentDetail? {
        let pointer = id.withCString { vt_detail_json(session, $0) }
        guard let pointer else { return nil }
        defer { vt_free_string(pointer) }
        let data = Data(String(cString: pointer).utf8)
        return try? JSONDecoder().decode(TorrentDetail.self, from: data)
    }

    nonisolated static func makeSession(
        _ configuration: SessionConfiguration
    ) -> (pointer: OpaquePointer?, error: String?) {
        do {
            try FileManager.default.createDirectory(
                atPath: configuration.downloadPath,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                atPath: configuration.resumePath,
                withIntermediateDirectories: true
            )
        } catch {
            return (nil, error.localizedDescription)
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let version = AppInfo.version == "—" ? "" : AppInfo.version
        let pointer = configuration.downloadPath.withCString { downloadPath in
            configuration.resumePath.withCString { resumePath in
                configuration.bindAddress.withCString { bindAddress in
                    configuration.proxyHost.withCString { hostPointer in
                        configuration.proxyUser.withCString { userPointer in
                            configuration.proxyPassword.withCString { passPointer in
                                version.withCString { versionPointer in
                                    vt_session_create_configured(
                                        downloadPath,
                                        resumePath,
                                        configuration.port,
                                        configuration.downloadLimit,
                                        configuration.uploadLimit,
                                        configuration.dht ? 1 : 0,
                                        configuration.pex ? 1 : 0,
                                        configuration.lsd ? 1 : 0,
                                        configuration.upnp ? 1 : 0,
                                        bindAddress,
                                        configuration.proxyEnabled ? 1 : 0,
                                        hostPointer,
                                        configuration.proxyPort,
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
        }

        let error = errorPointer.map { String(cString: $0) }
        if let errorPointer {
            vt_free_string(errorPointer)
        }

        if let pointer {
            // Always apply the limit, including "unlimited": libtorrent's default
            // is 3 downloads + 5 seeds, which would silently queue the torrents of
            // a user who never asked for a queue.
            _ = vt_set_active_limit(pointer, configuration.maxActive)
        }

        return (pointer, error)
    }
}
