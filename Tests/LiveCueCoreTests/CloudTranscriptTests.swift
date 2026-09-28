import XCTest
@testable import LiveCueCore

final class CloudTranscriptTests: XCTestCase {
    func testCumulativePartialsAndOverlappingTurns() {
        var state = CloudTranscript()
        XCTAssertNil(state.apply(type: "speechStart", turn: 1, text: nil, processedMs: 200))
        _ = state.apply(type: "transcript", turn: nil, text: "First", processedMs: 500)
        _ = state.apply(type: "transcript", turn: nil, text: "First sentence", processedMs: 900)
        XCTAssertEqual(state.partialText, "First sentence")
        _ = state.apply(type: "speechEnd", turn: 1, text: nil, processedMs: 1000)
        XCTAssertEqual(state.partialText, "First sentence")
        _ = state.apply(type: "speechStart", turn: 2, text: nil, processedMs: 1100)
        _ = state.apply(type: "transcript", turn: nil, text: "Second", processedMs: 1300)
        let final = state.apply(type: "speechComplete", turn: 1, text: "First sentence.", processedMs: 1000)
        XCTAssertEqual(final?.text, "First sentence.")
        XCTAssertEqual(final?.startSeconds, 0.2)
        XCTAssertEqual(state.partialText, "Second")
        XCTAssertNil(state.apply(type: "speechComplete", turn: 1, text: "Duplicate.", processedMs: 1000))
        _ = state.apply(type: "speechComplete", turn: 2, text: "Second.", processedMs: 2000)
        XCTAssertEqual(state.partialText, "")
    }
    func testEmptyFinalDoesNotCreateSegment() {
        var state = CloudTranscript()
        _ = state.apply(type: "speechStart", turn: 1, text: nil, processedMs: 0)
        XCTAssertNil(state.apply(type: "speechComplete", turn: 1, text: "  ", processedMs: 100))
    }
}
