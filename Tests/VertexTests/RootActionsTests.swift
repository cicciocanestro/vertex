#if DEBUG
    import Foundation
    @testable import VertexKit

    enum RootActionsTests {
        static func runAll() {
            print("\n\u{001B}[1m[Suite: RootActionsTests]\u{001B}[0m")

            TestRunner.run("Root: guardie delle azioni, modali e filtri") {
                try guardsAndCommands()
            }
            TestRunner.run("Root: prompt di eliminazione, drop e larghezza inspector") {
                try pureDecisions()
            }
            TestRunner.run("Root: densità della lista e badge dei tab") {
                try densityAndBadges()
            }
        }

        private static func densityAndBadges() throws {
            try TestRunner.assertEqual(ListDensity(rawValue: "compact"), .compact)
            try TestRunner.assertEqual(
                ListDensity(rawValue: "bogus") ?? .comfortable,
                .comfortable
            )
            try TestRunner.assertEqual(ListDensity.comfortable.rowSpacing, 7)
            try TestRunner.assertEqual(ListDensity.comfortable.rowPadding, 9)
            try TestRunner.assertEqual(ListDensity.comfortable.ringSize, 42)
            try TestRunner.assertEqual(ListDensity.compact.rowSpacing, 4)
            try TestRunner.assertEqual(ListDensity.compact.rowPadding, 5)
            try TestRunner.assertEqual(ListDensity.compact.ringSize, 36)

            let json = """
                {"files":[
                    {"index":0,"path":"a.bin","size":10,"progress":1,"priority":4},
                    {"index":1,"path":"b.bin","size":20,"progress":1,"priority":4}
                ],
                "trackers":[
                    {"url":"udp://tracker","verified":true,"fails":0,"message":"","peers":2,"seeds":1}
                ],
                "peers":[
                    {"endpoint":"1.2.3.4:6881","client":"v","progress":1,"downloadRate":0,"uploadRate":0,"flags":"","source":"tracker"}
                ],
                "metadata":true}
                """
            let detail = try JSONDecoder().decode(
                TorrentDetail.self,
                from: Data(json.utf8)
            )
            try TestRunner.assertEqual(
                InspectorBadge.count(for: .files, detail: detail), 2)
            try TestRunner.assertEqual(
                InspectorBadge.count(for: .peers, detail: detail), 1)
            try TestRunner.assertEqual(
                InspectorBadge.count(for: .trackers, detail: detail), 1)
            try TestRunner.assertEqual(
                InspectorBadge.count(for: .files, detail: nil), 0,
                "Senza dettaglio caricato il badge è assente, non uno spinner")
        }

        private static func guardsAndCommands() throws {
            try onMain {
                let workspace = try IntegrationWorkspace()
                defer { workspace.cleanup() }

                let download = try workspace.directory("root-actions-download")
                let resume = try workspace.directory("root-actions-resume")
                let configuration = SessionConfiguration(
                    downloadPath: download.path,
                    resumePath: resume.path,
                    port: Int32(try TestsSupport.freeTCPPort())
                )
                let engine = TorrentEngine(configuration: configuration)

                var modal: ActiveModal?
                var focused = 0
                var toggled = 0
                var picked = 0
                var pasted = 0
                var deleted: [Torrent] = []
                var filter: TorrentFilter?

                let actions = RootActionFactory.make(
                    engine: engine,
                    RootActionDependencies(
                        isModalOpen: { modal != nil },
                        selectedTorrent: { nil },
                        selectedTorrents: { [] },
                        setModal: { modal = $0 },
                        focusSearch: { focused += 1 },
                        toggleInspector: { toggled += 1 },
                        requestDeletion: { deleted = $0 },
                        chooseFile: { picked += 1 },
                        pasteMagnet: { pasted += 1 },
                        setFilter: { filter = $0 }
                    )
                )

                // A modal blocks every command that would act on the list.
                modal = .settings
                actions.onAddFile()
                actions.onPauseResume()
                actions.onRemove()
                actions.onReveal()
                actions.onMoveStorage()
                actions.onCopyMagnet()
                actions.onFind()
                actions.onToggleInspector()
                try TestRunner.assertEqual(picked, 0)
                try TestRunner.assertEqual(focused, 0)
                try TestRunner.assertEqual(toggled, 0)
                try TestRunner.assertEqual(deleted.count, 0)
                try TestRunner.assertEqual(engine.toast, nil)

                actions.onAddMagnet()
                try TestRunner.assertEqual(modal, .add(.magnet))
                actions.onSettings()
                try TestRunner.assertEqual(modal, .settings)
                actions.onDiagnostics()
                try TestRunner.assertEqual(modal, .diagnostics)
                actions.onPasteMagnet()
                try TestRunner.assertEqual(pasted, 1)

                modal = nil
                actions.onFilter("bogus")
                try TestRunner.assertEqual(filter, nil)
                actions.onFilter(TorrentFilter.seeding.rawValue)
                try TestRunner.assertEqual(filter, .seeding)

                actions.onAddFile()
                try TestRunner.assertEqual(picked, 1)
                actions.onFind()
                try TestRunner.assertEqual(focused, 1)
                actions.onToggleInspector()
                try TestRunner.assertEqual(toggled, 1)

                // Without a selection the command explains itself instead of
                // silently doing nothing.
                actions.onPauseResume()
                try TestRunner.assertEqual(engine.toast?.text, L("Seleziona un torrent"))
                engine.dismissToast()

                actions.onRemove()
                try TestRunner.assertEqual(engine.toast?.text, L("Seleziona un torrent"))
                engine.dismissToast()
                try TestRunner.assertEqual(deleted.count, 0)
            }
        }

        private static func pureDecisions() throws {
            try TestRunner.assertEqual(
                RootActionFactory.deletionTitle(count: 1),
                L("Rimuovere il torrent?")
            )
            try TestRunner.assertEqual(
                RootActionFactory.deletionTitle(count: 3),
                LF("Rimuovere %ld torrent?", 3)
            )
            try TestRunner.assertEqual(
                RootActionFactory.deletionMessage(count: 1, name: "film.mkv"),
                LF(
                    "“%@”\nI file scaricati restano sul disco se scegli di rimuovere solo il torrent.",
                    "film.mkv"
                )
            )
            try TestRunner.assertEqual(
                RootActionFactory.deletionMessage(count: 2, name: "film.mkv"),
                L("I file scaricati restano sul disco se scegli di rimuovere solo dalla lista.")
            )

            try TestRunner.assertTrue(
                RootActionFactory.acceptsDrop(modalOpen: false, isReady: true))
            try TestRunner.assertFalse(
                RootActionFactory.acceptsDrop(modalOpen: true, isReady: true))
            try TestRunner.assertFalse(
                RootActionFactory.acceptsDrop(modalOpen: false, isReady: false))

            try TestRunner.assertEqual(
                RootActionFactory.toastBottomPadding(multiSelection: false), 56)
            try TestRunner.assertEqual(
                RootActionFactory.toastBottomPadding(multiSelection: true), 96)

            let magnet = "magnet:?xt=urn:btih:" + String(repeating: "a", count: 40)
            try TestRunner.assertEqual(RootActionFactory.magnetToAdd(from: nil), nil)
            try TestRunner.assertEqual(
                RootActionFactory.magnetToAdd(from: "  non un magnet  "), nil)
            try TestRunner.assertEqual(
                RootActionFactory.magnetToAdd(from: "  \(magnet)\n"), magnet)

            let torrent = Torrent(
                id: "root-action-id",
                name: "Root.mkv",
                stateCode: 3,
                progress: 0.2,
                size: 1024,
                downloaded: 200,
                uploaded: 0,
                downloadRate: 0,
                uploadRate: 0,
                peers: 1,
                seeds: 1,
                eta: 10,
                finished: false,
                seeding: false,
                paused: false,
                sequential: false,
                hasMetadata: true,
                savePath: "/tmp",
                ratio: 0,
                added: 0,
                error: ""
            )
            try TestRunner.assertEqual(
                RootActionFactory.inspectorToggle(
                    selectedIDs: ["root-action-id"], visible: [torrent]),
                .deselect
            )
            try TestRunner.assertEqual(
                RootActionFactory.inspectorToggle(selectedIDs: [], visible: [torrent]),
                .select("root-action-id")
            )
            try TestRunner.assertEqual(
                RootActionFactory.inspectorToggle(selectedIDs: [], visible: []),
                .none
            )

            try TestRunner.assertEqual(
                RootActionFactory.toastActionRoute(.reveal(path: "/tmp/file"), pathExists: { _ in true }),
                .revealExisting("/tmp/file")
            )
            try TestRunner.assertEqual(
                RootActionFactory.toastActionRoute(.reveal(path: "/tmp/file"), pathExists: { _ in false }),
                .revealParent("/tmp/file")
            )
            try TestRunner.assertEqual(
                RootActionFactory.toastActionRoute(.openFolder(path: "/tmp"), pathExists: { _ in true }),
                .openFolder("/tmp")
            )

            try TestRunner.assertEqual(InspectorResize.clamped(100), 320)
            try TestRunner.assertEqual(InspectorResize.clamped(900), 520)
            try TestRunner.assertEqual(InspectorResize.clamped(400), 400)
            try TestRunner.assertEqual(
                InspectorResize.dragged(from: 400, translation: -100), 500)
            try TestRunner.assertEqual(
                InspectorResize.dragged(from: 400, translation: 300), 320)
            try TestRunner.assertEqual(
                InspectorResize.stepped(510, direction: .increment), 520)
            try TestRunner.assertEqual(
                InspectorResize.stepped(325, direction: .decrement), 320)
        }
    }
#endif
