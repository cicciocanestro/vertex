import Foundation
import UniformTypeIdentifiers

enum TorrentDropItem {
    case torrent(URL)
    case magnet(String)
}

/// Shared drag-and-drop reader for the main window and the add sheet.
/// It only validates the item; applying the result stays with the caller.
enum TorrentDropHandler {
    @discardableResult
    static func handle(
        _ providers: [NSItemProvider],
        onItem: @escaping (TorrentDropItem) -> Void
    ) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, TorrentInput.isTorrentFile(url) else { return }
                    DispatchQueue.main.async {
                        onItem(.torrent(url))
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, TorrentInput.isMagnet(text) else { return }
                    DispatchQueue.main.async {
                        onItem(.magnet(text))
                    }
                }
            }
        }

        return handled
    }
}
