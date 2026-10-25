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
    static var passed = 0
    static var failed = 0
    static var failures: [String] = []

    static func run(_ name: String, _ testBlock: () throws -> Void, file: StaticString = #file, line: UInt = #line) {
        print("  • \(name)... ", terminator: "")
        fflush(stdout)
        do {
            try testBlock()
            passed += 1
            print("\u{001B}[32m✓ PASS\u{001B}[0m")
        } catch let failure as TestFailure {
            failed += 1
            print("\u{001B}[31m✗ FAIL\u{001B}[0m")
            let detail = "    [\(name)] \(failure.message) (\(failure.file):\(failure.line))"
            failures.append(detail)
            print("\u{001B}[31m\(detail)\u{001B}[0m")
        } catch {
            failed += 1
            print("\u{001B}[31m✗ ERROR\u{001B}[0m")
            let detail = "    [\(name)] Unexpected error: \(error) (\(file):\(line))"
            failures.append(detail)
            print("\u{001B}[31m\(detail)\u{001B}[0m")
        }
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
