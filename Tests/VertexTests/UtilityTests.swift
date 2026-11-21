#if DEBUG
    import Foundation
    @testable import VertexKit

    private final class DropBox<T>: @unchecked Sendable {
        var value: T?
    }

    enum UtilityTests {
        static func runAll() {
            print("\n\u{001B}[1m[Suite: UtilityTests]\u{001B}[0m")

            TestRunner.run("Utility: validazione di magnet e file") {
                try TestRunner.assertTrue(TorrentInput.isMagnet("magnet:?xt=urn:btih:abc"))
                try TestRunner.assertTrue(
                    TorrentInput.isMagnet("  MAGNET:?xt=urn:btih:abc\n"),
                    "Spazi e maiuscole non devono invalidare il magnet"
                )
                try TestRunner.assertFalse(TorrentInput.isMagnet(""), "La stringa vuota non è un magnet")
                try TestRunner.assertFalse(TorrentInput.isMagnet("https://example.com/a"))
                try TestRunner.assertFalse(TorrentInput.isMagnet("magnet"))

                let torrent = URL(fileURLWithPath: "/tmp/Example.TORRENT")
                try TestRunner.assertTrue(TorrentInput.isTorrentFile(torrent))
                try TestRunner.assertFalse(
                    TorrentInput.isTorrentFile(URL(fileURLWithPath: "/tmp/example.txt"))
                )
                try TestRunner.assertFalse(
                    TorrentInput.isTorrentFile(URL(string: "https://example.com/a.torrent")!),
                    "Un URL remoto non è un file locale"
                )
            }

            TestRunner.run("Utility: drag and drop di magnet e file rifiutati") {
                let hash = String(repeating: "a", count: 40)
                let magnetProvider = NSItemProvider(
                    object: "magnet:?xt=urn:btih:\(hash)" as NSString
                )
                let dropped = onMain { DropBox<TorrentDropItem>() }
                let rejected = onMain { DropBox<String>() }

                let handled = onMain {
                    TorrentDropHandler.handle(
                        [magnetProvider],
                        onItem: { dropped.value = $0 },
                        onRejected: { rejected.value = $0 ?? "" }
                    )
                }
                try TestRunner.assertTrue(handled, "Un provider testuale deve essere gestito")
                try TestsSupport.waitFor("drop del magnet") {
                    onMain {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                        return dropped.value != nil
                    }
                }
                if case .magnet(let text)? = onMain({ dropped.value }) {
                    try TestRunner.assertEqual(text, "magnet:?xt=urn:btih:\(hash)")
                } else {
                    try TestRunner.assertTrue(false, "Il drop deve produrre un magnet")
                }

                let textProvider = NSItemProvider(object: "not a magnet" as NSString)
                _ = onMain {
                    TorrentDropHandler.handle(
                        [textProvider],
                        onItem: { _ in },
                        onRejected: { rejected.value = $0 ?? "nessun nome" }
                    )
                }
                try TestsSupport.waitFor("drop rifiutato") {
                    onMain {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                        return rejected.value != nil
                    }
                }
                try TestRunner.assertEqual(onMain { rejected.value }, "nessun nome")
            }
        }
    }
#endif
