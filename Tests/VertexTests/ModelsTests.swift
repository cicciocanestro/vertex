import Foundation
import VertexKit

enum ModelsTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: ModelsTests]\u{001B}[0m")

        TestRunner.run("Snapshot JSON Decoding: parsing completo") {
            let json = """
            {
                "download_rate": 1048576,
                "upload_rate": 524288,
                "active": 2,
                "paused_count": 1,
                "dht_nodes": 128,
                "alert_error": "",
                "listen_actual_port": 6881,
                "listening": true,
                "bind_address": "10.8.0.2",
                "listen_error": "",
                "portmap": {
                    "tcp": {"mapped": true, "external_port": 6881, "transport": "UPnP", "error": ""},
                    "udp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "error": ""
                },
                "proxy": {
                    "enabled": true,
                    "type": "SOCKS5",
                    "hostname": "127.0.0.1",
                    "port": 1080
                },
                "port": 6881,
                "torrents": [
                    {
                        "id": "abc123def456",
                        "name": "Ubuntu 24.04 LTS Desktop",
                        "state_code": 3,
                        "progress": 0.65,
                        "size": 4294967296,
                        "downloaded": 2791728742,
                        "uploaded": 104857600,
                        "download_rate": 1048576,
                        "upload_rate": 524288,
                        "peers": 42,
                        "seeds": 150,
                        "eta": 1433,
                        "finished": false,
                        "seeding": false,
                        "paused": false,
                        "sequential": true,
                        "has_metadata": true,
                        "save_path": "/Users/test/Downloads/Vertex",
                        "ratio": 0.037,
                        "added": 1729600000,
                        "error": ""
                    }
                ]
            }
            """

            guard let data = json.data(using: .utf8) else {
                try TestRunner.assertTrue(false, "Impossibile convertire JSON in Data")
                return
            }

            let decoder = JSONDecoder()
            let snapshot = try decoder.decode(VertexSnapshot.self, from: data)

            try TestRunner.assertEqual(snapshot.downloadRate, 1048576)
            try TestRunner.assertEqual(snapshot.uploadRate, 524288)
            try TestRunner.assertEqual(snapshot.active, 2)
            try TestRunner.assertEqual(snapshot.dhtNodes, 128)
            try TestRunner.assertEqual(snapshot.alertError, "")
            try TestRunner.assertEqual(snapshot.listening, true)
            try TestRunner.assertEqual(snapshot.listenActualPort, 6881)
            try TestRunner.assertEqual(snapshot.portmap.tcp.mapped, true)
            try TestRunner.assertEqual(snapshot.portmap.tcp.externalPort, 6881)
            try TestRunner.assertEqual(snapshot.bindAddress, "10.8.0.2")
            try TestRunner.assertEqual(snapshot.listenError, "")
            try TestRunner.assertTrue(snapshot.stats.isBoundToAddress)
            try TestRunner.assertEqual(snapshot.stats.bindAddress, "10.8.0.2")
            try TestRunner.assertTrue(snapshot.stats.isProxyActive)
            try TestRunner.assertEqual(snapshot.stats.proxy.hostname, "127.0.0.1")
            try TestRunner.assertEqual(snapshot.stats.proxy.port, 1080)
            try TestRunner.assertFalse(snapshot.stats.proxy.hasError)
            try TestRunner.assertEqual(snapshot.stats.proxy.error, "")
            try TestRunner.assertEqual(snapshot.torrents.count, 1)

            let t = snapshot.torrents[0]
            try TestRunner.assertEqual(t.id, "abc123def456")
            try TestRunner.assertEqual(t.name, "Ubuntu 24.04 LTS Desktop")
            try TestRunner.assertEqual(t.stateCode, 3)
            try TestRunner.assertEqual(t.progress, 0.65)
            try TestRunner.assertEqual(t.size, 4294967296)
            try TestRunner.assertEqual(t.peers, 42)
            try TestRunner.assertEqual(t.seeds, 150)
            try TestRunner.assertEqual(t.sequential, true)
            try TestRunner.assertEqual(t.hasMetadata, true)
            try TestRunner.assertEqual(t.error, "")
        }

        TestRunner.run("Snapshot JSON Decoding: ETA sconosciuta conserva -1") {
            // The C++ bridge emits -1 when the ETA cannot be computed (paused,
            // metadata, verification, no payload rate). The model must keep that
            // sentinel: clamping it to 0 made InspectorView show "Completato".
            let json = """
            {
                "download_rate": 0,
                "upload_rate": 0,
                "active": 0,
                "paused_count": 2,
                "dht_nodes": 0,
                "alert_error": "",
                "listen_actual_port": 6881,
                "listening": true,
                "bind_address": "",
                "listen_error": "",
                "portmap": {
                    "tcp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "udp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "error": ""
                },
                "proxy": {
                    "enabled": false,
                    "type": "None",
                    "hostname": "",
                    "port": 0
                },
                "port": 6881,
                "torrents": [
                    {
                        "id": "paused123456",
                        "name": "Torrent in pausa",
                        "state_code": 3,
                        "progress": 0.4,
                        "size": 1000,
                        "downloaded": 400,
                        "uploaded": 0,
                        "download_rate": 0,
                        "upload_rate": 0,
                        "peers": 0,
                        "seeds": 0,
                        "eta": -1,
                        "finished": false,
                        "seeding": false,
                        "paused": true,
                        "sequential": false,
                        "has_metadata": true,
                        "save_path": "/tmp",
                        "ratio": 0,
                        "added": 0,
                        "error": ""
                    },
                    {
                        "id": "metadata1234",
                        "name": "Torrent senza metadati",
                        "state_code": 2,
                        "progress": 0,
                        "size": 0,
                        "downloaded": 0,
                        "uploaded": 0,
                        "download_rate": 0,
                        "upload_rate": 0,
                        "peers": 3,
                        "seeds": 0,
                        "eta": -42,
                        "finished": false,
                        "seeding": false,
                        "paused": false,
                        "sequential": false,
                        "has_metadata": false,
                        "save_path": "/tmp",
                        "ratio": 0,
                        "added": 0,
                        "error": ""
                    }
                ]
            }
            """
            guard let data = json.data(using: .utf8) else {
                try TestRunner.assertTrue(false, "Impossibile convertire JSON in Data")
                return
            }

            let snapshot = try JSONDecoder().decode(VertexSnapshot.self, from: data)
            try TestRunner.assertEqual(snapshot.torrents.count, 2)
            try TestRunner.assertEqual(snapshot.torrents[0].eta, -1)
            try TestRunner.assertEqual(Fmt.eta(snapshot.torrents[0].eta), "—")
            // Anything below -1 is clamped to the sentinel, never to 0.
            try TestRunner.assertEqual(snapshot.torrents[1].eta, -1)
            try TestRunner.assertEqual(Fmt.eta(snapshot.torrents[1].eta), "—")
        }

        TestRunner.run("PortMapSnapshot: errori TCP e UDP separati") {
            let json = """
            {
                "tcp": {
                    "mapped": false,
                    "external_port": 0,
                    "transport": "",
                    "error": "UPnP: timeout"
                },
                "udp": {
                    "mapped": true,
                    "external_port": 6881,
                    "transport": "NAT-PMP",
                    "error": ""
                },
                "error": ""
            }
            """
            guard let data = json.data(using: .utf8) else {
                try TestRunner.assertTrue(false, "Impossibile convertire JSON in Data")
                return
            }

            let portmap = try JSONDecoder().decode(PortMapSnapshot.self, from: data)
            try TestRunner.assertEqual(portmap.tcp.error, "UPnP: timeout")
            try TestRunner.assertTrue(portmap.tcp.hasError)
            try TestRunner.assertFalse(portmap.tcp.mapped)
            try TestRunner.assertEqual(portmap.udp.error, "")
            try TestRunner.assertFalse(portmap.udp.hasError)
            try TestRunner.assertTrue(portmap.udp.mapped)
            try TestRunner.assertEqual(portmap.udp.transport, "NAT-PMP")
            try TestRunner.assertTrue(portmap.hasError)
        }

        TestRunner.run("TorrentDetail JSON Decoding") {
            let json = """
            {
                "files": [
                    {
                        "index": 0,
                        "path": "ubuntu-24.04-desktop-arm64.iso",
                        "size": 4294967296,
                        "progress": 0.65,
                        "priority": 4
                    }
                ],
                "trackers": [
                    {
                        "url": "https://torrent.ubuntu.com/announce",
                        "verified": true,
                        "fails": 0,
                        "message": "OK",
                        "peers": 42,
                        "seeds": 150
                    }
                ],
                "metadata": true
            }
            """
            guard let data = json.data(using: .utf8) else {
                try TestRunner.assertTrue(false, "Impossibile convertire JSON in Data")
                return
            }

            let detail = try JSONDecoder().decode(TorrentDetail.self, from: data)
            try TestRunner.assertEqual(detail.metadata, true)
            try TestRunner.assertEqual(detail.trackers.count, 1)
            try TestRunner.assertEqual(detail.trackers[0].url, "https://torrent.ubuntu.com/announce")
            try TestRunner.assertEqual(detail.trackers[0].verified, true)
            try TestRunner.assertEqual(detail.trackers[0].fails, 0)
            try TestRunner.assertEqual(detail.files.count, 1)
            try TestRunner.assertEqual(detail.files[0].path, "ubuntu-24.04-desktop-arm64.iso")
            try TestRunner.assertEqual(detail.files[0].priority, 4)
            try TestRunner.assertEqual(detail.files[0].isWanted, true)
        }

        TestRunner.run("TorrentFilter: logica di filtraggio") {
            // States and flags as libtorrent actually reports them: a fully
            // downloaded torrent is a pure seeder (state 5, is_seeding true),
            // even when paused; state 4 only happens when some pieces are
            // filtered (files set to Skip).
            let activeDownloading = Torrent.test(id: "1", name: "T1", stateCode: 3)
            let pausedTorrent = Torrent.test(id: "2", name: "T2", stateCode: 3, paused: true)
            let seedingTorrent = Torrent.test(id: "3", name: "T3", stateCode: 5, uploadRate: 1024, finished: true, seeding: true)
            let pausedCompleted = Torrent.test(
                id: "4", name: "T4", stateCode: 5, finished: true, seeding: true, paused: true
            )
            let skippedFilesCompleted = Torrent.test(id: "5", name: "T5", stateCode: 4, finished: true)
            let checking = Torrent.test(id: "6", name: "T6", stateCode: 1)
            let idleCompleted = Torrent.test(id: "7", name: "T7", stateCode: 5, uploadRate: 0, finished: true, seeding: true)

            let all = [
                activeDownloading,
                pausedTorrent,
                seedingTorrent,
                pausedCompleted,
                skippedFilesCompleted,
                checking,
                idleCompleted
            ]

            // A finished download with filtered pieces is "completato".
            try TestRunner.assertEqual(TorrentFilter.category(for: skippedFilesCompleted), .completed)
            try TestRunner.assertEqual(skippedFilesCompleted.phase, .completed)
            // An active seeder with upload > 0 is seeding.
            try TestRunner.assertEqual(TorrentFilter.category(for: seedingTorrent), .seeding)
            try TestRunner.assertEqual(seedingTorrent.phase, .seeding)
            // A finished torrent that is paused shows as .completed phase (green ✓) but categorizes in paused filter.
            try TestRunner.assertEqual(pausedCompleted.phase, .completed)
            try TestRunner.assertEqual(TorrentFilter.category(for: pausedCompleted), .paused)
            // A finished torrent in seed with uploadRate == 0 shows as .completed phase (green ✓) and categorizes in completed.
            try TestRunner.assertEqual(idleCompleted.phase, .completed)
            try TestRunner.assertEqual(TorrentFilter.category(for: idleCompleted), .completed)

            let filteredDownloading = all.filter { TorrentFilter.downloading.matches($0) }
            try TestRunner.assertEqual(filteredDownloading.map(\.id), ["1", "6"])

            let filteredPaused = all.filter { TorrentFilter.paused.matches($0) }
            try TestRunner.assertEqual(filteredPaused.map(\.id), ["2", "4"])

            let filteredSeeding = all.filter { TorrentFilter.seeding.matches($0) }
            try TestRunner.assertEqual(filteredSeeding.map(\.id), ["3"])

            // "Completati" is the overlapping bucket: every finished torrent,
            // seeded ones included, so the chip is not empty for a normal
            // library (where every finished torrent is a seeder).
            let filteredCompleted = all.filter { TorrentFilter.completed.matches($0) }
            try TestRunner.assertEqual(filteredCompleted.map(\.id), ["3", "4", "5", "7"])
            try TestRunner.assertTrue(
                filteredCompleted.contains { TorrentFilter.seeding.matches($0) },
                "Un torrent in seed deve comparire anche tra i completati"
            )
            try TestRunner.assertFalse(
                filteredCompleted.contains { $0.id == "1" || $0.id == "2" || $0.id == "6" },
                "I torrent non finiti non sono completati"
            )

            // The three primary buckets plus the state-4 group are exclusive
            // and cover the whole list exactly once.
            let completedGroup = all.filter { TorrentFilter.category(for: $0) == .completed }
            try TestRunner.assertEqual(completedGroup.map(\.id), ["5", "7"])
            let exclusive = filteredDownloading + filteredPaused + filteredSeeding + completedGroup
            try TestRunner.assertEqual(exclusive.count, all.count)
            try TestRunner.assertEqual(Set(exclusive.map(\.id)), Set(all.map(\.id)))
            try TestRunner.assertFalse(filteredSeeding.contains { $0.id == "4" || $0.id == "5" || $0.id == "7" })

            let counts = TorrentListPipeline.applyWithCounts(
                to: all,
                filter: .all,
                search: "",
                sort: .recent
            ).counts
            try TestRunner.assertEqual(counts[.all, default: -1], 7)
            try TestRunner.assertEqual(counts[.downloading, default: -1], 2)
            try TestRunner.assertEqual(counts[.seeding, default: -1], 1)
            try TestRunner.assertEqual(counts[.paused, default: -1], 2)
            try TestRunner.assertEqual(counts[.completed, default: -1], 4)
        }

        TestRunner.run("TorrentListPipeline: filtro, ricerca e ordinamento") {
            let tA = Torrent.test(id: "A", name: "Alpha", progress: 0.1, size: 100, downloadRate: 50, added: 100)
            let tB = Torrent.test(id: "B", name: "Beta", progress: 0.9, size: 500, downloadRate: 500, added: 200)

            // `ascending: false` means "descending" for every criterion; the
            // filter bar asks for `defaultAscending` when the user picks one,
            // which is A→Z only for names.
            let byNameDescending = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .name)
            try TestRunner.assertEqual(byNameDescending.map(\.id), ["B", "A"])

            try TestRunner.assertEqual(TorrentSort.name.defaultAscending, true)
            try TestRunner.assertEqual(TorrentSort.recent.defaultAscending, false)
            try TestRunner.assertEqual(TorrentSort.size.defaultAscending, false)

            let byProgress = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .progress)
            try TestRunner.assertEqual(byProgress.first?.id, "B")

            let bySize = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .size)
            try TestRunner.assertEqual(bySize.first?.id, "B")

            let bySpeed = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .speed)
            try TestRunner.assertEqual(bySpeed.first?.id, "B")

            let byRecent = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .recent)
            try TestRunner.assertEqual(byRecent.first?.id, "B")

            // Ascending / inverted sort order for every criterion.
            let byNameAscending = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .name, ascending: true)
            try TestRunner.assertEqual(byNameAscending.map(\.id), ["A", "B"])

            // Names are compared with `localizedStandardCompare`: an uppercase
            // name must not sort before a lowercase one of the same letter.
            let lower = Torrent.test(id: "L", name: "alpha")
            let upper = Torrent.test(id: "U", name: "Beta")
            let caseInsensitive = TorrentListPipeline.apply(
                to: [upper, lower], filter: .all, search: "", sort: .name, ascending: true
            )
            try TestRunner.assertEqual(caseInsensitive.map(\.id), ["L", "U"])

            let byProgressAsc = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .progress, ascending: true)
            try TestRunner.assertEqual(byProgressAsc.first?.id, "A")

            let bySizeAsc = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .size, ascending: true)
            try TestRunner.assertEqual(bySizeAsc.first?.id, "A")

            let bySpeedAsc = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .speed, ascending: true)
            try TestRunner.assertEqual(bySpeedAsc.first?.id, "A")

            let byRecentAsc = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .recent, ascending: true)
            try TestRunner.assertEqual(byRecentAsc.first?.id, "A")

            let searched = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "alp", sort: .name)
            try TestRunner.assertEqual(searched.map(\.id), ["A"])

            let paused = Torrent.test(id: "P", name: "Paused", paused: true)
            let filtered = TorrentListPipeline.apply(to: [tA, paused], filter: .paused, search: "", sort: .name)
            try TestRunner.assertEqual(filtered.map(\.id), ["P"])

            let result = TorrentListPipeline.applyWithCounts(
                to: [tA, paused],
                filter: .all,
                search: "",
                sort: .name,
                ascending: true
            )
            try TestRunner.assertEqual(result.torrents.map(\.id), ["A", "P"])
            try TestRunner.assertEqual(result.counts[.all, default: -1], 2)
            try TestRunner.assertEqual(result.counts[.downloading, default: -1], 1)
            try TestRunner.assertEqual(result.counts[.paused, default: -1], 1)
            try TestRunner.assertEqual(result.counts[.completed, default: -1], 0)
            try TestRunner.assertEqual(result.counts[.seeding, default: -1], 0)

            // Load smoke test: the list pipeline must stay linear enough for a
            // realistic library and keep the exclusive counts consistent.
            var many: [Torrent] = []
            many.reserveCapacity(5_000)
            for index in 0..<5_000 {
                many.append(Torrent.test(
                    id: String(index),
                    name: "Torrent \(index)",
                    progress: Double(index % 100) / 100,
                    size: Int64(index),
                    downloadRate: Int64(index % 7),
                    finished: index % 3 == 0,
                    paused: index % 5 == 0,
                    added: Int64(index)
                ))
            }
            let started = Date()
            let load = TorrentListPipeline.applyWithCounts(
                to: many,
                filter: .all,
                search: "Torrent",
                sort: .name
            )
            let elapsed = Date().timeIntervalSince(started)
            try TestRunner.assertEqual(load.torrents.count, 5_000)
            try TestRunner.assertEqual(load.counts[.all, default: -1], 5_000)
            try TestRunner.assertTrue(
                elapsed < 5,
                "La pipeline di 5000 torrent ha impiegato \(elapsed)s"
            )
        }

        TestRunner.run("Coda: fase queued, categoria e decodifica") {
            // libtorrent pauses the torrents that do not fit in the active limit
            // and keeps them auto-managed: that is the queued state.
            let queued = Torrent.test(
                id: "Q", name: "Queued", paused: true, autoManaged: true
            )
            let queuedSeed = Torrent.test(
                id: "QS", name: "QueuedSeed", stateCode: 5, finished: true,
                seeding: true, paused: true, autoManaged: true
            )
            let manualPause = Torrent.test(
                id: "P", name: "Paused", paused: true, autoManaged: false
            )

            try TestRunner.assertEqual(queued.phase, .queued)
            try TestRunner.assertTrue(queued.isQueued)
            try TestRunner.assertEqual(manualPause.phase, .paused)
            try TestRunner.assertFalse(manualPause.isQueued)

            // The queue does not invent a new bucket: a waiting torrent belongs to
            // the list it will run in, and "Paused" keeps meaning "paused by you".
            try TestRunner.assertEqual(TorrentFilter.category(for: queued), .downloading)
            try TestRunner.assertEqual(TorrentFilter.category(for: queuedSeed), .seeding)
            try TestRunner.assertEqual(TorrentFilter.category(for: manualPause), .paused)
            try TestRunner.assertTrue(TorrentFilter.downloading.matches(queued))
            try TestRunner.assertFalse(TorrentFilter.paused.matches(queued))

            try TestRunner.assertEqual(TorrentPhase.queued.label, L("In coda"))

            let withFlag = """
            {"id":"a","name":"A","state_code":3,"progress":0.1,"size":10,"downloaded":1,
             "uploaded":0,"download_rate":0,"upload_rate":0,"peers":0,"seeds":0,"eta":-1,
             "finished":false,"seeding":false,"paused":true,"auto_managed":true,
             "sequential":false,"has_metadata":true,"save_path":"/tmp","ratio":0,"added":0,
             "error":""}
            """
            let decoded = try JSONDecoder().decode(Torrent.self, from: Data(withFlag.utf8))
            try TestRunner.assertTrue(decoded.autoManaged)
            try TestRunner.assertEqual(decoded.phase, .queued)

            let withoutFlag = withFlag.replacingOccurrences(of: "\"auto_managed\":true,", with: "")
            let legacy = try JSONDecoder().decode(Torrent.self, from: Data(withoutFlag.utf8))
            try TestRunner.assertFalse(legacy.autoManaged)
            try TestRunner.assertEqual(legacy.phase, .paused)
        }

        TestRunner.run("Navigazione da tastiera: limiti della lista") {
            try TestRunner.assertNil(TorrentListNavigation.nextIndex(current: nil, count: 0, delta: 1))
            try TestRunner.assertEqual(TorrentListNavigation.nextIndex(current: nil, count: 3, delta: 1), 0)
            try TestRunner.assertEqual(TorrentListNavigation.nextIndex(current: 0, count: 3, delta: -1), 0)
            try TestRunner.assertEqual(TorrentListNavigation.nextIndex(current: 2, count: 3, delta: 1), 2)
            try TestRunner.assertEqual(TorrentListNavigation.nextIndex(current: 1, count: 3, delta: -1), 0)
            try TestRunner.assertEqual(TorrentListNavigation.nextIndex(current: 1, count: 3, delta: 1), 2)
        }
    }
}
