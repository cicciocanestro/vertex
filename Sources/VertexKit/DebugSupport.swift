#if DEBUG
import Foundation

enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VERTEX_DEMO"] == "1"
    }

    private static let demoDownloadPath: String = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Vertex", isDirectory: true).path ?? "/tmp/Vertex"
    }()

    static func torrents() -> [Torrent] {
        [
            Torrent(
                id: "8f14e45fceea167a5a36dedd4bea2543a1b2c3d4",
                name: "Big.Buck.Bunny.4K.OPEN.MOVIE.mkv",
                stateCode: 3,
                progress: 0.427,
                size: 19_726_740_480,
                downloaded: 8_422_000_000,
                uploaded: 1_240_000_000,
                downloadRate: 8_640_000,
                uploadRate: 640_000,
                peers: 34,
                seeds: 12,
                eta: 1_308,
                finished: false,
                seeding: false,
                paused: false,
                sequential: false,
                hasMetadata: true,
                savePath: demoDownloadPath,
                files: 3,
                ratio: 0.15,
                added: Int64(Date().timeIntervalSince1970) - 1_200,
                error: ""
            ),
            Torrent(
                id: "c9f0f895fb98ab9159f51fd0297e236d1e2f3a4b",
                name: "Sintel.2010.4K.DCP.REMUX",
                stateCode: 2,
                progress: 0,
                size: 0,
                downloaded: 0,
                uploaded: 0,
                downloadRate: 0,
                uploadRate: 0,
                peers: 6,
                seeds: 0,
                eta: -1,
                finished: false,
                seeding: false,
                paused: false,
                sequential: false,
                hasMetadata: false,
                savePath: demoDownloadPath,
                files: 0,
                ratio: 0,
                added: Int64(Date().timeIntervalSince1970) - 640,
                error: ""
            ),
            Torrent(
                id: "45c48cce2e2d7fbdea1afc51c7c6ad26f5e4d3c2",
                name: "ubuntu-24.04.2-desktop-amd64.iso",
                stateCode: 5,
                progress: 1,
                size: 6_128_123_904,
                downloaded: 6_128_123_904,
                uploaded: 19_126_000_000,
                downloadRate: 0,
                uploadRate: 2_400_000,
                peers: 18,
                seeds: 5,
                eta: 0,
                finished: true,
                seeding: true,
                paused: false,
                sequential: false,
                hasMetadata: true,
                savePath: demoDownloadPath,
                files: 1,
                ratio: 3.12,
                added: Int64(Date().timeIntervalSince1970) - 86_400,
                error: ""
            ),
            Torrent(
                id: "d3d9446802a44259755d38e6d163e820aabbccdd",
                name: "Cosmos.Laundromat.2022.OPEN.MOVIE.mkv",
                stateCode: 3,
                progress: 0.634,
                size: 8_718_000_000,
                downloaded: 5_527_000_000,
                uploaded: 312_000_000,
                downloadRate: 0,
                uploadRate: 0,
                peers: 0,
                seeds: 0,
                eta: -1,
                finished: false,
                seeding: false,
                paused: true,
                sequential: false,
                hasMetadata: true,
                savePath: demoDownloadPath,
                files: 2,
                ratio: 0.06,
                added: Int64(Date().timeIntervalSince1970) - 172_800,
                error: ""
            ),
            Torrent(
                id: "6512bd43d9caa6e02c990b0a82652dcae5f6a7b8",
                name: "Open.Movie.Project.Assets.2025.zip",
                stateCode: 4,
                progress: 1,
                size: 2_311_000_000,
                downloaded: 2_311_000_000,
                uploaded: 890_000_000,
                downloadRate: 0,
                uploadRate: 0,
                peers: 0,
                seeds: 0,
                eta: 0,
                finished: true,
                seeding: false,
                paused: false,
                sequential: true,
                hasMetadata: true,
                savePath: demoDownloadPath,
                files: 48,
                ratio: 0.38,
                added: Int64(Date().timeIntervalSince1970) - 604_800,
                error: ""
            )
        ]
    }

    static func history(base: Double, spread: Double, count: Int = 80) -> [Double] {
        (0..<count).map { index in
            let wave = sin(Double(index) / 5.5) * 0.35 + sin(Double(index) / 2.1) * 0.12
            return max(0, base * (1 + wave * spread))
        }
    }
}
#endif

#if DEBUG
extension DemoData {
    static func detail(for torrent: Torrent?) -> TorrentDetail? {
        guard let torrent, torrent.hasMetadata else { return nil }
        let files: [TorrentFile]
        if torrent.files > 1 {
            files = [
                TorrentFile(index: 0, path: "video/main-feature.mkv", size: Int64(Double(torrent.size) * 0.82), progress: torrent.finished ? 1 : torrent.progress, priority: 4),
                TorrentFile(index: 1, path: "audio/italian.ac3", size: Int64(Double(torrent.size) * 0.12), progress: torrent.finished ? 1 : torrent.progress, priority: 4),
                TorrentFile(index: 2, path: "subtitles/italian.srt", size: 48_210, progress: torrent.finished ? 1 : min(1, torrent.progress + 0.2), priority: 4),
                TorrentFile(index: 3, path: "extras/behind-the-scenes.mkv", size: Int64(Double(torrent.size) * 0.06), progress: torrent.finished ? 1 : 0, priority: 0)
            ]
        } else {
            files = [TorrentFile(index: 0, path: torrent.name, size: torrent.size, progress: torrent.progress, priority: 4)]
        }
        return TorrentDetail(
            files: files,
            trackers: [
                TorrentTracker(url: "udp://tracker.opentrackr.org:1337/announce", verified: true, fails: 0, message: "", peers: 132, seeds: 48),
                TorrentTracker(url: "https://tracker2.ctix.cn:443/announce", verified: true, fails: 0, message: "", peers: 84, seeds: 31),
                TorrentTracker(url: "udp://open.stealth.si:80/announce", verified: false, fails: 1, message: "Connection timed out", peers: -1, seeds: -1)
            ],
            metadata: true
        )
    }
}
#endif
