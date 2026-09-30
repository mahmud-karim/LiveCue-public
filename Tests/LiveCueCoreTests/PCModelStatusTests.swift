import XCTest
@testable import LiveCueCore

final class PCModelStatusTests: XCTestCase {
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
