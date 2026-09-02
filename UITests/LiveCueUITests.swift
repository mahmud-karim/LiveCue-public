import XCTest

final class LiveCueUITests: XCTestCase {
    func testConversationAndAssistFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 10))
        app.buttons["start-session"].tap()
        XCTAssertTrue(app.staticTexts["What is the main advantage of local transcription?"].waitForExistence(timeout: 5))
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
    }
}

