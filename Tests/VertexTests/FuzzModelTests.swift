#if DEBUG
import Foundation
@testable import VertexKit

/// Deterministic SplitMix64: the fuzz corpus must be reproducible, otherwise a
/// failure cannot be replayed.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ upper: Int) -> Int {
        Int(next() % UInt64(max(upper, 1)))
    }
}

enum FuzzModelTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: FuzzModelTests]\u{001B}[0m")

        TestRunner.run("Fuzz: decodifica JSON resistente a mutazioni") {
            let snapshotSeed = Data("""
                {"torrents":[{"id":"abc","name":"A \\"quoted\\".mkv","state_code":3,
                "progress":0.5,"size":1024,"downloaded":512,"uploaded":0,
                "download_rate":10,"upload_rate":0,"peers":1,"seeds":2,"eta":60,
                "finished":false,"seeding":false,"paused":false,"sequential":false,
                "has_metadata":true,"save_path":"/tmp","ratio":0.1,"added":1,"error":""}],
                "download_rate":10,"upload_rate":0,"active":1,"paused_count":0,
                "dht_nodes":3,"port":6881,"listen_actual_port":6881,"listening":true,
                "portmap":{"tcp":{"mapped":false,"external_port":0,"transport":"","error":""},
                "udp":{"mapped":false,"external_port":0,"transport":"","error":""},"error":""},
                "bind_address":"","listen_error":"","alert_error":"","alert_errors":[],
                "proxy":{"enabled":false,"type":"None","hostname":"","port":0,"auth":false,"error":""}}
                """.utf8)

            let detailSeed = Data("""
                {"files":[{"index":0,"path":"a.mkv","size":10,"progress":0.5,"priority":4}],
                "trackers":[{"url":"udp://x:1","verified":true,"fails":0,"message":"",
                "peers":1,"seeds":2}],
                "peers":[{"endpoint":"1.2.3.4:1","client":"x","progress":0.5,
                "download_rate":1,"upload_rate":2,"flags":"D","source":"tracker"}],
                "metadata":true}
                """.utf8)

            let decoder = JSONDecoder()
            // The corpus must start valid, otherwise the mutations test nothing
            // but the error path.
            try TestRunner.assertNotNil(
                try? decoder.decode(VertexSnapshot.self, from: snapshotSeed),
                "Il seed dello snapshot deve decodificarsi"
            )
            try TestRunner.assertNotNil(
                try? decoder.decode(TorrentDetail.self, from: detailSeed),
                "Il seed del dettaglio deve decodificarsi"
            )

            var rng = SplitMix64(state: 0xC0FFEE_1234)
            for _ in 0..<10_000 {
                var snapshot = [UInt8](snapshotSeed)
                var detail = [UInt8](detailSeed)
                for _ in 0..<(1 + rng.int(4)) {
                    mutate(&snapshot, &rng)
                    mutate(&detail, &rng)
                }
                // Decoding may fail, but it must never trap: the UI relies on
                // `try?` for every snapshot and detail payload.
                _ = try? decoder.decode(VertexSnapshot.self, from: Data(snapshot))
                _ = try? decoder.decode(TorrentDetail.self, from: Data(detail))
            }
        }
    }

    private static func mutate(_ bytes: inout [UInt8], _ rng: inout SplitMix64) {
        switch rng.int(5) {
        case 0:
            if !bytes.isEmpty { bytes[rng.int(bytes.count)] ^= UInt8(1 << rng.int(8)) }
        case 1:
            if !bytes.isEmpty { bytes[rng.int(bytes.count)] = UInt8(rng.int(256)) }
        case 2:
            bytes.insert(UInt8(rng.int(256)), at: rng.int(bytes.count + 1))
        case 3:
            if !bytes.isEmpty { bytes.remove(at: rng.int(bytes.count)) }
        default:
            if bytes.count > 2 {
                let start = rng.int(bytes.count)
                let end = start + rng.int(bytes.count - start)
                bytes.removeSubrange(start..<end)
            }
        }
        if bytes.count > 16_384 {
            bytes.removeLast(bytes.count - 16_384)
        }
    }
}
#endif
