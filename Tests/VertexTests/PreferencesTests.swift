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

        TestRunner.run("Limite torrent attivi: validazione") {
            try TestRunner.assertTrue(Preferences.isValidActiveLimit(0))
            try TestRunner.assertTrue(Preferences.isValidActiveLimit(1))
            try TestRunner.assertTrue(Preferences.isValidActiveLimit(Preferences.maximumActiveTorrents))
            try TestRunner.assertFalse(Preferences.isValidActiveLimit(-1))
            try TestRunner.assertFalse(
                Preferences.isValidActiveLimit(Preferences.maximumActiveTorrents + 1)
            )
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

        TestRunner.run("BindAddress: solo indirizzi IPv4 letterali") {
            try TestRunner.assertEqual(Preferences.normalizedBindAddress(nil), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress(""), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("   "), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("10.8.0.2"), "10.8.0.2")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress(" 10.8.0.2 "), "10.8.0.2")
            // Nomi di interfaccia, hostname e IPv6 non sono accettati: il
            // bridge riceve il valore così com'è e solo un indirizzo letterale
            // vincola sia il socket in ascolto sia la sorgente in uscita.
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("utun3"), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("localhost"), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("::1"), "")
            try TestRunner.assertEqual(Preferences.normalizedBindAddress("10.8.0.256"), "")

            try TestRunner.assertTrue(Preferences.isValidIPv4("192.168.1.10"))
            try TestRunner.assertFalse(Preferences.isValidIPv4("0.0.0.0")) // rejected: not a usable bind address
            try TestRunner.assertFalse(Preferences.isValidIPv4("127.0.0.1")) // rejected: loopback
            try TestRunner.assertFalse(Preferences.isValidIPv4("169.254.1.1")) // rejected: link-local
            try TestRunner.assertFalse(Preferences.isValidIPv4("192.168.1")) // rejected: short form
            try TestRunner.assertFalse(Preferences.isValidIPv4("192.168.001.001")) // rejected: leading zeros
            try TestRunner.assertFalse(Preferences.isValidIPv4("192.168.1.10.1"))
        }

        TestRunner.run("Defaults: unica fonte per i valori registrati") {
            let defaults = PrefDefault.dictionary
            let expectedKeys: Set<String> = [
                PrefKey.downloadPath,
                PrefKey.downloadLimitKB,
                PrefKey.uploadLimitKB,
                PrefKey.listenPort,
                PrefKey.maxActiveTorrents,
                PrefKey.bindAddress,
                PrefKey.dhtEnabled,
                PrefKey.pexEnabled,
                PrefKey.lsdEnabled,
                PrefKey.upnpEnabled,
                PrefKey.startPaused,
                PrefKey.sequentialDefault,
                PrefKey.appearance,
                PrefKey.proxyEnabled,
                PrefKey.proxyHost,
                PrefKey.proxyPort,
                PrefKey.proxyUser,
                PrefKey.proxyPassword
            ]
            try TestRunner.assertEqual(Set(defaults.keys), expectedKeys)
            try TestRunner.assertEqual(defaults[PrefKey.downloadPath] as? String, Preferences.suggestedDownloadPath)
            try TestRunner.assertEqual(defaults[PrefKey.listenPort] as? Int, 6881)
            try TestRunner.assertEqual(defaults[PrefKey.maxActiveTorrents] as? Int, 0)
            try TestRunner.assertEqual(defaults[PrefKey.bindAddress] as? String, "")
            try TestRunner.assertEqual(defaults[PrefKey.downloadLimitKB] as? Int, 0)
            try TestRunner.assertEqual(defaults[PrefKey.uploadLimitKB] as? Int, 0)
            try TestRunner.assertEqual(defaults[PrefKey.dhtEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.pexEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.upnpEnabled] as? Bool, true)
            try TestRunner.assertEqual(defaults[PrefKey.startPaused] as? Bool, false)
            try TestRunner.assertEqual(defaults[PrefKey.appearance] as? String, "system")
            try TestRunner.assertEqual(defaults[PrefKey.proxyEnabled] as? Bool, false)
            try TestRunner.assertEqual(defaults[PrefKey.proxyHost] as? String, "127.0.0.1")
            try TestRunner.assertEqual(defaults[PrefKey.proxyPort] as? Int, 1080)
            try TestRunner.assertEqual(defaults[PrefKey.proxyUser] as? String, "")
            try TestRunner.assertEqual(defaults[PrefKey.proxyPassword] as? String, "")
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

        TestRunner.run("Startup validation: valori fuori range vengono ripristinati") {
            // LOW #9: validateAllPreferences() resets a corrupted plist to defaults.
            // Snapshot and restore the affected keys so the test does not leak into
            // the real user defaults.
            let defaults = UserDefaults.standard
            let keys = [
                PrefKey.listenPort, PrefKey.downloadLimitKB, PrefKey.uploadLimitKB,
                PrefKey.bindAddress, PrefKey.appearance, PrefKey.downloadPath,
                PrefKey.proxyPort, PrefKey.proxyHost
            ]
            let backup = keys.compactMap { defaults.object(forKey: $0) }
            defer {
                for (key, value) in zip(keys, backup) {
                    if let string = value as? String {
                        defaults.set(string, forKey: key)
                    } else if let number = value as? NSNumber {
                        defaults.set(number, forKey: key)
                    } else if let bool = value as? Bool {
                        defaults.set(bool, forKey: key)
                    }
                }
            }

            // Corrupt every preference at once.
            defaults.set(99999, forKey: PrefKey.listenPort)
            defaults.set(-5, forKey: PrefKey.downloadLimitKB)
            // Int32.max is above the representable KB range: it must be clamped
            // to the maximum valid limit rather than left as a raw sentinel.
            defaults.set(Int32.max, forKey: PrefKey.uploadLimitKB)
            defaults.set("utun3", forKey: PrefKey.bindAddress)
            defaults.set("chartreuse", forKey: PrefKey.appearance)
            defaults.set(88888, forKey: PrefKey.proxyPort)
            defaults.set("  proxy.local  ", forKey: PrefKey.proxyHost)
            // A .torrent file is a common mis-selection: the path must be resolved
            // to its parent directory rather than left pointing at the file.
            defaults.set("/tmp/corrupt-download.torrent", forKey: PrefKey.downloadPath)

            TorrentEngine.validateAllPreferences()

            try TestRunner.assertEqual(defaults.integer(forKey: PrefKey.listenPort), 6881)
            try TestRunner.assertEqual(defaults.integer(forKey: PrefKey.downloadLimitKB), 0)
            try TestRunner.assertEqual(
                defaults.integer(forKey: PrefKey.uploadLimitKB),
                Preferences.maximumLimitKB
            )
            try TestRunner.assertEqual(defaults.string(forKey: PrefKey.bindAddress), "")
            try TestRunner.assertEqual(
                defaults.string(forKey: PrefKey.appearance),
                PrefDefault.appearance
            )
            try TestRunner.assertEqual(
                defaults.integer(forKey: PrefKey.maxActiveTorrents),
                PrefDefault.maxActiveTorrents
            )
            try TestRunner.assertEqual(defaults.integer(forKey: PrefKey.proxyPort), 1080)
            try TestRunner.assertEqual(defaults.string(forKey: PrefKey.proxyHost), "proxy.local")
            try TestRunner.assertEqual(
                defaults.string(forKey: PrefKey.downloadPath),
                "/tmp"
            )
        }
    }
}
