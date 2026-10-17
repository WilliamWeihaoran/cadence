#if os(iOS)
import UIKit
import XCTest

/// T-3147: drive the tab-bar gesture, not the button's accessibility actions.
/// T-3195: verify the shared capture card's layout and field transitions on phone and iPad.
@MainActor
final class CadenceCapturePaletteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testCoordinateTapOpensTaskCapture() throws {
        let plus = try launchAndFindTabBarPlus()
        attach("tap-before")
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        attach("tap-after")
        XCTAssertTrue(app.textFields["capture-title"].waitForExistence(timeout: 5),
                      "The physical tap did not open task capture. \(app.debugDescription)")
        XCTAssertTrue(app.buttons["capture-cancel"].exists)
    }

    /// Measures delivered hold durations, not XCTest command scheduling latency.
    /// Mid-touch visibility must be checked in the accompanying screen recording.
    func testHoldDurationSweepRecordsTapOrPaletteResolution() throws {
        for duration in [0.1, 0.25, 0.4, 0.6, 0.9, 1.2] {
            let plus = try launchAndFindTabBarPlus()
            attach("duration-\(duration)-before")
            print("CAPTURE-DURATION-BEGIN seconds=\(duration) epoch=\(Date().timeIntervalSince1970)")
            plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: duration)
            let openedTask = app.textFields["capture-title"].waitForExistence(timeout: 2)
            print("CAPTURE-DURATION-RESULT seconds=\(duration) openedTask=\(openedTask)")
            attach("duration-\(duration)-after")
            if openedTask {
                XCTAssertTrue(app.buttons["capture-cancel"].exists)
            } else {
                XCTAssertTrue(app.buttons["New Task"].isHittable,
                              "Hold ended in neither task capture nor the tab-bar surface.")
            }
            app.terminate()
        }
    }

    /// Provision only our private directories; offline SwiftData fixtures replace these stores
    /// while the app is stopped, before the separate measurement test is run.
    func testPrepareLoadMeasurementStoreDirectories() throws {
        try requireLargeStoreMeasurement()
        for count in [0, 100, 2_000] {
            _ = try launchAndFindTabBarPlus(storeID: loadStoreID(count))
            print("CAPTURE-LOAD-PREPARED count=\(count) storeID=\(loadStoreID(count))")
            app.terminate()
        }
    }

    func testLargeStoreHoldSweepOnIndexAndTaskList() throws {
        try requireLargeStoreMeasurement()
        for count in [0, 100, 2_000] {
            _ = try launchAndFindTabBarPlus(storeID: loadStoreID(count))
            if count > 0 {
                XCTAssertTrue(app.buttons.matching(CadenceUITestQuery.identifying("Tasks, \(count) open tasks"))
                    .firstMatch.waitForExistence(timeout: 5),
                              "The app did not load the verified fixture population")
            }
            for page in ["index", "task-list"] {
                if page == "task-list" {
                    let screen = app.windows.firstMatch.frame
                    let rows = app.buttons.matching(NSPredicate(
                        format: "label == %@ OR label BEGINSWITH %@", "Tasks", "Tasks, "
                    )).allElementsBoundByIndex.filter {
                        $0.isHittable && $0.frame.midY < screen.minY + screen.height * 0.75
                    }
                    XCTAssertEqual(rows.count, 1, "No unique Tasks destination above the tab bar")
                    try XCTUnwrap(rows.first).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    XCTAssertTrue(app.buttons["All"].waitForExistence(timeout: 5))
                    attach("load-\(count)-task-list-entry")
                    if count > 0 {
                        let task = app.descendants(matching: .any).matching(NSPredicate(
                            format: "label CONTAINS %@", "Capture load task 0"
                        )).firstMatch
                        XCTAssertTrue(task.waitForExistence(timeout: 5), "The seeded task list is not rendered")
                        XCTAssertTrue(task.isHittable, "A seeded row must actually be visible")
                    }
                }
                attach("load-\(count)-\(page)-before")
                for duration in [0.1, 0.25, 0.4, 0.6, 0.9, 1.2] {
                    let plus = app.buttons["New Task"]
                    XCTAssertTrue(plus.isHittable)
                    print("CAPTURE-LOAD-BEGIN count=\(count) page=\(page) seconds=\(duration) epoch=\(Date().timeIntervalSince1970)")
                    plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: duration)
                    let openedTask = app.textFields["capture-title"].waitForExistence(timeout: 2)
                    print("CAPTURE-LOAD-RESULT count=\(count) page=\(page) seconds=\(duration) openedTask=\(openedTask)")
                    attach("load-\(count)-\(page)-\(duration)-after")
                    if openedTask {
                        app.buttons["capture-cancel"].tap()
                        XCTAssertTrue(app.buttons["New Task"].waitForExistence(timeout: 5))
                    } else {
                        XCTAssertTrue(plus.isHittable)
                    }
                }
            }
            app.terminate()
        }
    }

    private func loadStoreID(_ count: Int) -> String {
        "codex-t3147-load-20261012-\(count)"
    }

    private func requireLargeStoreMeasurement() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-t3147-large-store-opt-in")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Large-store measurement requires verified offline fixtures and opt-in at \(marker.path)")
        }
    }

    func testStationaryHoldThenSlideUpReachesEventCapture() throws {
        let plus = try launchAndFindTabBarPlus()
        let start = plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Shipping bottom-centre event tile: index 1 of three, 90 degrees, radius 92pt.
        let event = start.withOffset(CGVector(dx: 0, dy: -92))
        attach("hold-before")
        print("CAPTURE-HOLD-BEGIN epoch=\(Date().timeIntervalSince1970) frame=\(plus.frame)")
        start.press(forDuration: 1.2, thenDragTo: event, withVelocity: .slow, thenHoldForDuration: 0.8)
        print("CAPTURE-HOLD-END epoch=\(Date().timeIntervalSince1970)")
        attach("hold-slide-after")
        XCTAssertTrue(app.textFields["capture-title"].waitForExistence(timeout: 5),
                      "A stationary hold and slide to the event tile did not open event capture. "
                      + "Capture present=\(app.textFields["capture-title"].exists). \(app.debugDescription)")
        XCTAssertTrue(app.segmentedControls["capture-kind"].buttons["Event"].isSelected)
    }

    /// The recording, not this post-release assertion, measures mid-hold visibility.
    func testStationaryHoldsOnEveryPhoneTabDoNotBecomeTaskTaps() throws {
        _ = try launchAndFindTabBarPlus()
        for label in ["Tasks", "Calendar", "Notes", "More"] {
            let screen = app.windows.firstMatch.frame
            let tabs = app.buttons.matching(identifier: label).allElementsBoundByIndex.filter {
                $0.isHittable && $0.frame.midY > screen.minY + screen.height * 0.75
            }
            XCTAssertEqual(tabs.count, 1, "No unique visible bottom tab for \(label)")
            let tab = try XCTUnwrap(tabs.first)
            tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let plus = app.buttons["New Task"]
            XCTAssertTrue(plus.waitForExistence(timeout: CadenceUITestBounds.firstPaint))
            XCTAssertTrue(plus.isHittable)
            attach("\(label)-stationary-before")
            print("CAPTURE-STATIONARY-BEGIN tab=\(label) epoch=\(Date().timeIntervalSince1970) frame=\(plus.frame)")
            plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
            print("CAPTURE-STATIONARY-END tab=\(label) epoch=\(Date().timeIntervalSince1970)")
            attach("\(label)-stationary-after")
            XCTAssertFalse(app.textFields["capture-title"].exists,
                           "A stationary hold on \(label) was delivered as a task tap.")
        }
    }

    private func launchAndFindTabBarPlus(storeID: String = "capture-\(UUID().uuidString)") throws -> XCUIElement {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This reproduction measures the iPhone tab-bar placement.")
        }
        let plus = try launchAndFindCapturePlus(storeID: storeID)
        XCTAssertTrue(app.buttons["Calendar"].exists)
        XCTAssertTrue(app.buttons["More"].exists)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(plus.frame.midY, screen.minY + screen.height * 0.75,
                             "The selected plus is not the phone's bottom tab-bar control.")
        return plus
    }

    private func launchAndFindCapturePlus(storeID: String = "capture-card-\(UUID().uuidString)") throws -> XCUIElement {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: storeID)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground))
        let buttons = app.buttons.matching(identifier: "New Task")
        let plus = buttons.firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: CadenceUITestBounds.firstPaint))
        XCTAssertEqual(buttons.count, 1, "The gesture must target one identifiable button, not a guessed match.")
        XCTAssertTrue(plus.isHittable)
        return plus
    }

    /// Runs on both standing devices; the same icons and chips must survive either layout.
    func testFloatingCaptureCardShrinksItsIconRowAndRestoresAClearedDueDate() throws {
        let plus = try launchAndFindCapturePlus()
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let title = app.textFields["capture-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-cancel"].isHittable)
        XCTAssertTrue(app.segmentedControls["capture-kind"].buttons["Task"].isSelected)
        XCTAssertFalse(app.staticTexts["None"].exists)
        let window = app.windows.firstMatch.frame
        let card = app.otherElements["capture-card"]
        XCTAssertTrue(card.exists)
        XCTAssertLessThan(card.frame.height, window.height * 0.8, "Capture is a card, not a full-screen form")
        XCTAssertGreaterThan(card.frame.minX, window.minX)
        XCTAssertLessThan(card.frame.maxX, window.maxX)
        attach("capture-card-empty")

        let due = app.buttons["capture-set-dueDate"]
        XCTAssertTrue(due.isHittable)
        let list = app.buttons["capture-set-list"]
        let tags = app.buttons["capture-set-tags"]
        XCTAssertLessThan(due.frame.minX, list.frame.minX)
        XCTAssertLessThan(list.frame.minX, tags.frame.minX)
        due.tap()
        XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5))
        app.buttons["Tomorrow"].tap()
        app.buttons["Done"].tap()
        let chip = app.buttons["capture-chip-dueDate"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertFalse(due.exists)
        XCTAssertLessThan(list.frame.minX, tags.frame.minX)
        attach("capture-card-due-chip")
        chip.tap()
        XCTAssertTrue(app.buttons["Clear Due"].waitForExistence(timeout: 5))
        app.buttons["Clear Due"].tap()
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertFalse(chip.exists)
        XCTAssertLessThan(due.frame.minX, list.frame.minX)
        attach("capture-card-cleared")

        app.buttons["capture-more"].tap()
        XCTAssertTrue(app.buttons["Repeat"].waitForExistence(timeout: 5))
        app.buttons["Repeat"].tap()
        XCTAssertTrue(app.buttons["Weekly"].waitForExistence(timeout: 5))
        app.buttons["Weekly"].tap()
        XCTAssertTrue(app.buttons["capture-chip-repeatRule"].waitForExistence(timeout: 5))
        attach("capture-card-repeat-chip")

        title.tap()
        title.typeText("Capture mode round trip")
        app.segmentedControls["capture-kind"].buttons["Event"].tap()
        XCTAssertTrue(app.segmentedControls["capture-kind"].buttons["Event"].isSelected)
        XCTAssertEqual(title.value as? String, "Capture mode round trip")
        attach("capture-card-event")
        app.segmentedControls["capture-kind"].buttons["Task"].tap()
        XCTAssertTrue(app.buttons["capture-chip-repeatRule"].exists)
        XCTAssertTrue(app.buttons["capture-set-doDate"].exists, "Visiting Event must not schedule the task")
        XCTAssertEqual(title.value as? String, "Capture mode round trip")
        attach("capture-card-task-restored")
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
#endif
