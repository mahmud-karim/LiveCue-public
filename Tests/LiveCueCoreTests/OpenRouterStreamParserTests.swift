import XCTest
@testable import LiveCueCore

final class OpenRouterStreamParserTests: XCTestCase {
    private func event(_ object: [String: Any], parser: inout OpenRouterStreamParser) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        _ = try parser.consumeLine("data: " + String(decoding: data, as: UTF8.self))
        _ = try parser.consumeLine("")
    }
    private func done(_ parser: inout OpenRouterStreamParser) throws {
        _ = try parser.consumeLine("data: [DONE]"); _ = try parser.consumeLine("")
    }
    func testCommentsMultilineUnicodeReasoningAndRepeatedTerminalUsage() throws {
        var parser = OpenRouterStreamParser()
        _ = try parser.consumeLine(": OPENROUTER PROCESSING")
        _ = try parser.consumeLine("event: message")
        _ = try parser.consumeLine("data: {\"id\":\"gen-1\",")
        _ = try parser.consumeLine("data: \"choices\":[{\"delta\":{\"reasoning\":\"not an answer\",\"content\":\"Café 世界\"}}]}")
        _ = try parser.consumeLine("")
        try event(["choices": [["delta": [:], "finish_reason": "stop"]]], parser: &parser)
        try event(["choices": [["delta": ["content": ""], "finish_reason": "stop"]], "usage": ["prompt_tokens": 10, "completion_tokens": 5, "cost": "0.002"]], parser: &parser)
        try done(&parser)
        let result = try parser.result()
        XCTAssertEqual(result.text, "Café 世界"); XCTAssertEqual(result.usage?.costCredits, 0.002)
        XCTAssertEqual(result.usage?.generationId, "gen-1")
    }
    func testTextBlocksAndUnknownAccountingDoNotDiscardAnswer() throws {
        let data = Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"A usable answer"},{"type":"reasoning","text":"Hidden"}]},"finish_reason":"stop"}],"usage":{"cost":{"unexpected":true}}}"#.utf8)
        let result = try OpenRouterStreamParser.completeJSON(data)
        XCTAssertEqual(result.text, "A usable answer"); XCTAssertNil(result.usage?.costCredits)
    }
    func testPlainAnswerNeverNeedsAUUIDOrMemoryObject() throws {
        let data = Data(#"{"choices":[{"message":{"content":"Use a queue. throughSegmentId is not a UUID."},"finish_reason":"stop"}]}"#.utf8)
        XCTAssertTrue(try OpenRouterStreamParser.completeJSON(data).text.contains("Use a queue"))
    }
    func testEmptyLengthResultIsReportedAsTruncatedNotMalformed() throws {
        let data = Data(#"{"choices":[{"message":{"content":null},"finish_reason":"length"}]}"#.utf8)
        XCTAssertThrowsError(try OpenRouterStreamParser.completeJSON(data)) { error in
            guard case OpenRouterError.truncated = error else { return XCTFail("Expected truncation") }
        }
    }
    func testDisconnectedStreamCannotBecomeCompletedAnswer() throws {
        var parser = OpenRouterStreamParser()
        try event(["choices": [["delta": ["content": "Partial"]]]], parser: &parser)
        XCTAssertThrowsError(try parser.result()); XCTAssertEqual(parser.text, "Partial")
        try done(&parser)
        XCTAssertThrowsError(try parser.result())
    }
    func testMidstreamErrorRetainsPreviewWithoutLeakingProviderMessage() throws {
        var parser = OpenRouterStreamParser()
        try event(["choices": [["delta": ["content": "Partial"]]]], parser: &parser)
        XCTAssertThrowsError(try event(["error": ["message": "synthetic-key private transcript"]], parser: &parser)) { error in
            XCTAssertFalse(error.localizedDescription.contains("synthetic-key"))
            XCTAssertFalse(error.localizedDescription.contains("private transcript"))
        }
        XCTAssertEqual(parser.text, "Partial")
        XCTAssertThrowsError(try parser.result())
    }
    func testMalformedOrOversizedEventsFailSafely() throws {
        var parser = OpenRouterStreamParser()
        _ = try parser.consumeLine("data: not-json")
        XCTAssertThrowsError(try parser.consumeLine(""))
        var oversized = OpenRouterStreamParser()
        XCTAssertThrowsError(try oversized.consumeLine("data: " + String(repeating: "x", count: 128 * 1024 + 1)))
    }
    func testRefusalAndToolCallAreNotAcceptedAsAnswers() throws {
        for reason in ["content_filter", "tool_calls", "error"] {
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "Not a completed answer"], "finish_reason": reason]]])
            XCTAssertThrowsError(try OpenRouterStreamParser.completeJSON(data))
        }
    }
}
