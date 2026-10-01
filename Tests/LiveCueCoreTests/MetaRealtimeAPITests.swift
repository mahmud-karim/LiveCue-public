import XCTest
@testable import LiveCueCore

final class MetaRealtimeAPITests: XCTestCase {
    func testDirectHandshakeUsesFixedTLSServiceAndNoPC() throws {
        XCTAssertEqual(MetaRealtimeAPI.endpoint.absoluteString, "wss://api.meta.ai/v1/asr/realtime")
        XCTAssertNil(MetaRealtimeAPI.endpoint.query)
        XCTAssertNil(MetaRealtimeAPI.endpoint.user)
        let encoded = try MetaRealtimeAPI.handshake(key: "synthetic-meta-unit-key")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        XCTAssertEqual((value["authorization"] as? [String: String])?["accessToken"], "Bearer synthetic-meta-unit-key")
        XCTAssertEqual(value["audioEncoding"] as? String, "PCM_24KHZ")
        XCTAssertEqual(value["mode"] as? String, "ENDPOINTING")
        XCTAssertEqual(value["partialMode"] as? String, "CUMULATIVE")
        XCTAssertEqual(value["model"] as? String, "muse-voice-transcribe-1.0")
        XCTAssertEqual(value["emitAudioProgress"] as? Bool, true)
        XCTAssertNil(value["endpoint"]); XCTAssertNil(value["token"])
        XCTAssertFalse(SpeechProvider.meta.usesPC)
        XCTAssertTrue(SpeechProvider.meta.isCloud)
        XCTAssertTrue(SpeechProvider.meta.streamsAudio)
        XCTAssertTrue(SpeechProvider.nemotron.usesPC)
        XCTAssertTrue(SpeechProvider.qwen3.usesPC)
        XCTAssertFalse(SpeechProvider.voz.streamsAudio)
        XCTAssertFalse(SpeechProvider.parakeet.streamsAudio)
    }
    func testInvalidKeysAndFailedAuthenticationAreSafe() throws {
        for key in ["", "key with spaces", "key\nsecret"] { XCTAssertThrowsError(try MetaRealtimeAPI.handshake(key: key)) }
        try MetaRealtimeAPI.acknowledge(["sessionId": "synthetic-session"])
        let invalid: [[String: Any]] = [["sessionId": ""], ["type": "error", "sessionId": "id", "message": "secret"], [:]]
        for value in invalid {
            XCTAssertThrowsError(try MetaRealtimeAPI.acknowledge(value)) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
        XCTAssertThrowsError(try MetaRealtimeAPI.event(["type": "error", "message": "synthetic-sensitive-key"], key: "synthetic-sensitive-key")) { error in
            XCTAssertFalse(error.localizedDescription.contains("synthetic-sensitive-key"))
        }
    }
    func testAllowlistedEventsPreserveCaptionsAndUsageWithoutSecrets() throws {
        let key = "synthetic-meta-key"
        let event = try MetaRealtimeAPI.event(["type": "transcript", "turnId": 2, "audioProcessedMs": 1234, "final": false,
            "transcript": "Hello " + key, "authorization": key, "metadata": key], key: key)
        XCTAssertEqual(event["transcript"] as? String, "Hello [redacted]")
        XCTAssertEqual(event["audioProcessedMs"] as? Int, 1234)
        XCTAssertEqual(event["final"] as? Bool, false)
        XCTAssertNil(event["authorization"]); XCTAssertNil(event["metadata"])
        XCTAssertTrue(try MetaRealtimeAPI.event(["type": "unknown", "transcript": key], key: key).isEmpty)
        var transcript = CloudTranscript()
        _ = transcript.apply(type: "speechStart", turn: 2, text: nil, processedMs: 0)
        _ = transcript.apply(type: "transcript", turn: 2, text: event["transcript"] as? String, processedMs: 1234)
        XCTAssertEqual(transcript.partialText, "Hello [redacted]")
        let final = try MetaRealtimeAPI.event(["type": "speechComplete", "turnId": 2, "audioProcessedMs": 2000, "transcript": "Hello world."], key: key)
        XCTAssertEqual(transcript.apply(type: "speechComplete", turn: final["turnId"] as? Int, text: final["transcript"] as? String, processedMs: 2000)?.text, "Hello world.")
        var usage = TranscriptionUsage(provider: "meta"); let id = UUID(); usage.begin(id)
        usage.update(id, sentMs: 2000, processedMs: 2000, hasTranscript: true); usage.finish(id, completed: true)
        XCTAssertEqual(usage.reportedSeconds, 2)
        XCTAssertGreaterThan(usage.estimatedUSD, 0)
        XCTAssertFalse(usage.incomplete)
    }
}
