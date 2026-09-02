import XCTest
@testable import LiveCueCore

final class LiveCueCoreTests: XCTestCase {
    func testContextIncludesOverlapAndNewSegments() {
        let segments = (0..<6).map { TranscriptSegment(text: "segment \($0)", startSeconds: Double($0), endSeconds: Double($0 + 1)) }
        var session = Session(segments: segments)
        session.memory = SessionMemory(summary: "Earlier context", facts: [], openQuestions: [], throughSegmentId: segments[3].id)
        let request = ContextBuilder.makeRequest(session: session, partial: "latest words", instruction: "Answer briefly")
        XCTAssertTrue(request.transcript.contains("segment 2"))
        XCTAssertTrue(request.transcript.contains("segment 5"))
        XCTAssertEqual(request.instruction, "Answer briefly")
    }

    func testContextIsCapped() {
        let session = Session(segments: [TranscriptSegment(text: String(repeating: "x", count: 100_000), startSeconds: 0, endSeconds: 1)])
        XCTAssertEqual(ContextBuilder.makeRequest(session: session, partial: nil, instruction: nil).transcript.count, 80_000)
    }

    func testWordErrorRate() {
        XCTAssertEqual(WordErrorRate.calculate(reference: "one two three", hypothesis: "one too three"), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(WordErrorRate.calculate(reference: "same words", hypothesis: "same words"), 0)
    }
}
