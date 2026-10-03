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

    /// **The right-click works. This assertion did not** (T-1970, measured 2026-10-02).
    ///
    /// The test had never executed once before the owner opened the interactive gate, and on its
    /// first three executions it failed saying *the right-click opened no Edit Area panel*. It had
    /// — measured against a control reading taken immediately before the click:
    ///
    /// ```
    /// BEFORE: 0 popover(s), 0 sheet(s), 0 dialog(s)
    /// AFTER:  0 popover(s), 1 sheet(s), 0 dialog(s);
    ///         sheet 0 (546.0, 301.0, 420.0, 412.0) holds 35 descendant(s)
    ///         [group  staticText:''  image:'Move'  textField  textField
    ///          button:'Use this colour' ×11  button:'Selected colour'
    ///          button:'folder.fill'  button:'checklist'  button:'briefcase.fill' …]
    /// ```
    ///
    /// 420pt wide is `ListEditorSheetShell`'s own `.frame(width: 420)`, and the colour swatches and
    /// the icon row are `ListEditorIdentityHeader`. That sheet is the Area editor.
    ///
    /// **What it does not publish is its own name.** `ListEditorSheetShell` draws the title through
    /// `SectionEyebrowLabel`, whose body is `Text(text.uppercased()).cadenceUppercaseLabel(…)` — and
    /// the one static text the sheet publishes carries an **empty label**. A sweep of
    /// `app.descendants(matching: .any)` for anything whose label contains *edit area*, in any case,
    /// matched **nothing anywhere in the app**, so neither `"Edit Area"` nor `"EDIT AREA"` nor a
    /// case-insensitive predicate for it can ever have resolved. The uppercasing was not the
    /// problem and fixing the case did not help: measured, that spelling fails too.
    ///
    /// **Correction (T-2022):** the label was the wrong field to read. macOS static text carries
    /// its string as the accessibility *value*, and the eyebrow's value was `EDIT AREA` all along;
    /// `testEditAreaSheetPublishesItsHeadingInWords` now asserts it, in natural case. Since T-2035
    /// the eyebrow is an `AXHeading`, not a static text, and a macOS heading carries its words in
    /// the *label*; that test reads the label, type-agnostically.
    ///
    /// So this test now asserts what the panel actually is rather than what it is called: a sheet
    /// that was not there before the click, carrying the list editor's identity header. The
    /// before-reading is half the evidence — a sheet counted only afterwards could have been on
    /// screen since launch.
    func testRightClickingSidebarListOpensEditPanel() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        XCTAssertTrue(
            alphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "there is no sidebar row to right-click. \(surfaceReport())"
        )

        // The control. Without a reading from BEFORE the click, a sheet counted after it proves
        // nothing: it could have been on screen since launch.
        XCTAssertEqual(
            app.sheets.count, 0,
            "a sheet is already open before the right-click, so this test cannot attribute one to "
            + "it. \(transientReport())"
        )
        let beforeClick = transientReport()

        alphaArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the right-click opened no sheet at all.\n  BEFORE: \(beforeClick)\n  AFTER:  "
            + "\(transientReport())\n  \(surfaceReport())"
        )

        // And it is the list editor, not some other sheet: `ListEditorIdentityHeader`'s colour
        // picker publishes exactly one *Selected colour* button, next to the name field.
        XCTAssertTrue(
            sheet.buttons["Selected colour"].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the right-click opened a sheet, but not the list editor — it carries no colour picker."
            + "\n  BEFORE: \(beforeClick)\n  AFTER:  \(transientReport())"
        )
        XCTAssertGreaterThan(
            sheet.textFields.count, 0,
            "the list editor sheet publishes no text field, so its name row is not there."
            + "\n  AFTER: \(transientReport())"
        )
    }

    /// **The Edit Area sheet names itself, in words** (T-2022).
    ///
    /// `ListEditorSheetShell` draws its title through `SectionEyebrowLabel`, and the sheet's one
    /// static text read as an empty `label`. That was the wrong field, not a missing heading: a
    /// macOS SwiftUI `Text` publishes its string as the static text's **value** and never fills the
    /// label, kerned or not — measured on the accessibility tree by
    /// `CadenceEyebrowAccessibilityTests`. What the eyebrow did publish was its glyphs,
    /// `EDIT AREA`. This asserts the sheet exposes its heading once, as the words `Edit Area`.
    ///
    /// **Read by label, from any element type (T-2035).** The eyebrow now carries `.isHeader`, which
    /// SwiftUI on macOS publishes as an `AXHeading` whose string is in the label, not as a static
    /// text with a value — measured in `CadenceEyebrowAccessibilityTests`. A `staticTexts` query
    /// for `value == "Edit Area"` would now match nothing by construction.
    func testEditAreaSheetPublishesItsHeadingInWords() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
        launchApp(resetStore: true, resetDefaults: true)

        let alphaArea = app.buttons["sidebar.list.area.alpha-area"]
        XCTAssertTrue(
            alphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "there is no sidebar row to right-click. \(surfaceReport())"
        )
        alphaArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the right-click opened no sheet. \(transientReport())"
        )
        XCTAssertTrue(
            sheet.buttons["Selected colour"].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the sheet is not the list editor. \(transientReport())"
        )

        let heading = sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Edit Area"))
        XCTAssertTrue(
            heading.firstMatch.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the Edit Area sheet publishes no heading labelled 'Edit Area'. Its static texts: "
            + staticTextReport(in: sheet)
        )
        XCTAssertEqual(
            heading.count, 1,
            "the sheet's heading should be published once. Its static texts: \(staticTextReport(in: sheet))"
        )
    }

    /// Every static text under `element`, with all three strings XCUITest can read off it. A label
    /// alone cannot tell *the text is gone* from *the text is in the value*, and on macOS a SwiftUI
    /// `Text` publishes its string as the accessibility value.
    private func staticTextReport(in element: XCUIElement) -> String {
        let texts = element.staticTexts.allElementsBoundByIndex.map { text in
            "[label:'\(text.label)' value:'\(String(describing: text.value ?? ""))' title:'\(text.title)']"
        }
        return texts.isEmpty ? "none" : texts.joined(separator: " ")
    }

    /// **XCUITest cannot perform this drag, and that is a measurement rather than a guess**
    /// (T-1970, 2026-10-02).
    ///
    /// The sidebar does not reorder by a pointer gesture a SwiftUI view interprets itself.
    /// `SidebarComponents` puts `.onDrag { NSItemProvider(object: target.providerText) }` on every
    /// list row and `.onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(…))` on the rows
    /// and on the leading drop zone, so a reorder is a real AppKit `NSDraggingSession`. XCUITest's
    /// synthesised events do not start one. Measured, on an unlocked Mac with the interactive
    /// marker present, against a fully populated sidebar (thirteen identifiers, all three seeded
    /// rows), over two different gesture APIs:
    ///
    /// - `press(forDuration: 0.5, thenDragTo:)` — the two rows' frames were **byte-identical before
    ///   and after**: Alpha Area minY 377.0, Gamma Area minY 441.0, both times. Nothing moved.
    /// - `press(forDuration: 1.0, thenDragTo:, withVelocity: .slow, thenHoldForDuration: 1.0)` —
    ///   the shape an AppKit drag session needs, with a hold to promise the item and a rest at the
    ///   destination before release. **Identical frames again**, same two numbers.
    /// - `click(forDuration:thenDragTo:)` does not even run here: it fails the gesture outright with
    ///   *"Failed to not hittable (in scroll view without scrollable trait)"*.
    ///
    /// The failure is in the harness, not in the product: **nothing here has shown a defect in the
    /// sidebar's reorder.** Its two halves are covered without a pointer —
    /// `CadenceReorderCommitSurfaceTests.thesidebarListDropCommitsProperlyRatherThanSwallowingIt`
    /// holds that `reorderList` commits rather than swallowing its save, and
    /// `…acommittedRowRenumberIsInTheStore` holds that a committed renumber is in the store and not
    /// only on screen. What is uncovered is the gesture itself, and no XCUITest written against
    /// this sidebar can cover it.
    ///
    /// Skipped loudly rather than deleted or left red: T-1724's lesson is that a gate with no
    /// working key is a silence, so the reason is in the skip's own message where a run log shows
    /// it. If someone finds a gesture that does drive the drag, this body is still here to use it.
    func testSidebarListReorderPersistsAcrossRelaunch() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
        throw XCTSkip(
            "XCUITest cannot drive this reorder: the sidebar's rows reorder through an AppKit "
            + "NSDraggingSession (`.onDrag` → NSItemProvider, `.onDrop` → SidebarListDropDelegate), "
            + "and synthesised pointer events do not start one. Measured 2026-10-02 on an unlocked "
            + "Mac with the interactive marker present: two gesture shapes left both rows' frames "
            + "identical (Alpha minY 377.0, Gamma minY 441.0, before and after), and a third fails "
            + "the gesture outright. The reorder's own halves are covered by "
            + "CadenceReorderCommitSurfaceTests; only the pointer is not."
        )
    }

    /// The body this test runs when a gesture that works is found. Unreachable today, and kept
    /// compiling on purpose — a body commented out is a body that rots.
    func reorderBodyForWhenAGestureThatWorksIsFound() {
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
        XCTAssertLessThan(
            alphaArea.frame.minY, gammaArea.frame.minY,
            "the seed does not start in the order this test drags out of: \(order(alphaArea, gammaArea))"
        )

        let before = order(alphaArea, gammaArea)
        drag(gammaArea, to: alphaArea)
        XCTAssertTrue(
            waitUntil("Gamma Area moves above Alpha Area") {
                gammaArea.frame.minY < alphaArea.frame.minY
            },
            "the drag did not reorder the sidebar. Before: \(before). After: \(order(alphaArea, gammaArea)). "
            + "\(dragReport(from: gammaArea, to: alphaArea)) \(surfaceReport())"
        )

        relaunchApp(resetStore: false, resetDefaults: false)
        let relaunchedAlphaArea = app.buttons["sidebar.list.area.alpha-area"]
        let relaunchedGammaArea = app.buttons["sidebar.list.area.gamma-area"]
        XCTAssertTrue(
            relaunchedAlphaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "Alpha Area did not come back after the relaunch. \(surfaceReport())"
        )
        XCTAssertTrue(
            relaunchedGammaArea.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "Gamma Area did not come back after the relaunch. \(surfaceReport())"
        )
        XCTAssertLessThan(
            relaunchedGammaArea.frame.minY, relaunchedAlphaArea.frame.minY,
            "the reorder did not survive the relaunch: \(order(relaunchedAlphaArea, relaunchedGammaArea))"
        )
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
    /// **What the right-click opened, if anything.**
    ///
    /// `surfaceReport()` describes the window, which is the wrong half of the question here: a
    /// context menu, a popover and a sheet are all siblings of the window rather than descendants
    /// of it, so a right-click that opens a menu with no *Edit Area* in it and a right-click that
    /// opens nothing at all produce an identical window report. Counting the transient surfaces
    /// separates them.
    ///
    /// The counts are read once, after a `waitForExistence` has already expired, because
    /// `XCUIApplication`'s transient-surface counts are served stale to a spin loop — a count
    /// taken in a polling predicate can report the previous snapshot indefinitely.
    private func transientReport() -> String {
        let sheets = app.sheets.allElementsBoundByIndex.enumerated().map { index, sheet in
            let descendants = sheet.descendants(matching: .any).allElementsBoundByIndex
            let described = descendants.prefix(24).map { "\($0.elementType.rawValue):'\($0.label)'" }
            return "sheet \(index) \(sheet.frame) holds \(descendants.count) descendant(s) ["
                + described.joined(separator: " ") + "]"
        }
        return "\(app.popovers.count) popover(s), \(app.sheets.count) sheet(s), \(app.dialogs.count) dialog(s); "
            + (sheets.isEmpty ? "no sheet contents" : sheets.joined(separator: "; ")) + "."
    }

    /// Every window the app publishes, with what it says.
    ///
    /// `app.windows.firstMatch` reported a single static text — the word *Cadence* — in a run where
    /// the sidebar published thirteen identifiers, so the window the report was describing was not
    /// the window the test is about. Which window is which has to be measured, not assumed.
    private func windowReport() -> String {
        let windows = app.windows.allElementsBoundByIndex.enumerated().map { index, window in
            let texts = window.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label).filter { !$0.isEmpty }
            let id = window.identifier.isEmpty ? "<unnamed>" : window.identifier
            return "window \(index) '\(id)' \(window.frame) says [" + texts.joined(separator: " | ") + "]"
        }
        let anyEditArea = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Edit Area"))
            .allElementsBoundByIndex
            .prefix(5)
            .map { "\($0.elementType.rawValue):'\($0.label)'" }
        return (windows.isEmpty ? "no windows" : windows.joined(separator: "; "))
            + "; anything labelled 'edit area' anywhere: "
            + (anyEditArea.isEmpty ? "nothing" : anyEditArea.joined(separator: " | ")) + "."
    }

    private func surfaceReport() -> String {
        let sidebar = app.identifiers(beginningWith: "sidebar.")
        let texts = app.windows.firstMatch.staticTexts.allElementsBoundByIndex
            .prefix(12)
            .map(\.label)
            .filter { !$0.isEmpty }
        return "sidebar publishes: \(sidebar); window says: "
            + (texts.isEmpty ? "nothing at all" : texts.joined(separator: " | "))
    }

    /// **A held, slow drag — because the sidebar reorders through an AppKit dragging session.**
    ///
    /// The rows are not moved by a pointer gesture the view interprets itself.
    /// `SidebarComponents` puts `.onDrag { NSItemProvider(object: …) }` on every list row and an
    /// `.onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(…))` on the row and on the
    /// leading drop zone, so a reorder is a real `NSDraggingSession`: the press has to be held long
    /// enough for AppKit to promise the item, the travel has to be slow enough for the destination
    /// to register a drag-entered, and the pointer has to rest at the destination before the
    /// release or the drop lands on nothing.
    ///
    /// `press(forDuration:thenDragTo:)` supplies none of that — it is a press, one jump, and a
    /// release. Measured 2026-10-02 on this test's first ever execution: the two rows' frames were
    /// **identical before and after** (Alpha minY 377.0, Gamma minY 441.0, both times), so the
    /// gesture moved nothing at all rather than moving the wrong thing.
    private func drag(_ source: XCUIElement, to target: XCUIElement) {
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(
            forDuration: Bounds.dragPickUp,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: Bounds.dragSettleBeforeRelease
        )
        _ = source
        _ = target
    }

    private enum Bounds {
        /// Long enough for AppKit to begin the dragging session rather than read a click.
        static let dragPickUp: TimeInterval = 1.0
        /// The pointer rests on the destination before release, so the drop delegate has a
        /// drag-entered to answer.
        static let dragSettleBeforeRelease: TimeInterval = 1.0
    }

    /// The two rows' vertical positions, which is the whole subject of the reorder assertion.
    ///
    /// A bare `XCTAssertTrue failed` on a 15-second interactive test cannot tell *the drag did
    /// nothing* from *the drag moved the wrong row* from *the rows are not where the test thinks*,
    /// and the three have different causes. T-1724's lesson about tests that have never executed
    /// applies in full: the first run of such a test is the only chance to learn anything from it,
    /// and a message-less assertion spends that run on nothing.
    private func order(_ alpha: XCUIElement, _ gamma: XCUIElement) -> String {
        "Alpha Area minY \(describe(alpha)) / Gamma Area minY \(describe(gamma))"
    }

    private func describe(_ element: XCUIElement) -> String {
        guard element.exists else { return "absent" }
        let frame = element.frame
        guard !frame.isNull else { return "no frame" }
        return String(format: "%.1f (frame %.1f, %.1f, %.1f×%.1f)",
                      frame.minY, frame.minX, frame.minY, frame.width, frame.height)
    }

    /// The path the pointer was actually asked to travel, so a drag that did nothing can be told
    /// from a drag that was never given anywhere to go.
    private func dragReport(from source: XCUIElement, to target: XCUIElement) -> String {
        guard source.exists, target.exists else { return "drag path: a row is absent." }
        let start = source.frame
        let end = target.frame
        return String(format: "drag path: pressed (%.1f, %.1f) and dragged to (%.1f, %.1f), %.1fpt.",
                      start.midX, start.midY,
                      end.midX, end.minY + end.height * 0.35,
                      abs((end.minY + end.height * 0.35) - start.midY))
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
