import XCTest

/// **What a task row does with a width it does not have enough of** — T-1432, measured on the
/// laid-out surface rather than read off the source that asks for it.
///
/// The owner filed this from a screenshot: a Today row whose title read about ten characters,
/// beside a due chip that had wrapped `51 days ago` onto three lines. The fix promoted the title
/// with `.layoutPriority(1)`, folded the four trailing chips into one `ViewThatFits`, and gave the
/// due chip `.lineLimit(1)`.
///
/// ### Why this is not a slower copy of the test that already exists
///
/// `CadenceTasksPanelMetricsTests.theRowsTitleIsLaidOutBeforeItsMetadata` pins the same fix and
/// says so honestly in its own comment: *"Source-scanned because SwiftUI's stack allocation is not
/// reachable from a unit test: there is no seam that reports which subview won the width."* It
/// therefore fails on exactly one event — someone deleting a modifier — and it is **green for every
/// layout the modifiers are present for**. That is a correlate of the defect, not the defect:
///
/// - `.layoutPriority(1)` on a child of an `HStack` does not guarantee the child gets width. It
///   orders the allocation. A later `.frame(maxWidth:)`, a `.fixedSize` on a sibling, a padding
///   that grows, or one more chip added outside the `ViewThatFits` all re-crush the title with
///   every one of the source scan's needles still in the file.
/// - `.lineLimit(1)` on the due chip's `Text` is one of two reasons the chip could be three lines
///   tall. The other is the chip being given a width it cannot draw in, and no scan of the chip's
///   own body can see that.
///
/// So the reading here is **geometry**: four frames off the accessibility tree, in points, of a
/// window that really laid itself out. Group 3 in `CadenceTodayCompositionUITests`' scale — good
/// evidence about layout, no evidence at all about drawing, and deliberately not group 4. Nothing
/// below screenshots anything.
///
/// ### Why every figure is a comparison
///
/// A title width in points is not portable. It depends on the system font, the display, the Xcode
/// major the app was built with — and this project builds on two (T-1279, T-1296). So no assertion
/// below names a number of points. Each one compares two elements measured **in the same window at
/// the same instant**, and the fixture plants the second element for exactly that purpose: two
/// rows, the same title length, differing only in what trails the title. That is the same
/// discipline `CadenceUITestPixelSupport` states for pixels — *an invariant of a fixture the test
/// itself planted* — applied to points.
///
/// ### Not gated behind the interactive opt-in
///
/// It clicks nothing, drags nothing and hovers nothing. The app launches to `.today`
/// (`macOSRootView.selection`) and the launch resets defaults, so the rows are on screen by the
/// time the window is. It still refuses a locked screen, because nothing in this target can launch
/// through one.
@MainActor
final class CadenceTodayRowCrushUITests: XCTestCase {

    /// Identifiers, restated because a UI-test bundle cannot import the app module.
    /// `CadenceAccessibilityIdentifiers` is the definition; this is the mirror.
    private enum ID {
        static let seededAreaRow = "sidebar.list.area.alpha-area"

        static func row(_ title: String) -> String { "today.task.row.\(slug(title))" }
        static func title(_ title: String) -> String { "task.row.\(slug(title)).title" }
        static func dueChip(_ title: String) -> String { "task.row.\(slug(title)).due" }

        private static func slug(_ value: String) -> String {
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
    }

    /// The fixture, restated. `CadenceUITestScenarioSeed.Fixture` is the definition.
    private enum Fixture {
        static let scenario = "today-row-crush"
        static let tail = " title that has to keep the majority of its own row, at a length no task pane on this machine can draw in full"
        static let crushedTitle = "Crushed" + tail
        static let bareTitle = "Control" + tail
    }

    /// The two bounds this test asserts against, and what each is worth.
    private enum Bound {
        /// **The majority rule.** The decorated row's title must be more than this share of the
        /// width the *same* title got with nothing trailing it.
        ///
        /// **Not measured on the running surface.** This target's rule is that a bound nobody has
        /// timed says so rather than borrowing the credibility of one that has been
        /// (`CadenceUITestBounds`), and the first run of this test could not be made: the Mac's
        /// screen was locked, `scripts/xcb.sh` refused, and a bound is not something to invent a
        /// number for afterwards. What *is* known is the reading the defect produced — the owner's
        /// screenshot is a title of about ten characters against a pane that drew the same string
        /// in full, so roughly **0.1** — and the reading the fix is arguing for, which is a title
        /// that keeps everything the metadata strip does not need.
        ///
        /// A half is therefore not a measurement rounded; it is the sentence *the decoration may
        /// cost the title some of its width and may not take most of it*, which is the smallest
        /// claim that still refuses the screenshot. **Do not raise it to chase a red run**: a run
        /// that comes in near 0.5 is a row whose decoration has grown, which is this defect
        /// returning by a different route. The activity log prints the measured share on every
        /// run, so the first green run is where the real figure gets written down.
        static let titleShareOfTheUndecoratedTitle: CGFloat = 0.5

        /// **The one-line rule.** The due chip's box, against one line of the title beside it.
        ///
        /// **Not measured on the running surface either**, for the same reason. It does not need
        /// to be, and that is the difference between this bound and the one above: the chip draws
        /// at `CadenceTaskRowMetrics.desktop.secondaryFontSize` with
        /// `CadenceTaskChipPadding.desktopVertical` either side of it, and the title line beside it
        /// is `titleFontSize`, which is larger. One line of chip is therefore *below* one title
        /// line whatever the fonts resolve to, and the wrap that filed this was three lines. Any
        /// cut between 1 and 3 states the same fact; 2 is the middle of it.
        ///
        /// Stated in title-lines rather than points so it survives a font, a display and an Xcode
        /// major — this project builds on two.
        static let dueChipHeightInTitleLines: CGFloat = 2
    }

    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
        storeID = "ui-row-crush-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    func testACrowdedTodayRowGivesItsTitleTheWidthAndKeepsItsDueChipToOneLine() throws {
        launchApp()

        XCTAssertTrue(
            app.buttons[ID.seededAreaRow].waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either"
        )

        let crushedRow = element(ID.row(Fixture.crushedTitle))
        let bareRow = element(ID.row(Fixture.bareTitle))
        XCTAssertTrue(
            crushedRow.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the decorated seeded row is not on Today"
        )
        XCTAssertTrue(bareRow.exists, "the undecorated control row is not on Today, so there is nothing to compare against")

        let crushedTitle = descendant(ID.title(Fixture.crushedTitle), of: crushedRow)
        let bareTitle = descendant(ID.title(Fixture.bareTitle), of: bareRow)
        XCTAssertTrue(crushedTitle.exists, "the decorated row's title element is not addressable")
        XCTAssertTrue(bareTitle.exists, "the control row's title element is not addressable")

        let dueChip = descendant(ID.dueChip(Fixture.crushedTitle), of: crushedRow)
        XCTAssertTrue(dueChip.exists, "the decorated row is drawing no due chip, so the chip assertions below are vacuous")
        XCTAssertFalse(
            descendant(ID.dueChip(Fixture.bareTitle), of: bareRow).exists,
            "the control row has a due chip too — the two rows no longer differ in what trails the title"
        )

        let crushedTitleFrame = crushedTitle.frame
        let bareTitleFrame = bareTitle.frame
        let dueChipFrame = dueChip.frame
        let crushedRowFrame = crushedRow.frame
        let bareRowFrame = bareRow.frame

        // Every figure this test reasoned about, in the run log, so a reader of a red run does not
        // have to re-derive them and a reader of a green one can see the margin.
        XCTContext.runActivity(
            named: """
            measured — row \(Int(crushedRowFrame.width))pt; title crushed \(Int(crushedTitleFrame.width))pt \
            / bare \(Int(bareTitleFrame.width))pt = \(String(format: "%.2f", crushedTitleFrame.width / max(bareTitleFrame.width, 1))); \
            due chip \(Int(dueChipFrame.height))pt against a \(Int(crushedTitleFrame.height))pt title line; \
            row heights \(Int(crushedRowFrame.height)) / \(Int(bareRowFrame.height))
            """
        ) { _ in }

        // ── NON-VACUITY ───────────────────────────────────────────────────────────────────────
        // The comparison means nothing unless the decoration actually cost the title something. If
        // these two were equal the fixture would have stopped crowding the row, and every bound
        // below would pass on a row that was never under pressure.
        XCTAssertGreaterThan(bareTitleFrame.width, 0, "the control row's title has no width")
        XCTAssertLessThan(
            crushedTitleFrame.width, bareTitleFrame.width,
            "the decorated row's title is as wide as the undecorated one's, so nothing is trailing it and "
            + "this fixture no longer reproduces the state T-1432 is about"
        )
        // And the title must be under pressure at all: a title that fits has no majority to lose.
        // Both are seeded far longer than any pane, so both are truncated — which shows up as the
        // title not filling the row it is in.
        XCTAssertLessThan(
            bareTitleFrame.width, bareRowFrame.width,
            "the control row's title fills its whole row, so the seeded title is short enough to fit and "
            + "the fixture is not crowding anything"
        )

        // ── THE MAJORITY RULE ─────────────────────────────────────────────────────────────────
        // The defect, stated as a number. Under it the title collapsed to roughly a tenth of what
        // the same string got with room; the decoration may cost the title width and may not take
        // most of it.
        XCTAssertGreaterThan(
            crushedTitleFrame.width,
            bareTitleFrame.width * Bound.titleShareOfTheUndecoratedTitle,
            "the decorated row's title is \(Int(crushedTitleFrame.width))pt where the same title with nothing "
            + "beside it got \(Int(bareTitleFrame.width))pt — the metadata is taking the row from its title again"
        )

        // ── THE ONE-LINE RULE ─────────────────────────────────────────────────────────────────
        XCTAssertGreaterThan(crushedTitleFrame.height, 0, "the title has no height to measure the chip against")
        XCTAssertLessThan(
            dueChipFrame.height,
            crushedTitleFrame.height * Bound.dueChipHeightInTitleLines,
            "the due chip is \(Int(dueChipFrame.height))pt tall beside a \(Int(crushedTitleFrame.height))pt "
            + "title line — it has wrapped onto more than one line again"
        )

        // The same fact from the row's side, and it is a *different* assertion: a chip can wrap
        // inside a row that clips it, and then only the row's height says so. The bare row is the
        // height of a row with no chip at all, so anything beyond one extra title line of
        // difference is the wrap pushing the row open.
        XCTAssertLessThan(
            crushedRowFrame.height,
            bareRowFrame.height + crushedTitleFrame.height,
            "the decorated row is \(Int(crushedRowFrame.height))pt against the control row's "
            + "\(Int(bareRowFrame.height))pt — something inside it took more than one line"
        )

        // ── AND THE ROW IS STILL A ROW ────────────────────────────────────────────────────────
        // Cheap, and it catches the fix's own failure mode in the other direction: a title given
        // `.layoutPriority(1)` with nothing to yield to it can push its neighbours out of the row.
        XCTAssertLessThanOrEqual(
            dueChipFrame.maxX, crushedRowFrame.maxX + 1,
            "the due chip is drawn past the right edge of its own row"
        )
        XCTAssertGreaterThanOrEqual(
            dueChipFrame.minX, crushedTitleFrame.maxX - 1,
            "the due chip and the title overlap"
        )
    }

    // MARK: - Small helpers

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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Scoped to the row on purpose. `MacTaskRow` is drawn by Today *and* by a list's detail pane
    /// from one call site, so `task.row.…` identifiers are not Today's alone; asking the row for
    /// them is what makes this a reading of Today.
    private func descendant(_ identifier: String, of row: XCUIElement) -> XCUIElement {
        row.descendants(matching: .any)[identifier]
    }
}
