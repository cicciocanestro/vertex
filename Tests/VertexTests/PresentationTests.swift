#if DEBUG
    import Foundation
    @testable import VertexKit

    enum PresentationTests {
        static func runAll() {
            print("\n\u{001B}[1m[Suite: PresentationTests]\u{001B}[0m")

            TestRunner.run("Presentation: etichette dei flag peer") {
                try TestRunner.assertEqual(
                    PeerFlagPresentation.labels(for: "DUEPIS"),
                    [
                        L("Download attivo"),
                        L("Upload attivo"),
                        L("Connessione cifrata"),
                        L("Trasporto uTP"),
                        L("Connessione in ingresso"),
                        L("Seed completo"),
                    ],
                    "I flag vanno tradotti nell'ordine della stringa"
                )
                try TestRunner.assertEqual(
                    PeerFlagPresentation.description(for: "Dd"),
                    L("Download attivo") + " · " + L("In attesa di sblocco")
                )
                try TestRunner.assertEqual(
                    PeerFlagPresentation.labels(for: "DXZ?").count, 1,
                    "I caratteri sconosciuti vanno ignorati"
                )
                try TestRunner.assertEqual(PeerFlagPresentation.description(for: ""), "")
            }

            TestRunner.run("Presentation: validazione del nuovo tracker") {
                try TestRunner.assertEqual(
                    TrackerInput.trimmed("  udp://tracker.example:80  \n"),
                    "udp://tracker.example:80"
                )
                try TestRunner.assertFalse(
                    TrackerInput.canAdd("tracker.example/announce", existing: []),
                    "Senza schema non è un tracker valido"
                )
                try TestRunner.assertTrue(
                    TrackerInput.canAdd(" https://tracker.example/a ", existing: ["udp://other"])
                )
                try TestRunner.assertFalse(
                    TrackerInput.canAdd(
                        "HTTPS://Tracker.Example/a",
                        existing: ["https://tracker.example/A"]
                    ),
                    "Il confronto con quelli esistenti deve ignorare il caso"
                )
                try TestRunner.assertFalse(TrackerInput.canAdd("   ", existing: []))
            }

            TestRunner.run("Presentation: priorità dei file") {
                try TestRunner.assertEqual(FilePriorityPresentation.label(.skip), L("Non scaricare"))
                try TestRunner.assertEqual(FilePriorityPresentation.label(.normal), L("Normale"))
                try TestRunner.assertEqual(FilePriorityPresentation.label(.high), L("Alta"))
                try TestRunner.assertEqual(FilePriorityPresentation.symbolName(.skip), "circle")
                try TestRunner.assertEqual(
                    FilePriorityPresentation.symbolName(.normal), "checkmark.circle.fill"
                )
                try TestRunner.assertEqual(
                    FilePriorityPresentation.symbolName(.high), "bolt.circle.fill"
                )
            }

            TestRunner.run("Presentation: checklist diagnostica") {
                var stats = SessionStats(
                    port: 6881,
                    actualPort: 6881,
                    isListening: true,
                    portmap: PortMapSnapshot(
                        tcp: PortMapInfo(mapped: true, externalPort: 49_152, transport: "UPnP"),
                        udp: PortMapInfo()
                    )
                )
                var checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: false
                )
                try TestRunner.assertEqual(
                    checks.map(\.id),
                    ["listen", "mapping", "proxy", "dht"]
                )
                try TestRunner.assertEqual(checks[0].status, .ok)
                try TestRunner.assertEqual(checks[1].status, .ok)
                try TestRunner.assertEqual(checks[2].status, .info)
                try TestRunner.assertEqual(checks[3].status, .info)

                stats.isListening = false
                stats.listenError = "boom"
                checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: false
                )
                try TestRunner.assertEqual(checks[0].status, .error)
                try TestRunner.assertEqual(checks[0].detail, "boom")

                stats.isListening = true
                stats.listenError = ""
                stats.proxy = ProxyInfo(
                    enabled: true,
                    hostname: "127.0.0.1",
                    port: 1080,
                    error: "refused"
                )
                checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: false
                )
                try TestRunner.assertEqual(
                    checks[1].status, .info,
                    "Il proxy disattiva la mappatura")
                try TestRunner.assertEqual(checks[2].status, .error)

                stats.proxy = ProxyInfo()
                stats.portmap = PortMapSnapshot()
                stats.dhtNodes = 5
                checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: true
                )
                try TestRunner.assertEqual(checks[1].status, .warning)
                try TestRunner.assertEqual(checks[3].status, .ok)

                // With an active SOCKS5 proxy and dhtEnabled == true, the bridge
                // disables DHT to avoid leaks: the checklist must report .info
                // rather than a misleading .warning ("In attesa").
                stats.proxy = ProxyInfo(enabled: true, hostname: "127.0.0.1", port: 1080)
                stats.dhtNodes = 0
                checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: true
                )
                try TestRunner.assertEqual(checks[3].status, .info)
                try TestRunner.assertEqual(
                    checks[3].detail,
                    L("Disattivato dal proxy SOCKS5 per prevenire leak.")
                )

                // #14: during vt_fail_close_proxy, hostname is "" and port is 0 while enabled == true:
                // UPnP and DHT must still report .info (disabled by SOCKS5), and StatusBarView help text
                // must surface the localized proxy error without formatting a broken "(:0)" endpoint.
                stats.proxy = ProxyInfo(
                    enabled: true,
                    type: "SOCKS5",
                    hostname: "",
                    port: 0,
                    error: "Host proxy non valido"
                )
                checks = DiagnosticsChecklist.checks(
                    stats: stats,
                    upnpEnabled: true,
                    dhtEnabled: true
                )
                try TestRunner.assertEqual(checks[1].status, .info)
                try TestRunner.assertEqual(checks[2].status, .error)
                try TestRunner.assertEqual(checks[2].detail, L("Host proxy non valido"))
                try TestRunner.assertEqual(checks[3].status, .info)
                try TestRunner.assertEqual(
                    StatusBarView.proxyHelpText(stats.proxy),
                    L("Host proxy non valido")
                )
                try TestRunner.assertFalse(StatusBarView.proxyHelpText(stats.proxy).contains(":0"))
                let reachableErr = ProxyInfo(
                    enabled: true,
                    type: "SOCKS5",
                    hostname: "127.0.0.1",
                    port: 1080,
                    error: "Connection refused"
                )
                try TestRunner.assertTrue(StatusBarView.proxyHelpText(reachableErr).contains("127.0.0.1:1080"))
            }

            TestRunner.run("Presentation: diagnostica rete") {
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.upnpDisabledReason(isProxyActive: true, upnpEnabled: true),
                    L("Disattivato dal proxy SOCKS5 per prevenire leak."),
                    "Il proxy ha la precedenza sul toggle"
                )
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.upnpDisabledReason(isProxyActive: false, upnpEnabled: false),
                    L("Disattivato in Impostazioni → Rete.")
                )
                try TestRunner.assertNil(
                    DiagnosticsPresentation.upnpDisabledReason(isProxyActive: false, upnpEnabled: true)
                )

                try TestRunner.assertEqual(
                    DiagnosticsPresentation.dhtDisabledReason(isProxyActive: true, dhtEnabled: true),
                    L("Disattivato dal proxy SOCKS5 per prevenire leak.")
                )
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.dhtDisabledReason(isProxyActive: false, dhtEnabled: false),
                    L("DHT disattivato")
                )
                try TestRunner.assertNil(
                    DiagnosticsPresentation.dhtDisabledReason(isProxyActive: false, dhtEnabled: true)
                )

                let mapped = PortMapInfo(mapped: true, externalPort: 49_152, transport: "UPnP")
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.reachabilityPort(tcp: mapped, effectivePort: 6881),
                    49_152,
                    "Un mapping valido deve essere testato sulla porta esterna"
                )
                let mappedWithoutPort = PortMapInfo(mapped: true, externalPort: 0)
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.reachabilityPort(
                        tcp: mappedWithoutPort, effectivePort: 6881
                    ),
                    6881,
                    "Senza porta esterna si torna alla porta di ascolto"
                )
                try TestRunner.assertEqual(
                    DiagnosticsPresentation.reachabilityPort(
                        tcp: PortMapInfo(), effectivePort: 6882
                    ),
                    6882
                )
            }

            TestRunner.run("Presentation: navigazione tastiera e clic riga torrent") {
                // Single-item list after deselection: navigationHeadID must not
                // block ↑/↓ from re-selecting the sole row.
                try TestRunner.assertEqual(
                    TorrentRowKeyboardNavigation.targetIndex(
                        visibleIDs: ["a"],
                        selectedIDs: [],
                        selectedID: nil,
                        navigationHeadID: "a",
                        delta: 1,
                        shift: false
                    ),
                    0
                )
                try TestRunner.assertEqual(
                    TorrentRowKeyboardNavigation.targetIndex(
                        visibleIDs: ["a", "b", "c"],
                        selectedIDs: [],
                        selectedID: nil,
                        navigationHeadID: "c",
                        delta: 1,
                        shift: false
                    ),
                    0,
                    "Dopo la deselezione le frecce devono ripartire dalla prima riga"
                )
                // Multi-selection extended to the bottom edge: plain ↓ collapses
                // onto the boundary row instead of returning nil.
                try TestRunner.assertEqual(
                    TorrentRowKeyboardNavigation.targetIndex(
                        visibleIDs: ["a", "b", "c"],
                        selectedIDs: ["a", "b", "c"],
                        selectedID: nil,
                        navigationHeadID: "c",
                        delta: 1,
                        shift: false
                    ),
                    2
                )
                try TestRunner.assertNil(
                    TorrentRowKeyboardNavigation.targetIndex(
                        visibleIDs: ["a", "b", "c"],
                        selectedIDs: ["c"],
                        selectedID: "c",
                        navigationHeadID: "c",
                        delta: 1,
                        shift: false
                    )
                )

                // Immediate click resolution preserves ⌘/⇧ and never triggers
                // Finder reveal on rapid ⌘-clicks.
                let cmdFirst = TorrentRowClickBehavior.resolve(
                    clickCount: 1,
                    command: true,
                    shift: false,
                    now: 10.0,
                    lastPlainClickTime: 0,
                    doubleClickInterval: 0.5
                )
                try TestRunner.assertEqual(cmdFirst.action, .select(command: true, shift: false))
                let cmdSecond = TorrentRowClickBehavior.resolve(
                    clickCount: 2,
                    command: true,
                    shift: false,
                    now: 10.1,
                    lastPlainClickTime: cmdFirst.nextLastPlainClickTime,
                    doubleClickInterval: 0.5
                )
                try TestRunner.assertEqual(cmdSecond.action, .select(command: true, shift: false))

                let plainFirst = TorrentRowClickBehavior.resolve(
                    clickCount: 1,
                    command: false,
                    shift: false,
                    now: 20.0,
                    lastPlainClickTime: 0,
                    doubleClickInterval: 0.5
                )
                try TestRunner.assertEqual(plainFirst.action, .select(command: false, shift: false))
                let plainDouble = TorrentRowClickBehavior.resolve(
                    clickCount: 2,
                    command: false,
                    shift: false,
                    now: 20.15,
                    lastPlainClickTime: plainFirst.nextLastPlainClickTime,
                    doubleClickInterval: 0.5
                )
                try TestRunner.assertEqual(plainDouble.action, .reveal)
            }

            TestRunner.run("Presentation: guardie RootActions e validazione impostazioni UI") {
                try TestRunner.assertTrue(
                    RootActionFactory.canPresentAdd(
                        modalOpen: false,
                        isReady: true,
                        isRestartingSession: false
                    )
                )
                try TestRunner.assertFalse(
                    RootActionFactory.canPresentAdd(
                        modalOpen: true,
                        isReady: true,
                        isRestartingSession: false
                    )
                )
                try TestRunner.assertFalse(
                    RootActionFactory.canPresentAdd(
                        modalOpen: false,
                        isReady: false,
                        isRestartingSession: false
                    )
                )
                try TestRunner.assertFalse(
                    RootActionFactory.acceptsDrop(
                        modalOpen: false,
                        isReady: true,
                        isRestartingSession: true
                    )
                )

                try TestRunner.assertFalse(
                    SettingsFieldValidation.isProxyHostValid("   ", proxyEnabled: true)
                )
                try TestRunner.assertTrue(
                    SettingsFieldValidation.isProxyHostValid("", proxyEnabled: false)
                )
                try TestRunner.assertFalse(
                    SettingsFieldValidation.isProxyPortValid(0, proxyEnabled: true)
                )
                try TestRunner.assertEqual(
                    SettingsFieldValidation.proxyIssueMessage(
                        host: "",
                        port: 1080,
                        proxyEnabled: true
                    ),
                    L("Host proxy non valido")
                )
                try TestRunner.assertTrue(
                    SettingsFieldValidation.hasSectionIssue(
                        .performance,
                        downloadLimitKB: 0,
                        uploadLimitKB: 0,
                        listenPort: 70_000,
                        maxActiveTorrents: 0,
                        seedRatioLimit: 0,
                        proxyEnabled: false,
                        proxyHost: "127.0.0.1",
                        proxyPort: 1080
                    )
                )
                try TestRunner.assertFalse(
                    SettingsFieldValidation.hasSectionIssue(
                        .network,
                        downloadLimitKB: 0,
                        uploadLimitKB: 0,
                        listenPort: 70_000,
                        maxActiveTorrents: 0,
                        seedRatioLimit: 0,
                        proxyEnabled: false,
                        proxyHost: "",
                        proxyPort: 0
                    )
                )
            }

            TestRunner.run("Presentation: riconciliazione tracker Inspector, debounce password e OpenPanel tilde") {
                // #7: unrelated detail refresh must preserve pending added/removed trackers
                // until they actually appear/disappear in detail.trackers.
                let oldTracker = TorrentTracker(
                    url: "udp://old.example:6969/announce",
                    verified: true,
                    fails: 0,
                    message: "",
                    peers: 1,
                    seeds: 1
                )
                let newURL = "udp://new.example:6969/announce"
                let staleReconcile = InspectorTrackerMutation.reconcile(
                    added: [newURL],
                    removed: ["udp://old.example:6969/announce"],
                    with: [oldTracker]
                )
                try TestRunner.assertEqual(staleReconcile.added, [newURL])
                try TestRunner.assertEqual(staleReconcile.removed, ["udp://old.example:6969/announce"])

                let newTracker = TorrentTracker(
                    url: newURL,
                    verified: false,
                    fails: 0,
                    message: "",
                    peers: -1,
                    seeds: -1
                )
                let appliedReconcile = InspectorTrackerMutation.reconcile(
                    added: [newURL],
                    removed: ["udp://old.example:6969/announce"],
                    with: [newTracker]
                )
                try TestRunner.assertEqual(appliedReconcile.added, [])
                try TestRunner.assertEqual(appliedReconcile.removed, [])

                // #11: an older detached save completing after a newer keystroke must leave
                // hasUnflushedEdits == true so flushProxyPassword still writes the latest edit.
                var saveTracker = ProxyPasswordSaveTracker()
                try TestRunner.assertFalse(saveTracker.hasUnflushedEdits)
                let gen1 = saveTracker.recordEdit()
                try TestRunner.assertTrue(saveTracker.hasUnflushedEdits)
                let gen2 = saveTracker.recordEdit()
                saveTracker.completeDebounceSave(generation: gen1, succeeded: true)
                try TestRunner.assertTrue(
                    saveTracker.hasUnflushedEdits,
                    "Il completamento di gen1 non deve cancellare la modifica successiva gen2"
                )
                try TestRunner.assertEqual(saveTracker.consumePendingFlush(), gen2)
                try TestRunner.assertFalse(saveTracker.hasUnflushedEdits)
                try TestRunner.assertNil(saveTracker.consumePendingFlush())

                // #21: OpenPanelFactory.directoryURL expands a leading ~ without touching NSRemoteOpenPanel XPC.
                let expectedExpanded = ("~/Downloads" as NSString).expandingTildeInPath
                try TestRunner.assertEqual(
                    OpenPanelFactory.directoryURL(for: "~/Downloads")?.standardizedFileURL.path,
                    URL(fileURLWithPath: expectedExpanded).standardizedFileURL.path
                )
                try TestRunner.assertEqual(
                    OpenPanelFactory.directoryURL(for: "/tmp")?.standardizedFileURL.path,
                    URL(fileURLWithPath: "/tmp").standardizedFileURL.path
                )
                try TestRunner.assertNil(OpenPanelFactory.directoryURL(for: ""))
                try TestRunner.assertNil(OpenPanelFactory.directoryURL(for: nil))
            }
        }
    }
#endif
