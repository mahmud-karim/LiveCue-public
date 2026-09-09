import Foundation

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var isFinal: Bool

    public init(id: UUID = UUID(), text: String, startSeconds: Double, endSeconds: Double, isFinal: Bool = true) {
        self.id = id
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.isFinal = isFinal
    }
}

public struct SessionMemory: Codable, Equatable, Sendable {
    public var summary: String
    public var facts: [String]
    public var openQuestions: [String]
    public var throughSegmentId: UUID?

    public init(summary: String = "", facts: [String] = [], openQuestions: [String] = [], throughSegmentId: UUID? = nil) {
        self.summary = summary
        self.facts = facts
        self.openQuestions = openQuestions
        self.throughSegmentId = throughSegmentId
    }
}

public struct AssistantTurn: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var request: String?
    public var detectedQuestion: String
    public var answer: String
    public var details: String
    public var performance: AssistPerformance?

    public init(id: UUID = UUID(), createdAt: Date = .now, request: String? = nil, detectedQuestion: String, answer: String, details: String, performance: AssistPerformance? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.request = request
        self.detectedQuestion = detectedQuestion
        self.answer = answer
        self.details = details
        self.performance = performance
    }
}

public struct SessionNotes: Codable, Equatable, Sendable {
    public var summary: String
    public var keyPoints: [String]
    public var actionItems: [String]
    public init(summary: String = "", keyPoints: [String] = [], actionItems: [String] = []) {
        self.summary = summary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
    }
}

public struct Session: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var segments: [TranscriptSegment]
    public var assistantTurns: [AssistantTurn]
    public var memory: SessionMemory
    public var notes: SessionNotes

    public init(id: UUID = UUID(), title: String = "New conversation", startedAt: Date = .now, endedAt: Date? = nil, segments: [TranscriptSegment] = [], assistantTurns: [AssistantTurn] = [], memory: SessionMemory = .init(), notes: SessionNotes = .init()) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.segments = segments
        self.assistantTurns = assistantTurns
        self.memory = memory
        self.notes = notes
    }
}

public struct AssistRequest: Codable, Equatable, Sendable {
    public var assistant: AssistantConfiguration?
    public var requestId: UUID
    public var sessionId: UUID
    public var instruction: String?
    public var memory: SessionMemory
    public var transcript: String
    public var partialTranscript: String?

    public init(requestId: UUID = UUID(), sessionId: UUID, instruction: String?, memory: SessionMemory, transcript: String, partialTranscript: String?) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.instruction = instruction
        self.memory = memory
        self.transcript = transcript
        self.partialTranscript = partialTranscript
    }
}

public struct AssistResponse: Codable, Equatable, Sendable {
    public var execution: RelayExecution?
    public var detectedQuestion: String
    public var answer: String
    public var details: String
    public var memory: SessionMemory

    public init(detectedQuestion: String, answer: String, details: String, memory: SessionMemory) {
        self.detectedQuestion = detectedQuestion
        self.answer = answer
        self.details = details
        self.memory = memory
    }
}

public struct SummaryResponse: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var keyPoints: [String]
    public var actionItems: [String]

    public init(title: String, summary: String, keyPoints: [String], actionItems: [String]) {
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
    }
}

public struct TranscriptionModel: Codable, Identifiable, Equatable, Sendable {
    public var id: String { variant }
    public var variant: String
    public var displayName: String
    public var approximateMegabytes: Int
    public var quality: String
    public var recommended: Bool

    public init(variant: String, displayName: String, approximateMegabytes: Int, quality: String, recommended: Bool) {
        self.variant = variant
        self.displayName = displayName
        self.approximateMegabytes = approximateMegabytes
        self.quality = quality
        self.recommended = recommended
    }
}

public struct BenchmarkResult: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var modelVariant: String
    public var createdAt: Date
    public var audioSeconds: Double
    public var processingSeconds: Double
    public var wordErrorRate: Double?
    public var transcript: String
    public init(id: UUID = UUID(), modelVariant: String, createdAt: Date = .now, audioSeconds: Double, processingSeconds: Double, wordErrorRate: Double?, transcript: String) {
        self.id = id; self.modelVariant = modelVariant; self.createdAt = createdAt; self.audioSeconds = audioSeconds; self.processingSeconds = processingSeconds; self.wordErrorRate = wordErrorRate; self.transcript = transcript
    }
}
