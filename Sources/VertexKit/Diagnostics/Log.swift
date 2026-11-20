import os

/// Structured logging through `os.Logger`.
///
/// Dynamic text stays private by default: libtorrent messages can embed a save
/// path or a peer address, and this client must not leak them into a system log
/// that another process may read.
package enum Log {
    private static let subsystem = "app.vertex.torrent"

    package static let session = Logger(subsystem: subsystem, category: "session")
    package static let engine = Logger(subsystem: subsystem, category: "engine")
}
