import XCTest

/// **The interactive gate here is the shared one, and was not always** (T-1724).
///
/// Until 2026-09-30 this file carried a private `requireInteractiveUITestsEnabled` that read
/// `CADENCE_RUN_INTERACTIVE_UI_TESTS` and nothing else — the one channel
/// `CadenceUITestEnvironment` was written to record as **undeliverable** to the macOS UI-test
/// runner, which is sandboxed into its own container and never sees a caller's environment. So the
/// two tests below could not be enabled by any invocation: with the marker file touched the target
/// ran 7 tests / 2 skipped, and those two were the skips. They had never executed once.
///
/// A gate with no working key is not a gate, it is a silence. The rule this leaves behind: there is
/// exactly one interactive opt-in in this target, `CadenceUITestEnvironment.requireInteractiveUITests()`,
/// and a per-suite copy of it is the defect rather than a convenience.
@MainActor
final class CadenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
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

        XCTAssertTrue(
            app.buttons["sidebar.destination.today"].waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the sidebar's Today destination never appeared. \(surfaceReport())"
        )
        XCTAssertTrue(
            app.buttons["sidebar.list.area.alpha-area"].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's first list never appeared. \(surfaceReport())"
        )
        XCTAssertTrue(app.buttons["sidebar.list.project.beta-project"].exists, "seeded project row absent. \(surfaceReport())")
        XCTAssertTrue(app.buttons["sidebar.list.area.gamma-area"].exists, "seeded second area row absent. \(surfaceReport())")
    }

    func testRightClickingSidebarListOpensEditPanel() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        XCTAssertTrue(
            alphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "there is no sidebar row to right-click. \(surfaceReport())"
        )
        alphaArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        XCTAssertTrue(
            app.staticTexts["Edit Area"].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the right-click opened no Edit Area panel. \(surfaceReport())"
        )
    }

    func testSidebarListReorderPersistsAcrossRelaunch() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        let gammaArea = app.buttons["sidebar.list.area.gamma-area"]
        XCTAssertTrue(
            alphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "there is no first sidebar row to drag. \(surfaceReport())"
        )
        XCTAssertTrue(
            gammaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "there is no second sidebar row to drag onto. \(surfaceReport())"
        )
        XCTAssertLessThan(alphaArea.frame.minY, gammaArea.frame.minY)

        drag(gammaArea, to: alphaArea)
        XCTAssertTrue(waitUntil("Gamma Area moves above Alpha Area") {
            gammaArea.frame.minY < alphaArea.frame.minY
        })

        relaunchApp(resetStore: false, resetDefaults: false)
        let relaunchedAlphaArea = app.buttons["sidebar.list.area.alpha-area"]
        let relaunchedGammaArea = app.buttons["sidebar.list.area.gamma-area"]
        XCTAssertTrue(relaunchedAlphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow))
        XCTAssertTrue(relaunchedGammaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow))
        XCTAssertLessThan(relaunchedGammaArea.frame.minY, relaunchedAlphaArea.frame.minY)
    }

    private func launchApp(resetStore: Bool, resetDefaults: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: storeID)
        if resetStore {
            app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        }
        if resetDefaults {
            app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        }
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
    }

    private func relaunchApp(resetStore: Bool, resetDefaults: Bool) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: CadenceUITestBounds.settle))
        launchApp(resetStore: resetStore, resetDefaults: resetDefaults)
    }

    /// **What the window is actually showing**, for a failure message that would otherwise be the
    /// bare word `XCTAssertTrue failed`.
    ///
    /// Every assertion in this file was written without one, which cost this suite a whole run
    /// when it went red: *the Today destination is absent* and *the app is on a different screen
    /// entirely* have the same symptom and different causes, and neither the run log nor the
    /// `.xcresult` says which. The sidebar's identifiers, plus the window's first few static
    /// texts, tell them apart in one line.
    private func surfaceReport() -> String {
        let sidebar = app.identifiers(beginningWith: "sidebar.")
        let texts = app.windows.firstMatch.staticTexts.allElementsBoundByIndex
            .prefix(12)
            .map(\.label)
            .filter { !$0.isEmpty }
        return "sidebar publishes: \(sidebar); window says: "
            + (texts.isEmpty ? "nothing at all" : texts.joined(separator: " | "))
    }

    private func drag(_ source: XCUIElement, to target: XCUIElement) {
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.5, thenDragTo: end)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = CadenceUITestBounds.settle,
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
