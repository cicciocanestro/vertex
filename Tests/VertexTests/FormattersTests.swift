import Foundation
import VertexKit

enum FormattersTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: FormattersTests]\u{001B}[0m")

        TestRunner.run("Bytes formatting: zero e piccoli valori") {
            try TestRunner.assertEqual(Fmt.bytes(0), "0 B")
            try TestRunner.assertEqual(Fmt.bytes(500), "500 B")
            try TestRunner.assertEqual(Fmt.bytes(999), "999 B")
        }

        TestRunner.run("Bytes formatting: scale KB, MB, GB") {
            let kb1 = Fmt.bytes(1000)
            try TestRunner.assertTrue(kb1.contains("KB"), "Atteso KB, ottenuto \(kb1)")

            let mb = Fmt.bytes(5_500_000)
            try TestRunner.assertTrue(mb.contains("MB"), "Atteso MB, ottenuto \(mb)")

            let gb = Fmt.bytes(12_400_000_000)
            try TestRunner.assertTrue(gb.contains("GB"), "Atteso GB, ottenuto \(gb)")
        }

        TestRunner.run("Bytes formatting: valori negativi") {
            try TestRunner.assertEqual(Fmt.bytes(-500), "-500 B")
        }

        TestRunner.run("Rate formatting: velocità di trasferimento") {
            try TestRunner.assertEqual(Fmt.rate(0), "0 B/s")
            let rateMb = Fmt.rate(2_500_000)
            try TestRunner.assertTrue(rateMb.hasSuffix("/s"))
            try TestRunner.assertTrue(rateMb.contains("MB"))
        }

        TestRunner.run("ETA formatting: casi limite e intervalli") {
            try TestRunner.assertEqual(Fmt.eta(-1), "—")
            try TestRunner.assertEqual(Fmt.eta(-100), "—")
            try TestRunner.assertEqual(Fmt.eta(0), L("Completato"))
            try TestRunner.assertEqual(Fmt.eta(45), "45s")
            try TestRunner.assertEqual(Fmt.eta(120), "2m")
            try TestRunner.assertEqual(Fmt.eta(3600), "1h")
            try TestRunner.assertEqual(Fmt.eta(3660), "1h 1m")

            let dayAndHour = Fmt.eta(90_000)
            try TestRunner.assertTrue(dayAndHour.contains("1h"))
        }

        TestRunner.run("Percent formatting: clamping e percentuali") {
            try TestRunner.assertEqual(Fmt.percent(0.0), "0%")
            try TestRunner.assertEqual(Fmt.percent(0.5), "50%")
            try TestRunner.assertEqual(Fmt.percent(1.0), "100%")
            try TestRunner.assertEqual(Fmt.percent(-0.2), "0%")
            try TestRunner.assertEqual(Fmt.percent(1.5), "100%")
        }

        TestRunner.run("Ratio formatting: formattazione con 2 decimali") {
            let zero = Fmt.ratio(0.0)
            try TestRunner.assertTrue(zero == "0.00" || zero == "0,00", "Atteso 0.00, ottenuto \(zero)")
            let oneAndHalf = Fmt.ratio(1.5)
            try TestRunner.assertTrue(oneAndHalf == "1.50" || oneAndHalf == "1,50", "Atteso 1.50, ottenuto \(oneAndHalf)")
        }
    }
}
