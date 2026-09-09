import Foundation

public struct PairingPayload: Codable, Equatable {
    public let endpoint: String
    public let token: String

    public static func parse(_ text: String) throws -> PairingPayload {
        guard text.utf8.count <= 8192, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              let url = URLComponents(string: value.endpoint), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              (16...512).contains(value.token.count), !value.token.contains(where: { $0.isWhitespace })
        else { throw NSError(domain: "LiveCue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Use the pairing QR from LiveCue Desktop. It must contain an HTTPS PC address and a valid pairing token."]) }
        return value
    }
}
