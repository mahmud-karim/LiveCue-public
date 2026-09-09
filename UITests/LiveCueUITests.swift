import XCTest

final class LiveCueUITests: XCTestCase {
    func testAssistantSelectionAndTiming() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["start-session"].tap()
        app.buttons["assistant-lab"].tap()
        XCTAssertTrue(app.buttons["choose-gpt-5.6-luna"].waitForExistence(timeout: 5))
        app.buttons["choose-gpt-5.6-luna"].tap()
        XCTAssertEqual(app.staticTexts["selected-assistant-model"].label, "gpt-5.6-luna")
        let selection = XCTAttachment(screenshot: app.screenshot()); selection.name = "Assistant model selection"; selection.lifetime = .keepAlways; add(selection)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["timing-disclosure"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["PC: Codex CLI call"].waitForExistence(timeout: 5))
        let timing = XCTAttachment(screenshot: app.screenshot()); timing.name = "Response timing breakdown"; timing.lifetime = .keepAlways; add(timing)
        app.swipeUp()
        XCTAssertTrue(app.buttons["retry-same-text"].exists)
        app.buttons["retry-same-text"].tap()
        XCTAssertTrue(app.staticTexts["Transcription (reused)"].waitForExistence(timeout: 5))
    }
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
        XCTAssertTrue(app.progressIndicators["model-download-progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reload"].waitForExistence(timeout: 8))
        let download = XCTAttachment(screenshot: app.screenshot())
        download.name = "Download progress"; download.lifetime = .keepAlways; add(download)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.buttons["start-session"].tap()
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        let live = XCTAttachment(screenshot: app.screenshot())
        live.name = "Live Parakeet"; live.lifetime = .keepAlways; add(live)
    }

    func testPairingOffersQRScanner() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["pair-pc"].tap()
        XCTAssertTrue(app.buttons["scan-pairing-qr"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "QR pairing"; shot.lifetime = .keepAlways; add(shot)
    }
}
