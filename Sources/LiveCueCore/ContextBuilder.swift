import Foundation

public enum ContextBuilder {
    public static let maximumCharacters = 80_000

    public static func makeRequest(session: Session, partial: String?, instruction: String?) -> AssistRequest {
        let finalized = session.segments.filter(\.isFinal)
        let memoryIndex = session.memory.throughSegmentId.flatMap { marker in finalized.firstIndex { $0.id == marker } }
        let newStart = memoryIndex.map { min($0 + 1, finalized.count) } ?? 0
        let overlapStart = max(0, newStart - 2)
        let transcript = finalized[overlapStart...].map(\.text).joined(separator: "\n")
        return AssistRequest(
            sessionId: session.id,
            instruction: instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            memory: session.memory,
            transcript: String(transcript.suffix(maximumCharacters)),
            partialTranscript: partial?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

public enum WordErrorRate {
    public static func calculate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let actual = words(hypothesis)
        guard !expected.isEmpty else { return actual.isEmpty ? 0 : 1 }
        var previous = Array(0...actual.count)
        for (i, expectedWord) in expected.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: actual.count)
            for (j, actualWord) in actual.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (expectedWord == actualWord ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[actual.count]) / Double(expected.count)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

