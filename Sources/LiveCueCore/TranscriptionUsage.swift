import Foundation

/// A pricing snapshot, not an invoice. Meta's published rate on 2026-09-28 is
/// $0.18/hour, rounded down to whole processed seconds per provider stream.
public struct TranscriptionUsage: Codable, Equatable, Sendable {
    public var provider: String
    public var hourlyRateUSD: Double
    public var pricingDate: String
    public private(set) var streams: [SpeechStreamUsage] = []

    public init(provider: String = "meta") {
        self.provider = provider
        hourlyRateUSD = provider == "meta" ? 0.18 : 0
        pricingDate = "2026-09-28"
    }

    public mutating func begin(_ id: UUID) {
        guard !streams.contains(where: { $0.id == id }) else { return }
        streams.append(SpeechStreamUsage(id: id))
    }
    public mutating func update(_ id: UUID, sentMs: Double? = nil, processedMs: Double? = nil, hasTranscript: Bool = false) {
        guard let index = streams.firstIndex(where: { $0.id == id }), streams[index].state == .streaming else { return }
        if let sentMs, sentMs.isFinite, sentMs >= 0 { streams[index].sentMs = max(streams[index].sentMs, sentMs) }
        if let processedMs, processedMs.isFinite, processedMs >= 0 {
            streams[index].processedMs = max(streams[index].processedMs ?? 0, processedMs)
        }
        streams[index].hasTranscript = streams[index].hasTranscript || hasTranscript
    }
    public mutating func finish(_ id: UUID, completed: Bool) {
        guard let index = streams.firstIndex(where: { $0.id == id }), streams[index].state == .streaming else { return }
        streams[index].state = completed ? .completed : .interrupted
    }
    public var estimatedSeconds: Double { streams.reduce(0) { $0 + $1.estimatedSeconds } }
    public var estimatedUSD: Double { estimatedSeconds * hourlyRateUSD / 3600 }
    public var reportedSeconds: Double { streams.reduce(0) { $0 + floor(($1.processedMs ?? 0) / 1000) } }
    public var incomplete: Bool { streams.contains { $0.state == .interrupted || ($0.state == .completed && $0.processedMs == nil) } }
    public var formattedCost: String { String(format: "$%.5f", estimatedUSD) }
}

public struct SpeechStreamUsage: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case streaming, completed, interrupted }
    public let id: UUID
    public var sentMs: Double = 0
    public var processedMs: Double?
    public var hasTranscript = false
    public var state: State = .streaming
    public var estimatedSeconds: Double {
        // Before finalization, sent audio provides a per-second estimate even
        // between progress events. Reconcile to provider progress after closing.
        if state == .streaming { return floor(max(sentMs, processedMs ?? 0) / 1000) }
        // Failed requests that produce no transcript are not billed by Meta.
        if state == .interrupted && !hasTranscript { return 0 }
        return floor((processedMs ?? sentMs) / 1000)
    }
}
