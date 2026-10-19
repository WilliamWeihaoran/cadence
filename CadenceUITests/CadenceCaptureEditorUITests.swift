#if os(iOS)
import UIKit
import XCTest

@MainActor
final class CadenceCaptureEditorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ scenario: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "capture-editor-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    private func photograph(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTodayTaskUsesCaptureCardAndKeepsRecordActions() {
        launch("today-row-crush")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Crushed title")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        row.tap()
        let title = app.textFields["capture-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["capture-save"].exists)
        XCTAssertTrue(app.buttons["capture-delete"].exists)
        XCTAssertFalse(app.buttons["capture-create"].exists)
        photograph("iPad task editing capture card")
        app.buttons["capture-delete"].tap()
        XCTAssertTrue(app.alerts["Delete Task?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        let complete = app.buttons["Complete task"]
        for _ in 0..<6 where !complete.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(complete.isHittable, app.debugDescription)
        photograph("iPad task completion and status")
        complete.tap()
        XCTAssertTrue(app.buttons["Mark task todo"].waitForExistence(timeout: 5))
        app.buttons["Mark task todo"].tap()
        for _ in 0..<6 where !app.buttons["capture-save"].isHittable { app.scrollViews.firstMatch.swipeDown() }
        app.buttons["capture-save"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
    }

    func testFixtureEventUsesReadOnlyCaptureCardWithoutCalendarAccess() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        launch("calendar-hues")
        let calendar = app.buttons.matching(NSPredicate(format: "label == %@", "Calendar")).firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), app.debugDescription)
        calendar.tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Month")).firstMatch.tap()
        let event = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Deep red event")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 10), app.debugDescription)
        event.tap()
        let title = app.textFields["capture-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(title.isEnabled)
        XCTAssertFalse(app.buttons["capture-save"].exists)
        XCTAssertFalse(app.buttons["capture-delete"].exists)
        XCTAssertTrue(app.buttons["capture-cancel"].exists)
        photograph("iPad read-only event capture card")
        app.buttons["capture-cancel"].tap()
    }
}
#endif
