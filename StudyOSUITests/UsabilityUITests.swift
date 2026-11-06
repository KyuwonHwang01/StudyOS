import XCTest

final class UsabilityUITests: XCTestCase {
    @MainActor func testAppearanceSelectionSavesAndReturnsWithoutAnExtraBackStep() {
        let app = launchFresh(); app.tabBars.buttons["Settings"].tap()
        let setting = app.buttons["appearanceSettings"]; XCTAssertTrue(setting.waitForExistence(timeout: 5)); setting.tap()
        let dark = app.buttons["Dark"]; XCTAssertTrue(dark.waitForExistence(timeout: 5)); dark.tap()
        XCTAssertTrue(setting.waitForExistence(timeout: 5)); XCTAssertTrue(setting.label.contains("Dark"))
        setting.tap(); let system = app.buttons["Follow system"]; XCTAssertTrue(system.waitForExistence(timeout: 5)); system.tap()
        XCTAssertTrue(setting.waitForExistence(timeout: 5)); XCTAssertTrue(setting.label.contains("Follow system"))
    }
    @MainActor private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication();app.launchArguments = ["-studyos-ui-testing","-studyos-ui-reset"];app.launch()
        XCTAssertTrue(app.navigationBars["StudyOS"].waitForExistence(timeout:10))
        let begin = app.buttons["beginFlow"];scrollTo(begin,app);begin.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5));return app
    }
    @MainActor private func scrollTo(_ element:XCUIElement,_ app:XCUIApplication) {
        let done = app.buttons["dismissKeyboard"]
        if done.exists && done.isHittable { done.tap() }
        for _ in 0..<12 { if element.exists && element.isHittable { return };app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    @MainActor private func createTask(_ title:String,_ app:XCUIApplication,step:String?=nil) {
        app.buttons["addTask"].tap();let field=app.textFields["taskTitle"]
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(title)
        if let step { let field=app.textFields["Add a step"];scrollTo(field,app);field.tap();field.typeText(step) }
        app.buttons["saveTask"].tap();XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5))
    }
    @MainActor func testFinishBackResumesAndClosePreservesTheSession() {
        let app=launchFresh();createTask("Resume correctly",app)
        app.buttons["startFocus"].tap();XCTAssertTrue(app.buttons["pauseResume"].waitForExistence(timeout:5))
        app.buttons["finishFocus"].tap();XCTAssertTrue(app.buttons["backToFocus"].waitForExistence(timeout:5));app.buttons["backToFocus"].tap()
        XCTAssertTrue(app.buttons["pauseResume"].label.contains("Pause"))
        app.buttons["closeFocus"].tap();XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5))
        let active=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Return to")).firstMatch
        XCTAssertTrue(active.exists);active.tap()
        XCTAssertTrue(app.buttons["focusTimer"].exists || app.staticTexts["focusTimer"].waitForExistence(timeout:5))
        app.buttons["finishFocus"].tap();app.buttons["saveSession"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5))
    }
    @MainActor func testChecklistSuggestsCompletionAndUndoKeepsTheSavedSession() {
        let app=launchFresh();createTask("Checklist completion",app,step:"Finish the small step")
        app.buttons["startFocus"].tap();XCTAssertTrue(app.staticTexts["focusTimer"].waitForExistence(timeout:5))
        let step=app.buttons["Finish the small step"];scrollTo(step,app);step.tap()
        let finish = app.buttons["finishFocus"]
        for _ in 0..<6 { if finish.exists && finish.isHittable { break }; app.swipeDown() }
        finish.tap()
        let complete=app.switches["finishTaskComplete"]
        XCTAssertTrue(complete.waitForExistence(timeout:5));XCTAssertEqual(complete.value as? String,"1")
        complete.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        let off = NSPredicate(format:"value == %@","0")
        XCTAssertTrue(complete.waitForExistence(timeout:3))
        expectation(for:off,evaluatedWith:complete);waitForExpectations(timeout:3)
        app.buttons["backToFocus"].tap();app.buttons["finishFocus"].tap()
        expectation(for:off,evaluatedWith:app.switches["finishTaskComplete"]);waitForExpectations(timeout:3)
        app.switches["finishTaskComplete"].coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        app.buttons["saveSession"].tap();let undo=app.buttons["undoAction"]
        XCTAssertTrue(undo.waitForExistence(timeout:5));undo.tap()
        XCTAssertTrue(app.buttons["startFocus"].waitForExistence(timeout:5))
        app.tabBars.buttons["Ocean"].tap();app.swipeUp();app.swipeUp();app.swipeUp();app.buttons["Session history"].tap()
        XCTAssertTrue(app.staticTexts["Checklist completion"].firstMatch.waitForExistence(timeout:5))
    }
    @MainActor func testDraftSurvivesCloseAndRelaunchAndInlineSubjectAndLinkSave() {
        let app=launchFresh();app.buttons["addTask"].tap()
        let title=app.textFields["taskTitle"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Persisted form draft")
        app.navigationBars["New task"].buttons["Close"].tap()
        app.terminate();app.launchArguments=["-studyos-ui-testing"];app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout:8));app.buttons["addTask"].tap()
        XCTAssertEqual(app.textFields["taskTitle"].value as? String,"Persisted form draft")
        app.buttons["addTaskSubject"].tap();let subject=app.textFields["subjectName"]
        XCTAssertTrue(subject.waitForExistence(timeout:5));subject.tap();subject.typeText("Inline course");app.buttons["saveSubject"].tap()
        let url=app.textFields["taskResourceURL"];scrollTo(url,app);url.tap();url.typeText("https://example.com/lesson")
        app.buttons["saveTask"].tap();XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5))
        app.buttons["addTask"].tap()
        XCTAssertNotEqual(app.textFields["taskTitle"].value as? String,"Persisted form draft")
        app.navigationBars["New task"].buttons["Close"].tap()
        app.buttons["startFocus"].tap();XCTAssertTrue(app.staticTexts["focusTimer"].waitForExistence(timeout:5))
        let resource=app.buttons["example.com"];scrollTo(resource,app);XCTAssertTrue(resource.exists)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Inline resource saved";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testExistingGoalFillsSubjectWithoutLeavingTaskForm() {
        let app=launchFresh();app.buttons["addTask"].tap()
        let title=app.textFields["taskTitle"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("First goal task")
        app.buttons["addTaskSubject"].tap();let name=app.textFields["subjectName"]
        XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("Goal course");app.buttons["saveSubject"].tap()
        let addGoal=app.buttons["addTaskGoal"];scrollTo(addGoal,app);addGoal.tap()
        let goal=app.textFields["goalTitle"];XCTAssertTrue(goal.waitForExistence(timeout:5));goal.tap();goal.typeText("Course exam");app.buttons["saveGoal"].tap();app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout:5));app.buttons["addTask"].tap()
        let picker=app.buttons["taskGoalPicker"];scrollTo(picker,app)
        picker.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        let choice=app.buttons["Course exam"];XCTAssertTrue(choice.waitForExistence(timeout:5));choice.tap()
        XCTAssertTrue(app.buttons["taskSubjectPicker"].label.contains("Goal course"))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Goal subject auto link";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testExistingReservationOpensMoveAndFocusUsesBlockTarget() {
        let app=launchFresh();app.buttons["addTask"].tap()
        let title=app.textFields["taskTitle"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Large task small block")
        let estimate=app.steppers["taskEstimate"];scrollTo(estimate,app)
        for _ in 0..<6 { app.buttons["taskEstimate-Increment"].tap() }
        app.buttons["saveTask"].tap();XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout:5))
        let row=app.buttons.containing(.staticText,identifier:"Large task small block").firstMatch;scrollTo(row,app);row.tap()
        let move=app.buttons["moveTaskBlock"];scrollTo(move,app);move.tap()
        let duration=app.steppers["blockDuration"];XCTAssertTrue(duration.waitForExistence(timeout:5))
        for _ in 0..<6 { app.buttons["blockDuration-Decrement"].tap() }
        app.buttons["saveBlock"].tap();XCTAssertTrue(app.buttons["moveTaskBlock"].waitForExistence(timeout:5));app.buttons["moveTaskBlock"].tap()
        XCTAssertTrue(app.navigationBars["Move study block"].waitForExistence(timeout:5))
        app.navigationBars["Move study block"].buttons["Close"].tap()
        let start=app.buttons["Start focus"]
        for _ in 0..<8 { if start.exists && start.isHittable { break };app.swipeDown() }
        start.tap();XCTAssertTrue(app.staticTexts["focusTarget"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["focusTarget"].label.contains("30 min"))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Block target focus";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testChangingLinkedSubjectAndChoosingAConflictingGoalResolveInPlace() {
        let app = launchFresh(); app.buttons["addTask"].tap()
        let title = app.textFields["taskTitle"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Resolve relationships here")
        app.buttons["addTaskSubject"].tap()
        let subject = app.textFields["subjectName"]; XCTAssertTrue(subject.waitForExistence(timeout: 5)); subject.tap(); subject.typeText("Original course"); app.buttons["saveSubject"].tap()
        let addGoal = app.buttons["addTaskGoal"]; scrollTo(addGoal, app); addGoal.tap()
        let goal = app.textFields["goalTitle"]; XCTAssertTrue(goal.waitForExistence(timeout: 5)); goal.tap(); goal.typeText("Original goal"); app.buttons["saveGoal"].tap()
        app.buttons["addTaskSubject"].tap()
        XCTAssertTrue(subject.waitForExistence(timeout: 5)); subject.tap(); subject.typeText("Different course"); app.buttons["saveSubject"].tap()
        let unlink = app.buttons["Change subject & unlink goal"]
        XCTAssertTrue(unlink.waitForExistence(timeout: 5)); unlink.tap()
        XCTAssertTrue(app.buttons["taskGoalPicker"].label.contains("No goal"))
        app.buttons["taskGoalPicker"].tap()
        let original = app.buttons["Original goal"]; XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let useSubject = app.buttons["Use goal's subject"]
        XCTAssertTrue(useSubject.waitForExistence(timeout: 5)); useSubject.tap()
        XCTAssertTrue(app.buttons["taskSubjectPicker"].label.contains("Original course"))
        XCTAssertTrue(app.buttons["taskGoalPicker"].label.contains("Original goal"))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Goal subject conflict resolved"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testUnderstandingCanBeRatedAndReviewIsAnExplicitChoice() {
        let app = launchFresh(); createTask("Rating review", app)
        app.buttons["startFocus"].tap(); XCTAssertTrue(app.buttons["finishFocus"].waitForExistence(timeout: 5)); app.buttons["finishFocus"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Understanding")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        let rating = app.buttons["2 / 5"]; XCTAssertTrue(rating.waitForExistence(timeout: 5)); rating.tap()
        let review = app.switches["Add a 15-minute review task"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertEqual(review.value as? String, "0")
        review.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(review.value as? String, "1")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Optional rating review choice"; attachment.lifetime = .keepAlways; add(attachment)
        let save = app.buttons["saveSession"]; scrollTo(save, app); save.tap()
        let ready = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ready when you are")).firstMatch
        scrollTo(ready, app); ready.tap()
        let task = app.staticTexts["Review · Rating review"].firstMatch; scrollTo(task, app); XCTAssertTrue(task.exists)
    }
    @MainActor func testArchiveFromDetailWithoutLibraryDetourAndUndo() {
        let app=launchFresh();createTask("Archive here",app)
        let task=app.buttons.containing(.staticText,identifier:"Archive here").firstMatch
        scrollTo(task,app);task.tap()
        let archive=app.buttons["archiveTask"];scrollTo(archive,app);archive.tap()
        XCTAssertTrue(app.buttons["undoAction"].waitForExistence(timeout:5));app.buttons["undoAction"].tap()
        XCTAssertTrue(app.buttons["startFocus"].waitForExistence(timeout:5))
    }
}
