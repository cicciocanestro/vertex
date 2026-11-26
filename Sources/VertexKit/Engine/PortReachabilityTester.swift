import Combine
import Darwin
import Foundation

@MainActor
final class PortReachabilityTester: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case open(openNodes: Int, totalNodes: Int)
        case closed(totalNodes: Int)
        case failed(String)
    }

    typealias Loader = @MainActor (URLRequest) async throws -> (Data, URLResponse)

    @Published private(set) var state: State = .idle
    @Published private(set) var publicIP: String?

    private static let maxResponseBytes = 65_536
    private static let ephemeralSession = URLSession(configuration: .ephemeral)
    private static let userAgent: String = {
        let version = AppInfo.version
        return "Vertex/\(version == "—" ? "1.0" : version)"
    }()

    private let load: Loader
    private let pollInterval: UInt64
    private var task: Task<Void, Never>?

    init(
        load: @escaping Loader = { try await PortReachabilityTester.ephemeralSession.data(for: $0) },
        pollInterval: UInt64 = 1_500_000_000
    ) {
        self.load = load
        self.pollInterval = pollInterval
    }

    func start(port: Int) {
        task?.cancel()
        publicIP = nil
        guard (1...65535).contains(port) else {
            state = .failed(L("Porta non valida"))
            return
        }
        guard !Preferences.userDefaults.bool(forKey: PrefKey.proxyEnabled) else {
            state = .failed(L("Test non disponibile con proxy SOCKS5 attivo"))
            return
        }
        state = .running

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(port: port)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func reset() {
        task?.cancel()
        task = nil
        publicIP = nil
        state = .idle
    }

    private func run(port: Int) async {
        do {
            let ip = try await fetchPublicIP()
            guard !Task.isCancelled else { return }
            publicIP = ip

            let check = try await startExternalCheck(ip: ip, port: port)
            guard !Task.isCancelled else { return }
            let expectedNodes = Set(check.nodes.keys)
            guard !expectedNodes.isEmpty else {
                throw TestError(L("Il servizio di test non ha restituito nodi."))
            }

            var lastOpen = 0
            var lastCompleted = 0
            var stablePolls = 0

            for _ in 0..<15 {
                do {
                    try await Task.sleep(nanoseconds: pollInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let result = try await fetchCheckResult(requestID: check.requestID)
                guard !Task.isCancelled else { return }
                var completed = 0
                var open = 0

                for node in expectedNodes {
                    guard let entries = result[node] as? [[String: Any]], !entries.isEmpty else {
                        continue
                    }
                    completed += 1
                    if entries.contains(where: { ($0["time"] as? NSNumber) != nil }) {
                        open += 1
                    }
                }

                if completed == expectedNodes.count {
                    state =
                        open > 0
                        ? .open(openNodes: open, totalNodes: completed)
                        : .closed(totalNodes: completed)
                    return
                }

                // A node may never answer (check-host drops it). Once at least
                // one result has arrived and the set stops changing for two
                // polls, report the partial outcome instead of waiting for all
                // 15 polls: the UI answers in seconds, not in half a minute.
                if completed > 0, completed == lastCompleted, open == lastOpen {
                    stablePolls += 1
                    if stablePolls >= 2 {
                        state =
                            open > 0
                            ? .open(openNodes: open, totalNodes: completed)
                            : .closed(totalNodes: completed)
                        return
                    }
                } else {
                    stablePolls = 0
                }

                lastOpen = open
                lastCompleted = completed
            }

            if lastCompleted > 0 {
                state =
                    lastOpen > 0
                    ? .open(openNodes: lastOpen, totalNodes: lastCompleted)
                    : .closed(totalNodes: lastCompleted)
            } else {
                state = .failed(L("Il servizio di test non ha risposto in tempo."))
            }
        } catch {
            if Task.isCancelled { return }
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchPublicIP() async throws -> String {
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            throw TestError(L("Indirizzo del servizio IP pubblico non valido."))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request)
        try validate(response, data: data)

        struct IPResponse: Decodable {
            let ip: String
        }

        let decoded = try JSONDecoder().decode(IPResponse.self, from: data)
        let candidate = decoded.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLiteralIPAddress(candidate) else {
            throw TestError(L("IP pubblico non disponibile."))
        }
        return candidate
    }

    private func startExternalCheck(ip: String, port: Int) async throws -> ExternalCheck {
        let hostEndpoint = ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)"
        var components = URLComponents(string: "https://check-host.net/check-tcp")
        components?.queryItems = [
            URLQueryItem(name: "host", value: hostEndpoint),
            URLQueryItem(name: "max_nodes", value: "3"),
        ]
        guard let url = components?.url else {
            throw TestError(L("Impossibile preparare il test esterno."))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request)
        try validate(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["ok"] as? Int) == 1,
            let requestID = root["request_id"] as? String,
            let nodes = root["nodes"] as? [String: Any]
        else {
            throw TestError(L("Il servizio di test ha restituito una risposta non valida."))
        }

        return ExternalCheck(requestID: requestID, nodes: nodes)
    }

    static func checkResultURL(for requestID: String) throws -> URL {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        guard !requestID.isEmpty,
            let encoded = requestID.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "https://check-host.net/check-result/\(encoded)")
        else {
            throw TestError(L("Risposta del test non valida."))
        }
        return url
    }

    private func fetchCheckResult(requestID: String) async throws -> [String: Any] {
        let url = try Self.checkResultURL(for: requestID)

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request)
        try validate(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError(L("Risposta del test non valida."))
        }
        return root
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw TestError(L("Il servizio di test non è raggiungibile."))
        }
        guard data.count <= Self.maxResponseBytes else {
            throw TestError(L("Il servizio di test ha restituito una risposta non valida."))
        }
    }

    nonisolated static func isLiteralIPAddress(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var v4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            return true
        }
        var v6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1
    }

    private struct ExternalCheck {
        let requestID: String
        let nodes: [String: Any]
    }

    private struct TestError: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }
}
