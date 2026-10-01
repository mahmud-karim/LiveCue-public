import Foundation

/// Provider credentials are used only at this fixed TLS destination, never in a URL.
public enum MetaRealtimeAPI {
    public static let endpoint = URL(string: "wss://api.meta.ai/v1/asr/realtime")!
    public static func handshake(key: String) throws -> String {
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw MetaSpeechError.missingKey }
        let value: [String: Any] = [
            "authorization": ["accessToken": "Bearer " + key],
            "model": "muse-voice-transcribe-1.0", "audioEncoding": "PCM_24KHZ",
            "mode": "ENDPOINTING", "partialMode": "CUMULATIVE", "emitAudioProgress": true
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    public static func acknowledge(_ value: [String: Any]) throws {
        guard value["type"] == nil, let id = value["sessionId"] as? String, !id.isEmpty else { throw MetaSpeechError.authentication }
    }
    /// Never surface raw provider errors/metadata: they could contain credentials.
    public static func event(_ value: [String: Any], key: String) throws -> [String: Any] {
        if value["type"] as? String == "error" { throw MetaSpeechError.provider }
        guard let type = value["type"] as? String,
              ["speechStart", "speechEnd", "speechComplete", "transcript", "audioProgress"].contains(type) else { return [:] }
        var clean: [String: Any] = ["type": type]
        for field in ["turnId", "audioProcessedMs"] { if let number = value[field] as? NSNumber { clean[field] = number } }
        if let final = value["final"] as? Bool { clean["final"] = final }
        if let text = value["transcript"] as? String { clean["transcript"] = String(text.replacingOccurrences(of: key, with: "[redacted]").prefix(32000)) }
        return clean
    }
}

public enum MetaSpeechError: LocalizedError {
    case missingKey, authentication, provider, connection
    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Meta API key in Transcription settings. It stays in this iPhone's Keychain."
        case .authentication: return "Meta did not accept the connection. Check the API key, account access, and billing in Transcription settings."
        case .provider: return "Meta transcription stopped. Check API access, billing, or rate limits before retrying."
        case .connection: return "Could not connect directly to Meta. Check this iPhone's internet connection and retry. No PC is required for Meta transcription."
        }
    }
}
