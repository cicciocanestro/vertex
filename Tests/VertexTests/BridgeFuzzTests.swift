import CTorrent
import Foundation
import VertexKit

/// Deterministic mutation fuzzing through the real bridge, so the parser paths
/// run under the address/thread sanitizers in CI. libtorrent itself is not
/// instrumented, but the bridge wrapper and its string handling are.
enum BridgeFuzzTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: BridgeFuzzTests]\u{001B}[0m")

        TestRunner.run("Bridge: fuzz di magnet e file .torrent") {
            let workspace = try IntegrationWorkspace()
            defer { workspace.cleanup() }
            let download = try workspace.directory("downloads")
            let resume = try workspace.directory("resume")

            let session = download.path.withCString { downloadPath in
                resume.path.withCString { resumePath in
                    vt_session_create_full(
                        downloadPath, resumePath, 6888,
                        0, 0, 0, 0, 0, 0, nil, nil
                    )
                }
            }
            guard let session else {
                try TestRunner.assertTrue(false, "Sessione non creata")
                return
            }
            defer { vt_session_destroy(session) }

            var rng = SplitMix64(state: 0xC0FFEE_2026)
            let torrentSeed = try Data(contentsOf: IntegrationFixture.v1.torrentURL)
            let torrentDirectory = try workspace.directory("fuzz")

            // Magnets: start from a valid prefix, then mutate the rest. A few
            // accepted handles are fine; the session is destroyed at the end.
            for _ in 0..<300 {
                var text = "magnet:?xt=urn:btih:"
                let length = rng.int(80)
                for _ in 0..<length {
                    text.append(mutationCharacter(&rng))
                }
                let rc = text.withCString { uri in
                    download.path.withCString { path in
                        vt_add_magnet(session, uri, path, 1, 0)
                    }
                }
                if rc != 0, let error = vt_last_error(session) { vt_free_string(error) }
            }

            // .torrent files: mutate the real fixture; most must be rejected
            // without taking the session down.
            for index in 0..<60 {
                var bytes = [UInt8](torrentSeed)
                for _ in 0..<(1 + rng.int(16)) {
                    mutateBytes(&bytes, &rng)
                }
                let url = torrentDirectory.appendingPathComponent("fuzz-\(index).torrent")
                try Data(bytes).write(to: url)
                let rc = url.path.withCString { filePointer in
                    download.path.withCString { path in
                        vt_add_torrent_file(session, filePointer, path, 1, 0)
                    }
                }
                if rc != 0, let error = vt_last_error(session) { vt_free_string(error) }
            }

            vt_session_poll(session)
            guard let snapshotPointer = vt_snapshot_json(session) else {
                try TestRunner.assertTrue(false, "Lo snapshot non è valido dopo il fuzz")
                return
            }
            defer { vt_free_string(snapshotPointer) }
            let json = Data(String(cString: snapshotPointer).utf8)
            try TestRunner.assertNotNil(
                try? JSONDecoder().decode(VertexSnapshot.self, from: json),
                "Lo snapshot deve restare decodificabile dopo gli input mutati"
            )
        }
    }

    private static func mutationCharacter(_ rng: inout SplitMix64) -> Character {
        let alphabet = Array(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                + ":/?&=.-_%[]()'\",; \\t\\n"
        )
        return alphabet[rng.int(alphabet.count)]
    }

    private static func mutateBytes(_ bytes: inout [UInt8], _ rng: inout SplitMix64) {
        switch rng.int(4) {
        case 0:
            if !bytes.isEmpty { bytes[rng.int(bytes.count)] ^= UInt8(1 << rng.int(8)) }
        case 1:
            if !bytes.isEmpty { bytes[rng.int(bytes.count)] = UInt8(rng.int(256)) }
        case 2:
            bytes.insert(UInt8(rng.int(256)), at: rng.int(bytes.count + 1))
        default:
            if bytes.count > 2 {
                let start = rng.int(bytes.count)
                bytes.removeSubrange(start..<(start + rng.int(bytes.count - start)))
            }
        }
        if bytes.count > 64 * 1024 {
            bytes.removeLast(bytes.count - 64 * 1024)
        }
    }
}

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
