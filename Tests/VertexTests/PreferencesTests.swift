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

        TestRunner.run("Limiti KB/s: validazione dei valori ammessi") {
            try TestRunner.assertTrue(Preferences.isValidLimitKB(0))
            try TestRunner.assertTrue(Preferences.isValidLimitKB(1024))
            try TestRunner.assertTrue(Preferences.isValidLimitKB(Preferences.maximumLimitKB))
            try TestRunner.assertFalse(Preferences.isValidLimitKB(-1))
            try TestRunner.assertFalse(Preferences.isValidLimitKB(Preferences.maximumLimitKB + 1))
        }

        TestRunner.run("ValidPort: validazione range porte TCP/UDP") {
            try TestRunner.assertEqual(Preferences.validPort(6881), 6881)
            try TestRunner.assertEqual(Preferences.validPort(80), 80)
            try TestRunner.assertEqual(Preferences.validPort(65535), 65535)
            // Fuori range: fallback a 6881
            try TestRunner.assertEqual(Preferences.validPort(0), 6881)
            try TestRunner.assertEqual(Preferences.validPort(-1), 6881)
            try TestRunner.assertEqual(Preferences.validPort(70000), 6881)
            try TestRunner.assertTrue(Preferences.isValidPort(1))
            try TestRunner.assertTrue(Preferences.isValidPort(6881))
            try TestRunner.assertTrue(Preferences.isValidPort(65535))
            try TestRunner.assertFalse(Preferences.isValidPort(0))
            try TestRunner.assertFalse(Preferences.isValidPort(-1))
            try TestRunner.assertFalse(Preferences.isValidPort(65536))
        }

        TestRunner.run("Defaults: unica fonte per i valori registrati") {
            let defaults = PrefDefault.dictionary
            let expectedKeys: Set<String> = [
                PrefKey.downloadPath,
                PrefKey.downloadLimitKB,
                PrefKey.uploadLimitKB,
                PrefKey.listenPort,
                PrefKey.dhtEnabled,
                PrefKey.pexEnabled,
                PrefKey.lsdEnabled,
                PrefKey.upnpEnabled,
                PrefKey.startPaused,
                PrefKey.sequentialDefault,
                PrefKey.appearance
            ]
            try TestRunner.assertEqual(Set(defaults.keys), expectedKeys)
            try TestRunner.assertEqual(defaults[PrefKey.downloadPath] as? String, Preferences.suggestedDownloadPath)
            try TestRunner.assertEqual(defaults[PrefKey.listenPort] as? Int, 6881)
            try TestRunner.assertEqual(defaults[PrefKey.downloadLimitKB] as? Int, 0)
            try TestRunner.assertEqual(defaults[PrefKey.uploadLimitKB] as? Int, 0)
            try TestRunner.assertEqual(defaults[PrefKey.dhtEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.pexEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.upnpEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.startPaused] as? Bool, false)
            try TestRunner.assertEqual(defaults[PrefKey.appearance] as? String, "dark")
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
