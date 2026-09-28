import Foundation

/// Cumulative partials replace each other. Completed turns can arrive out of order.
public struct CloudTranscript {
    private var active: Int?
    private var partials: [Int: String] = [:]
    private var starts: [Int: Double] = [:]
    private var completed: Set<Int> = []
    public init() {}
    public var partialText: String { partials.keys.sorted().compactMap { partials[$0] }.joined(separator: " ") }
    public mutating func apply(type: String, turn: Int?, text: String?, processedMs: Double) -> TranscriptSegment? {
        if type == "speechStart", let turn {
            active = turn; starts[turn] = processedMs / 1000
        } else if type == "transcript", let active, !completed.contains(active) {
            partials[active] = text ?? ""
        } else if type == "speechComplete", let turn, !completed.contains(turn) {
            completed.insert(turn); partials.removeValue(forKey: turn)
            let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return .init(text: value, startSeconds: starts[turn] ?? 0, endSeconds: processedMs / 1000) }
        }
        return nil
    }
}
