// **macOS only — T-2074/T-2075.** Until this target was asked to build for an iOS Simulator it
// had no platform guards at all, because it had never been built for anything but macOS: it reaches
// AppKit, `XCUIElement.rightClick()`, `CGSessionCopyCurrentDictionary` and identifiers only the
// desktop surface publishes. The guard is here rather than around the individual call sites because
// nothing in this file is about iOS; the iOS half of the target is `CadenceIOSSeededStoreUITests`.
#if os(macOS)
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
/// ### What it caught on its first run, and what it did not
///
/// Everything above is the case for this file, and it was written before the file had ever run.
/// The first three runs it was able to make (2026-09-29, T-1488) refuted half of it, so the record
/// is here rather than in the ledger alone:
///
/// - **Deleting `.layoutPriority(1)` from the title, and deleting the due chip's `.lineLimit(1)`,
///   each left every figure below byte-identical** — both compiled, both relinked and re-signed the
///   app, and the row still came out 342pt with a 143 / 232 title. The layout does not depend on
///   either modifier at the width this test launches to, most plausibly because every
///   `metadataStrip` variant is `.fixedSize(horizontal: true, vertical: false)`: a fixed-width
///   sibling does not contend for width with a flexible one, so the priority has nothing to order.
///   **The source scan refuses both of those and this test refuses neither** ([[T-1721]]) — the
///   exact inverse of the paragraph above. So the scan is not a slower duplicate of this file and
///   is **not to be deleted on the strength of this file existing**.
/// - **The defect itself passed.** A `.frame(width: 40)` pinned on the title gave crushed 36pt /
///   bare 39pt = **0.92** against the majority rule's 0.5, and the run was green: a ten-character
///   title in a 342pt row, which is character for character the owner's screenshot in T-1432. The
///   scan was green through it too, because nothing it greps for had moved. **Neither test caught
///   the defect either test exists for** ([[T-1720]]). `Bound.titleShareOfItsOwnRow` below is the
///   repair, and it is the assertion that makes this file worth its nine seconds.
///
/// The division of labour, stated rather than implied: the scan refuses the **removal of the fix's
/// modifiers**, this file refuses a **title that lost its own row, however it lost it**. Neither
/// subsumes the other, and a change only one of them catches is the normal case, not a bug in the
/// other.
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
        /// The control for the row above: a sidebar destination **no seed creates**, so its absence
        /// means the launch drew nothing rather than that the seed failed. See T-1954 / T-2020.
        static let todayDestinationControl = "sidebar.destination.today"

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
        /// **Measured 2026-09-29** (T-1488), on the first three runs this test was ever able to
        /// make — the screen was locked for the whole of the run that wrote it, so until then the
        /// figure below did not exist. Three consecutive runs on this Mac, Xcode 27.0, default
        /// window: **crushed 143pt / bare 232pt = 0.62**, in a 342pt row. Byte-identical all three
        /// times; the variation across runs is zero, not small.
        ///
        /// **The bound stays at 0.5, and the measurement is not a reason to move it.** What the
        /// defect produced is the other end of this scale — the owner's screenshot is a title of
        /// about ten characters against a pane that drew the same string in full, so roughly
        /// **0.1**. A half is not a measurement rounded; it is the sentence *the decoration may
        /// cost the title some of its width and may not take most of it*, which is the smallest
        /// claim that still refuses the screenshot. Raising it toward 0.62 would convert a
        /// statement about the defect into a pin on today's chip inventory, and the next chip
        /// added to the metadata strip would then fail this test for being a chip rather than for
        /// crushing anything.
        ///
        /// **Do not raise it to chase a red run**, and read a future run that comes in near 0.5 as
        /// the finding it is: the margin here is 0.12, so the strip would have to take roughly
        /// another 28pt of a 342pt row before this fires. That is a row whose decoration has
        /// grown, which is this defect returning by a different route.
        static let titleShareOfTheUndecoratedTitle: CGFloat = 0.5

        /// **The one-line rule.** The due chip's box, against one line of the title beside it.
        ///
        /// **Measured 2026-09-29** (T-1488), same three runs: the chip's box came out **18pt
        /// against a 19pt title line**, i.e. 0.95 title-lines, against a bound of 2. The two rows'
        /// heights came out **36pt and 36pt** — identical, so the decorated row took *no* extra
        /// height at all, where the companion assertion below allows it one title line (55pt).
        ///
        /// The measurement confirms the derivation rather than replacing it, and the bound was
        /// never waiting on it: the chip draws at `CadenceTaskRowMetrics.desktop.secondaryFontSize`
        /// with `CadenceTaskChipPadding.desktopVertical` either side of it, and the title line
        /// beside it is `titleFontSize`, which is larger. One line of chip is therefore *below* one
        /// title line whatever the fonts resolve to, and the wrap that filed this was three lines.
        /// Any cut between 1 and 3 states the same fact; 2 is the middle of it.
        ///
        /// **Not lowered toward 0.95.** A cut just above the measurement would fire on a chip that
        /// gained a point of padding, which is not this defect; the defect is a chip that wrapped,
        /// and a wrap cannot land between 1 and 2 lines.
        ///
        /// Stated in title-lines rather than points so it survives a font, a display and an Xcode
        /// major — this project builds on two.
        static let dueChipHeightInTitleLines: CGFloat = 2

        /// **The own-row rule, and the reason the majority rule above cannot stand alone.**
        ///
        /// That bound divides the decorated row's title by the **control row's** title, and one
        /// `MacTaskRow` call site draws both rows. Numerator and denominator therefore move
        /// together under anything that crushes the title in *every* row, and the ratio does not
        /// move at all. Measured 2026-09-29 (T-1488): a `.frame(width: 40)` pinned on the title
        /// gave **crushed 36pt / bare 39pt = 0.92**, sailed past 0.5, and the run was **green** —
        /// the test passing the defect it was written to refuse ([[T-1720]]).
        ///
        /// This is the assertion that ratio cannot express: the title against **its own row**.
        /// `MacTaskRow` does not decide that width — the pane above it hands the row the width and
        /// the row's `HStack` divides it — so the row frame is the one reference in reach that a
        /// crush *inside* the stack cannot drag down together with the title. That is the whole
        /// property being bought here, and it is why this is not simply a second ratio.
        ///
        /// **Measured**, this Mac, Xcode 27.0, default window, and re-measured 2026-10-03
        /// (agent `rowcrush`) byte-identically to T-1488's three runs: healthy **143 / 342 =
        /// 0.42**; the 40pt pin **36 / 342 = 0.11**; the screenshot that filed T-1432 is a title of
        /// about ten characters where the pane drew the whole string, so roughly **0.18**. **A
        /// quarter refuses all three and clears the healthy reading by 0.17.** It is not the
        /// measurement rounded down — it is the smallest round share that still calls a title
        /// holding a quarter of its own row uncrushed.
        ///
        /// **Unlike the ratio above this is a share of the window, and that is the cost.** At the
        /// measured row the title has 143pt and everything else in it 199pt, so on a linear
        /// reading the bound would fire below roughly a 265pt row. The strip does not stay 199pt:
        /// `metadataStrip` is a `ViewThatFits` and sheds chips as the row narrows, which is the
        /// half of T-1432's fix this file cannot otherwise see. So a red run here says either the
        /// row got narrow enough that the strip ran out of chips to shed, or the title stopped
        /// being laid out first — and both of those are this defect, not a portability artefact.
        ///
        /// **Do not lower it to chase a red run**, and do not raise it toward 0.42 either: 0.42 is
        /// today's chip inventory, and pinning that would fail this test for the next chip added
        /// rather than for anything crushing a title.
        static let titleShareOfItsOwnRow: CGFloat = 0.25
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

        // **The control, and the reason it is here** (T-1954, refuted by `seedrace` in `acd36856`).
        // `sidebar.destination.today` is a STATIC sidebar row — `SidebarView` builds it from
        // `destination.rawValue` and no seed creates it — so it is present in any launch that drew
        // a sidebar at all. The seeded row below exists only because the seed committed an `Area`.
        // Asked without the control, the seeded row's absence reads as a seeding bug, and that is
        // exactly how T-1954 was mis-filed: in both launches that "proved" one, the control was
        // absent too, so those launches had drawn no UI whatsoever. Roughly 2 in 40 launches do
        // that, and the cause is open as T-2020.
        XCTAssertTrue(
            app.buttons.element(identified: ID.todayDestinationControl).waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the sidebar drew no static Today row, so this launch drew no UI at all — nothing "
            + "below is evidence about the seed. See T-2020."
        )
        XCTAssertTrue(
            app.buttons.element(identified: ID.seededAreaRow).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either"
        )

        let crushedRow = element(ID.row(Fixture.crushedTitle))
        let bareRow = element(ID.row(Fixture.bareTitle))
        XCTAssertTrue(
            crushedRow.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the decorated seeded row is not on Today. Rows Today is publishing: \(seededRowIdentifiers())"
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
            / bare \(Int(bareTitleFrame.width))pt = \(String(format: "%.2f", crushedTitleFrame.width / max(bareTitleFrame.width, 1))), \
            and \(String(format: "%.2f", crushedTitleFrame.width / max(crushedRowFrame.width, 1))) of its own row; \
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

        // ── THE OWN-ROW RULE ──────────────────────────────────────────────────────────────────
        // The rule above compares two things `MacTaskRow` draws, so it reads 1.0 on a crush that
        // takes both. This one compares the title against a width `MacTaskRow` is handed rather
        // than one it allocates, which is the only reference in this window that does not move
        // with the title. See `Bound.titleShareOfItsOwnRow`, and T-1720 for the green run that
        // made it necessary.
        XCTAssertGreaterThan(crushedRowFrame.width, 0, "the decorated row has no width to take a share of")
        XCTAssertGreaterThan(
            crushedTitleFrame.width,
            crushedRowFrame.width * Bound.titleShareOfItsOwnRow,
            "the decorated row's title is \(Int(crushedTitleFrame.width))pt of a \(Int(crushedRowFrame.width))pt row — "
            + String(format: "%.2f", crushedTitleFrame.width / max(crushedRowFrame.width, 1))
            + " of its own row, under the \(Bound.titleShareOfItsOwnRow) this test refuses. The title has lost "
            + "its row, and it does not matter which subview took it"
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

    /// **Why this is a predicate and not a subscript.** `XCUIElementQuery`'s string subscript
    /// refuses an identifier longer than 128 characters, and raises
    /// `NSInternalInconsistencyException` — *"Invalid query - string identifier … exceeds maximum
    /// length of 128 characters"* — rather than returning a query that does not match. Measured on
    /// this test's first ever run, 2026-09-29 (T-1488): the fixture's crushed row resolves to a
    /// 129-character identifier, because the slug is derived from a title that is deliberately
    /// longer than any pane can draw.
    ///
    /// The length is the fixture's whole point, so the identifier is not what moves. The error
    /// names its own workaround and this is it: match `identifier` through an `NSPredicate`, which
    /// carries no such cap. Since T-1725 that form lives once, in `CadenceUITestQuery`, and this
    /// is a name for it rather than a fourth copy of it.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendant(identified: identifier)
    }

    /// Scoped to the row on purpose. `MacTaskRow` is drawn by Today *and* by a list's detail pane
    /// from one call site, so `task.row.…` identifiers are not Today's alone; asking the row for
    /// them is what makes this a reading of Today.
    private func descendant(_ identifier: String, of row: XCUIElement) -> XCUIElement {
        row.descendant(identified: identifier)
    }

    /// What Today is actually publishing, for the failure message above.
    ///
    /// "No such element" and "an element whose identifier is not the one this test computed" are
    /// different findings with the same symptom, and a reader of a red run cannot tell them apart
    /// from the absence alone. This prints the identifiers, with their lengths, so they can be.
    private func seededRowIdentifiers() -> String {
        app.identifiers(beginningWith: "today.task.row.")
    }
}
#endif
