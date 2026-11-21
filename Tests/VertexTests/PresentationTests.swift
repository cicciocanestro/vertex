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

            TestRunner.run("Presentation: ricerca nelle impostazioni") {
                try TestRunner.assertEqual(
                    SettingsSearch.matchingSections(SettingsSection.allCases, query: ""),
                    SettingsSection.allCases,
                    "Una ricerca vuota mostra tutte le sezioni"
                )
                try TestRunner.assertEqual(
                    SettingsSearch.matchingSections(SettingsSection.allCases, query: "proxy"),
                    [.proxy]
                )
                try TestRunner.assertEqual(
                    SettingsSearch.matchingSections(SettingsSection.allCases, query: "  PROXY  "),
                    [.proxy],
                    "Spazi e maiuscole non devono contare"
                )
                try TestRunner.assertEqual(
                    SettingsSearch.matchingSections(SettingsSection.allCases, query: "zzz"),
                    [],
                    "Una ricerca senza corrispondenze non deve restituire sezioni"
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
        }
    }
#endif
