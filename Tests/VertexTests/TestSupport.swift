import Foundation
import VertexKit
import CTorrent

// MARK: - Lightweight Test Framework for CLT & CI

struct TestFailure: Error {
    let message: String
    let file: StaticString
    let line: UInt
}

final class TestRunner {
    struct TestRecord {
        let suite: String
        let name: String
        let duration: TimeInterval
        let failure: String?
    }

    static var passed = 0
    static var failed = 0
    static var failures: [String] = []
    static var records: [TestRecord] = []
    static var suiteOrder: [String] = []
    static var currentSuite = "Tests"

    static func beginSuite(_ name: String) {
        currentSuite = name
        if !suiteOrder.contains(name) {
            suiteOrder.append(name)
        }
    }

    static func run(_ name: String, _ testBlock: () throws -> Void, file: StaticString = #file, line: UInt = #line) {
        print("  • \(name)... ", terminator: "")
        fflush(stdout)
        let started = Date()
        let failureMessage: String?
        do {
            try testBlock()
            passed += 1
            failureMessage = nil
            print("\u{001B}[32m✓ PASS\u{001B}[0m")
        } catch let failure as TestFailure {
            failed += 1
            let detail = "    [\(name)] \(failure.message) (\(failure.file):\(failure.line))"
            failures.append(detail)
            failureMessage = "\(failure.message) (\(failure.file):\(failure.line))"
            print("\u{001B}[31m✗ FAIL\u{001B}[0m")
            print("\u{001B}[31m\(detail)\u{001B}[0m")
        } catch {
            failed += 1
            let detail = "    [\(name)] Unexpected error: \(error) (\(file):\(line))"
            failures.append(detail)
            failureMessage = "Unexpected error: \(error) (\(file):\(line))"
            print("\u{001B}[31m✗ ERROR\u{001B}[0m")
            print("\u{001B}[31m\(detail)\u{001B}[0m")
        }

        records.append(TestRecord(
            suite: currentSuite,
            name: name,
            duration: Date().timeIntervalSince(started),
            failure: failureMessage
        ))
    }

    static func writeJUnit(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        func escape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }

        func timeString(_ value: TimeInterval) -> String {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        let totalTime = records.reduce(0) { $0 + $1.duration }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<testsuites tests=\"\(records.count)\" failures=\"\(failed)\" time=\""
        xml += timeString(totalTime) + "\">\n"

        for suite in suiteOrder {
            let suiteRecords = records.filter { $0.suite == suite }
            guard !suiteRecords.isEmpty else { continue }
            let suiteTime = suiteRecords.reduce(0) { $0 + $1.duration }
            let suiteFailures = suiteRecords.compactMap(\.failure).count
            xml += "  <testsuite name=\"\(escape(suite))\" tests=\"\(suiteRecords.count)\" "
            xml += "failures=\"\(suiteFailures)\" time=\"\(timeString(suiteTime))\">\n"
            for record in suiteRecords {
                xml += "    <testcase classname=\"\(escape(suite))\" name=\"\(escape(record.name))\" "
                xml += "time=\"\(timeString(record.duration))\">"
                if let failure = record.failure {
                    xml += "<failure message=\"\(escape(failure))\">\(escape(failure))</failure>"
                }
                xml += "</testcase>\n"
            }
            xml += "  </testsuite>\n"
        }

        xml += "</testsuites>\n"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
        if a != b {
            throw TestFailure(
                message: "Expected '\(b)', got '\(a)'" + (message.isEmpty ? "" : " (\(message))"),
                file: file,
                line: line
            )
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String = "Expected true, got false", file: StaticString = #file, line: UInt = #line) throws {
        if !condition {
            throw TestFailure(message: message, file: file, line: line)
        }
    }

    static func assertFalse(_ condition: Bool, _ message: String = "Expected false, got true", file: StaticString = #file, line: UInt = #line) throws {
        if condition {
            throw TestFailure(message: message, file: file, line: line)
        }
    }

    static func assertNotNil<T>(_ value: T?, _ message: String = "Expected non-nil value", file: StaticString = #file, line: UInt = #line) throws {
        if value == nil {
            throw TestFailure(message: message, file: file, line: line)
        }
    }

    static func assertNil<T>(_ value: T?, _ message: String = "Expected nil value", file: StaticString = #file, line: UInt = #line) throws {
        if value != nil {
            throw TestFailure(message: message, file: file, line: line)
        }
    }
}

// MARK: - Test Helpers

extension Torrent {
    static func test(
        id: String,
        name: String,
        state: String = "downloading",
        stateCode: Int = 3,
        progress: Double = 0.0,
        size: Int64 = 1024,
        downloaded: Int64 = 0,
        uploaded: Int64 = 0,
        downloadRate: Int64 = 0,
        uploadRate: Int64 = 0,
        peers: Int = 0,
        seeds: Int = 0,
        eta: Int64 = 0,
        finished: Bool = false,
        seeding: Bool = false,
        paused: Bool = false,
        sequential: Bool = false,
        hasMetadata: Bool = true,
        savePath: String = "/tmp",
        files: Int = 1,
        ratio: Double = 0.0,
        added: Int64 = 0,
        error: String = ""
    ) -> Torrent {
        Torrent(
            id: id,
            name: name,
            state: state,
            stateCode: stateCode,
            progress: progress,
            size: size,
            downloaded: downloaded,
            uploaded: uploaded,
            downloadRate: downloadRate,
            uploadRate: uploadRate,
            peers: peers,
            seeds: seeds,
            eta: eta,
            finished: finished,
            seeding: seeding,
            paused: paused,
            sequential: sequential,
            hasMetadata: hasMetadata,
            savePath: savePath,
            files: files,
            ratio: ratio,
            added: added,
            error: error
        )
    }
}
