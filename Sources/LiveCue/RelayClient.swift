import Foundation
import LiveCueCore

enum RelayError: LocalizedError {
    case notPaired, invalidEndpoint, server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .notPaired: "Pair this iPhone with the Windows relay first."
        case .invalidEndpoint: "The relay address is invalid."
        case .server(let message): message
        case .invalidResponse: "The relay returned an unreadable response."
        }
    }
}

actor RelayClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func health(endpoint: String, token: String?) async throws -> Bool {
        let _: HealthResponse = try await request(path: "/v1/health", method: "GET", endpoint: endpoint, token: token, body: Optional<String>.none)
        return true
    }

    func verify(endpoint: String, token: String) async throws {
        let _: HealthResponse = try await request(path: "/v1/pair/verify", method: "POST", endpoint: endpoint, token: token, body: ["device": "LiveCue iPhone"])
    }

    func assist(_ body: AssistRequest, endpoint: String, token: String) async throws -> AssistResponse {
        try await request(path: "/v1/assist", method: "POST", endpoint: endpoint, token: token, body: body)
    }

    func summarize(session: Session, endpoint: String, token: String) async throws -> SummaryResponse {
        struct SummaryBody: Codable { var sessionId: UUID; var transcript: String; var memory: SessionMemory }
        let body = SummaryBody(sessionId: session.id, transcript: session.segments.map(\.text).joined(separator: "\n"), memory: session.memory)
        return try await request(path: "/v1/session-summary", method: "POST", endpoint: endpoint, token: token, body: body)
    }

    private func request<Input: Encodable, Output: Decodable>(path: String, method: String, endpoint: String, token: String?, body: Input?) async throws -> Output {
        guard let base = URL(string: endpoint), let url = URL(string: path, relativeTo: base) else { throw RelayError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 65
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder.liveCue.encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder.liveCue.decode(ErrorEnvelope.self, from: data).error) ?? "Relay error (\(http.statusCode))."
            throw RelayError.server(message)
        }
        guard let decoded = try? JSONDecoder.liveCue.decode(Output.self, from: data) else { throw RelayError.invalidResponse }
        return decoded
    }
}

private struct HealthResponse: Codable { var ok: Bool }
private struct ErrorEnvelope: Codable { var error: String }

