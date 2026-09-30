import Foundation

public enum AssistantProvider: String, Codable, CaseIterable, Sendable {
    case codex, openrouter
    public var name: String { self == .codex ? "PC · Codex" : "OpenRouter · direct" }
}

public struct AssistantConfiguration: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String
    public var provider: AssistantProvider
    public init(model: String = "gpt-5.6-sol", reasoningEffort: String = "low", provider: AssistantProvider = .codex) {
        self.model = model; self.reasoningEffort = reasoningEffort; self.provider = provider
    }
    private enum CodingKeys: String, CodingKey { case model, reasoningEffort, provider }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(String.self, forKey: .model)
        reasoningEffort = try c.decode(String.self, forKey: .reasoningEffort)
        provider = try c.decodeIfPresent(AssistantProvider.self, forKey: .provider) ?? .codex
    }
}

public struct AssistantModelOption: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var reasoningEfforts: [String]
    public var structuredOutputs: Bool?
    public var promptPrice: String?
    public var completionPrice: String?
    public init(id: String, name: String, reasoningEfforts: [String], structuredOutputs: Bool? = nil, promptPrice: String? = nil, completionPrice: String? = nil) {
        self.id = id; self.name = name; self.reasoningEfforts = reasoningEfforts
        self.structuredOutputs = structuredOutputs; self.promptPrice = promptPrice; self.completionPrice = completionPrice
    }
}

public struct RelayExecution: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String
    public var codexMs: Double
    public var relayTotalMs: Double
    public var requestReadMs: Double
    public var relayOverheadMs: Double
    public var usage: AssistantUsage?
    public init(model: String, reasoningEffort: String, codexMs: Double, relayTotalMs: Double, requestReadMs: Double, relayOverheadMs: Double) {
        self.model = model; self.reasoningEffort = reasoningEffort; self.codexMs = codexMs
        self.relayTotalMs = relayTotalMs; self.requestReadMs = requestReadMs; self.relayOverheadMs = relayOverheadMs
    }
}

public struct AssistantUsage: Codable, Equatable, Sendable {
    public var generationId: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var costCredits: Double?
    public init(generationId: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil, costCredits: Double? = nil) {
        self.generationId = generationId; self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.costCredits = costCredits
    }
}

public struct AssistPerformance: Codable, Equatable, Sendable {
    public var configuration: AssistantConfiguration
    public var speechModel: String
    public var reusedText: Bool
    public var transcriptionMs: Double
    public var contextMs: Double
    public var roundTripMs: Double
    public var totalMs: Double
    public var lastLiveChunkMs: Double?
    public var transcriptCharacters: Int
    public var execution: RelayExecution?
    public var transportEstimateMs: Double? {
        execution.map { max(0, roundTripMs - $0.relayTotalMs) }
    }
    public init(configuration: AssistantConfiguration, speechModel: String, reusedText: Bool, transcriptionMs: Double, contextMs: Double, roundTripMs: Double, totalMs: Double, lastLiveChunkMs: Double?, transcriptCharacters: Int, execution: RelayExecution?) {
        self.configuration = configuration; self.speechModel = speechModel; self.reusedText = reusedText
        self.transcriptionMs = transcriptionMs; self.contextMs = contextMs; self.roundTripMs = roundTripMs
        self.totalMs = totalMs; self.lastLiveChunkMs = lastLiveChunkMs
        self.transcriptCharacters = transcriptCharacters; self.execution = execution
    }
}
