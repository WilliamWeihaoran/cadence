import XCTest

@MainActor
final class CadenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storeID = "ui-\(name)-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    func testLaunchesToTodayWithSeededSidebarLists() throws {
        launchApp(resetStore: true, resetDefaults: true)

        XCTAssertTrue(app.buttons["sidebar.destination.today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sidebar.list.area.alpha-area"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar.list.project.beta-project"].exists)
        XCTAssertTrue(app.buttons["sidebar.list.area.gamma-area"].exists)
    }

    func testThemeSelectionPersistsAcrossRelaunch() throws {
        try requireInteractiveUITestsEnabled()
        launchApp(resetStore: true, resetDefaults: true)

        openSettings()
        let daylightTheme = app.buttons["settings.theme.daylight"]
        daylightTheme.click()
        XCTAssertTrue(waitUntil("Daylight theme becomes active") {
            daylightTheme.value as? String == "Active"
        })

        relaunchApp(resetStore: false, resetDefaults: false)
        openSettings()
        XCTAssertEqual(app.buttons["settings.theme.daylight"].value as? String, "Active")
    }

    func testRightClickingSidebarListOpensEditPanel() throws {
        try requireInteractiveUITestsEnabled()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        XCTAssertTrue(alphaArea.waitForExistence(timeout: 5))
        alphaArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        XCTAssertTrue(app.staticTexts["Edit Area"].waitForExistence(timeout: 5))
    }

    func testSidebarListReorderPersistsAcrossRelaunch() throws {
        try requireInteractiveUITestsEnabled()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        let gammaArea = app.buttons["sidebar.list.area.gamma-area"]
        XCTAssertTrue(alphaArea.waitForExistence(timeout: 5))
        XCTAssertTrue(gammaArea.waitForExistence(timeout: 5))
        XCTAssertLessThan(alphaArea.frame.minY, gammaArea.frame.minY)

        drag(gammaArea, to: alphaArea)
        XCTAssertTrue(waitUntil("Gamma Area moves above Alpha Area") {
            gammaArea.frame.minY < alphaArea.frame.minY
        })

        relaunchApp(resetStore: false, resetDefaults: false)
        let relaunchedAlphaArea = app.buttons["sidebar.list.area.alpha-area"]
        let relaunchedGammaArea = app.buttons["sidebar.list.area.gamma-area"]
        XCTAssertTrue(relaunchedAlphaArea.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedGammaArea.waitForExistence(timeout: 5))
        XCTAssertLessThan(relaunchedGammaArea.frame.minY, relaunchedAlphaArea.frame.minY)
    }

    private func launchApp(resetStore: Bool, resetDefaults: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_STORE_ID"] = storeID
        if resetStore {
            app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        }
        if resetDefaults {
            app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func relaunchApp(resetStore: Bool, resetDefaults: Bool) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        launchApp(resetStore: resetStore, resetDefaults: resetDefaults)
    }

    private func openSettings() {
        let settings = app.buttons["sidebar.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil("Settings sidebar button is hittable") {
            settings.isHittable
        })
        settings.click()
        let daylightTheme = app.buttons["settings.theme.daylight"]
        XCTAssertTrue(daylightTheme.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil("Daylight theme button is hittable") {
            daylightTheme.isHittable
        })
    }

    private func drag(_ source: XCUIElement, to target: XCUIElement) {
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.5, thenDragTo: end)
    }

    private func requireInteractiveUITestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["CADENCE_RUN_INTERACTIVE_UI_TESTS"] == "1" else {
            throw XCTSkip("Set CADENCE_RUN_INTERACTIVE_UI_TESTS=1 to run click, context-menu, and drag UI tests.")
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        predicate: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTContext.runActivity(named: "Timed out waiting for \(description)") { _ in }
        return false
    }
}
