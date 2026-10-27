import AppKit
import SwiftUI

extension Notification.Name {
    static let vertexAddFile = Notification.Name("vertex.addFile")
    static let vertexAddMagnet = Notification.Name("vertex.addMagnet")
    static let vertexPasteMagnet = Notification.Name("vertex.pasteMagnet")
    static let vertexPauseResume = Notification.Name("vertex.pauseResume")
    static let vertexRemove = Notification.Name("vertex.remove")
    static let vertexReveal = Notification.Name("vertex.reveal")
    static let vertexCopyMagnet = Notification.Name("vertex.copyMagnet")
    static let vertexFind = Notification.Name("vertex.find")
    static let vertexToggleInspector = Notification.Name("vertex.toggleInspector")
    static let vertexSettings = Notification.Name("vertex.settings")
    static let vertexDiagnostics = Notification.Name("vertex.diagnostics")
    static let vertexFilter = Notification.Name("vertex.filter")
}

/// Menu actions exposed by the app. Keeping the notification mapping in one
/// place makes it testable and avoids duplicating the filter raw values in the
/// menu definitions.
enum AppCommand: Equatable {
    case addFile
    case addMagnet
    case pasteMagnet
    case pauseResume
    case reveal
    case copyMagnet
    case remove
    case find
    case toggleInspector
    case diagnostics
    case settings
    case filter(TorrentFilter)

    var notification: Notification.Name {
        switch self {
        case .addFile: return .vertexAddFile
        case .addMagnet: return .vertexAddMagnet
        case .pasteMagnet: return .vertexPasteMagnet
        case .pauseResume: return .vertexPauseResume
        case .reveal: return .vertexReveal
        case .copyMagnet: return .vertexCopyMagnet
        case .remove: return .vertexRemove
        case .find: return .vertexFind
        case .toggleInspector: return .vertexToggleInspector
        case .diagnostics: return .vertexDiagnostics
        case .settings: return .vertexSettings
        case .filter: return .vertexFilter
        }
    }

    /// Payload attached to the notification, if the command needs one.
    var object: String? {
        guard case .filter(let filter) = self else { return nil }
        return filter.rawValue
    }
}

enum AppCommandDispatcher {
    static func post(_ command: AppCommand, to center: NotificationCenter = .default) {
        center.post(name: command.notification, object: command.object)
    }
}

package struct AppCommands: Commands {
    package init() {}

    package var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Aggiungi file .torrent…") {
                post(.addFile)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Aggiungi link magnet…") {
                post(.addMagnet)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Incolla magnet dagli appunti") {
                post(.pasteMagnet)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        CommandMenu("Torrent") {
            Button("Pausa / Riprendi") {
                post(.pauseResume)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Mostra nel Finder") {
                post(.reveal)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Copia link magnet") {
                post(.copyMagnet)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Rimuovi…") {
                post(.remove)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        CommandMenu("Vista") {
            Button("Cerca") {
                post(.find)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Mostra / nascondi dettagli") {
                post(.toggleInspector)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Diagnostica rete…") {
                post(.diagnostics)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("Tutti") { post(.filter(.all)) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Download") { post(.filter(.downloading)) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Seed") { post(.filter(.seeding)) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Completati") { post(.filter(.completed)) }
                .keyboardShortcut("4", modifiers: .command)
            Button("In pausa") { post(.filter(.paused)) }
                .keyboardShortcut("5", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button("Informazioni su Vertex") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Button("Licenze open source") {
                openLicenses()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Impostazioni…") {
                post(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func post(_ command: AppCommand) {
        AppCommandDispatcher.post(command)
    }

    private func openLicenses() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Licenses") else {
            return
        }
        NSWorkspace.shared.open(folder)
    }
}
