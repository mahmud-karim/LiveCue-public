import Foundation

public enum SpeechProvider: String, CaseIterable {
    case meta, nemotron, qwen3, voz, parakeet
    public var usesPC: Bool { isPCLocal }
    public var isCloud: Bool { self == .meta }
    public var streamsAudio: Bool { isCloud || isPCLocal }
    public var isPCLocal: Bool { self == .nemotron || self == .qwen3 }
    public var sampleRate: Int { self == .meta ? 24000 : 16000 }
    public var name: String {
        switch self {
        case .meta: return "Meta Muse · cloud"
        case .nemotron: return "Nemotron 3.5 · PC"
        case .qwen3: return "Qwen3 1.7B · PC"
        case .voz: return "Voz · iPhone"
        case .parakeet: return "Parakeet · iPhone"
        }
    }
}
