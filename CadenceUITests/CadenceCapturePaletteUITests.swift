#if os(iOS)
import UIKit
import XCTest

/// T-3147: drive the tab-bar gesture, not the button's accessibility actions.
@MainActor
final class CadenceCapturePaletteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This reproduction measures the iPhone tab-bar placement.")
        }
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
        XCTAssertTrue(app.navigationBars["New task"].waitForExistence(timeout: 5),
                      "The physical tap did not open task capture. \(app.debugDescription)")
        XCTAssertTrue(app.buttons["Cancel"].exists)
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
            let openedTask = app.navigationBars["New task"].waitForExistence(timeout: 2)
            print("CAPTURE-DURATION-RESULT seconds=\(duration) openedTask=\(openedTask)")
            attach("duration-\(duration)-after")
            if openedTask {
                XCTAssertTrue(app.buttons["Cancel"].exists)
            } else {
                XCTAssertTrue(app.buttons["New Task"].isHittable,
                              "Hold ended in neither task capture nor the tab-bar surface.")
            }
            app.terminate()
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
        XCTAssertTrue(app.textFields["Event title"].waitForExistence(timeout: 5),
                      "A stationary hold and slide to the event tile did not open event capture. "
                      + "Task capture present=\(app.navigationBars["New task"].exists). \(app.debugDescription)")
        XCTAssertFalse(app.navigationBars["New task"].exists)
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
            XCTAssertFalse(app.navigationBars["New task"].exists,
                           "A stationary hold on \(label) was delivered as a task tap.")
        }
    }

    private func launchAndFindTabBarPlus() throws -> XCUIElement {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "capture-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground))
        let buttons = app.buttons.matching(identifier: "New Task")
        let plus = buttons.firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: CadenceUITestBounds.firstPaint))
        XCTAssertEqual(buttons.count, 1, "The gesture must target one identifiable button, not a guessed match.")
        XCTAssertTrue(plus.isHittable)
        XCTAssertTrue(app.buttons["Calendar"].exists)
        XCTAssertTrue(app.buttons["More"].exists)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(plus.frame.midY, screen.minY + screen.height * 0.75,
                             "The selected plus is not the phone's bottom tab-bar control.")
        return plus
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
