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

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Aggiungi file .torrent…") {
                post(.vertexAddFile)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Aggiungi link magnet…") {
                post(.vertexAddMagnet)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Incolla magnet dagli appunti") {
                post(.vertexPasteMagnet)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        CommandMenu("Torrent") {
            Button("Pausa / Riprendi") {
                post(.vertexPauseResume)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Mostra nel Finder") {
                post(.vertexReveal)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Copia link magnet") {
                post(.vertexCopyMagnet)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Rimuovi…") {
                post(.vertexRemove)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        CommandMenu("Vista") {
            Button("Cerca") {
                post(.vertexFind)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Mostra / nascondi dettagli") {
                post(.vertexToggleInspector)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Diagnostica rete…") {
                post(.vertexDiagnostics)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("Tutti") { post(.vertexFilter, object: TorrentFilter.all.rawValue) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Download") { post(.vertexFilter, object: TorrentFilter.downloading.rawValue) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Seed") { post(.vertexFilter, object: TorrentFilter.seeding.rawValue) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Completati") { post(.vertexFilter, object: TorrentFilter.completed.rawValue) }
                .keyboardShortcut("4", modifiers: .command)
            Button("In pausa") { post(.vertexFilter, object: TorrentFilter.paused.rawValue) }
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
                post(.vertexSettings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func post(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }

    private func openLicenses() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Licenses") else {
            return
        }
        NSWorkspace.shared.open(folder)
    }
}
