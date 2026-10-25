import Foundation
import VertexKit

enum PreferencesTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: PreferencesTests]\u{001B}[0m")

        TestRunner.run("LimitBytes: clamping e prevenzione overflow Int32") {
            try TestRunner.assertEqual(Preferences.limitBytes(fromKB: 0), 0)
            try TestRunner.assertEqual(Preferences.limitBytes(fromKB: 1024), 1024 * 1024)
            try TestRunner.assertEqual(Preferences.limitBytes(fromKB: -50), 0)

            // Test overflow avoidance con valori molto grandi
            let maxLimit = Preferences.limitBytes(fromKB: Int.max)
            try TestRunner.assertTrue(maxLimit > 0, "Il limite deve rimanere positivo")
            try TestRunner.assertTrue(maxLimit <= Int32.max, "Il limite deve rientrare in Int32")
        }

        TestRunner.run("ValidPort: validazione range porte TCP/UDP") {
            try TestRunner.assertEqual(Preferences.validPort(6881), 6881)
            try TestRunner.assertEqual(Preferences.validPort(80), 80)
            try TestRunner.assertEqual(Preferences.validPort(65535), 65535)
            // Fuori range: fallback a 6881
            try TestRunner.assertEqual(Preferences.validPort(0), 6881)
            try TestRunner.assertEqual(Preferences.validPort(-1), 6881)
            try TestRunner.assertEqual(Preferences.validPort(70000), 6881)
        }

        TestRunner.run("ResolvedDownloadPath: sanitizzazione e percorsi fallback") {
            let fallback = Preferences.suggestedDownloadPath
            try TestRunner.assertEqual(Preferences.resolvedDownloadPath(""), fallback)
            try TestRunner.assertEqual(Preferences.resolvedDownloadPath("   "), fallback)
            try TestRunner.assertEqual(Preferences.resolvedDownloadPath(nil), fallback)

            // Espansione tilde
            let tildePath = Preferences.resolvedDownloadPath("~/Downloads")
            try TestRunner.assertFalse(tildePath.hasPrefix("~"), "La tilde deve essere espansa")

            // Se il percorso finisce per .torrent (errore comune di selezione file)
            let torrentFilePath = "/tmp/sample_download/test.torrent"
            let resolvedTorrentDir = Preferences.resolvedDownloadPath(torrentFilePath)
            try TestRunner.assertEqual(resolvedTorrentDir, "/tmp/sample_download")
        }
    }
}
