import Foundation

public struct AssistantConfiguration: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String
    public init(model: String = "gpt-5.6-sol", reasoningEffort: String = "low") {
        self.model = model; self.reasoningEffort = reasoningEffort
    }
}

public struct AssistantModelOption: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var reasoningEfforts: [String]
    public init(id: String, name: String, reasoningEfforts: [String]) {
        self.id = id; self.name = name; self.reasoningEfforts = reasoningEfforts
    }
}

public struct RelayExecution: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String
    public var codexMs: Double
    public var relayTotalMs: Double
    public var requestReadMs: Double
    public var relayOverheadMs: Double
    public init(model: String, reasoningEffort: String, codexMs: Double, relayTotalMs: Double, requestReadMs: Double, relayOverheadMs: Double) {
        self.model = model; self.reasoningEffort = reasoningEffort; self.codexMs = codexMs
        self.relayTotalMs = relayTotalMs; self.requestReadMs = requestReadMs; self.relayOverheadMs = relayOverheadMs
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
