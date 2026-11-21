import Compression
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
            try TestRunner.assertNil(
                GeoIP.ipv4Address(fromEndpoint: "[::1]:6881"),
                "ipv4Address deve rifiutare IPv6"
            )
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "2001:db8::1:6881"))
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "1.2.3.256:1"))
            try TestRunner.assertNil(GeoIP.ipv4Address(fromEndpoint: "host:6881"))
        }

        TestRunner.run("GeoIP: parsing IPv6") {
            let address = GeoIP.ipv6Address(fromEndpoint: "[2001:4860:1c00::1]:6881")
            try TestRunner.assertEqual(address?.high, 0x2001_4860_1c00_0000)
            try TestRunner.assertEqual(address?.low, 1)

            let loopback = GeoIP.ipv6Address(fromEndpoint: "[::1]:1")
            try TestRunner.assertEqual(loopback?.high, 0)
            try TestRunner.assertEqual(loopback?.low, 1)

            try TestRunner.assertNil(GeoIP.ipv6Address(fromEndpoint: "1.2.3.4:6881"))
            try TestRunner.assertNil(GeoIP.ipv6Address(fromEndpoint: "[not-an-address]:1"))
            try TestRunner.assertNil(GeoIP.ipv6Address(fromEndpoint: "[2001:db8::1"))
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

        TestRunner.run("GeoIP: IPv6 privati e speciali") {
            let local = [
                "[::1]:1", "[fe80::1]:1", "[fd12:3456::1]:1",
                "[ff02::1]:1", "[::ffff:192.168.1.1]:1",
            ]
            for endpoint in local {
                try TestRunner.assertTrue(
                    GeoIP.isLocalEndpoint(endpoint),
                    "\(endpoint) deve essere considerato locale"
                )
            }
            for endpoint in [
                "[2001:4860:1c00::1]:1", "[::ffff:8.8.8.8]:1", "[2001:470:2bf::1]:1",
            ] {
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

        TestRunner.run("GeoIP: lookup IPv6 nella tabella compatta") {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let url = root.appendingPathComponent("Resources/GeoIP/country-v6.bin.z")
            guard let table = GeoIPv6Table.load(from: url) else {
                try TestRunner.assertTrue(false, "Tabella GeoIP IPv6 non caricata: \(url.path)")
                return
            }

            let cases: [(String, String)] = [
                ("2001:4860:1c00::1", "US"),
                ("2001:470:2bf::1", "IT"),
                ("2001:4860::1", "CA"),
            ]
            for (address, expected) in cases {
                guard let value = GeoIP.ipv6Address(fromEndpoint: address) else {
                    try TestRunner.assertTrue(false, "Indirizzo non valido: \(address)")
                    return
                }
                try TestRunner.assertEqual(table.countryCode(for: value), expected)
            }

            // DB-IP covers the reserved prefixes too and reports them as ZZ.
            let reserved = GeoIP.ipv6Address(fromEndpoint: "2001:db8::1")
            try TestRunner.assertEqual(
                reserved.map { table.countryCode(for: $0) } ?? nil,
                "ZZ"
            )
        }

        TestRunner.run("GeoIP: tabella IPv6 minima e fuori range") {
            guard let table = makeTinyV6Table() else {
                try TestRunner.assertTrue(false, "Tabella IPv6 minima non creata")
                return
            }
            try TestRunner.assertEqual(
                table.countryCode(for: IPv6Address(high: 0, low: 0)),
                "IT"
            )
            try TestRunner.assertNil(
                table.countryCode(for: IPv6Address(high: 0, low: 2)),
                "Un indirizzo fuori range non deve produrre un codice"
            )
        }
    }

    /// Builds the compact format in memory: one country, one range [0, 1].
    private static func makeTinyV6Table() -> GeoIPv6Table? {
        var payload: [UInt8] = [1, 0]  // country count (little endian)
        payload += Array("IT".utf8)
        payload += [0]  // start delta from zero
        payload += [1]  // range length: covers 0...1
        payload += [0]  // country index

        let capacity = payload.count * 4 + 64
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = payload.withUnsafeBytes { source in
            buffer.withUnsafeMutableBytes { destination in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }

        var data = Data()
        var size = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        data.append(contentsOf: buffer.prefix(written))
        return GeoIPv6Table(compressed: data)
    }
}
