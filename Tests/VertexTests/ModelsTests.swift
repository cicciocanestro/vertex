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
                "listen_actual_port": 6881,
                "listening": true,
                "bind_address": "10.8.0.2",
                "listen_error": "",
                "portmap": {
                    "tcp": {"mapped": true, "external_port": 6881, "transport": "UPnP", "error": ""},
                    "udp": {"mapped": false, "external_port": 0, "transport": "", "error": ""},
                    "error": ""
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
            try TestRunner.assertEqual(snapshot.listening, true)
            try TestRunner.assertEqual(snapshot.listenActualPort, 6881)
            try TestRunner.assertEqual(snapshot.portmap.tcp.mapped, true)
            try TestRunner.assertEqual(snapshot.portmap.tcp.externalPort, 6881)
            try TestRunner.assertEqual(snapshot.bindAddress, "10.8.0.2")
            try TestRunner.assertEqual(snapshot.listenError, "")
            try TestRunner.assertTrue(snapshot.stats.isBoundToAddress)
            try TestRunner.assertEqual(snapshot.stats.bindAddress, "10.8.0.2")
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
            let activeDownloading = Torrent.test(id: "1", name: "T1", finished: false, paused: false)
            let pausedTorrent = Torrent.test(id: "2", name: "T2", finished: false, paused: true)
            let seedingTorrent = Torrent.test(id: "3", name: "T3", finished: true, seeding: true, paused: false)
            let pausedCompleted = Torrent.test(id: "4", name: "T4", finished: true, seeding: false, paused: true)
            let completedOnly = Torrent.test(id: "5", name: "T5", finished: true, seeding: false, paused: false)
            let checking = Torrent.test(id: "6", name: "T6", stateCode: 1, hasMetadata: true)

            let all = [
                activeDownloading,
                pausedTorrent,
                seedingTorrent,
                pausedCompleted,
                completedOnly,
                checking
            ]

            let filteredDownloading = all.filter { TorrentFilter.downloading.matches($0) }
            try TestRunner.assertEqual(filteredDownloading.map(\.id), ["1", "6"])

            let filteredPaused = all.filter { TorrentFilter.paused.matches($0) }
            try TestRunner.assertEqual(filteredPaused.map(\.id), ["2", "4"])

            let filteredSeeding = all.filter { TorrentFilter.seeding.matches($0) }
            try TestRunner.assertEqual(filteredSeeding.map(\.id), ["3"])

            let filteredCompleted = all.filter { TorrentFilter.completed.matches($0) }
            try TestRunner.assertEqual(filteredCompleted.map(\.id), ["5"])

            // Every torrent belongs to exactly one filter: pause prevails, and
            // a seeding torrent is not also counted as completed.
            let exclusive = filteredDownloading + filteredPaused + filteredSeeding + filteredCompleted
            try TestRunner.assertEqual(exclusive.count, all.count)
            try TestRunner.assertEqual(Set(exclusive.map(\.id)), Set(all.map(\.id)))
            try TestRunner.assertFalse(filteredCompleted.contains { $0.id == "3" || $0.id == "4" })
            try TestRunner.assertFalse(filteredSeeding.contains { $0.id == "4" || $0.id == "5" })
        }

        TestRunner.run("TorrentListPipeline: filtro, ricerca e ordinamento") {
            let tA = Torrent.test(id: "A", name: "Alpha", progress: 0.1, size: 100, downloadRate: 50, added: 100)
            let tB = Torrent.test(id: "B", name: "Beta", progress: 0.9, size: 500, downloadRate: 500, added: 200)

            let all = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .name)
            try TestRunner.assertEqual(all.map(\.id), ["A", "B"])

            let byProgress = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .progress)
            try TestRunner.assertEqual(byProgress.first?.id, "B")

            let bySize = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .size)
            try TestRunner.assertEqual(bySize.first?.id, "B")

            let bySpeed = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .speed)
            try TestRunner.assertEqual(bySpeed.first?.id, "B")

            let byRecent = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "", sort: .recent)
            try TestRunner.assertEqual(byRecent.first?.id, "B")

            let searched = TorrentListPipeline.apply(to: [tA, tB], filter: .all, search: "alp", sort: .name)
            try TestRunner.assertEqual(searched.map(\.id), ["A"])

            let paused = Torrent.test(id: "P", name: "Paused", paused: true)
            let filtered = TorrentListPipeline.apply(to: [tA, paused], filter: .paused, search: "", sort: .name)
            try TestRunner.assertEqual(filtered.map(\.id), ["P"])

            let result = TorrentListPipeline.applyWithCounts(
                to: [tA, paused],
                filter: .all,
                search: "",
                sort: .name
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
    }
}
