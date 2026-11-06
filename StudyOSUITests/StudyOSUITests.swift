import XCTest

final class StudyOSUITests: XCTestCase {
    @MainActor func testAvailabilityFollowsDailyTimeAndGoalCanBeCreatedInsideTask() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-studyos-ui-testing", "-studyos-ui-reset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout: 10))
        let availability = app.steppers["dailyAvailability"]
        scrollTo(availability, in: app)
        for _ in 0..<8 { app.buttons["dailyAvailability-Increment"].tap() }
        XCTAssertTrue(app.staticTexts["Daily availability: 300 min"].exists)
        XCTAssertTrue(app.staticTexts["Daily maximum: 300 min"].exists)
        let maximum = app.steppers["dailyMaximum"]
        let decrement = maximum.buttons["dailyMaximum-Decrement"]
        if decrement.isEnabled { decrement.tap() }
        XCTAssertTrue(app.staticTexts["Daily maximum: 300 min"].exists)
        let begin = app.buttons["beginFlow"]
        scrollTo(begin, in: app); begin.tap()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 5)); app.buttons["addTask"].tap()
        let title = app.textFields["taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Keep this task draft")
        let addGoal = app.buttons["addTaskGoal"]
        scrollTo(addGoal, in: app)
        XCTAssertFalse(app.buttons["taskGoalPicker"].exists)
        XCTAssertTrue(app.staticTexts["noGoalsMessage"].exists)
        addGoal.tap()
        let goalTitle = app.textFields["goalTitle"]
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 5)); goalTitle.tap(); goalTitle.typeText("Finish the proposal")
        app.buttons["saveGoal"].tap()
        XCTAssertTrue(app.buttons["taskGoalPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["taskGoalPicker"].label.contains("Finish the proposal"))
        XCTAssertEqual(app.textFields["taskTitle"].value as? String, "Keep this task draft")
        capture(app, "Task with new goal")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Study availability"].tap()
        XCTAssertTrue(app.steppers["weekdayAvailability-2"].waitForExistence(timeout: 5))
        app.buttons["weekdayAvailability-2-Increment"].tap()
        let settingsMaximum = app.steppers["dailyMaximum"]
        scrollTo(settingsMaximum, in: app)
        XCTAssertTrue(app.staticTexts["Daily maximum: 315 min"].exists)
        let settingsDecrement = settingsMaximum.buttons["dailyMaximum-Decrement"]
        if settingsDecrement.isEnabled { settingsDecrement.tap() }
        XCTAssertTrue(app.staticTexts["Daily maximum: 315 min"].exists)
        capture(app, "Availability maximum follows")
        app.navigationBars["Study availability"].buttons["Save"].tap()
    }

    @MainActor func testFlowMonthNavigationAndSelectedDayTask() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-studyos-ui-testing", "-studyos-ui-reset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout: 10))
        let begin = app.buttons["beginFlow"]; scrollTo(begin, in: app); begin.tap()
        XCTAssertTrue(app.tabBars.buttons["Flow"].waitForExistence(timeout: 5)); app.tabBars.buttons["Flow"].tap()
        XCTAssertTrue(app.otherElements["monthCalendar"].exists)
        let monthTitle = app.staticTexts["flowPeriodTitle"].label
        app.buttons["nextCalendarPeriod"].tap()
        XCTAssertNotEqual(app.staticTexts["flowPeriodTitle"].label, monthTitle)
        app.buttons["previousCalendarPeriod"].tap()
        XCTAssertEqual(app.staticTexts["flowPeriodTitle"].label, monthTitle)
        let cal = Calendar.current, tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let c = cal.dateComponents([.era, .year, .month, .day], from: tomorrow)
        let id = "flowDay-\(c.era ?? 1)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        app.buttons[id].tap()
        XCTAssertTrue(app.buttons[id].isSelected)
        capture(app, "Month calendar")
        let add = app.buttons["Add task"]; scrollTo(add, in: app); add.tap()
        let title = app.textFields["taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Selected calendar day")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Selected calendar day").firstMatch.waitForExistence(timeout: 5))
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        app.segmentedControls["calendarScope"].buttons["Week"].tap()
        XCTAssertFalse(app.otherElements["monthCalendar"].exists)
        app.segmentedControls["calendarScope"].buttons["Month"].tap()
        XCTAssertTrue(app.otherElements["monthCalendar"].exists)
    }

    @MainActor func testOnboardingTaskFocusAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-studyos-ui-testing", "-studyos-ui-reset"]
        app.launch()
        let begin = app.buttons["beginFlow"]
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout: 10))
        for _ in 0..<6 { if begin.exists && begin.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(begin.exists && begin.isHittable)
        begin.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        capture(app, "Today empty")
        app.buttons["addTask"].tap()
        let field = app.textFields["taskTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("UI Integration Focus")
        app.buttons["saveTask"].tap()
        capture(app, "Today task")
        let focus = app.buttons["startFocus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5)); focus.tap()
        XCTAssertTrue(app.staticTexts["focusTimer"].waitForExistence(timeout: 5))
        capture(app, "Focus")
        let notes = app.textFields["quickNotes"]
        if notes.exists { notes.tap(); notes.typeText("Persist this note") }
        app.buttons["pauseResume"].tap()
        app.buttons["finishFocus"].tap()
        XCTAssertTrue(app.buttons["saveSession"].waitForExistence(timeout: 5))
        app.buttons["saveSession"].tap()
        XCTAssertTrue(app.tabBars.buttons["Ocean"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Ocean"].tap()
        capture(app, "Ocean")
        app.tabBars.buttons["Flow"].tap(); capture(app, "Flow")
        app.tabBars.buttons["Settings"].tap(); capture(app, "Settings")
        app.terminate(); app.launchArguments = ["-studyos-ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Ocean"].tap()
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        app.buttons["Session history"].tap()
        XCTAssertTrue(app.staticTexts["UI Integration Focus"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testAllTabsAtCurrentAccessibilitySettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-studyos-ui-testing", "-studyos-ui-reset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout: 10))
        let begin = app.buttons["beginFlow"]
        for _ in 0..<16 { if begin.exists && begin.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(begin.exists && begin.isHittable); begin.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        capture(app, "Accessibility Today")
        for title in ["Flow", "Ocean", "Settings"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].exists)
            capture(app, "Accessibility " + title)
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let done = app.buttons["dismissKeyboard"]
        if done.exists && done.isHittable { done.tap() }
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
