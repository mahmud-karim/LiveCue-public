import XCTest
@testable import LiveCueCore

final class SpeechProviderTests: XCTestCase {
    func testLocalProvidersNeverAccrueAPICost() throws {
        for provider in [SpeechProvider.nemotron, .qwen3] {
            XCTAssertTrue(provider.usesPC)
            XCTAssertTrue(provider.isPCLocal)
            XCTAssertEqual(provider.sampleRate, 16000)
            var usage = TranscriptionUsage(provider: provider.rawValue)
            let id = UUID(); usage.begin(id)
            usage.update(id, sentMs: 60000, processedMs: 60000, hasTranscript: true)
            usage.finish(id, completed: true)
            XCTAssertEqual(usage.estimatedUSD, 0)
            XCTAssertEqual(usage.reportedSeconds, 60)
            XCTAssertEqual(try JSONDecoder().decode(TranscriptionUsage.self, from: JSONEncoder().encode(usage)), usage)
        }
        XCTAssertEqual(SpeechProvider.meta.sampleRate, 24000)
        XCTAssertFalse(SpeechProvider.voz.usesPC)
    }
    func testRollingCaptionsDoNotDuplicate() {
        var transcript = CloudTranscript()
        XCTAssertNil(transcript.apply(type: "speechStart", turn: 1, text: nil, processedMs: 0))
        XCTAssertNil(transcript.apply(type: "transcript", turn: 1, text: "First words", processedMs: 1000))
        XCTAssertEqual(transcript.partialText, "First words")
        XCTAssertEqual(transcript.apply(type: "speechComplete", turn: 1, text: "First words.", processedMs: 30000)?.text, "First words.")
        XCTAssertTrue(transcript.partialText.isEmpty)
        XCTAssertNil(transcript.apply(type: "speechStart", turn: 2, text: nil, processedMs: 30000))
        XCTAssertNil(transcript.apply(type: "transcript", turn: 2, text: "Next words", processedMs: 31000))
        XCTAssertEqual(transcript.apply(type: "speechComplete", turn: 2, text: "Next words.", processedMs: 32000)?.startSeconds, 30)
        XCTAssertTrue(transcript.partialText.isEmpty)
    }
}
