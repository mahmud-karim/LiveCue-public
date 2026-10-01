import XCTest
@testable import LiveCueCore

private final class RouterProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handle!(request)
            let prefix = String(decoding: data.prefix(20), as: UTF8.self)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": prefix.hasPrefix("data:") || prefix.hasPrefix(":") ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class OpenRouterClientTests: XCTestCase {
    private func client() -> OpenRouterClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RouterProtocol.self]
        return OpenRouterClient(session: URLSession(configuration: config))
    }
    override func tearDown() { RouterProtocol.handle = nil; super.tearDown() }
    func testLegacyConfigurationAndUsagePersistence() throws {
        let old = Data(#"{"model":"gpt-6-luna","reasoningEffort":"low"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AssistantConfiguration.self, from: old).provider, .codex)
        let direct = AssistantConfiguration(model: "test/model", reasoningEffort: "default", provider: .openrouter)
        XCTAssertEqual(try JSONDecoder().decode(AssistantConfiguration.self, from: JSONEncoder().encode(direct)), direct)
        var execution = RelayExecution(model: "test/model", reasoningEffort: "default", codexMs: 0, relayTotalMs: 0, requestReadMs: 0, relayOverheadMs: 0)
        execution.usage = AssistantUsage(promptTokens: 100, completionTokens: 30, costCredits: 0.001)
        XCTAssertEqual(try JSONDecoder().decode(RelayExecution.self, from: JSONEncoder().encode(execution)), execution)
    }
    func testPublicCatalogFiltersAndDoesNotSendKey() async throws {
        RouterProtocol.handle = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/models")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data(#"{"data":[{"id":"text/model","name":"Text","architecture":{"input_modalities":["text"],"output_modalities":["text"]},"supported_parameters":["structured_outputs"],"pricing":{"prompt":"0.000001","completion":"0.000002"}},{"id":"audio/model","name":"Audio","architecture":{"input_modalities":["audio"],"output_modalities":["audio"]}}]}"#.utf8))
        }
        let options = try await client().models()
        XCTAssertEqual(options.count, 1); XCTAssertEqual(options[0].structuredOutputs, true)
        XCTAssertEqual(options[0].promptPrice, "0.000001")
    }
    func testVerificationIsReadOnlyAndFixedHost() async throws {
        RouterProtocol.handle = { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-fixture-key")
            return (200, Data(#"{"data":{"is_free_tier":false}}"#.utf8))
        }
        try await client().verifyKey("synthetic-fixture-key")
    }
    func testThreeConsecutivePlainAssistsKeepLocalMemoryAndUsageWithoutSchema() async throws {
        let cursor = UUID(); var count = 0
        RouterProtocol.handle = { request in
            count += 1
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? self.readBody(request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "test/structured")
            XCTAssertNil(body["response_format"]); XCTAssertNil(body["provider"]); XCTAssertNil(body["models"])
            XCTAssertEqual(body["stream"] as? Bool, true)
            let messages = body["messages"] as! [[String: String]]
            XCTAssertFalse(messages.description.contains("synthetic-fixture-key"))
            if count > 1 { XCTAssertTrue(messages.description.contains("Answer 1")) }
            let content = "Answer \(count)"
            let data = try JSONSerialization.data(withJSONObject: ["id":"generation-test", "model":"test/structured", "choices":[["message":["content":content],"finish_reason":"stop"]],"usage":["prompt_tokens":100,"completion_tokens":20,"cost":0.002]])
            return (200, data)
        }
        let router = client(); var memory = SessionMemory()
        for i in 1...3 {
            let input = AssistRequest(sessionId: UUID(), instruction: "Briefly", memory: memory, transcript: "Question \(i)", partialTranscript: nil)
            let response = try await router.assist(input, option: .init(id: "test/structured", name: "Test", reasoningEfforts: ["default"], structuredOutputs: true), key: "synthetic-fixture-key", throughSegmentId: cursor)
            XCTAssertEqual(response.answer, "Answer \(i)"); XCTAssertEqual(response.memory.throughSegmentId, cursor)
            XCTAssertEqual(response.execution?.usage?.costCredits, 0.002); memory = response.memory
        }
        XCTAssertEqual(count, 3)
    }
    func testRealStreamingTransportUpdatesTextAndKeepsFinalUsage() async throws {
        RouterProtocol.handle = { _ in
            let stream = ": OPENROUTER PROCESSING\n\ndata: {\"id\":\"gen-test\",\"model\":\"test/stream\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello \"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"世界\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: {\"choices\":[],\"usage\":{\"cost\":0.001}}\n\ndata: [DONE]\n\n"
            return (200, Data(stream.utf8))
        }
        let updates = StreamUpdates()
        let result = try await client().assist(.init(sessionId: UUID(), instruction: nil, memory: .init(), transcript: "Hi", partialTranscript: nil), option: .init(id: "test/stream", name: "Stream", reasoningEfforts: ["default"], structuredOutputs: true), key: "fixture", throughSegmentId: nil) { text in await updates.add(text) }
        XCTAssertEqual(result.answer, "Hello 世界")
        XCTAssertEqual(result.execution?.usage?.costCredits, 0.001)
        let values = await updates.values
        XCTAssertEqual(values, ["Hello ", "Hello 世界"])
    }
    func testErrorsDoNotLeakKeyOrRetryAndRecoveryWorks() async throws {
        var status = 401; var count = 0
        RouterProtocol.handle = { _ in
            count += 1
            return (status, status == 200 ? Data(#"{"choices":[{"message":{"content":"Recovered answer"},"finish_reason":"stop"}]}"#.utf8) : Data(#"{"error":"synthetic-fixture-key private transcript"}"#.utf8))
        }
        let router = client()
        let input = AssistRequest(sessionId: UUID(), instruction: nil, memory: .init(), transcript: "Hello", partialTranscript: nil)
        let option = AssistantModelOption(id: "test/plain", name: "Plain", reasoningEfforts: ["default"])
        for code in [401, 402, 429, 503] {
            status = code
            do { _ = try await router.assist(input, option: option, key: "synthetic-fixture-key", throughSegmentId: nil); XCTFail("Expected failure") }
            catch { XCTAssertFalse(error.localizedDescription.contains("synthetic-fixture-key")); XCTAssertFalse(error.localizedDescription.contains("private transcript")) }
        }
        XCTAssertEqual(count, 4); status = 200
        let result = try await router.assist(input, option: option, key: "synthetic-fixture-key", throughSegmentId: nil)
        XCTAssertEqual(result.answer, "Recovered answer"); XCTAssertNil(result.execution?.usage?.costCredits)
        XCTAssertEqual(count, 5)
    }
    func testTruncationIsNotSavedAsCompleteAnswer() async throws {
        RouterProtocol.handle = { _ in (200, Data(#"{"choices":[{"message":{"content":"Cut off"},"finish_reason":"length"}]}"#.utf8)) }
        do {
            _ = try await client().assist(.init(sessionId: UUID(), instruction: nil, memory: .init(), transcript: "Hello", partialTranscript: nil), option: .init(id: "test/plain", name: "Plain", reasoningEfforts: ["default"]), key: "fixture", throughSegmentId: nil)
            XCTFail("Expected truncated error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("response limit")) }
    }
    private func readBody(_ request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }; var result = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; result.append(contentsOf: bytes.prefix(n)) }
        return result
    }
}

private actor StreamUpdates {
    var values: [String] = []
    func add(_ text: String) { values.append(text) }
}
