import XCTest

final class RecoveryUITests: XCTestCase {
    @MainActor func testRecoveryOfferAddAndDeclineOnRealRelaunch() async throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-studyos-ui-testing", "-studyos-ui-reset"]; app.launch()
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout: 10))
        let begin = app.buttons["beginFlow"]
        for _ in 0..<12 { if begin.exists && begin.isHittable { break }; app.swipeUp() }
        begin.tap(); XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 5)); app.buttons["addTask"].tap()
        let title = app.textFields["taskTitle"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Recovery review task"); app.buttons["saveTask"].tap()
        let focus = app.buttons["startFocus"]; XCTAssertTrue(focus.waitForExistence(timeout: 5)); focus.tap()
        XCTAssertTrue(app.staticTexts["focusTimer"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-studyos-ui-testing"]
        try await Task.sleep(for: .seconds(62)); app.launch()
        let alert = app.alerts["Add time from before the app closed?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        capture(app, "Recovery offer after termination")
        app.terminate(); app.launch()
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        capture(app, "Unanswered recovery survives another launch")
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add ")).firstMatch.tap()
        let timer = app.staticTexts["focusTimer"]; XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let saved = timer.value as? String; XCTAssertNotNil(saved); XCTAssertTrue(saved?.contains("m") == true || saved?.contains("h") == true)
        XCTAssertTrue(app.buttons["pauseResume"].label.contains("Resume"))
        app.terminate(); app.launch()
        XCTAssertTrue(timer.waitForExistence(timeout: 10)); XCTAssertFalse(alert.exists); XCTAssertEqual(timer.value as? String, saved)
        app.buttons["pauseResume"].tap(); app.terminate()
        try await Task.sleep(for: .seconds(62)); app.launch()
        XCTAssertTrue(alert.waitForExistence(timeout: 12)); capture(app, "Recovery offer before decline")
        let beforeDecline = timer.value as? String
        app.buttons["Don't add"].tap(); XCTAssertFalse(alert.exists); XCTAssertEqual(timer.value as? String, beforeDecline)
        app.terminate(); app.launch()
        XCTAssertTrue(timer.waitForExistence(timeout: 10)); XCTAssertFalse(alert.exists); XCTAssertEqual(timer.value as? String, beforeDecline)
        capture(app, "Recovery declined time retained")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
