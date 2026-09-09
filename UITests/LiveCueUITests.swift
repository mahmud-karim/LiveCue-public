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
        let voz = XCTAttachment(screenshot: app.screenshot())
        voz.name = "Voz on Assist"; voz.lifetime = .keepAlways; add(voz)
        app.buttons["end-session"].tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Live Parakeet"].tap()
        app.buttons["download-model"].tap()
        app.buttons["Download & use"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.buttons["start-session"].tap()
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        let live = XCTAttachment(screenshot: app.screenshot())
        live.name = "Live Parakeet"; live.lifetime = .keepAlways; add(live)
    }
}
