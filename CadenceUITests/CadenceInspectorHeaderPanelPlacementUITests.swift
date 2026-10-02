import XCTest

/// **Where the task inspector's five child panels actually open** — T-1722, read off the running
/// surface rather than off the app's own model of it.
///
/// ### Why this test exists at all
///
/// `CadenceInspectorChildPopoverPlacementTests` (unit target) asks
/// `TaskInspectorChildPopoverPlacement.panelFrame(anchoredTo:panelSize:)` where a panel goes and
/// asserts against the answer. That function is *this repository's own arithmetic*, so the suite is
/// a statement about the arithmetic and about nothing else. It was green — 14 tests — for the whole
/// of the time the estimate chip's roller was opening across four of the inspector's rows, because
/// the thing that decides the side on a real Mac is **AppKit**, and AppKit was never asked. T-1480
/// and T-1510 both closed on that model alone.
///
/// So the reading below is `app.popovers`: the frames of the real `NSPopover` windows, in points,
/// after a real click. A model test that agrees with itself is not evidence about `NSPopover`.
///
/// ### All five anchors, because they share one type
///
/// `TaskInspectorChildPopoverPlacement.besideInspector` is carried by the priority tile, the
/// estimate chip and the Schedule well's Do / Due / Repeat rows. The header two are pinned to the
/// **ends** of the content column and are narrower than it; the Schedule three **span** it. That
/// difference is the whole of T-1510's argument and it had never been observed on either kind, so
/// both kinds are measured here.
///
/// ### What it asserts, and why it is a relation
///
/// Never a point figure — CI builds on Xcode 26 and this Mac runs 27.0 (T-1279, T-1296), and a
/// popover's absolute origin depends on the window, the display and where the row that opened the
/// inspector happened to be. Every assertion compares rectangles measured **in the same window at
/// the same instant**:
///
/// - The inspector's **content column** is not a constant. It is derived from the two controls the
///   header row ends in: the priority tile is its leading-most element and the estimate chip its
///   trailing-most, so `[tile.minX, chip.maxX]` *is* the band the inspector draws its rows in.
///   Both are read from the live accessibility tree. Reading the column off
///   `TaskInspectorPopoverMetrics` instead would reintroduce exactly the circularity this test
///   exists to break.
/// - A panel passes when it **clears that column** — when the panel and the column do not overlap
///   horizontally. That is the defect stated exactly: T-1722's estimate roller came out at
///   x ∈ [1059, 1345] against a column of [1111, 1419] and covered the title row, the list row, Do
///   and Due.
///
/// ### What it measured, before the fix and after
///
/// **2026-09-30, this Mac, Xcode 27.0, inspector (1084, 227, 362, 522), column x ∈ [1111, 1419].**
/// Every one of the five panels opened off the **opposite** edge of its anchor from the one its
/// `arrowEdge:` declared — the three Schedule rows included. They were clear anyway, and that is
/// the finding: they span the column, so both of their ends are its ends.
///
/// | anchor | declared | opened off | covered |
/// |---|---|---|---|
/// | Priority (1111, 254, 28, 28) | `.leading` | trailing → (1139, 186, 186, 164) | **186pt** |
/// | Estimate (1362, 254, 57, 28) | `.trailing` | leading → (1076, 125, 286, 286) | **251pt** |
/// | Do (1111, 369, 308, 32) | `.trailing` | leading → (819, 182, 292, 406) | 0 |
/// | Due (1111, 402, 308, 32) | `.trailing` | leading → (819, 236, 292, 365) | 0 |
/// | Repeat (1111, 435, 308, 32) | `.trailing` | leading → (817, 406, 294, 91) | 0 |
///
/// Available space does not explain it: the priority tile's declared leading side would have put
/// its panel at x ∈ [925, 1111] on a 1512pt display, which fits and is where it did *not* go.
///
/// **After the fix**, same window, same column: Priority **(925, 186, 186, 164)** and Estimate
/// **(825, 125, 286, 286)**, both x ∈ [·, 1111] — flush against the column's leading edge and clear
/// of every row. The three Schedule readings are byte-identical to the ones above. Note that all
/// five still open off the edge *opposite* the one they declare: the inversion did not go away and
/// the fix does not depend on it going away.
///
/// The **side** is deliberately not pinned. Which end a panel leaves by is AppKit's to choose — it
/// weighs the room left on the display, and an inspector opened from a row near the right edge of a
/// 1512pt screen has none on its trailing side for a 286pt roller. The product requirement is that
/// the panel does not sit on top of the rows; the side it clears by is not a requirement and
/// pinning it would make this test fail on a differently placed window. Both sides are *reported*,
/// in the activity below, because which one AppKit picked is the finding.
///
/// ### Interactive
///
/// It clicks: once on the Today row that opens the inspector, then once on each control and once
/// more to dismiss each panel. So it takes the pointer, and it is gated like every other test in
/// this target that does (`CadenceUITestEnvironment.requireInteractiveUITests` — the marker-file
/// channel, since the environment variable cannot reach the runner; T-1724).
///
/// [[T-1741]] asked whether that is a schedule at all and settled it: the gate **stays**, because
/// there is no unattended Mac here and CI does not run this target (T-531); the SILENCE goes.
/// `scripts/xcb.sh` now ends any run that skipped tests with `INTERACTIVE-SKIPPED`, naming them
/// and naming the `touch` that enables them, so a green default run no longer reads as though
/// these assertions were made.
@MainActor
final class CadenceInspectorHeaderPanelPlacementUITests: XCTestCase {

    /// Identifiers, restated because a UI-test bundle cannot import the app module.
    /// `CadenceAccessibilityIdentifiers` is the definition; this is the mirror.
    private enum ID {
        static let seededAreaRow = "sidebar.list.area.alpha-area"
        /// The control for the row above: a sidebar destination **no seed creates**, so its absence
        /// means the launch drew nothing rather than that the seed failed. See T-1954 / T-2020.
        static let todayDestinationControl = "sidebar.destination.today"
        static let todayRow = "today.task.row.today-one"

        /// `CadenceAccessibilityIdentifiers.inspectorPanelControl(_:)`.
        static func control(_ field: String) -> String {
            "inspector.control.\(field.lowercased())"
        }
    }

    /// The five anchors, in the order the inspector draws them.
    ///
    /// `spansColumn` is not decoration: it is T-1510's claim about each anchor, and the activity
    /// log below prints it beside the measured side so a reader can see whether the two kinds of
    /// anchor behaved differently. It is asserted against the measured geometry rather than
    /// trusted.
    private struct Anchor {
        let field: String
        let spansColumn: Bool
    }

    private static let anchors: [Anchor] = [
        Anchor(field: "Priority", spansColumn: false),
        Anchor(field: "Estimate", spansColumn: false),
        Anchor(field: "Do", spansColumn: true),
        Anchor(field: "Due", spansColumn: true),
        Anchor(field: "Repeat", spansColumn: true),
    ]

    private enum Fixture {
        static let scenario = "today-geometry"
    }

    /// One point, for a panel hung flush against the column's edge: the panel's boundary and the
    /// column's boundary are then the same coordinate, and a rounding of the two frames through the
    /// accessibility tree must not read as an overlap.
    private static let tolerance: CGFloat = 1

    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        try CadenceUITestEnvironment.requireInteractiveUITests()
        // **True, deliberately.** The body below is a sweep of five independent readings, and
        // stopping at the first bad one is exactly how three of them stayed unobserved: T-1480
        // closed the Do / Due / Repeat rows and T-1510 the two header controls on arithmetic
        // alone, and a run that aborts on the priority tile reports nothing about the other four.
        // Every failure message carries the anchor's name, so a red run is still readable.
        continueAfterFailure = true
        storeID = "ui-inspector-panels-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    func testEveryInspectorPanelOpensClearOfTheRowsItIsOpenedFrom() throws {
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

        let row = app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifying(ID.todayRow))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the seeded Today row is not on screen, so there is nothing to open an inspector from"
        )
        row.click()

        let inspector = app.popovers.firstMatch
        XCTAssertTrue(
            inspector.waitForExistence(timeout: CadenceUITestBounds.settle),
            "clicking the seeded row opened no popover, so the task inspector never appeared"
        )
        // Exactly one, so `inspectorFrame` is unambiguous and a child panel can be told from its
        // parent by frame alone.
        XCTAssertEqual(app.popovers.count, 1, "more than the inspector is on screen before anything was clicked")
        let inspectorFrame = inspector.frame

        // ── THE COLUMN, DERIVED FROM THE SURFACE ──────────────────────────────────────────────
        let tileFrame = try frame(ofControl: "Priority", in: inspector)
        let chipFrame = try frame(ofControl: "Estimate", in: inspector)
        XCTAssertLessThan(
            tileFrame.minX, chipFrame.minX,
            "the priority tile is not leading the estimate chip on the title row, so the two no longer "
            + "bound the content column and every figure below is about something else"
        )
        let column = CGRect(
            x: tileFrame.minX,
            y: inspectorFrame.minY,
            width: chipFrame.maxX - tileFrame.minX,
            height: inspectorFrame.height
        )
        XCTAssertGreaterThan(column.width, tileFrame.width, "the derived content column is no wider than the tile that starts it")

        var report: [String] = ["inspector \(describe(inspectorFrame)); column x ∈ [\(Int(column.minX)), \(Int(column.maxX))]"]

        for anchor in Self.anchors {
            // A dismissal that took the inspector with it would otherwise cost every remaining
            // reading — which is how two runs of this sweep reported four anchors instead of five.
            if app.popovers.count == 0 {
                row.click()
                XCTAssertTrue(
                    inspector.waitForExistence(timeout: CadenceUITestBounds.settle),
                    "the inspector closed during the sweep and would not reopen, so \(anchor.field) cannot be read"
                )
            }

            let anchorFrame = try frame(ofControl: anchor.field, in: inspector)

            // The declared claim, checked against the surface rather than believed: T-1510 says
            // the two header controls do NOT span the column and the three Schedule rows DO, and
            // that is the premise its whole per-anchor argument rests on.
            let spans = anchorFrame.minX <= column.minX + Self.tolerance
                && anchorFrame.maxX >= column.maxX - Self.tolerance
            XCTAssertEqual(
                spans, anchor.spansColumn,
                "\(anchor.field)'s anchor is \(describe(anchorFrame)) against a column of "
                + "[\(Int(column.minX)), \(Int(column.maxX))] — it \(spans ? "spans" : "does not span") the column, "
                + "which is the opposite of what the placement rule assumes about it"
            )

            guard let panel = panel(openedBy: anchor.field, in: inspector, parentFrame: inspectorFrame) else {
                report.append("\(anchor.field): no panel opened")
                continue
            }
            // Which side of **its own anchor** the panel took, which is the fact that reads
            // against the declared `arrowEdge`. Not which half of the column it landed in: a
            // 186pt panel hung off a tile at the column's leading end is still in the leading
            // half whichever edge it left by, so that reading would have said nothing.
            let side = panel.midX < anchorFrame.midX ? "leading" : "trailing"
            report.append(
                "\(anchor.field): anchor \(describe(anchorFrame)) \(anchor.spansColumn ? "spans" : "pinned") "
                + "→ panel \(describe(panel)) off its \(side) edge"
            )
            assertPanelClearsColumn(panel, column: column, anchor: anchorFrame, named: anchor.field)
            dismissChildPanel(panel, inside: inspector, inspectorFrame: inspectorFrame, titleRow: tileFrame)
        }

        // Every figure this test reasoned about, in the run log, so a reader of a red run does not
        // have to re-derive them and a reader of a green one can see which side each panel took.
        XCTContext.runActivity(named: "measured — " + report.joined(separator: " ;; ")) { _ in }
    }

    // MARK: - The assertion

    /// The whole product requirement, as a relation between two rectangles measured together.
    private func assertPanelClearsColumn(_ panel: CGRect, column: CGRect, anchor: CGRect, named name: String) {
        // ── NON-VACUITY ───────────────────────────────────────────────────────────────────────
        // A panel with no area clears everything, and so does one that opened somewhere else
        // entirely. Neither is this test passing.
        XCTAssertGreaterThan(panel.width, 0, "the \(name) panel has no width, so it cannot be covering or clearing anything")
        XCTAssertGreaterThan(panel.height, 0, "the \(name) panel has no height")
        let verticalOverlap = min(panel.maxY, column.maxY) - max(panel.minY, column.minY)
        XCTAssertGreaterThan(
            verticalOverlap, 0,
            "the \(name) panel shares no vertical space with the inspector, so it is not beside it at all"
        )

        // ── THE RULE ──────────────────────────────────────────────────────────────────────────
        // T-1722: the estimate roller opened across the title row, the list row, Do and Due. A
        // panel opened from inside the inspector must leave the content column, by whichever end
        // AppKit has room for.
        let overlap = max(0, min(panel.maxX, column.maxX) - max(panel.minX, column.minX))
        XCTAssertLessThanOrEqual(
            overlap, Self.tolerance,
            "the \(name) panel is at x ∈ [\(Int(panel.minX)), \(Int(panel.maxX))] against a content column of "
            + "[\(Int(column.minX)), \(Int(column.maxX))] — it covers \(Int(overlap))pt of the rows the inspector "
            + "is drawing. Its anchor is at x ∈ [\(Int(anchor.minX)), \(Int(anchor.maxX))]."
        )
    }

    // MARK: - Small helpers

    private func control(_ field: String, in inspector: XCUIElement) -> XCUIElement {
        inspector.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifying(ID.control(field)))
            .firstMatch
    }

    private func frame(ofControl field: String, in inspector: XCUIElement) throws -> CGRect {
        let element = control(field, in: inspector)
        guard element.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            throw NotAddressable(
                message: "the inspector's \(field) control is not addressable. "
                + "Identifiers present: \(inspectorControlIdentifiers(in: inspector))"
            )
        }
        return element.frame
    }

    /// A control the sweep cannot find at all. Thrown rather than asserted so the failure names
    /// the control and ends the run there: with no anchor there is no column and nothing below is
    /// a reading of anything.
    private struct NotAddressable: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Click the control, wait for a second popover, and return the one that is not the inspector.
    ///
    /// `nil` rather than a throw: the caller is sweeping five anchors and a throw would end the
    /// run at the first one, which is the reporting failure this whole test is a reaction to.
    private func panel(openedBy field: String, in inspector: XCUIElement, parentFrame: CGRect) -> CGRect? {
        control(field, in: inspector).click()
        guard childPanel.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            XCTFail("clicking the \(field) control opened no popover of its own. On screen: \(popoverFrames())")
            return nil
        }

        let panels = app.popovers.allElementsBoundByIndex.map(\.frame).filter { $0 != parentFrame }
        guard let panel = panels.first else {
            XCTFail("the \(field) control's panel cannot be told apart from the inspector")
            return nil
        }
        XCTAssertEqual(panels.count, 1, "more than one child panel is open, so the \(field) reading is ambiguous")
        return panel
    }

    /// Dismiss the child panel with a click **inside the inspector and outside the panel**.
    ///
    /// **Not Escape.** Escape was the first thing this tried and it does not close these panels:
    /// measured across three runs, the panel was still on screen a full 5s after
    /// `app.typeKey(.escape)`, every time, with its frame unchanged. Filed as T-1742 — through the
    /// harness only, so it may be XCUITest not delivering the key rather than the app not handling
    /// it, and this test is not the place to decide which.
    ///
    /// **Not a click anywhere outside either**, which would close the inspector along with the
    /// panel. A macOS transient popover closes on a click outside *itself*, and the inspector is
    /// its own window, so a point inside the inspector and outside the panel dismisses exactly one
    /// of the two. The point is derived from the two frames rather than guessed: whichever side of
    /// the panel leaves room inside the inspector, near the top, above the title row.
    ///
    /// **Why the sweep cannot just skip this.** The click that opens the next panel would
    /// otherwise be spent closing this one — measured: with the priority panel still up, the click
    /// on the estimate chip dismissed it and opened nothing, and the estimate reading was lost for
    /// two whole runs. The two header controls share one anchor now, so that click has nowhere
    /// else to land.
    private func dismissChildPanel(
        _ panel: CGRect,
        inside inspector: XCUIElement,
        inspectorFrame: CGRect,
        titleRow: CGRect
    ) {
        let trailingGap = inspectorFrame.maxX - panel.maxX
        let leadingGap = panel.minX - inspectorFrame.minX
        let x = trailingGap >= leadingGap
            ? (max(panel.maxX, inspectorFrame.minX) + inspectorFrame.maxX) / 2
            : (inspectorFrame.minX + min(panel.minX, inspectorFrame.maxX)) / 2
        // Just under the title row, in the band the tags and the breadcrumb sit in — indented past
        // this x, so the point carries no control. **Not `inspectorFrame.minY + 6`**, which was the
        // first attempt: an `XCUIElement`'s frame for a popover includes chrome the window does not
        // draw into, so a click 6pt below its top edge landed *outside* the inspector and closed it
        // along with the panel. Measured 2026-09-30.
        let y = titleRow.maxY + 16

        inspector.coordinate(
            withNormalizedOffset: CGVector(
                dx: (x - inspectorFrame.minX) / inspectorFrame.width,
                dy: (y - inspectorFrame.minY) / inspectorFrame.height
            )
        ).click()

        XCTAssertTrue(
            childPanel.waitForNonExistence(timeout: CadenceUITestBounds.settle),
            "the child panel did not close on a click at (\(Int(x)), \(Int(y))), inside the inspector and clear of the "
            + "panel, so the next reading would see two panels. On screen: \(popoverFrames())"
        )
        XCTAssertTrue(
            inspector.exists,
            "the dismissing click closed the inspector itself, so the rest of the sweep has nothing to open"
        )
    }

    /// The second popover — the child, whichever it is.
    ///
    /// **An element wait, not a spin on `app.popovers.count`.** Measured on this test's first two
    /// runs: both a tight loop over `count` and an `XCTNSPredicateExpectation` on the query
    /// reported the child panel as still open for a whole 5s wait, on four of five dismissals —
    /// and the very next click then found exactly one child, which it could not have if the
    /// previous one were really still up. `count` was being served from a snapshot neither wait
    /// gave the runner a reason to refresh. `waitForExistence` / `waitForNonExistence` on an
    /// element are the APIs that do.
    private var childPanel: XCUIElement { app.popovers.element(boundBy: 1) }

    /// Every popover on screen, for a failure message. Which panel is up, and where, is the
    /// difference between "it did not open" and "it opened somewhere this query does not look".
    private func popoverFrames() -> String {
        let frames = app.popovers.allElementsBoundByIndex.map { describe($0.frame) }
        return frames.isEmpty ? "no popovers at all" : frames.joined(separator: " ;; ")
    }

    /// What the inspector is actually publishing, for the failure message above. "No such element"
    /// and "an element whose identifier is not the one this test computed" are different findings
    /// with the same symptom.
    private func inspectorControlIdentifiers(in inspector: XCUIElement) -> String {
        let found = inspector.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifiers(beginningWith: "inspector.control."))
            .allElementsBoundByIndex
            .map(\.identifier)
        return found.isEmpty ? "none at all" : found.joined(separator: " ;; ")
    }

    private func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width)), \(Int(rect.height)))"
    }

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
}
