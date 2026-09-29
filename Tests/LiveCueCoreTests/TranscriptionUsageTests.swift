import XCTest
@testable import LiveCueCore

final class TranscriptionUsageTests: XCTestCase {
    func testLiveEstimateReconcilesToProcessedAudioAndRoundsPerStream() {
        var usage = TranscriptionUsage()
        let first = UUID(), second = UUID()
        usage.begin(first)
        usage.update(first, sentMs: 31900, processedMs: 30400, hasTranscript: true)
        XCTAssertEqual(usage.estimatedUSD, 31 * 0.00005, accuracy: 0.0000001)
        usage.finish(first, completed: true)
        XCTAssertEqual(usage.estimatedUSD, 30 * 0.00005, accuracy: 0.0000001)
        usage.begin(second)
        usage.update(second, sentMs: 1900, processedMs: 1900, hasTranscript: true)
        usage.finish(second, completed: true)
        XCTAssertEqual(usage.estimatedSeconds, 31) // Not floor(30.4 + 1.9).
        XCTAssertEqual(usage.formattedCost, "$0.00155")
        XCTAssertFalse(usage.incomplete)
    }
    func testEverySecondChangesCounterAndDoesNotCountPausedTime() {
        var usage = TranscriptionUsage(); let id = UUID(); usage.begin(id)
        usage.update(id, sentMs: 1000, processedMs: 1000, hasTranscript: true)
        XCTAssertEqual(usage.formattedCost, "$0.00005")
        usage.update(id, sentMs: 2000, processedMs: 2000)
        XCTAssertEqual(usage.formattedCost, "$0.00010")
        usage.finish(id, completed: true)
        usage.update(id, sentMs: 999000, processedMs: 999000)
        XCTAssertEqual(usage.formattedCost, "$0.00010")
    }
    func testProgressIsCumulativeNotSummedAndRejectsInvalidNumbers() {
        var usage = TranscriptionUsage(); let id = UUID(); usage.begin(id); usage.begin(id)
        usage.update(id, sentMs: 3000, processedMs: 2000)
        usage.update(id, sentMs: -1, processedMs: .nan)
        usage.update(id, processedMs: 1000)
        XCTAssertEqual(usage.streams.count, 1)
        XCTAssertEqual(usage.reportedSeconds, 2)
        XCTAssertEqual(usage.estimatedSeconds, 3)
    }
    func testInterruptedStreamAndFailureBeforeTranscript() {
        var usage = TranscriptionUsage(); let id = UUID(); usage.begin(id)
        usage.update(id, sentMs: 10000, processedMs: 6000)
        usage.finish(id, completed: false)
        XCTAssertTrue(usage.incomplete)
        XCTAssertEqual(usage.estimatedUSD, 0)
        let resumed = UUID(); usage.begin(resumed)
        usage.update(resumed, sentMs: 5000, processedMs: 4000, hasTranscript: true)
        usage.finish(resumed, completed: false)
        XCTAssertEqual(usage.estimatedUSD, 0.0002, accuracy: 0.0000001)
    }
    func testHistoryRoundTripLegacyAndLocalCosts() throws {
        let legacy = Session()
        let encoded = try JSONEncoder().encode(legacy)
        XCTAssertNil(try JSONDecoder().decode(Session.self, from: encoded).transcriptionUsage)
        var updated = legacy
        var usage = TranscriptionUsage(); let id = UUID(); usage.begin(id)
        usage.update(id, sentMs: 600000, processedMs: 600000, hasTranscript: true); usage.finish(id, completed: true)
        updated.transcriptionUsage = usage
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(decoded, updated)
        XCTAssertEqual(decoded.transcriptionUsage!.estimatedUSD, 0.03, accuracy: 0.0000001)
        XCTAssertEqual(TranscriptionUsage(provider: "parakeet").estimatedUSD, 0)
    }
}
