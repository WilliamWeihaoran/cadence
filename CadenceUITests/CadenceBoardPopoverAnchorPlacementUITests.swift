import XCTest

/// **Where the app's remaining `arrowEdge: .trailing` popovers actually open** — T-1740, read off
/// the running surface with the instrument T-1722 built rather than argued about from source.
///
/// ### The finding this was a follow-on to, and what happened to it
///
/// `CadenceInspectorHeaderPanelPlacementUITests` measured five anchors inside the task inspector
/// and found every one of them opening off the edge **opposite** the one its `arrowEdge:` declared,
/// with available space ruled out as the explanation. T-1740 generalised that into its own title —
/// *every* `arrowEdge: .trailing` in the app opens on the leading side — and asked for the other
/// eight call sites to be looked at.
///
/// **They do not.** Six of the eight were measured here, in two windows on 2026-09-30, this Mac,
/// Xcode 27.0, window (40, 54, 1400, 858) on a 1512pt display, and **every one of them opened off
/// the trailing edge it declared.** So the inversion is not a property of `arrowEdge:`, it is
/// something about where the inspector's anchors sit, and a fix anywhere that had *corrected an
/// edge* would have been correcting a coincidence. The part of T-1722 that generalises is the
/// other part: **an anchor that spans the content has both of its ends at the content's ends, so
/// the side the platform picks cannot put the panel on top of it.**
///
/// ### What was measured, and the one defect in it
///
/// Board card box (564, 191, 282, 146), the content it draws x ∈ [578, 830]:
///
/// | site | anchor | declared | opened off | covers |
/// |---|---|---|---|---|
/// | `KanbanCardMetaSupportViews:47` list picker | chip (578, 301, 252, 26) | `.trailing` | trailing → (830, 202, 216, 225) | 0 |
/// | `KanbanCardMetaSupportViews:150` tag picker | strip (578, 245, 57, 19) | `.trailing` | trailing → (636, 199, 266, 111) | **194pt** |
/// | `KanbanCardView:132` duration roller | card, `.rect(.bounds)` | `.trailing` | trailing → (846, 121, 286, 286) | 0 |
/// | `KanbanCardView:129` task inspector | card, `.rect(.bounds)` | `.trailing` | trailing → (846, 33, 362, 523) | 0 |
/// | `CalendarBoardItemSupportViews:39` block detail | card (564, 345, 282, 70) | `.trailing` | trailing → (846, 197, 402, 367) | 0 |
/// | `TasksPanelComponents:174` task inspector | row (754, 243, 372, 36) | `.trailing` | trailing → (1096, 33, 362, 523) | 10pt |
///
/// **One defect, and it is the shape T-1722 named.** The tag strip is 57pt at the leading end of a
/// 252pt content column, and its picker came out across 194pt of the card it was opened from — its
/// own title, its chips, the strip itself. Nothing was wrong with the edge; the panel went exactly
/// where it asked to go. The anchor was the wrong shape, so `KanbanCard` presents that picker from
/// its own bounds now and the panel moved to (846, 209, 266, 111), clear of everything.
///
/// **The list chip is clear, and structurally rather than by luck.** `KanbanCard.metadataRows`
/// puts the list chip **alone on its own row**, so it spans the card's content column and both of
/// its ends are the column's ends. That is the same property the fix gives the tag picker; if the
/// chip is ever packed beside another, this suite goes red.
///
/// **Today's row covers 10pt, and no anchor can undo it.** The row spans its column and the panel
/// still laps its due chip, because a flush placement would have ended at x = 1488 on a 1512pt
/// screen: the panel is already spilling 18pt past the window's own trailing edge. That is the
/// display running out of room, measured, and it is [[T-1845]].
///
/// Two of the eight are **not** measured here and neither is touched: the Calendar Board's event
/// card, whose card exists only for a real EventKit event the UI-test host has no access to
/// ([[T-1843]]), and the timeline's draft block, which only exists during a drag-to-create
/// ([[T-1844]]). Both are card- or canvas-spanning anchors by construction, which is an argument
/// and not a reading — which is why they are filed rather than declared safe.
///
/// ### The container, derived from the surface
///
/// Never from a metrics type. Reading the container off the app's own constants is the circularity
/// that let T-1510 pass while the app did the opposite. The container is **what the card (or the
/// row) actually draws**: the union of the frames of every element it publishes — its title, its
/// chips, its strip — read live from the accessibility tree, and never its own padded box.
///
/// That distinction is not pedantry and it changed three verdicts. The card's box ends at x = 846
/// and its content at 830, because `KanbanCard` pads its trailing edge by 16pt; a panel hung flush
/// off the trailing-most chip therefore laps the **box** by 16pt while covering nothing at all.
/// Asserting against the box would have reported a defect over empty padding.
///
/// The **side** is deliberately never asserted. Which end a panel leaves by is AppKit's, it weighs
/// the room left on the display, and pinning it would make this suite fail on a moved window. The
/// end each panel took is reported in the activity log, because which one the platform picked is
/// the finding — and on this surface it picked the declared one six times out of six.
///
/// ### Interactive
///
/// It clicks. So it is gated like every other test in this target that takes the pointer
/// (`CadenceUITestEnvironment.requireInteractiveUITests` — the marker-file channel, since the
/// environment variable cannot reach the runner; T-1724). That gate is [[T-1741]]'s subject, and
/// T-1741 settled it: the gate **stays** — there is no unattended Mac to move it to, and CI does
/// not run this target at all (T-531) — and what goes is the silence. A default
/// `-only-testing:CadenceUITests` run still skips these two tests, and `scripts/xcb.sh` now says
/// so by name in its postflight (`INTERACTIVE-SKIPPED`), with the `touch` that turns them on.
@MainActor
final class CadenceBoardPopoverAnchorPlacementUITests: XCTestCase {

    /// Identifiers and fixture strings, restated because a UI-test bundle cannot import the app
    /// module. `CadenceAccessibilityIdentifiers` and `CadenceUITestScenarioSeed.Fixture` are the
    /// definitions; this is the mirror.
    private enum ID {
        static let seededAreaRow = "sidebar.list.area.alpha-area"
        static let calendarDestination = "sidebar.destination.calendar"

        static let cardTitle = "Board Anchor Card"
        static let bundleTitle = "Anchor Block"

        static func slug(_ value: String) -> String {
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }

        static var boardCard: String { "board.card.\(slug(cardTitle))" }
        static var boardBundle: String { "board.bundle.\(slug(bundleTitle))" }
        static func boardControl(_ field: String) -> String { "\(boardCard).control.\(slug(field))" }
        static var todayRow: String { "today.task.row.\(slug(cardTitle))" }
    }

    private enum Fixture {
        static let scenario = "popover-anchors"
    }

    /// One point, for a panel hung flush against its container's edge: the two boundaries are then
    /// the same coordinate and a rounding of the two frames through the accessibility tree must not
    /// read as an overlap. Same figure and same reason as the inspector sweep's.
    private static let tolerance: CGFloat = 1

    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        try CadenceUITestEnvironment.requireInteractiveUITests()
        // **True, deliberately** — the same reason the inspector sweep gives. The body is a sweep
        // of independent readings and stopping at the first bad one reports nothing about the
        // rest, which is how sites stay unobserved. Every message names its anchor.
        continueAfterFailure = true
        storeID = "ui-board-popovers-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    // MARK: - The board's five anchors

    func testEveryBoardCardPanelOpensClearOfTheCardItIsOpenedFrom() throws {
        launchApp()
        try openCalendarBoard()

        let card = element(ID.boardCard)
        XCTAssertTrue(
            card.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the seeded board card is not on the Calendar Board, so there is nothing to open a panel from. "
            + "Board identifiers on screen: \(identifiers(beginningWith: "board."))"
        )
        let cardFrame = card.frame
        XCTAssertGreaterThan(cardFrame.width, 0, "the board card has no width, so every figure below is about nothing")

        let cardContent = content(of: card, named: "card")
        var report: [String] = [
            "window \(describe(app.windows.firstMatch.frame))",
            "card box \(describe(cardFrame)); card CONTENT x ∈ [\(Int(cardContent.minX)), \(Int(cardContent.maxX))]"
        ]

        // ── THE TWO CHIPS ─────────────────────────────────────────────────────────────────────
        // Both are opened by a chip tens of points wide inside a card hundreds of points wide,
        // which is the inspector's priority tile again and is what this sweep was written for. Only
        // one of them is still *anchored* to its chip; see the note in the loop.
        for field in ["List", "Tags"] {
            let control = element(ID.boardControl(field))
            guard control.waitForExistence(timeout: CadenceUITestBounds.settle) else {
                XCTFail(
                    "the card's \(field) chip is not addressable, so its panel cannot be read. "
                    + "Card identifiers on screen: \(identifiers(beginningWith: ID.boardCard))"
                )
                continue
            }
            // **The anchor is not always the thing that was clicked.** The list picker is
            // presented by the chip, so the chip is its anchor; the tag picker is opened by the
            // strip and presented by the CARD (T-1740's fix), so the card is. Which it is is a
            // fact about the code, so it is named here — and then the spanning claim about it is
            // measured rather than assumed.
            let anchorFrame = field == "List" ? control.frame : cardFrame
            guard let panel = panel(openedBy: control, named: field) else {
                report.append("\(field): no panel opened")
                continue
            }
            report.append(reading(named: field, anchor: anchorFrame, panel: panel, spans: spans(anchorFrame, cardContent)))
            assertPlacementIsSafe(content: cardContent, panel: panel, anchor: anchorFrame, named: field)
            dismiss(panel, named: field)
        }

        // ── THE CARD-SPANNING ANCHORS ─────────────────────────────────────────────────────────
        // `attachmentAnchor: .rect(.bounds)` on the card itself, and all of them on the SAME view:
        // `KanbanCard` now chains three `.popover` modifiers onto one card. T-1722 measured that
        // two chained `.popover`s on the inspector's title row did **not** both present, so whether
        // each of these opens at all is itself a reading — and all three did, at three distinct
        // frames, in one run.
        let duration = element(ID.boardControl("Estimate"))
        if duration.waitForExistence(timeout: CadenceUITestBounds.settle) {
            let anchorFrame = duration.frame
            if let panel = panel(openedBy: duration, named: "Duration") {
                report.append(reading(named: "Duration", anchor: cardFrame, panel: panel, spans: spans(cardFrame, cardContent)))
                report.append("Duration: its trigger badge is \(describe(anchorFrame)), its anchor is the card")
                assertPlacementIsSafe(content: cardContent, panel: panel, anchor: cardFrame, named: "Duration")
                dismiss(panel, named: "Duration")
            } else {
                report.append("Duration: no panel opened — three chained `.popover`s on one card (cf. T-1722)")
            }
        } else {
            XCTFail("the card's duration badge is not addressable. On the card: \(identifiers(beginningWith: ID.boardCard))")
        }

        // The card's own inspector, opened by **right-clicking** it.
        //
        // Not a left click at a derived point inside the card: measured 2026-09-30, a click 8% in
        // and 92% down a card carrying a schedule row, a title, a tag strip and a chip row landed
        // on the **list chip**, and the run reported the list picker's frame a second time under
        // the inspector's name. A card of this size has almost no surface that is not a control.
        // `KanbanCard` carries a `RightClickActionTrigger` overlay across its whole box that sets
        // `showTaskInspector`, so a right click opens exactly this popover from anywhere on it.
        if let panel = panel(openedBy: card, named: "Card inspector", rightClick: true) {
            report.append(reading(named: "Card inspector", anchor: cardFrame, panel: panel, spans: spans(cardFrame, cardContent)))
            assertPlacementIsSafe(content: cardContent, panel: panel, anchor: cardFrame, named: "Card inspector")
            dismiss(panel, named: "Card inspector")
        } else {
            report.append("Card inspector: no panel opened")
        }

        // ── THE BLOCK CARD, a fifth anchor of the same kind on the same board ──────────────────
        let bundle = element(ID.boardBundle)
        if bundle.waitForExistence(timeout: CadenceUITestBounds.settle) {
            let bundleFrame = bundle.frame
            let bundleContent = content(of: bundle, named: "block card")
            if let panel = panel(openedBy: bundle, named: "Block") {
                report.append(reading(named: "Block", anchor: bundleFrame, panel: panel, spans: spans(bundleFrame, bundleContent)))
                assertPlacementIsSafe(content: bundleContent, panel: panel, anchor: bundleFrame, named: "Block")
                dismiss(panel, named: "Block")
            } else {
                report.append("Block: no panel opened")
            }
        } else {
            report.append("Block: the seeded block card is not on the board")
        }

        XCTContext.runActivity(named: "measured — " + report.joined(separator: " ;; ")) { _ in }
    }

    // MARK: - The task row's inspector

    func testTheTaskRowInspectorOpensClearOfTheRowItIsOpenedFrom() throws {
        launchApp()

        XCTAssertTrue(
            element(ID.seededAreaRow).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either"
        )

        let row = element(ID.todayRow)
        XCTAssertTrue(
            row.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the seeded Today row is not on screen, so there is nothing to open an inspector from"
        )
        let rowFrame = row.frame
        let rowContent = content(of: row, named: "task row")
        guard let panel = panel(openedBy: row, named: "Task row") else { return }

        XCTContext.runActivity(
            named: "measured — window \(describe(app.windows.firstMatch.frame)); row box \(describe(rowFrame)); row CONTENT x ∈ "
            + "[\(Int(rowContent.minX)), \(Int(rowContent.maxX))] ;; "
            + reading(named: "Task row", anchor: rowFrame, panel: panel, spans: spans(rowFrame, rowContent))
        ) { _ in }
        assertPlacementIsSafe(content: rowContent, panel: panel, anchor: rowFrame, named: "Task row")
    }

    // MARK: - The assertion

    /// **The whole product requirement, as a relation between rectangles that are all on screen.**
    ///
    ///     the panel covers none of the content it was opened from,
    ///     unless the display itself has run out of room for it — and then it covers no more of it
    ///     than the panel is already spilling past the window's own edge.
    ///
    /// **The anchor is deliberately not in it, and that is a correction.** The first version of
    /// this assertion was a disjunction — *the anchor spans the content, OR the panel clears it* —
    /// with the anchor taken from what the source says each popover is attached to. It let the
    /// mutation through. Giving the card's tag popover an `attachmentAnchor` of a 57pt slot moved
    /// the panel to x ∈ [621, 887] across 209pt of a card whose content is [578, 830], and the test
    /// passed, because the test was still calling the anchor "the card". **An attachment anchor is
    /// not observable through the accessibility tree**; only the panel and the content are. A claim
    /// about a rectangle nothing on screen publishes is a claim read back out of the source, which
    /// is the circularity that let T-1510 pass while the app did the opposite. So the anchor is
    /// reported, never asserted, and the rule is about what a person can see.
    ///
    /// **The second clause is a relation, not an exemption.** A popover is its own window and can
    /// extend past the app's; when it does, it is because the *display* has no more room on that
    /// side, and the platform pulls it back over whatever is behind it. Measured 2026-09-30, window
    /// (40, 54, 1400, 858) on a 1512pt screen: Today's row inspector wanted x ∈ [1126, 1488] and
    /// came out at [1096, 1458], spilling 18pt past the window's trailing edge and covering 10pt of
    /// the row's due chip. Nothing about the anchor caused that and no anchor can undo it. But the
    /// spill **bounds** it: a panel pushed back further than it is spilling was pushed back by
    /// something else, and that something else is the defect. A panel hung off a 57pt chip at a
    /// row's leading end covers hundreds of points while spilling none.
    ///
    /// Never a point figure (T-1279 / T-1296) and never the side. Which end a panel leaves by is
    /// AppKit's; the end each one took is reported in the activity log, because which one the
    /// platform picked is the finding, and it is not a requirement.
    private func assertPlacementIsSafe(
        content container: CGRect,
        panel panelReading: Panel,
        anchor: CGRect,
        named name: String
    ) {
        let panel = panelReading.content
        let window = app.windows.firstMatch.frame

        // ── NON-VACUITY ───────────────────────────────────────────────────────────────────────
        // A panel with no area clears everything, and so does one that opened somewhere else
        // entirely. Neither is this test passing.
        XCTAssertGreaterThan(panel.width, 0, "the \(name) panel has no width, so it cannot be covering or clearing anything")
        XCTAssertGreaterThan(panel.height, 0, "the \(name) panel has no height")
        XCTAssertGreaterThan(container.width, 0, "the \(name) container draws nothing, so there is nothing to be clear of")
        XCTAssertGreaterThan(window.width, 0, "there is no window to measure the display's constraint against")
        let verticalOverlap = min(panel.maxY, container.maxY) - max(panel.minY, container.minY)
        XCTAssertGreaterThan(
            verticalOverlap, 0,
            "the \(name) panel shares no vertical space with the content it opened from, so it is not beside it at all"
        )

        // ── THE RULE ──────────────────────────────────────────────────────────────────────────
        let overlap = max(0, min(panel.maxX, container.maxX) - max(panel.minX, container.minX))
        let spill = max(0, max(panel.maxX - window.maxX, window.minX - panel.minX))
        XCTAssertLessThanOrEqual(
            overlap, spill + Self.tolerance,
            "the \(name) panel is at x ∈ [\(Int(panel.minX)), \(Int(panel.maxX))] and covers \(Int(overlap))pt of the "
            + "content it was opened from, x ∈ [\(Int(container.minX)), \(Int(container.maxX))]. It is spilling "
            + "\(Int(spill))pt past the window \(describe(window)), so the display's edge accounts for at most that "
            + "much of it. Its anchor is reported as x ∈ [\(Int(anchor.minX)), \(Int(anchor.maxX))], which is what "
            + "the source says it is attached to and not something this test can see."
        )
    }

    // MARK: - Opening and dismissing

    /// Click something, wait for a popover, and return its frame.
    ///
    /// `nil` rather than a throw: the caller is sweeping several anchors and a throw would end the
    /// run at the first one, which is the reporting failure this method exists to avoid.
    private func panel(openedBy control: XCUIElement, named name: String, rightClick: Bool = false) -> Panel? {
        if rightClick {
            control.rightClick()
        } else {
            control.click()
        }
        return settledPanel(named: name)
    }

    /// **What a container actually draws**, as the union of the frames of the elements it
    /// publishes — and this is the rectangle every assertion below is about.
    ///
    /// Not the container's own box. A `KanbanCard` is 282pt wide and pads its trailing edge by
    /// 16pt, and a `MacTaskRow` pads both of its; a panel hung flush off the trailing-most chip in
    /// either therefore overlaps the **box** while covering nothing at all. Measured 2026-09-30:
    /// the list picker at x ∈ [830, 1046] against a card box of [564, 846] and card content ending
    /// at 830. Asserting against the box would report a 16pt defect over empty padding, and a
    /// guard that cries at padding is a guard someone turns off.
    ///
    /// Derived from the live tree, like everything else here: `TaskInspectorPopoverMetrics` and
    /// friends are the app's own model of its layout, and reading the container off them is the
    /// circularity T-1510 passed through.
    private func content(of container: XCUIElement, named name: String) -> CGRect {
        let box = container.frame
        let frames = container.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.width > 0 && $0.height > 0 && box.intersects($0) }
            .map { $0.intersection(box) }
        guard let first = frames.first else {
            XCTFail("the \(name) publishes no child elements, so there is nothing to say it covers or clears")
            return box
        }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    private func settledPanel(named name: String) -> Panel? {
        let popover = app.popovers.firstMatch
        guard popover.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            XCTFail("clicking \(name) opened no popover. On screen: \(popoverFrames())")
            return nil
        }
        let frames = app.popovers.allElementsBoundByIndex.map(\.frame)
        guard let frame = frames.first else {
            XCTFail("\(name)'s popover exists but has no frame")
            return nil
        }
        XCTAssertEqual(frames.count, 1, "more than one popover is open, so the \(name) reading is ambiguous: \(popoverFrames())")
        return Panel(box: frame, content: content(of: popover, named: "\(name) panel"))
    }

    /// A panel as two rectangles: the element's box and **what it draws inside it**.
    ///
    /// An `XCUIElement`'s frame for a popover includes chrome the window does not draw into, which
    /// is already written into the inspector sweep as the reason a click 6pt inside a popover's top
    /// edge lands outside it. If that chrome had horizontal width, a panel whose *box* laps a card
    /// by a few points would be covering nothing, and asserting on the box would report it anyway.
    ///
    /// **Measured, it has none.** Across all six readings on 2026-09-30 the two rectangles came out
    /// byte-identical, so the chrome the inspector sweep hit is vertical only and every figure in
    /// this suite would be the same either way. The pair is kept because that is a reading of this
    /// Mac at this Xcode and not a guarantee, and because a run where they diverge should say so in
    /// the log rather than quietly change what the assertion means.
    private struct Panel {
        let box: CGRect
        let content: CGRect
    }

    /// Dismiss with a click **outside the panel and inside the window**, at a point derived from
    /// the two live frames.
    ///
    /// **Not Escape.** T-1742: measured three times on the inspector's panels, the panel was still
    /// on screen a full 5s after `app.typeKey(.escape)` with its frame unchanged.
    ///
    /// The point is the middle of whichever horizontal gap the panel leaves inside the window, low
    /// in the window where a day column is empty. Derived rather than guessed, because a fixed
    /// point is a point that lands on the panel exactly when the panel is where it should not be —
    /// which is the run where the reading matters most.
    private func dismiss(_ panelReading: Panel, named name: String) {
        let panel = panelReading.box
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let trailingGap = windowFrame.maxX - panel.maxX
        let leadingGap = panel.minX - windowFrame.minX
        let x = trailingGap >= leadingGap
            ? (max(panel.maxX, windowFrame.minX) + windowFrame.maxX) / 2
            : (windowFrame.minX + min(panel.minX, windowFrame.maxX)) / 2
        // Near the bottom of the window, which on both surfaces under test is empty column space.
        // **Not the window's own bottom edge**: an `XCUIElement`'s frame includes chrome the window
        // does not draw into, so a click a few points inside an edge can land outside it (measured
        // 2026-09-30, on the inspector's top edge).
        let y = windowFrame.maxY - 60

        window.coordinate(
            withNormalizedOffset: CGVector(
                dx: (x - windowFrame.minX) / windowFrame.width,
                dy: (y - windowFrame.minY) / windowFrame.height
            )
        ).click()

        XCTAssertTrue(
            app.popovers.firstMatch.waitForNonExistence(timeout: CadenceUITestBounds.settle),
            "the \(name) panel did not close on a click at (\(Int(x)), \(Int(y))), inside the window and clear of the "
            + "panel, so the next reading would see two panels. On screen: \(popoverFrames())"
        )
    }

    // MARK: - Navigation

    private func openCalendarBoard() throws {
        XCTAssertTrue(
            element(ID.seededAreaRow).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either"
        )
        let calendar = element(ID.calendarDestination)
        guard calendar.waitForExistence(timeout: CadenceUITestBounds.firstPaint) else {
            throw NotAddressable(message: "the sidebar has no Calendar row (\(ID.calendarDestination))")
        }
        calendar.click()

        // The Board presentation is a plain labelled button in the calendar's own header. It has no
        // identifier of its own and does not need one: "Board" is a single word on a control whose
        // text is not a field's value, so a label query here cannot stop matching for the reasons
        // T-1722's five composed rows could.
        let board = app.buttons["Board"]
        guard board.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            throw NotAddressable(message: "the calendar page offers no Board control; buttons: \(buttonLabels())")
        }
        board.click()
    }

    private struct NotAddressable: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    // MARK: - Small helpers

    /// Predicate-backed, via `CadenceUITestQuery` (T-1725): `ID.boardCard` and friends are slugged
    /// from titles, and the string subscript raises past 128 characters instead of not matching.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendant(identified: identifier)
    }

    private func spans(_ anchor: CGRect, _ container: CGRect) -> Bool {
        anchor.minX <= container.minX + Self.tolerance && anchor.maxX >= container.maxX - Self.tolerance
    }

    /// One line of the run log: where the source says the panel is attached, where it actually
    /// came out, and which side of that attachment it took.
    ///
    /// Every word of this is **reported and none of it is asserted**. The declared anchor is read
    /// out of the source by whoever wrote the call — it is not published by the accessibility tree
    /// and a run cannot check it, which is why the assertion above stopped using it. The side is
    /// AppKit's to choose. Both are here because they are the finding: T-1722 measured the
    /// inspector's five anchors opening off the edge *opposite* the one they declared, and this
    /// suite measured six more opening off the edge they declared — so the inversion is not a
    /// property of `arrowEdge:` and a fix that corrected an edge would have been fixing a
    /// coincidence.
    private func reading(named name: String, anchor: CGRect, panel: Panel, spans: Bool) -> String {
        let side = panel.content.midX < anchor.midX ? "leading" : "trailing"
        return "\(name): declared anchor \(describe(anchor)) (\(spans ? "spans" : "pinned inside") the content) "
            + "→ panel box \(describe(panel.box)) drawing \(describe(panel.content)) off its \(side) edge"
    }

    private func popoverFrames() -> String {
        let frames = app.popovers.allElementsBoundByIndex.map { describe($0.frame) }
        return frames.isEmpty ? "no popovers at all" : frames.joined(separator: " ;; ")
    }

    /// What the surface is actually publishing, for a failure message. "No such element" and "an
    /// element whose identifier is not the one this test computed" are different findings with the
    /// same symptom.
    private func identifiers(beginningWith prefix: String) -> String {
        app.identifiers(beginningWith: prefix)
    }

    private func buttonLabels() -> String {
        let found = app.buttons.allElementsBoundByIndex.prefix(40).map(\.label)
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
