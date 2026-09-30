import XCTest
@testable import LiveCueCore

final class PCModelStatusTests: XCTestCase {
    func testHomeStatusDistinguishesLoadingReadyBusyStoppedAndFailure() {
        XCTAssertEqual(PCModelStatus(state: "starting", model: "nemotron", elapsedSeconds: 42, message: "Loading").homeLabel(for: "nemotron"), "Loading · 42s")
        XCTAssertEqual(PCModelStatus(state: "ready", model: "nemotron", message: "Loaded").homeLabel(for: "nemotron"), "Ready")
        XCTAssertEqual(PCModelStatus(state: "ready", model: "nemotron", busy: true, message: "Listening").homeLabel(for: "nemotron"), "In use")
        XCTAssertEqual(PCModelStatus(state: "ready", model: "qwen3", message: "Loaded").homeLabel(for: "nemotron"), "Different model loaded")
        XCTAssertEqual(PCModelStatus(state: "error", model: "nemotron", message: "Failed").homeLabel(for: "nemotron"), "Error · open Settings")
        XCTAssertEqual(PCModelStatus(state: "stopped", message: "Stopped").homeLabel(for: "nemotron"), "Stopped · open Settings")
    }
    func testReadinessRequiresTheSelectedModel() throws {
        let json = "{\"state\":\"ready\",\"model\":\"nemotron\",\"busy\":false,\"elapsedSeconds\":0,\"message\":\"Ready\"}"
        let status = try JSONDecoder().decode(PCModelStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.isReady(for: "nemotron"))
        XCTAssertFalse(status.isReady(for: "qwen3"))
        XCTAssertFalse(status.isChanging)
        XCTAssertTrue(PCModelStatus(state: "starting", model: "nemotron", message: "Loading").isChanging)
        XCTAssertFalse(PCModelStatus(state: "error", model: "nemotron", message: "Failed").isReady(for: "nemotron"))
    }
}
