import Foundation

/// Shared validation for torrent input. Keeping the magnet/file rules in one
/// place prevents the drop, paste, open-panel and add paths from drifting.
package enum TorrentInput {
    package static func isMagnet(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("magnet:")
    }

    package static func isTorrentFile(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "torrent"
    }
}
