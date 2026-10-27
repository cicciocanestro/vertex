#if DEBUG
import Foundation
@testable import VertexKit

enum AppCommandsTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: AppCommandsTests]\u{001B}[0m")

        TestRunner.run("AppCommand: mapping delle notifiche") {
            try notificationMapping()
        }
        TestRunner.run("AppCommand: filtri e payload") {
            try filterCommands()
        }
        TestRunner.run("AppCommandDispatcher: invio sul NotificationCenter") {
            try dispatcher()
        }
        TestRunner.run("RootEventHandlerActions: routing delle notifiche") {
            try rootEventRouting()
        }
        TestRunner.run("RootEventHandlerActions: notifiche e payload ignorati") {
            try rootEventRejectsInvalidInput()
        }
        TestRunner.run("AppCommands: costruzione dell'albero dei menu") {
            try menuConstruction()
        }
    }

    // MARK: - Cases

    private static func notificationMapping() throws {
        let expected: [(AppCommand, Notification.Name)] = [
            (.addFile, .vertexAddFile),
            (.addMagnet, .vertexAddMagnet),
            (.pasteMagnet, .vertexPasteMagnet),
            (.pauseResume, .vertexPauseResume),
            (.reveal, .vertexReveal),
            (.copyMagnet, .vertexCopyMagnet),
            (.remove, .vertexRemove),
            (.find, .vertexFind),
            (.toggleInspector, .vertexToggleInspector),
            (.diagnostics, .vertexDiagnostics),
            (.settings, .vertexSettings),
            (.filter(.all), .vertexFilter)
        ]

        for (command, notification) in expected {
            try TestRunner.assertEqual(command.notification, notification)
        }

        for command in [
            AppCommand.addFile,
            .addMagnet,
            .pasteMagnet,
            .pauseResume,
            .reveal,
            .copyMagnet,
            .remove,
            .find,
            .toggleInspector,
            .diagnostics,
            .settings
        ] {
            try TestRunner.assertNil(
                command.object,
                "Solo i comandi di filtro devono avere un payload"
            )
        }
    }

    private static func filterCommands() throws {
        try TestRunner.assertEqual(
            AppCommand.filter(.all).object,
            TorrentFilter.all.rawValue
        )

        let commands = TorrentFilter.allCases.map(AppCommand.filter)
        try TestRunner.assertEqual(commands.count, 5)
        try TestRunner.assertEqual(
            commands.compactMap(\.object),
            TorrentFilter.allCases.map(\.rawValue)
        )
        for command in commands {
            try TestRunner.assertEqual(command.notification, .vertexFilter)
        }
    }

    private static func dispatcher() throws {
        let center = NotificationCenter()
        let recorder = NotificationRecorder()
        let token = center.addObserver(forName: nil, object: nil, queue: nil) { note in
            recorder.record(note)
        }
        defer { center.removeObserver(token) }

        let commands: [AppCommand] = [
            .addFile,
            .addMagnet,
            .pasteMagnet,
            .pauseResume,
            .reveal,
            .copyMagnet,
            .remove,
            .find,
            .toggleInspector,
            .diagnostics,
            .settings,
            .filter(.seeding)
        ]

        for command in commands {
            AppCommandDispatcher.post(command, to: center)
        }

        try TestRunner.assertEqual(recorder.names, commands.map(\.notification))
        try TestRunner.assertEqual(
            recorder.objects,
            commands.map { $0.object }
        )
    }

    private static func rootEventRouting() throws {
        let recorder = ActionRecorder()
        var actions = RootEventHandlerActions()
        actions.onAddFile = { recorder.actions.append("addFile") }
        actions.onAddMagnet = { recorder.actions.append("addMagnet") }
        actions.onPasteMagnet = { recorder.actions.append("pasteMagnet") }
        actions.onPauseResume = { recorder.actions.append("pauseResume") }
        actions.onRemove = { recorder.actions.append("remove") }
        actions.onReveal = { recorder.actions.append("reveal") }
        actions.onCopyMagnet = { recorder.actions.append("copyMagnet") }
        actions.onFind = { recorder.actions.append("find") }
        actions.onToggleInspector = { recorder.actions.append("toggleInspector") }
        actions.onSettings = { recorder.actions.append("settings") }
        actions.onDiagnostics = { recorder.actions.append("diagnostics") }
        actions.onFilter = { recorder.filters.append($0) }

        let notifications: [Notification.Name] = [
            .vertexAddFile,
            .vertexAddMagnet,
            .vertexPasteMagnet,
            .vertexPauseResume,
            .vertexRemove,
            .vertexReveal,
            .vertexCopyMagnet,
            .vertexFind,
            .vertexToggleInspector,
            .vertexSettings,
            .vertexDiagnostics
        ]
        for notification in notifications {
            actions.handle(notification)
        }

        try TestRunner.assertEqual(
            recorder.actions,
            [
                "addFile",
                "addMagnet",
                "pasteMagnet",
                "pauseResume",
                "remove",
                "reveal",
                "copyMagnet",
                "find",
                "toggleInspector",
                "settings",
                "diagnostics"
            ]
        )
        try TestRunner.assertEqual(recorder.filters, [])
    }

    private static func rootEventRejectsInvalidInput() throws {
        let recorder = ActionRecorder()
        var actions = RootEventHandlerActions()
        actions.onFilter = { recorder.filters.append($0) }
        actions.onAddFile = { recorder.actions.append("addFile") }

        actions.handle(.vertexFilter, object: TorrentFilter.paused.rawValue)
        actions.handle(.vertexFilter)
        actions.handle(.vertexFilter, object: 42)
        actions.handle(Notification.Name("vertex.unknown"))
        actions.handle(.vertexAddFile, object: "ignored")

        try TestRunner.assertEqual(recorder.filters, [TorrentFilter.paused.rawValue])
        try TestRunner.assertEqual(recorder.actions, ["addFile"])
    }

    // MARK: - Helpers

    private static func menuConstruction() throws {
        try MainActor.assumeIsolated {
            // Building the command tree must not require a running app or
            // execute any notification. This covers the menu definitions that
            // are otherwise only reached when SwiftUI creates the main menu.
            _ = AppCommands().body
        }
    }

    private final class NotificationRecorder {
        private(set) var names: [Notification.Name] = []
        private(set) var objects: [String?] = []

        func record(_ note: Notification) {
            names.append(note.name)
            objects.append(note.object as? String)
        }
    }

    private final class ActionRecorder {
        var actions: [String] = []
        var filters: [String] = []
    }
}
#endif
