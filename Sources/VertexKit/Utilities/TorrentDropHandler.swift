import Foundation
import UniformTypeIdentifiers

enum TorrentDropItem {
    case torrent(URL)
    case magnet(String)
}

/// Shared drag-and-drop reader for the main window and the add sheet.
/// It only validates the item; applying the result stays with the caller.
///
/// A dropped item that is not a `.torrent` or a magnet link is reported through
/// `onRejected` (with the file name when there is one): accepting the drop and
/// then doing nothing looked like the app had ignored the user.
enum TorrentDropHandler {
    /// The callbacks are `@MainActor` because both call sites touch UI state, and
    /// because the item providers complete on an arbitrary queue: hopping with
    /// `Task { @MainActor in … }` is what makes the hand-off explicit.
    @discardableResult
    static func handle(
        _ providers: [NSItemProvider],
        onItem: @escaping @MainActor (TorrentDropItem) -> Void,
        onRejected: (@MainActor (String?) -> Void)? = nil
    ) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    guard TorrentInput.isTorrentFile(url) else {
                        let name = url.lastPathComponent
                        Task { @MainActor in onRejected?(name) }
                        return
                    }
                    Task { @MainActor in onItem(.torrent(url)) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    guard TorrentInput.isMagnet(text) else {
                        Task { @MainActor in onRejected?(nil) }
                        return
                    }
                    Task { @MainActor in onItem(.magnet(text)) }
                }
            }
        }

        return handled
    }
}
