import Foundation

print("\u{001B}[1;34m=== VERTEX TEST SUITE ===\u{001B}[0m")
let startTime = Date()

TestRunner.beginSuite("FormattersTests")
FormattersTests.runAll()
TestRunner.beginSuite("PreferencesTests")
PreferencesTests.runAll()
TestRunner.beginSuite("ModelsTests")
ModelsTests.runAll()
TestRunner.beginSuite("CTorrentBridgeTests")
CTorrentBridgeTests.runAll()
TestRunner.beginSuite("TorrentIntegrationTests")
TorrentIntegrationTests.runAll()

let elapsed = String(format: "%.3f", Date().timeIntervalSince(startTime))

print("\n\u{001B}[1m--- RIEPILOGO TEST ---\u{001B}[0m")
print("Superati:  \u{001B}[32m\(TestRunner.passed)\u{001B}[0m")
print("Falliti:   \u{001B}[\(TestRunner.failed == 0 ? "32m0" : "31m\(TestRunner.failed)")\u{001B}[0m")
print("Tempo:     \(elapsed)s")

let reportPath = ProcessInfo.processInfo.environment["VERTEX_TEST_REPORT"]
    ?? ".build/vertex-test-results.xml"
do {
    try TestRunner.writeJUnit(to: URL(fileURLWithPath: reportPath))
    print("Report:    \(reportPath)")
} catch {
    print("Avviso: impossibile scrivere il report JUnit: \(error)")
}

if TestRunner.failed > 0 {
    print("\n\u{001B}[31mErrori rilevati:\u{001B}[0m")
    for failure in TestRunner.failures {
        print("  - \(failure)")
    }
    exit(1)
} else {
    print("\n\u{001B}[32;1m✓ TUTTI I TEST SONO STATI SUPERATI CON SUCCESSO!\u{001B}[0m\n")
    exit(0)
}
