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
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Crushed title")).firstMatch
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
        let card = app.otherElements["capture-card"]
        let editorScroll = app.scrollViews.containing(.any, identifier: "capture-card").firstMatch
        let complete = card.buttons["Complete task"]
        for _ in 0..<6 where !complete.isHittable { editorScroll.swipeUp() }
        XCTAssertTrue(complete.isHittable, app.debugDescription)
        photograph("iPad task completion and status")
        complete.tap()
        XCTAssertTrue(card.buttons["Mark task todo"].waitForExistence(timeout: 5))
        card.buttons["Mark task todo"].tap()
        for _ in 0..<6 where !app.buttons["capture-save"].isHittable { editorScroll.swipeDown() }
        app.buttons["capture-save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let create = app.buttons["New Task"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(app.buttons["capture-create"].waitForExistence(timeout: 5))
        photograph("iPad creation card primary arrow")
        app.buttons["capture-set-doDate"].tap()
        let datePopover = app.popovers.firstMatch
        let untimed = datePopover.switches["Without time"]
        XCTAssertTrue(untimed.waitForExistence(timeout: 5), app.debugDescription)
        untimed.tap()
        let done = datePopover.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(datePopover.waitForNonExistence(timeout: 5))
        let timedDay = app.buttons["capture-chip-doDate"]
        XCTAssertTrue(timedDay.waitForExistence(timeout: 5))
        XCTAssertTrue(timedDay.label.contains(" · "), timedDay.label)
        photograph("iPad capture time adopts today")
        app.buttons["capture-cancel"].tap()
    }

    func testFixtureEventUsesCaptureCardWithoutCalendarAccess() {
        launch("calendar-hues")
        let calendar = app.buttons.matching(NSPredicate(format: "label == %@", "Calendar")).firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), app.debugDescription)
        if !calendar.isHittable {
            let sidebar = app.buttons["Show Sidebar"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5), app.debugDescription)
            sidebar.tap()
        }
        calendar.tap()
        let hideSidebar = app.buttons["Hide Sidebar"]
        if hideSidebar.isHittable { hideSidebar.tap() }
        let month = app.buttons.matching(NSPredicate(format: "label == %@", "Month")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<3 where !month.isSelected { month.tap() }
        XCTAssertTrue(month.isSelected, app.debugDescription)
        let event = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Deep red event")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 10), app.debugDescription)
        event.tap()
        let title = app.textFields["capture-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(title.isEnabled)
        XCTAssertTrue(app.buttons["capture-save"].exists)
        XCTAssertFalse(app.buttons["capture-save"].isEnabled)
        XCTAssertTrue(app.buttons["capture-delete"].exists)
        XCTAssertTrue(app.staticTexts["No writable calendars are available."].exists)
        XCTAssertTrue(app.buttons["capture-cancel"].exists)
        photograph("iPad event capture card without writable calendars")
        app.buttons["capture-cancel"].tap()
    }
}
#endif
