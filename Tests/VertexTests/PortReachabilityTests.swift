#if DEBUG
import Foundation
@testable import VertexKit

enum PortReachabilityTests {
    static func runAll() {
        print("\n\u{001B}[1m[Suite: PortReachabilityTests]\u{001B}[0m")

        TestRunner.run("PortReachability: porta aperta e IP pubblico") {
            try openPort()
        }
        TestRunner.run("PortReachability: porta chiusa") {
            try closedPort()
        }
        TestRunner.run("PortReachability: risposta del servizio non valida") {
            try invalidServiceResponse()
        }
        TestRunner.run("PortReachability: errore HTTP") {
            try httpError()
        }
        TestRunner.run("PortReachability: nessun nodo disponibile") {
            try noNodes()
        }
        TestRunner.run("PortReachability: timeout parziale con porta aperta") {
            try partialOpen()
        }
        TestRunner.run("PortReachability: timeout parziale con porta chiusa") {
            try partialClosed()
        }
        TestRunner.run("PortReachability: reset durante il test") {
            try resetWhileRunning()
        }
        TestRunner.run("PortReachability: IP pubblico vuoto") {
            try emptyPublicIP()
        }
        TestRunner.run("PortReachability: risposta non HTTP") {
            try nonHTTPResponse()
        }
        TestRunner.run("PortReachability: risultato malformato") {
            try malformedResult()
        }
    }

    // MARK: - Cases

    private static func openPort() throws {
        let (tester, stub) = onMain {
            makeTester(
                check: #"{"ok":1,"request_id":"req-1","nodes":{"node-1":{},"node-2":{}}}"#,
                result: #"{"node-1":[{"time":0.12}],"node-2":[{"time":0.34}]}"#
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        try TestRunner.assertEqual(onMain { tester.state }, .running)

        let state = try onMain { try waitForState(tester) }
        try TestRunner.assertEqual(
            state,
            .open(openNodes: 2, totalNodes: 2),
            "Entrambi i nodi devono risultare raggiungibili"
        )
        try TestRunner.assertEqual(onMain { tester.publicIP }, "203.0.113.5")

        let requests = onMain { stub.requests }
        try TestRunner.assertTrue(requests.count >= 3, "Il test deve contattare IP, check e risultato")
        let ipRequest = requests.first { $0.url?.host == "api.ipify.org" }
        try TestRunner.assertTrue(
            ipRequest?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Vertex/") == true,
            "Il servizio IP deve ricevere lo User-Agent di Vertex"
        )
        let checkRequest = requests.first { $0.url?.path == "/check-tcp" }
        try TestRunner.assertEqual(checkRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        try TestRunner.assertTrue(
            checkRequest?.url?.query?.contains("6881") == true,
            "La porta selezionata deve essere inviata al servizio"
        )
        try TestRunner.assertTrue(
            requests.contains { $0.url?.path == "/check-result/req-1" },
            "Il test deve interrogare il risultato della richiesta"
        )
    }

    private static func closedPort() throws {
        let (tester, _) = onMain {
            makeTester(
                check: #"{"ok":1,"request_id":"req-2","nodes":{"node-1":{},"node-2":{}}}"#,
                result: #"{"node-1":[{"error":"timeout"}],"node-2":[{"error":"refused"}]}"#
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        try TestRunner.assertEqual(
            state,
            .closed(totalNodes: 2),
            "Senza risposte valide la porta deve risultare chiusa"
        )
    }

    private static func invalidServiceResponse() throws {
        let (tester, _) = onMain {
            makeTester(check: #"{"ok":0}"#)
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "L'errore deve avere un messaggio")
    }

    private static func httpError() throws {
        let (tester, stub) = onMain {
            makeTester { _ in
                (500, Data())
            }
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "L'errore HTTP deve avere un messaggio")
        try TestRunner.assertFalse(
            onMain { stub.requests.contains { $0.url?.path == "/check-tcp" } },
            "Con IP non disponibile non deve partire il test TCP"
        )
    }

    private static func noNodes() throws {
        let (tester, _) = onMain {
            makeTester(check: #"{"ok":1,"request_id":"req-3","nodes":{}}"#)
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "L'assenza di nodi deve produrre un errore")
    }

    private static func partialOpen() throws {
        let (tester, _) = onMain {
            makeTester(
                check: #"{"ok":1,"request_id":"req-4","nodes":{"node-1":{},"node-2":{}}}"#,
                result: #"{"node-1":[{"time":0.1}]}"#
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        try TestRunner.assertEqual(
            state,
            .open(openNodes: 1, totalNodes: 1),
            "I nodi che hanno risposto prima del timeout devono essere conteggiati"
        )
    }

    private static func partialClosed() throws {
        let (tester, _) = onMain {
            makeTester(
                check: #"{"ok":1,"request_id":"req-5","nodes":{"node-1":{},"node-2":{}}}"#,
                result: #"{"node-1":[{"error":"timeout"}]}"#
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        try TestRunner.assertEqual(
            state,
            .closed(totalNodes: 1),
            "I nodi che hanno risposto senza successo devono risultare chiusi"
        )
    }

    private static func resetWhileRunning() throws {
        let tester = onMain {
            PortReachabilityTester(
                load: { _ in
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw CancellationError()
                },
                pollInterval: 1_000_000
            )
        }

        onMain { tester.start(port: 6881) }
        try TestRunner.assertEqual(onMain { tester.state }, .running)
        onMain { tester.reset() }
        try TestRunner.assertEqual(onMain { tester.state }, .idle)
        try TestRunner.assertNil(onMain { tester.publicIP })
    }

    private static func emptyPublicIP() throws {
        let (tester, _) = onMain {
            makeTester(ip: "", check: "")
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "Un IP vuoto deve produrre un errore")
    }

    private static func nonHTTPResponse() throws {
        let tester = onMain {
            PortReachabilityTester(
                load: { request in
                    let url = request.url ?? URL(string: "https://stub.invalid")!
                    return (
                        Data(),
                        URLResponse(
                            url: url,
                            mimeType: nil,
                            expectedContentLength: 0,
                            textEncodingName: nil
                        )
                    )
                },
                pollInterval: 1_000_000
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "Una risposta non HTTP deve produrre un errore")
    }

    private static func malformedResult() throws {
        let (tester, _) = onMain {
            makeTester(
                check: #"{"ok":1,"request_id":"req-6","nodes":{"node-1":{}}}"#,
                result: "not-json"
            )
        }
        defer { onMain { tester.reset() } }

        onMain { tester.start(port: 6881) }
        let state = try onMain { try waitForState(tester) }
        let message = try failureMessage(state)
        try TestRunner.assertFalse(message.isEmpty, "Un risultato malformato deve produrre un errore")
    }

    // MARK: - Helpers

    private static func failureMessage(
        _ state: PortReachabilityTester.State,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> String {
        guard case .failed(let message) = state else {
            throw TestFailure(
                message: "Atteso stato failed, ottenuto \(state)",
                file: file,
                line: line
            )
        }
        return message
    }

    @MainActor
    private static func makeTester(
        pollInterval: UInt64 = 1_000_000,
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> (tester: PortReachabilityTester, stub: HTTPStub) {
        let stub = HTTPStub(handler: handler)
        let tester = PortReachabilityTester(load: stub.load, pollInterval: pollInterval)
        return (tester, stub)
    }

    /// Builds the common IP → check-tcp → check-result flow. Tests that need a
    /// different transport (HTTP error, non-HTTP response, reset) keep their
    /// own loader.
    @MainActor
    private static func makeTester(
        ip: String = "203.0.113.5",
        check: String,
        result: String? = nil,
        pollInterval: UInt64 = 1_000_000
    ) -> (tester: PortReachabilityTester, stub: HTTPStub) {
        makeTester(pollInterval: pollInterval) { request in
            if request.url?.host == "api.ipify.org" {
                return (200, Data("{\"ip\":\"\(ip)\"}".utf8))
            }
            switch request.url?.path {
            case "/check-tcp":
                return (200, Data(check.utf8))
            case let path where path?.hasPrefix("/check-result/") == true:
                guard let result else { return (404, Data()) }
                return (200, Data(result.utf8))
            default:
                return (404, Data())
            }
        }
    }

    @MainActor
    private static func waitForState(
        _ tester: PortReachabilityTester,
        timeout: TimeInterval = 5
    ) throws -> PortReachabilityTester.State {
        var resolved: PortReachabilityTester.State?
        try TestsSupport.waitFor("stato del tester di raggiungibilità", timeout: timeout) {
            onMain {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                let state = tester.state
                guard state != .idle, state != .running else { return false }
                resolved = state
                return true
            }
        }
        return resolved ?? tester.state
    }
}

@MainActor
private final class HTTPStub {
    private(set) var requests: [URLRequest] = []
    private let handler: (URLRequest) throws -> (Int, Data)

    init(handler: @escaping (URLRequest) throws -> (Int, Data)) {
        self.handler = handler
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let (status, data) = try handler(request)
        let url = request.url ?? URL(string: "https://stub.invalid")!
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw StubError.invalidResponse
        }
        return (data, response)
    }
}

private enum StubError: Error {
    case invalidResponse
}
#endif
