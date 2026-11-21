import Foundation
import VertexKit

enum GeoIPTests {
    static func runAll() {
        TestRunner.run("GeoIP: bandiera da codice paese") {
            try TestRunner.assertEqual(GeoIP.flag(for: "IT"), "🇮🇹")
            try TestRunner.assertEqual(GeoIP.flag(for: "it"), "🇮🇹")
            try TestRunner.assertEqual(GeoIP.flag(for: "ZZ"), "🇿🇿")
            try TestRunner.assertNil(GeoIP.flag(for: "I"), "Un codice di un carattere non è valido")
            try TestRunner.assertNil(GeoIP.flag(for: "ITA"), "Un codice di tre caratteri non è valido")
        }

        TestRunner.run("GeoIP: parsing dell'endpoint") {
            try TestRunner.assertEqual(GeoIP.ipv4Address(fromEndpoint: "8.8.8.8:6881"), 0x0808_0808)
            try TestRunner.assertEqual(GeoIP.ipv4Address(fromEndpoint: "1.2.3.4"), 0x0102_0304)
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "[::1]:6881"), "IPv6 non è supportato")
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "2001:db8::1:6881"))
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "1.2.3.256:1"))
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "host:6881"))
        }

        TestRunner.run("GeoIP: indirizzi privati e speciali") {
            let local = [
                "10.1.2.3:1", "172.16.0.1:1", "172.31.255.255:1",
                "192.168.1.1:1", "127.0.0.1:1", "100.64.0.1:1",
                "169.254.1.1:1", "224.0.0.1:1",
            ]
            for endpoint in local {
                try TestRunner.assertTrue(
                    GeoIP.isLocalEndpoint(endpoint),
                    "\(endpoint) deve essere considerato locale"
                )
            }
            for endpoint in ["8.8.8.8:1", "151.15.0.1:1", "172.32.0.1:1"] {
                try TestRunner.assertFalse(
                    GeoIP.isLocalEndpoint(endpoint),
                    "\(endpoint) non deve essere considerato locale"
                )
            }
        }

        TestRunner.run("GeoIP: lookup nella tabella compatta") {
            // The test runner has no app bundle: read the committed table from
            // the source tree, like the integration fixtures do.
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let url = root.appendingPathComponent("Resources/GeoIP/country-v4.bin.z")
            guard let table = GeoIPTable.load(from: url) else {
                try TestRunner.assertTrue(false, "Tabella GeoIP non caricata: \(url.path)")
                return
            }

            let cases: [(String, String)] = [
                ("8.8.8.8", "US"),
                ("151.15.0.1", "IT"),
                ("1.0.0.1", "AU"),
            ]
            for (address, expected) in cases {
                guard let value = GeoIP.ipv4Address(fromEndpoint: address) else {
                    try TestRunner.assertTrue(false, "Indirizzo non valido: \(address)")
                    return
                }
                try TestRunner.assertEqual(table.countryCode(for: value), expected)
            }
        }
    }
}
