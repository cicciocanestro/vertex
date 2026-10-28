import AppKit
import UniformTypeIdentifiers

/// Single place for the open panels used by the main window, the add sheet and
/// settings. Keeps the torrent type filter and the directory options aligned.
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
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        return panel
    }
}
