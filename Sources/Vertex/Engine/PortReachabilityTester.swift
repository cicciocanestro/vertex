import Combine
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

    @Published private(set) var state: State = .idle
    @Published private(set) var publicIP: String?

    private var task: Task<Void, Never>?

    func start(port: Int) {
        task?.cancel()
        publicIP = nil
        state = .running

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(port: port)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
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
            let expectedNodes = Set(check.nodes.keys)
            guard !expectedNodes.isEmpty else {
                throw TestError("Il servizio di test non ha restituito nodi.")
            }

            var lastOpen = 0
            var lastCompleted = 0

            for _ in 0..<15 {
                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let result = try await fetchCheckResult(requestID: check.requestID)
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

                lastOpen = open
                lastCompleted = completed

                if completed == expectedNodes.count {
                    state = open > 0
                        ? .open(openNodes: open, totalNodes: completed)
                        : .closed(totalNodes: completed)
                    return
                }
            }

            if lastCompleted > 0 {
                state = lastOpen > 0
                    ? .open(openNodes: lastOpen, totalNodes: lastCompleted)
                    : .closed(totalNodes: lastCompleted)
            } else {
                state = .failed("Il servizio di test non ha risposto in tempo.")
            }
        } catch {
            if Task.isCancelled { return }
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchPublicIP() async throws -> String {
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            throw TestError("Indirizzo del servizio IP pubblico non valido.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Vertex/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        struct IPResponse: Decodable {
            let ip: String
        }

        let decoded = try JSONDecoder().decode(IPResponse.self, from: data)
        guard !decoded.ip.isEmpty else {
            throw TestError("IP pubblico non disponibile.")
        }
        return decoded.ip
    }

    private func startExternalCheck(ip: String, port: Int) async throws -> ExternalCheck {
        var components = URLComponents(string: "https://check-host.net/check-tcp")
        components?.queryItems = [
            URLQueryItem(name: "host", value: "\(ip):\(port)"),
            URLQueryItem(name: "max_nodes", value: "3")
        ]
        guard let url = components?.url else {
            throw TestError("Impossibile preparare il test esterno.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Vertex/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["ok"] as? Int) == 1,
              let requestID = root["request_id"] as? String,
              let nodes = root["nodes"] as? [String: Any] else {
            throw TestError("Il servizio di test ha restituito una risposta non valida.")
        }

        return ExternalCheck(requestID: requestID, nodes: nodes)
    }

    private func fetchCheckResult(requestID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://check-host.net/check-result/\(requestID)") else {
            throw TestError("Risposta del test non valida.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Vertex/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError("Risposta del test non valida.")
        }
        return root
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TestError("Il servizio di test non è raggiungibile.")
        }
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
