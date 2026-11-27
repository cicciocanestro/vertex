import AppKit
import UniformTypeIdentifiers

/// Single place for the open panels used by the main window, the add sheet and
/// settings. Keeps the torrent type filter and the directory options aligned.
@MainActor
enum OpenPanelFactory {
    static func torrent(
        allowMultiple: Bool,
        prompt: String,
        modal: Bool = false
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        if modal {
            panel.level = .modalPanel
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowMultiple
        panel.prompt = prompt
        if let type = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [type]
        }
        return panel
    }

    nonisolated static func directoryURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    static func directory(
        startingAt path: String?,
        prompt: String = L("Scegli"),
        modal: Bool = false
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        if modal {
            panel.level = .modalPanel
        }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if let directoryURL = directoryURL(for: path) {
            panel.directoryURL = directoryURL
        }
        return panel
    }
}
