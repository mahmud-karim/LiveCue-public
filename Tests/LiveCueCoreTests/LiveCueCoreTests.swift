import XCTest
@testable import LiveCueCore

final class LiveCueCoreTests: XCTestCase {
    func testLegacyAnswersDecodeWithoutTiming() throws {
        let turn = AssistantTurn(detectedQuestion: "Q", answer: "A", details: "")
        let data = try JSONEncoder().encode(turn)
        XCTAssertNil(try JSONDecoder().decode(AssistantTurn.self, from: data).performance)
    }
    func testPerformanceRoundTripAndTransportEstimate() throws {
        let selection = AssistantConfiguration(model: "gpt-5.6-luna", reasoningEffort: "low")
        let execution = RelayExecution(model: selection.model, reasoningEffort: "low", codexMs: 500, relayTotalMs: 520, requestReadMs: 2, relayOverheadMs: 20)
        let metrics = AssistPerformance(configuration: selection, speechModel: "voz", reusedText: false, transcriptionMs: 100, contextMs: 1, roundTripMs: 550, totalMs: 651, lastLiveChunkMs: nil, transcriptCharacters: 20, execution: execution)
        XCTAssertEqual(metrics.transportEstimateMs, 30)
        let turn = AssistantTurn(detectedQuestion: "Q", answer: "A", details: "", performance: metrics)
        XCTAssertEqual(try JSONDecoder().decode(AssistantTurn.self, from: JSONEncoder().encode(turn)), turn)
    }
    func testPairingQRValidation() throws {
        let valid = "{\"endpoint\":\"https://pc.example.test/\",\"token\":\"fixture-token-1234567890\"}"
        XCTAssertEqual(try PairingPayload.parse(valid).endpoint, "https://pc.example.test/")
        XCTAssertThrowsError(try PairingPayload.parse(valid.replacingOccurrences(of: "https://", with: "http://")))
        XCTAssertThrowsError(try PairingPayload.parse(valid.replacingOccurrences(of: "pc.example.test/", with: "user:pass@pc.example.test/")))
        XCTAssertThrowsError(try PairingPayload.parse("not a pairing QR"))
        XCTAssertThrowsError(try PairingPayload.parse(valid.replacingOccurrences(of: "fixture-token-1234567890", with: "short")))
    }
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
