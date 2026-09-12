import AppKit
import XCTest

/// **The one test in this repository that looks at the composed main window.**
///
/// Codex's inventory, 2026-09-05: of 4,431 `@Test` declarations, four exercise a running surface,
/// and all four are opt-in. No test entered full screen, populated Today with rollover tasks,
/// loaded an image note, resized its editor, or compared successive frames of a hover — which is,
/// item for item, the list of the four defects the user found that week by opening the app: a
/// flickering rollover section, a divider drawn as focused, a mis-spaced header, and text drawn
/// over a picture.
///
/// Two things that inventory also established, so they are not re-litigated here:
///
/// - `CadenceTests` is **app-hosted** (`BUNDLE_LOADER` / `TEST_HOST`). Those 4,400 tests could not
///   execute without the app; "would they pass if it never launched" is not a question.
/// - It is **not** true that nothing renders. `MarkdownEditorDrawOrderTests`,
///   `MarkdownImageSizingTests`, `MarkdownTableHostedEditingTests` and `MarkdownListSupportTests`
///   do real AppKit work offscreen, drawing into bitmaps and building an `NSWindow`. They are
///   *component* tests. What was missing is the SwiftUI composition: the window, at a real size,
///   with the panes laid out against each other.
///
/// So this is one scenario, not five sketches, and its assertions are **grouped by how much they
/// are worth** — because conflating those is how a green suite came to mean less than it looked:
///
/// 1. **Process start.** The app launched and reached the foreground. Strongest and least
///    interesting: it is a precondition, not a finding.
/// 2. **Surface existence.** Today is on screen and the seeded state reached it — the rollover
///    banner, the rows, the picture's note. Strong: an identifier either resolves or does not.
/// 3. **Geometry.** Where the accessibility tree says the boxes are, before and after a full-screen
///    resize and before and after a hover is released. Good evidence about layout, and **no
///    evidence at all about drawing** — a divider lit as focused has exactly the geometry of one
///    that is not.
/// 4. **Pixel.** What was actually painted, read back from a window screenshot. The only group that
///    can see the drawing defects, and the weakest: it can fail for a display profile, a stray
///    system window, or an appearance setting. Stated only as invariants of a fixture this test
///    planted itself. There is no golden image here and there should not be one.
///
/// ### What is not pinned yet
///
/// The **flicker** is not. A flickering section is a frame that differs from the frames either
/// side of it, and `XCUIScreenshot` samples on demand rather than per frame, so this can compare
/// *settled* states and not the transition between them. The hover comparison below catches
/// hover-state *residue* — a fill or a ring that never cleared — which is a neighbour of the
/// defect, not the defect. Filed as the open half of T-1068.
@MainActor
final class CadenceTodayCompositionUITests: XCTestCase {

    // MARK: - The two vocabularies this test shares with the app

    /// Identifiers, restated because a UI test bundle cannot import the app module.
    ///
    /// The app's copy is `CadenceAccessibilityIdentifiers`, and it is the definition; this is the
    /// mirror. Both are named so that a mismatch is one grep rather than a hunt through literals —
    /// which is the best a test-bundle boundary allows.
    private enum ID {
        static let todayDestination = "sidebar.destination.today"
        static let rolloverBanner = "today.rollover.banner"
        static let notesPane = "today.notes.pane"
        static let seededAreaRow = "sidebar.list.area.alpha-area"

        static func section(_ title: String) -> String { "today.tasks.section.\(slug(title))" }
        static func row(_ title: String) -> String { "today.task.row.\(slug(title))" }

        private static func slug(_ value: String) -> String {
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
    }

    /// The fixture, restated for the same reason. `CadenceUITestScenarioSeed.Fixture` is the
    /// definition.
    private enum Fixture {
        static let scenario = "today-geometry"
        static let hostListName = "Alpha Area"
        static let pastDoTaskNames = ["Rollover One", "Rollover Two", "Rollover Three"]
        static let overdueTaskNames = ["Overdue One", "Overdue Two"]
        static let todayTaskNames = ["Today One", "Today Two"]
        static let imageAspect: CGFloat = 500.0 / 800.0
    }

    /// Bounds this test waits on that `CadenceUITestBounds` does not already name. Both are
    /// **unmeasured** — the value the test was written with — and say so, per this target's rule
    /// that a bound nobody has measured must not borrow the credibility of one that has been.
    private enum Bounds {
        /// How long a full-screen transition may take to stop moving the window.
        static let fullScreenSettle: TimeInterval = 20
        /// How long after a mouse move before the hover state is assumed to have finished
        /// animating. The panel animates hover at 0.12–0.15s; this is an order of magnitude over.
        static let hoverSettle: TimeInterval = 1.5
        /// How long after the window has stopped moving before its contents are read. The frame
        /// settling is not the paint finishing, and the pixel group reads paint.
        static let paintAfterResize: TimeInterval = 2
    }

    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
        storeID = "ui-composition-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    func testTodayHoldsItsGeometryAndItsPictureAcrossFullScreenAndHover() throws {
        try requireInteractiveUITestsEnabled()

        // ── GROUP 1: PROCESS START ────────────────────────────────────────────────────────────
        // Precondition, not a finding. Everything below is void if this fails, which is why it is
        // separated: a suite that reports "3 passed" over a launch failure has said nothing.
        let window = XCTContext.runActivity(named: "group 1 — process start") { _ -> XCUIElement in
            launchApp()
            XCTAssertEqual(app.state, .runningForeground, "app is not in the foreground")
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: CadenceUITestBounds.firstPaint), "no main window")
            return window
        }

        // ── GROUP 2: SURFACE EXISTENCE ────────────────────────────────────────────────────────
        // Each of these is an identifier resolving against a live tree. Strong evidence, and
        // deliberately separate from geometry: an element can exist at a nonsense position.
        XCTContext.runActivity(named: "group 2 — surface existence") { _ in
            XCTAssertTrue(
                app.buttons[ID.seededAreaRow].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
                "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either"
            )
            app.buttons[ID.todayDestination].click()
            // Today is identified by what it *draws*, not by `TodayView`'s own
            // `accessibilityIdentifier("screen.today")`. That identifier produces no element:
            // measured 2026-09-06 against a full tree dump, nothing in the app answers to it,
            // because it sits on a `GeometryReader` that is not itself an accessibility element.
            // Filed under [[T-1068]].
            XCTAssertTrue(
                app.descendants(matching: .any)[ID.rolloverBanner].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
                "the rollover banner is absent, so the seeded past-do tasks did not reach Today"
            )
            for name in Fixture.overdueTaskNames + Fixture.todayTaskNames {
                XCTAssertTrue(
                    row(name).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
                    "seeded row '\(name)' is not on Today"
                )
            }
            XCTAssertTrue(
                sectionHeader(Fixture.hostListName).exists,
                "Today has no group heading for the list the fixture put its tasks in"
            )
            // The other half of the banner's contract, and the reason the seed distinguishes
            // past-do from past-due at all: while the offer is on screen the offered tasks are
            // withheld from the groups below it, because the banner is already listing them.
            for name in Fixture.pastDoTaskNames {
                XCTAssertFalse(
                    row(name).exists,
                    "'\(name)' is both in the rollover offer and in the group under it — the same row twice"
                )
            }
        }

        // ── GROUP 3: GEOMETRY, at the window's launch size ────────────────────────────────────
        let windowed = try XCTContext.runActivity(named: "group 3a — geometry, windowed") { _ in
            let snapshot = try captureGeometry()
            assertLayoutInvariants(snapshot, state: "windowed")
            return snapshot
        }

        // ── GROUP 4: PIXEL, at the window's launch size ───────────────────────────────────────
        // **Conditional, and deliberately so.** Today drops its notes column below 1092pt of pane
        // width, so at the window's launch size the picture may not be drawn at all — which is not a
        // defect and must not be reported as one. The unconditional version of this assertion runs
        // in full screen below, where the column is guaranteed.
        try XCTContext.runActivity(named: "group 4a — pixel, windowed") { _ in
            try assertFixtureImageIsUndrawnOverIfDrawnAtAll(window, state: "windowed")
        }

        // ── THE RESIZE: full screen ───────────────────────────────────────────────────────────
        // A real resize, and the one the user performs: `cmd-ctrl-f`. It is worth more than
        // dragging a corner because Today's pane composition is chosen by *pane width* —
        // `CadenceDesktopSplitLayout.todayLayout` — so full screen crosses the thresholds a
        // narrow window never reaches.
        XCTAssertTrue(toggleFullScreen(), "the window never settled at a new size after View ▸ Enter Full Screen")
        // The transition has stopped moving the window; this is the paint after it.
        settle(Bounds.paintAfterResize)

        try XCTContext.runActivity(named: "group 3b — geometry, full screen") { _ in
            let full = try captureGeometry()
            assertLayoutInvariants(full, state: "full screen")
            // **Different, not wider** — and the difference is the point. A wider *window* gives
            // Today a *narrower* task pane, because at 1092pt of pane it stops being two columns
            // and becomes three: the notes column appears and takes its minimum out of the task
            // column's share. Asserting "wider" would encode the naive expectation and fail on the
            // correct behaviour. What must be true is that the pane was laid out again.
            XCTAssertNotEqual(
                full.firstSectionHeader.width,
                windowed.firstSectionHeader.width,
                accuracy: 2,
                "the task pane is \(full.firstSectionHeader.width)pt in both states, so nothing was re-laid out"
            )
        }

        try XCTContext.runActivity(named: "group 4b — pixel, full screen") { _ in
            XCTAssertTrue(
                notesPaneIsDrawn,
                "full screen did not give Today its three-pane layout, so the note holding the picture is not on screen"
            )
            assertFixtureImageIsUndrawnOver(try bitmap(of: window), state: "full screen")
        }

        // ── THE HOVER, and its release ────────────────────────────────────────────────────────
        let beforeHover = try captureGeometry()
        let beforeHoverBitmap = try bitmap(of: window)
        // An **overdue** row, not one of the past-do ones: while the rollover banner is up,
        // `CadenceTodayRolloverSupport.groupedTasks` withholds exactly the tasks the banner is
        // offering, so `Rollover One` is deliberately not a row at this moment. Hovering something
        // that is not there would hover nothing and the comparison below would be vacuous.
        let hoverTarget = row(Fixture.overdueTaskNames[0])
        XCTAssertTrue(hoverTarget.exists, "nothing to hover")
        hoverTarget.hover()
        settle(Bounds.hoverSettle)
        let duringHoverBitmap = try bitmap(of: window)
        releaseHover()
        settle(Bounds.hoverSettle)

        try XCTContext.runActivity(named: "group 3c — geometry, after the hover was released") { _ in
            let after = try captureGeometry()
            assertLayoutInvariants(after, state: "after hover release")
            assertSameGeometry(beforeHover, after)
        }

        try XCTContext.runActivity(named: "group 4c — pixel, after the hover was released") { _ in
            let after = try bitmap(of: window)
            let region = try XCTUnwrap(
                pixelRect(of: beforeHover.rowRegion, bitmap: after),
                "could not map the task rows onto the screenshot"
            )

            // The hover must have *done* something, or the comparison after it is vacuous — a
            // test that proves a no-op reverted is a test that proves nothing. This is the guard
            // against exactly that.
            let duringDelta = CadenceUITestPixel.differingPixelCount(beforeHoverBitmap, duringHoverBitmap, in: region)
            XCTAssertNotNil(duringDelta, "the two shots are different sizes; the window moved under the comparison")
            XCTAssertGreaterThan(
                duringDelta ?? 0, 0,
                "hovering a task row changed nothing on screen, so the release comparison below proves nothing"
            )

            let releasedDelta = CadenceUITestPixel.differingPixelCount(beforeHoverBitmap, after, in: region)
            XCTAssertEqual(
                releasedDelta, 0,
                "the rows do not look the way they did before the hover — \(releasedDelta ?? -1) pixels of the "
                + "hover state survived it being released"
            )
        }

        // ── THE RESIZE BACK ───────────────────────────────────────────────────────────────────
        // Restoring is a second resize, and it is asserted separately rather than assumed
        // symmetric: the defects this exists for are not symmetric either.
        XCTAssertTrue(toggleFullScreen(), "the window never came back out of full screen")
        settle(Bounds.paintAfterResize)
        try XCTContext.runActivity(named: "group 3d — geometry, restored") { _ in
            assertLayoutInvariants(try captureGeometry(), state: "restored")
        }
        try XCTContext.runActivity(named: "group 4d — pixel, restored") { _ in
            try assertFixtureImageIsUndrawnOverIfDrawnAtAll(window, state: "restored")
        }
    }

    // MARK: - Geometry

    /// The boxes this test reasons about, read in one pass so every figure in a comparison came
    /// from the same moment.
    private struct Geometry {
        let banner: CGRect
        let firstSectionHeader: CGRect
        let rows: [(name: String, frame: CGRect)]

        /// The union of the rows, which is the region the hover comparison is asked of. Not the
        /// whole window: a window holds a clock and a blinking caret, and comparing those measures
        /// the desktop.
        var rowRegion: CGRect {
            rows.reduce(CGRect.null) { $0.union($1.frame) }
        }
    }

    /// Thrown rather than asserted, so the caller's activity name says which capture failed.
    private struct SurfaceGone: Error, CustomStringConvertible {
        let description: String
    }

    private func captureGeometry() throws -> Geometry {
        let header = sectionHeader(Fixture.hostListName)
        guard header.exists else {
            throw SurfaceGone(description: "Today's group heading is not on screen; nothing to measure against")
        }

        let names = Fixture.overdueTaskNames + Fixture.todayTaskNames
        let rows = names.compactMap { name -> (name: String, frame: CGRect)? in
            let element = row(name)
            guard element.exists else { return nil }
            return (name, element.frame)
        }
        guard !rows.isEmpty else {
            throw SurfaceGone(description: "no seeded rows are on screen")
        }

        return Geometry(
            banner: app.descendants(matching: .any)[ID.rolloverBanner].exists
                ? app.descendants(matching: .any)[ID.rolloverBanner].frame
                : .null,
            firstSectionHeader: header.frame,
            rows: rows
        )
    }

    /// The four layout facts that hold on Today at **any** width, each of them a defect found by
    /// hand this week turned into a predicate: a heading out of its rows' gutter, a heading that
    /// has collapsed onto or drifted away from its group, rows that overlap each other, and a
    /// banner that has fallen inside the groups it is offering to change.
    private func assertLayoutInvariants(_ geometry: Geometry, state: String) {
        // A heading indented away from the rows it labels — the defect
        // `CadencePageHeaderMetrics`/`TasksPanelMetrics` both carry comments about.
        for row in geometry.rows {
            XCTAssertEqual(
                geometry.firstSectionHeader.minX, row.frame.minX, accuracy: 2,
                "[\(state)] the group heading does not share the gutter of its row '\(row.name)'"
            )
        }

        // The heading's box is the same width as the rows', because both are the pane's full width
        // and the insets live inside them. A change that padded one and not the other is exactly
        // the "header indented from the rows under it" shape, and shows up here.
        for row in geometry.rows {
            XCTAssertEqual(
                geometry.firstSectionHeader.width, row.frame.width, accuracy: 2,
                "[\(state)] the group heading is not the width of its row '\(row.name)'"
            )
        }

        // A heading that has drifted off the top of its own group, or overlapped into it.
        //
        // **The gap measured on 2026-09-06 is 0, and 0 is correct.** The heading's accessibility
        // frame already contains `TasksPanelMetrics.sectionHeaderBottomInset`, so its box abuts the
        // first row's rather than standing off from it. The bound is therefore `0 ..< 24`: negative
        // means the heading has been drawn over its own rows, and 24 is a heading that has come
        // adrift from the group it names.
        if let first = geometry.rows.min(by: { $0.frame.minY < $1.frame.minY }) {
            let gap = first.frame.minY - geometry.firstSectionHeader.maxY
            XCTAssertGreaterThanOrEqual(gap, 0, "[\(state)] the heading's box overlaps its first row by \(-gap)pt")
            XCTAssertLessThanOrEqual(
                gap, 24,
                "[\(state)] there are \(gap)pt between the heading and its first row; it no longer reads as its heading"
            )
        }

        // Rows that overlap each other.
        let ordered = geometry.rows.sorted { $0.frame.minY < $1.frame.minY }
        for (above, below) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(
                above.frame.maxY, below.frame.minY + 1,
                "[\(state)] '\(above.name)' overlaps '\(below.name)'"
            )
        }

        // The banner is above the groups it is offering to change, not inside them.
        if !geometry.banner.isNull {
            XCTAssertLessThanOrEqual(
                geometry.banner.maxY, geometry.firstSectionHeader.minY + 1,
                "[\(state)] the rollover banner is no longer above Today's first group"
            )
        }
    }

    private func assertSameGeometry(_ before: Geometry, _ after: Geometry) {
        XCTAssertEqual(before.rows.count, after.rows.count, "a row appeared or vanished across the hover")
        for (b, a) in zip(before.rows, after.rows) {
            XCTAssertEqual(b.name, a.name, "the rows reordered across the hover")
            XCTAssertEqual(b.frame.minX, a.frame.minX, accuracy: 0.5, "'\(b.name)' moved horizontally across the hover")
            XCTAssertEqual(b.frame.minY, a.frame.minY, accuracy: 0.5, "'\(b.name)' moved vertically across the hover")
            XCTAssertEqual(b.frame.height, a.frame.height, accuracy: 0.5, "'\(b.name)' changed height across the hover")
        }
    }

    // MARK: - Pixel

    private func bitmap(of window: XCUIElement) throws -> CadenceUITestPixel.Bitmap {
        let width = try XCTUnwrap(currentWindowFrame(), "there is no window to screenshot").width
        return try XCTUnwrap(
            CadenceUITestPixel.Bitmap(screenshot: window.screenshot(), pointWidth: width),
            "could not read the window screenshot as pixels"
        )
    }

    /// **The picture, and nothing on top of it.**
    ///
    /// The fixture is a single flat colour, so its correct rendering is one sentence: every pixel
    /// inside its box is that colour. Text drawn over it breaks that sentence; nothing else does.
    /// The block is found by search rather than by asking where it is, because the picture is
    /// drawn inside an `NSTextView` and has no accessibility element — and giving it one would
    /// report where the layout manager *thinks* it put the image, which is the very thing under
    /// suspicion.
    private func assertFixtureImageIsUndrawnOver(_ bitmap: CadenceUITestPixel.Bitmap, state: String) {
        guard let block = CadenceUITestPixel.dominantSaturatedBlock(in: bitmap) else {
            XCTFail("[\(state)] the fixture picture is not on screen at all — no saturated block in the window")
            return
        }

        XCTAssertGreaterThan(
            block.bounds.width, 40,
            "[\(state)] the saturated block found is too small to be the picture (\(block.bounds))"
        )
        XCTAssertEqual(
            block.bounds.height / max(block.bounds.width, 1), Fixture.imageAspect, accuracy: 0.05,
            "[\(state)] the picture's box is \(block.bounds) — the wrong shape for an 800×500 image"
        )
        XCTAssertEqual(
            CadenceUITestPixel.foreignPixelCount(in: bitmap, block: block), 0,
            "[\(state)] something is drawn on top of the picture: pixels inside \(block.bounds) are not \(block.colour.description)"
        )
    }

    /// Whether Today is wide enough to be drawing its notes column at this moment.
    private var notesPaneIsDrawn: Bool {
        app.descendants(matching: .any)[ID.notesPane].exists
    }

    /// The picture assertion at a width where the notes column may legitimately be absent.
    ///
    /// Absence is **recorded, not asserted**: a conditional assertion that quietly passes when its
    /// subject is missing is the exact shape this whole ticket is about, so the condition is written
    /// into the activity log where a reader of a green run can see which states were actually
    /// checked.
    private func assertFixtureImageIsUndrawnOverIfDrawnAtAll(_ window: XCUIElement, state: String) throws {
        guard notesPaneIsDrawn else {
            XCTContext.runActivity(named: "[\(state)] no notes column at this width — the picture was not checked") { _ in }
            return
        }
        assertFixtureImageIsUndrawnOver(try bitmap(of: window), state: state)
    }

    /// An element's frame, in points on screen, expressed in the window screenshot's pixels.
    private func pixelRect(of frame: CGRect, bitmap: CadenceUITestPixel.Bitmap) -> CGRect? {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        guard let origin = currentWindowFrame()?.origin else { return nil }
        let scale = bitmap.scale
        return CGRect(
            x: (frame.minX - origin.x) * scale,
            y: (frame.minY - origin.y) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    // MARK: - Driving the window

    private func launchApp() {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: storeID)
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = Fixture.scenario
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
    }

    /// The main window's frame, or `nil` when there is no window in the tree to ask.
    ///
    /// **`nil` is a state this test met, not a defensive flourish.** Measured 2026-09-06: for part
    /// of a `cmd-ctrl-f` transition the app has **no** `Window` descendant at all, and reading
    /// `.frame` through it fails the test outright with *"No matches found for first query match
    /// sequence: `Descendants matching type Window`"*. A full-screen wait that cannot survive the
    /// window being briefly absent cannot wait for a full-screen transition.
    private func currentWindowFrame() -> CGRect? {
        let window = app.windows.firstMatch
        guard window.exists else { return nil }
        return window.frame
    }

    /// **View ▸ Enter Full Screen, not `cmd-ctrl-f`.**
    ///
    /// The keyboard shortcut was the first thing tried and it does nothing here. Measured
    /// 2026-09-06: after `app.typeKey("f", modifierFlags: [.command, .control])` the window frame
    /// was still `(60, 90, 1280, 800)` twenty seconds later, and the menu item in the tree dump
    /// taken at that moment still read *"Enter Full Screen"* — so the key was delivered and the
    /// app did not act on it, rather than the wait being too short. The menu item behind it,
    /// `toggleFullScreen:`, is present and works.
    ///
    /// The menu is also the route that survives the state it is toggling: in full screen the
    /// window's own traffic-light buttons are hidden, so `XCUIIdentifierFullScreenWindow` can take
    /// you in and cannot bring you back. One mechanism, both directions.
    private func toggleFullScreen() -> Bool {
        guard let before = currentWindowFrame() else { return false }
        let viewMenu = app.menuBars.menuBarItems["View"]
        guard viewMenu.waitForExistence(timeout: CadenceUITestBounds.settle) else { return false }
        viewMenu.click()
        let item = app.menuItems["toggleFullScreen:"]
        guard item.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            return false
        }
        item.click()
        return waitForFrameToSettle(differentFrom: before)
    }

    /// Waits for the window to have moved **and** stopped moving. Both halves matter: a single
    /// "has it changed" check catches the first frame of the animation, and every measurement
    /// after it would be of a window mid-flight.
    private func waitForFrameToSettle(differentFrom before: CGRect) -> Bool {
        let deadline = Date().addingTimeInterval(Bounds.fullScreenSettle)
        var previous = before
        var stableSince: Date?
        while Date() < deadline {
            settle(0.25)
            // A window that is not in the tree right now is the transition in progress, not a
            // verdict. Keep waiting.
            guard let current = currentWindowFrame() else {
                stableSince = nil
                continue
            }
            if current != previous {
                previous = current
                stableSince = nil
                continue
            }
            if current == before { continue }
            if let stableSince, Date().timeIntervalSince(stableSince) > 0.75 { return true }
            if stableSince == nil { stableSince = Date() }
        }
        XCTContext.runActivity(named: "the window frame never settled after cmd-ctrl-f") { _ in }
        return false
    }

    /// Moves the pointer off every row, which is the only way to end a hover: `XCUIElement.hover()`
    /// has no inverse. The sidebar's search field is used because it is a long way from the task
    /// pane and does not itself change on hover.
    private func releaseHover() {
        let neutral = app.descendants(matching: .any)["sidebar.search"]
        if neutral.exists {
            neutral.hover()
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).hover()
        }
    }

    // MARK: - Small helpers

    private func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[ID.row(name)]
    }

    private func sectionHeader(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[ID.section(title)]
    }

    /// `RunLoop`, not `sleep`: this process is driving a UI and must keep servicing its own
    /// run loop while it waits.
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func requireInteractiveUITestsEnabled() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()
    }
}
