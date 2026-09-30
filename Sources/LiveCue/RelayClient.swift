import Foundation
import LiveCueCore

enum RelayError: LocalizedError {
    case notPaired, invalidEndpoint, unauthorized, server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .notPaired: "Pair this iPhone with the Windows relay first."
        case .invalidEndpoint: "The relay address is invalid."
        case .unauthorized: "The PC no longer recognizes this pairing. Scan its pairing QR once to reconnect."
        case .server(let message): message
        case .invalidResponse: "The relay returned an unreadable response."
        }
    }
}

actor RelayClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func models(endpoint: String, token: String) async throws -> [AssistantModelOption] {
        struct Catalog: Decodable { var models: [AssistantModelOption] }
        let catalog: Catalog = try await request(path: "/v1/models", method: "GET", endpoint: endpoint, token: token, body: Optional<String>.none)
        return catalog.models
    }

    func health(endpoint: String, token: String?) async throws -> Bool {
        let _: HealthResponse = try await request(path: "/v1/health", method: "GET", endpoint: endpoint, token: token, body: Optional<String>.none, timeout: 8)
        return true
    }

    func verify(endpoint: String, token: String) async throws {
        let _: HealthResponse = try await request(path: "/v1/pair/verify", method: "POST", endpoint: endpoint, token: token, body: ["device": "LiveCue iPhone"])
    }

    func assist(_ body: AssistRequest, endpoint: String, token: String) async throws -> AssistResponse {
        try await request(path: "/v1/assist", method: "POST", endpoint: endpoint, token: token, body: body)
    }

    func summarize(session: Session, endpoint: String, token: String, assistant: AssistantConfiguration) async throws -> SummaryResponse {
        struct SummaryBody: Codable { var sessionId: UUID; var transcript: String; var memory: SessionMemory; var assistant: AssistantConfiguration }
        let body = SummaryBody(sessionId: session.id, transcript: session.segments.map(\.text).joined(separator: "\n"), memory: session.memory, assistant: assistant)
        return try await request(path: "/v1/session-summary", method: "POST", endpoint: endpoint, token: token, body: body)
    }

    private func request<Input: Encodable, Output: Decodable>(path: String, method: String, endpoint: String, token: String?, body: Input?, timeout: TimeInterval = 65) async throws -> Output {
        guard let base = URL(string: endpoint), let url = URL(string: path, relativeTo: base) else { throw RelayError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder.liveCue.encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw RelayError.unauthorized }
            let message = (try? JSONDecoder.liveCue.decode(ErrorEnvelope.self, from: data).error) ?? "Relay error (\(http.statusCode))."
            throw RelayError.server(message)
        }
        guard let decoded = try? JSONDecoder.liveCue.decode(Output.self, from: data) else { throw RelayError.invalidResponse }
        return decoded
    }
}

enum ConnectionMessage {
    static func describe(_ error: Error, saved: Bool) -> String {
        let prefix = saved ? "Your pairing is saved. " : ""
        if let error = error as? URLError {
            switch error.code {
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return prefix + "The secure connection to your PC failed. Check the PC tunnel and retry. Scanning the QR again will not repair this connection."
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return prefix + "Your PC is currently unreachable. Keep LiveCue Desktop running and check your internet connection. The app will reconnect automatically."
            default: break
            }
        }
        return prefix + error.localizedDescription
    }
}

private struct HealthResponse: Codable { var ok: Bool }
private struct ErrorEnvelope: Codable { var error: String }
