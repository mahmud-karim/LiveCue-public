import XCTest

final class LiveCueUITests: XCTestCase {
    func testDirectOpenRouterKeyPersistenceAndThreeAssistsWithoutPC() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-openrouter-ui-reset", "-on-device-ready", "-pc-offline", "-pc-catalog-slow"]
        app.launch(); app.buttons["assistant-lab"].tap()
        app.buttons["assistant-provider"].tap()
        app.buttons["assistant-provider-openrouter"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let key = app.secureTextFields["openrouter-key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap(); key.typeText("synthetic-mobile-key")
        app.buttons["save-openrouter-key"].tap()
        XCTAssertEqual(app.staticTexts["openrouter-key-state"].label, "Key saved")
        app.buttons["verify-openrouter-key"].tap()
        XCTAssertFalse(app.staticTexts["synthetic-mobile-key"].exists)
        app.swipeUp(); app.buttons["openrouter-model-picker"].tap()
        XCTAssertTrue(app.buttons["choose-test/direct"].waitForExistence(timeout: 5)); app.buttons["choose-test/direct"].tap()
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "OpenRouter direct settings - key hidden"; settings.lifetime = .keepAlways; add(settings)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-openrouter-persistence-test", "-on-device-ready", "-pc-offline"]
        app.launch(); app.buttons["assistant-lab"].tap()
        XCTAssertEqual(app.staticTexts["openrouter-key-state"].label, "Key saved")
        app.swipeUp(); XCTAssertEqual(app.staticTexts["selected-assistant-model"].label, "test/direct")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["OpenRouter direct"].exists)
        app.buttons["start-session"].tap()
        for _ in 0..<3 {
            app.buttons["assist-button"].tap()
            XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10)); XCTAssertEqual(app.alerts.count, 0)
            app.buttons["dismiss-answer"].tap()
        }
        app.buttons["end-session"].tap(); app.buttons["assistant-lab"].tap()
        app.swipeUp()
        let runs = XCTAttachment(screenshot: app.screenshot()); runs.name = "Three consecutive OpenRouter answers"; runs.lifetime = .keepAlways; add(runs)
        app.swipeDown(); app.buttons["remove-openrouter-key"].tap()
        XCTAssertEqual(app.staticTexts["openrouter-key-state"].label, "No key saved")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["start-session"].tap(); app.buttons["assist-button"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenRouter API key")).firstMatch.exists)
    }
    func testPCModelStartStopInSettings() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["start-pc-model"].exists)
        for provider in ["nemotron", "qwen3"] {
            app.buttons["speech-provider"].tap(); app.buttons["provider-" + provider].tap()
            XCTAssertTrue(app.buttons["start-pc-model"].waitForExistence(timeout: 5))
            app.buttons["start-pc-model"].tap()
            let ready = NSPredicate(format: "label == %@", "Ready")
            expectation(for: ready, evaluatedWith: app.staticTexts["pc-model-state"])
            waitForExpectations(timeout: 5)
            XCTAssertFalse(app.buttons["start-pc-model"].isEnabled)
            XCTAssertTrue(app.buttons["stop-pc-model"].isEnabled)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = provider + " PC model ready with Start Stop"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["stop-pc-model"].tap()
            expectation(for: NSPredicate(format: "label == %@", "Stopped"), evaluatedWith: app.staticTexts["pc-model-state"])
            waitForExpectations(timeout: 5)
            XCTAssertTrue(app.buttons["start-pc-model"].isEnabled)
            XCTAssertFalse(app.buttons["stop-pc-model"].isEnabled)
        }
    }
    func testPCModelStartupErrorAllowsRetry() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-pc-model-start-error"]; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["speech-provider"].tap(); app.buttons["provider-nemotron"].tap()
        app.buttons["start-pc-model"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Error"), evaluatedWith: app.staticTexts["pc-model-state"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["pc-model-message"].label.contains("Docker Desktop"))
        XCTAssertTrue(app.buttons["start-pc-model"].isEnabled)
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.staticTexts["home-pc-model-state"].label.contains("Error"))
        XCTAssertFalse(app.buttons["start-session"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "PC startup failure retry"; shot.lifetime = .keepAlways; add(shot)
    }
    func testPairingSurvivesRelaunchAndMissingKeychainCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-pairing-persistence-test", "-save-pairing-fixture"]
        app.launch()
        app.buttons["pair-pc"].tap()
        XCTAssertTrue(app.staticTexts["saved-pc-address"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["saved-pc-address"].label, "https://saved-pc.example.test:10000/")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-pairing-persistence-test", "-drop-test-keychain"]
        app.launch()
        app.buttons["pair-pc"].tap()
        XCTAssertTrue(app.staticTexts["saved-pc-address"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["saved-pc-address"].label, "https://saved-pc.example.test:10000/")
        XCTAssertTrue(app.buttons["reconnect-pc"].isHittable)
        XCTAssertFalse(app.buttons["scan-pairing-qr"].exists)
        app.buttons["reconnect-pc"].tap()
        XCTAssertTrue(app.staticTexts["saved-pc-state"].label.contains("Connected"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Saved PC pairing after relaunch"; shot.lifetime = .keepAlways; add(shot)
    }
    func testPCLocalSpeechChoicesHideCostInConversationAndHistory() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        for provider in ["nemotron", "qwen3"] {
            app.tabBars.buttons["Settings"].tap()
            app.buttons["speech-provider"].tap()
            XCTAssertTrue(app.buttons["provider-" + provider].waitForExistence(timeout: 5))
            let picker = XCTAttachment(screenshot: app.screenshot()); picker.name = "PC speech model choices"; picker.lifetime = .keepAlways; add(picker)
            app.buttons["provider-" + provider].tap()
            app.buttons["start-pc-model"].tap()
            expectation(for: NSPredicate(format: "label == %@", "Ready"), evaluatedWith: app.staticTexts["pc-model-state"])
            waitForExpectations(timeout: 5)
            app.tabBars.buttons["Live"].tap()
            XCTAssertFalse(app.buttons["download-model"].exists)
            app.buttons["start-session"].tap()
            XCTAssertTrue(app.buttons["assist-button"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["live-transcription-cost"].exists)
            let live = XCTAttachment(screenshot: app.screenshot()); live.name = provider + " live conversation"; live.lifetime = .keepAlways; add(live)
            app.buttons["assist-button"].tap()
            XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 5))
            app.buttons["dismiss-answer"].tap()
            app.buttons["pause-session"].tap()
            XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
            app.buttons["end-session"].tap()
            XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
            app.tabBars.buttons["History"].tap()
            XCTAssertTrue(app.staticTexts["history-local-transcription"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["history-local-transcription"].firstMatch.label.contains("$"))
            XCTAssertFalse(app.staticTexts["history-transcription-cost"].exists)
        }
    }
    func testHomeShowsPCModelLoadingReadyAndStoppedWithoutScrolling() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-pc-model-slow-start"]; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["speech-provider"].tap(); app.buttons["provider-nemotron"].tap()
        app.buttons["start-pc-model"].tap()
        app.tabBars.buttons["Live"].tap()
        let state = app.staticTexts["home-pc-model-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertTrue(state.label.contains("Loading"))
        XCTAssertFalse(app.buttons["start-session"].isEnabled)
        let loading = XCTAttachment(screenshot: app.screenshot()); loading.name = "Home PC model loading"; loading.lifetime = .keepAlways; add(loading)
        expectation(for: NSPredicate(format: "label == %@", "Ready"), evaluatedWith: state)
        waitForExpectations(timeout: 12)
        XCTAssertTrue(app.buttons["start-session"].isEnabled)
        XCTAssertTrue(app.buttons["start-session"].isHittable)
        XCTAssertTrue(app.buttons["transcription-settings"].isHittable)
        let ready = XCTAttachment(screenshot: app.screenshot()); ready.name = "Home PC model ready"; ready.lifetime = .keepAlways; add(ready)
        app.tabBars.buttons["Settings"].tap(); app.buttons["stop-pc-model"].tap()
        app.tabBars.buttons["Live"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Stopped"), evaluatedWith: state)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["start-session"].isEnabled)
    }
    func testLunaLowSelectionCanAssist() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["assistant-lab"].tap()
        XCTAssertTrue(app.buttons["choose-gpt-6-luna"].waitForExistence(timeout: 5))
        app.buttons["choose-gpt-6-luna"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["start-session"].tap(); app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testAssistantSelectionAndTiming() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["start-session"].tap()
        app.buttons["assistant-lab"].tap()
        XCTAssertTrue(app.buttons["choose-gpt-6-astra"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-gpt-5.6-luna"].waitForExistence(timeout: 5))
        app.buttons["choose-gpt-5.6-luna"].tap()
        XCTAssertEqual(app.staticTexts["selected-assistant-model"].label, "gpt-5.6-luna")
        app.buttons["reasoning-picker"].tap()
        XCTAssertTrue(app.buttons["effort-none"].waitForExistence(timeout: 5))
        app.buttons["effort-none"].tap()
        XCTAssertTrue(app.staticTexts["Reasoning: none"].waitForExistence(timeout: 5))
        let selection = XCTAttachment(screenshot: app.screenshot()); selection.name = "Assistant model selection"; selection.lifetime = .keepAlways; add(selection)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["timing-disclosure"].tap()
        app.swipeUp()
        // LabeledContent exposes its label and value together to accessibility.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "PC: Codex CLI call,")).firstMatch.waitForExistence(timeout: 5))
        let timing = XCTAttachment(screenshot: app.screenshot()); timing.name = "Response timing breakdown"; timing.lifetime = .keepAlways; add(timing)
        app.swipeUp()
        XCTAssertTrue(app.buttons["retry-same-text"].exists)
        app.buttons["retry-same-text"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Transcription (reused),")).firstMatch.waitForExistence(timeout: 5))
        let retry = XCTAttachment(screenshot: app.screenshot()); retry.name = "Same-text retry timing"; retry.lifetime = .keepAlways; add(retry)
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
        app.buttons["dismiss-answer"].tap()
        app.buttons["end-session"].tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "transcript segments")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["speech-provider"].tap()
        XCTAssertTrue(app.buttons["provider-parakeet"].waitForExistence(timeout: 5))
        app.buttons["provider-parakeet"].tap()
        app.tabBars.buttons["Live"].tap()
        app.buttons["download-model"].tap()
        app.buttons["Download & use"].tap()
        XCTAssertTrue(app.progressIndicators["model-download-progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reload"].waitForExistence(timeout: 8))
        let download = XCTAttachment(screenshot: app.screenshot())
        download.name = "Download progress"; download.lifetime = .keepAlways; add(download)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.buttons["start-session"].tap()
        XCTAssertFalse(app.staticTexts["live-transcription-cost"].exists)
        app.buttons["assist-button"].tap()
        XCTAssertTrue(app.staticTexts["assistant-answer"].waitForExistence(timeout: 10))
        let live = XCTAttachment(screenshot: app.screenshot())
        live.name = "Live Parakeet"; live.lifetime = .keepAlways; add(live)
    }

    func testPairingOffersQRScanner() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["pair-pc"].tap()
        if app.buttons["show-pairing-options"].exists { app.buttons["show-pairing-options"].tap() }
        XCTAssertTrue(app.buttons["scan-pairing-qr"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "QR pairing"; shot.lifetime = .keepAlways; add(shot)
    }
    func testMintSettingsAndCloudDisclosure() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Audio streams through your PC to Meta")).firstMatch.exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Midnight Mint"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Midnight Mint")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Midnight Mint Settings"; shot.lifetime = .keepAlways; add(shot)
    }

    func testFocusedConversationCostPauseAndHistory() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        for id in ["pair-pc", "assistant-lab", "start-session"] { XCTAssertTrue(app.buttons[id].isHittable) }
        XCTAssertFalse(app.staticTexts["live-transcription-cost"].exists)
        let start = app.buttons["start-session"].frame
        XCTAssertLessThan(start.maxY, app.tabBars.firstMatch.frame.minY + 1)
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "0.5.1 Home - no scroll"; home.lifetime = .keepAlways; add(home)
        app.buttons["start-session"].tap()
        XCTAssertTrue(app.staticTexts["live-transcription-cost"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.textFields["assistant-instruction"].exists)
        let cost = app.staticTexts["live-transcription-cost"]
        let positive = expectation(for: NSPredicate(format: "label != %@", "$0.00000 USD"), evaluatedWith: cost)
        wait(for: [positive], timeout: 5)
        let live = XCTAttachment(screenshot: app.screenshot()); live.name = "0.5.1 Live waveform and cost"; live.lifetime = .keepAlways; add(live)
        app.buttons["pause-session"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        let pausedCost = cost.label
        let unchanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in cost.label != pausedCost }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [unchanged], timeout: 2), .timedOut)
        XCTAssertEqual(app.tabBars.count, 0)
        app.buttons["end-session"].tap()
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        let saved = app.staticTexts["history-transcription-cost"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains(pausedCost))
        let history = XCTAttachment(screenshot: app.screenshot()); history.name = "0.5.1 History costs"; history.lifetime = .keepAlways; add(history)
    }

    func testInstructionsLiveOnlyInSettingsAndPersist() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "assistant-instruction").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        // Allow the remote simulator to deliver each keystroke before sending the next.
        for character in "Answer briefly." { input.typeText(String(character)) }
        let entered = input.value as? String ?? ""
        XCTAssertTrue(entered.contains("Answer briefly."), "Instruction typing must succeed before testing persistence: \(entered)")
        app.buttons["finish-instruction"].tap()
        app.tabBars.buttons["Live"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["Settings"].tap()
        let restored = app.descendants(matching: .any).matching(identifier: "assistant-instruction").firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String ?? "", entered)
    }
}
