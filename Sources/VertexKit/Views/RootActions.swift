import CoreGraphics
import Foundation

/// Decisions behind RootView's menu/shortcut actions. They live here, not in
/// the view, so the guards (no shortcuts behind a modal, no actions without a
/// selection) can be tested without driving AppKit.
struct RootActionDependencies {
    let isModalOpen: () -> Bool
    let selectedTorrent: () -> Torrent?
    let selectedTorrents: () -> [Torrent]
    let setModal: (ActiveModal?) -> Void
    let focusSearch: () -> Void
    let toggleInspector: () -> Void
    let requestDeletion: ([Torrent]) -> Void
    let chooseFile: () -> Void
    let pasteMagnet: () -> Void
    let setFilter: (TorrentFilter) -> Void
}

enum RootActionFactory {
    @MainActor
    static func make(
        engine: TorrentEngine,
        _ dependencies: RootActionDependencies
    ) -> RootEventHandlerActions {
        RootEventHandlerActions(
            onAddFile: {
                guard !dependencies.isModalOpen() else { return }
                dependencies.chooseFile()
            },
            onAddMagnet: {
                dependencies.setModal(.add(.magnet))
            },
            onPasteMagnet: dependencies.pasteMagnet,
            onPauseResume: {
                guard !dependencies.isModalOpen() else { return }
                let selected = dependencies.selectedTorrents()
                guard !selected.isEmpty else {
                    engine.showToast(L("Seleziona un torrent"), kind: .info)
                    return
                }
                engine.togglePause(selected)
            },
            onRemove: {
                guard !dependencies.isModalOpen() else { return }
                let selected = dependencies.selectedTorrents()
                guard !selected.isEmpty else {
                    engine.showToast(L("Seleziona un torrent"), kind: .info)
                    return
                }
                dependencies.requestDeletion(selected)
            },
            onReveal: {
                guard !dependencies.isModalOpen() else { return }
                if let torrent = dependencies.selectedTorrent() {
                    engine.reveal(torrent)
                }
            },
            onMoveStorage: {
                guard !dependencies.isModalOpen() else { return }
                if let torrent = dependencies.selectedTorrent() {
                    engine.chooseAndMoveStorage(for: torrent)
                }
            },
            onCopyMagnet: {
                guard !dependencies.isModalOpen() else { return }
                if let torrent = dependencies.selectedTorrent() {
                    engine.copyMagnet(for: torrent)
                }
            },
            onFind: {
                guard !dependencies.isModalOpen() else { return }
                dependencies.focusSearch()
            },
            onToggleInspector: {
                guard !dependencies.isModalOpen() else { return }
                dependencies.toggleInspector()
            },
            onSettings: {
                dependencies.setModal(.settings)
            },
            onDiagnostics: {
                dependencies.setModal(.diagnostics)
            },
            onFilter: { raw in
                guard let value = TorrentFilter(rawValue: raw) else { return }
                dependencies.setFilter(value)
            }
        )
    }

    static func deletionTitle(count: Int) -> String {
        count > 1 ? LF("Rimuovere %ld torrent?", count) : L("Rimuovere il torrent?")
    }

    static func deletionMessage(count: Int, name: String?) -> String {
        if count == 1, let name {
            return LF(
                "“%@”\nI file scaricati restano sul disco se scegli di rimuovere solo il torrent.",
                name
            )
        }
        return L("I file scaricati restano sul disco se scegli di rimuovere solo dalla lista.")
    }

    static func acceptsDrop(modalOpen: Bool, isReady: Bool) -> Bool {
        !modalOpen && isReady
    }

    static func toastBottomPadding(multiSelection: Bool) -> CGFloat {
        multiSelection ? 96 : 56
    }
}

extension RootActionFactory {
    /// A clipboard magnet, trimmed; nil means the paste should open the add
    /// sheet instead of adding something invalid.
    static func magnetToAdd(from clipboard: String?) -> String? {
        guard
            let clipboard = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines),
            TorrentInput.isMagnet(clipboard)
        else { return nil }
        return clipboard
    }
}

enum InspectorToggle: Equatable {
    case deselect
    case select(String)
    case none
}

extension RootActionFactory {
    static func inspectorToggle(
        selectedIDs: Set<String>,
        visible: [Torrent]
    ) -> InspectorToggle {
        if !selectedIDs.isEmpty { return .deselect }
        guard let first = visible.first else { return .none }
        return .select(first.id)
    }
}

enum ToastActionRoute: Equatable {
    case revealExisting(String)
    case revealParent(String)
    case openFolder(String)
}

extension RootActionFactory {
    static func toastActionRoute(
        _ action: ToastMessage.Action,
        pathExists: (String) -> Bool
    ) -> ToastActionRoute {
        switch action {
        case .reveal(let path):
            return pathExists(path) ? .revealExisting(path) : .revealParent(path)
        case .openFolder(let path):
            return .openFolder(path)
        }
    }
}

/// Width math for the list/inspector divider. Clamping on read and on write
/// keeps both panes usable when a window moves between displays.
enum InspectorResize {
    enum Direction {
        case increment
        case decrement
    }

    static let minimum: CGFloat = 320
    static let maximum: CGFloat = 520
    static let defaultValue: CGFloat = 350
    private static let step: CGFloat = 20

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimum), maximum)
    }

    static func dragged(from start: CGFloat, translation: CGFloat) -> CGFloat {
        clamped(start - translation)
    }

    static func stepped(_ width: CGFloat, direction: Direction) -> CGFloat {
        switch direction {
        case .increment: return clamped(width + step)
        case .decrement: return clamped(width - step)
        }
    }
}
