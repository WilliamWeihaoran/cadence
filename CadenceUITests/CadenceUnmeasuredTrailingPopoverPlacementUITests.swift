// **macOS only — T-2074/T-2075.** Until this target was asked to build for an iOS Simulator it
// had no platform guards at all, because it had never been built for anything but macOS: it reaches
// AppKit, `XCUIElement.rightClick()`, `CGSessionCopyCurrentDictionary` and identifiers only the
// desktop surface publishes. The guard is here rather than around the individual call sites because
// nothing in this file is about iOS; the iOS half of the target is `CadenceIOSSeededStoreUITests`.
#if os(macOS)
import XCTest

/// **The two `arrowEdge: .trailing` sites [[T-1740]] left unmeasured**, read off the running
/// surface with the same instrument the other six were read with.
///
/// ### What was left, and why it was left
///
/// T-1740 swept the app's eight remaining `arrowEdge: .trailing` popovers and measured six of
/// them. It did not touch the other two, deliberately, and said so in its closing line: a site
/// nothing can put on screen is a site nobody has a reading of, and an untested change to one is
/// an argument. The two were filed as [[T-1843]] and [[T-1844]] rather than fixed.
///
/// | site | why it was unreachable | what this suite does about it |
/// |---|---|---|
/// | `CalendarBoardItemSupportViews` event card | drawn only for a real `EKEvent`, and the UI-test host holds no EventKit authorisation | `CalendarBoardUITestEventSupport` injects one unsaved event into the board's day query, under this scenario only |
/// | `TimelineDayCanvasShellViews` draft popover | exists only once a drag-to-create has been made on the timeline canvas | presses and drags on a live canvas frame, and reports what the gesture actually produced |
///
/// ### Two premises inherited from the tickets, and what happened to each
///
/// **T-1740's own premise was wrong and it closed saying so** — it generalised an inversion found
/// in the task inspector into "every `arrowEdge: .trailing` opens on the leading side", and then
/// six of six opened off the edge they declared. So nothing here expects an edge. The side is
/// reported and never asserted, exactly as in `CadenceBoardPopoverAnchorPlacementUITests`, and for
/// the same reason: which end a panel leaves by is AppKit's, weighed against the room left on the
/// display, and pinning it would make this suite fail on a moved window.
///
/// **T-1844's premise is wrong in a second, smaller way**, and it is worth writing down because it
/// is what made the test writable. The ticket says the draft block "exists only while a drag-to-
/// create is in flight", so reading its popover would need a measurement taken mid-gesture. It does
/// not. `TimelineDayCanvasStateSupport.commitDraftSelection` is the `onEnded` handler: it moves the
/// draft from `.live` to `.pending` and sets `showNewTaskPopover = true`. **The popover opens when
/// the pointer comes up and stays open afterwards** — the ghost is the mid-gesture half, the
/// popover is the after half. A `press(forDuration:thenDragTo:)` is therefore a sufficient
/// instrument, and nothing here has to read a frame while a button is held down.
///
/// ### The rule, restated
///
/// One relation between rectangles that are all on screen, copied verbatim in meaning from the
/// sweep this follows:
///
///     the panel covers none of the content it was opened from, unless the display itself has run
///     out of room for it — and then it covers no more of it than the panel is already spilling
///     past the window's own edge.
///
/// Never a point figure, never the side, and the attachment anchor reported rather than asserted —
/// with one difference. On the timeline the anchor **is** a view (`TimelineDraftPopoverAnchor`'s
/// `Color.clear`) and it now carries an identifier, so the claim T-1844 was filed with — "full
/// canvas width, so it spans its container by construction" — is read off the tree here instead of
/// off the source. That is the one thing T-1740 could not do for the sites it measured, and it is
/// the difference between a reading and a restatement.
///
/// ### Interactive
///
/// Both tests click, and one of them drags, so both are gated on
/// `CadenceUITestEnvironment.requireInteractiveUITests` — the marker-file channel, since the
/// environment variable cannot reach the runner (T-1724/T-1741). A default
/// `-only-testing:CadenceUITests` run skips them and `scripts/xcb.sh` says so by name.
@MainActor
final class CadenceUnmeasuredTrailingPopoverPlacementUITests: XCTestCase {

    /// Identifiers and fixture strings, restated because a UI-test bundle cannot import the app
    /// module. `CadenceAccessibilityIdentifiers` and `CadenceUITestScenarioSeed.Fixture` are the
    /// definitions; this is the mirror.
    private enum ID {
        static let seededAreaRow = "sidebar.list.area.alpha-area"
        /// The control for the row above: a sidebar destination **no seed creates**, so its absence
        /// means the launch drew nothing rather than that the seed failed. See T-1954 / T-2020.
        static let todayDestinationControl = "sidebar.destination.today"
        static let calendarDestination = "sidebar.destination.calendar"

        static let eventTitle = "Anchor Event"
        static let timelineCanvasPrefix = "timeline.day.canvas."
        static let draftBlock = "timeline.draft.block"
        static let draftAnchor = "timeline.draft.anchor"

        static func slug(_ value: String) -> String {
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }

        static var boardEventCard: String { "board.event.\(slug(eventTitle))" }
    }

    private enum Fixture {
        static let scenario = "popover-anchors"
    }

    /// One point, for a panel hung flush against its container's edge: the two boundaries are then
    /// the same coordinate and a rounding of the two frames through the accessibility tree must not
    /// read as an overlap. Same figure and same reason as the two sweeps this follows.
    private static let tolerance: CGFloat = 1

    /// How far down the canvas the drag-to-create travels. Comfortably past
    /// `TimelineCreateGridLayer`'s `minimumDistance: 8` — a gesture that does not clear it produces
    /// no draft at all, and "no draft" and "a draft whose popover is misplaced" are findings that
    /// must not share a symptom.
    private static let draftDragDistance: CGFloat = 72

    /// How much of a day column has to be **on screen** before a press inside it means anything.
    ///
    /// **Measured, and it is the reason this constant exists.** The first run of this test chose a
    /// column whose own frame was `(-106, -179, 154, 1308)` — the calendar's timeline had scrolled
    /// it almost entirely off the leading edge — leaving `8pt` of it inside the window. The press
    /// and the release both landed in that sliver, no draft appeared, and the test was one line
    /// away from reporting "XCUITest cannot drive this gesture" about a column that was not there.
    /// **The test is a relation, not a figure, for the reason this constant was wrong twice.** The
    /// first cut asked for `8pt` of a column and got the sliver. The second asked for `160pt` and
    /// rejected **every** column on the board, because a day column on this surface is `154pt`
    /// wide in total — so the threshold was wider than the thing it was measuring. What the test
    /// actually needs is a column the window is not clipping, which is a comparison between the
    /// column's own width and how much of it survives the intersection; the figure below is only a
    /// floor under "a column at all".
    private static let minimumUsableCanvasWidth: CGFloat = 60

    private var app: XCUIApplication!
    private var storeID: String!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        try CadenceUITestEnvironment.requireInteractiveUITests()
        // **True, deliberately** — a sweep that stops at its first bad reading reports nothing
        // about the rest, which is how sites stay unobserved. Every message names its site.
        continueAfterFailure = true
        storeID = "ui-unmeasured-popovers-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        storeID = nil
    }

    // MARK: - T-1843: the Calendar Board's event card

    func testTheCalendarBoardEventCardPanelOpensClearOfTheCardItIsOpenedFrom() throws {
        launchApp()
        try openCalendarBoard()

        let card = probe(ID.boardEventCard)
        XCTAssertTrue(
            card.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "no event card reached the Calendar Board, so T-1843's site is still unmeasured — and this run says "
            + "nothing about where its popover lands. The seam that puts one there is "
            + "`CalendarBoardUITestEventSupport`; board identifiers on screen: \(ids(beginningWith: "board."))"
        )
        let cardFrame = card.frame
        XCTAssertGreaterThan(cardFrame.width, 0, "the event card has no width, so every figure below is about nothing")

        let cardContent = drawnContent(of: card, named: "event card")
        guard let panel = panelOpened(by: card, named: "Board event") else {
            XCTFail("the event card opened no popover, so the site is reachable but still unmeasured")
            return
        }

        XCTContext.runActivity(
            named: "measured — window \(rect(app.windows.firstMatch.frame)); event card box \(rect(cardFrame)); "
            + "card CONTENT x ∈ [\(Int(cardContent.minX)), \(Int(cardContent.maxX))] ;; "
            + line(named: "Board event", anchor: cardFrame, panel: panel, spans: spansIt(cardFrame, cardContent))
        ) { _ in }

        assertPanelIsClear(of: cardContent, panel: panel, anchor: cardFrame, named: "Board event")
        dismissPanel(panel, named: "Board event")
    }

    // MARK: - T-1844: the timeline's drag-to-create draft

    func testTheTimelineDraftPanelOpensClearOfTheDraftItIsOpenedFrom() throws {
        launchApp()
        try openCalendarTimeline()

        let window = app.windows.firstMatch.frame
        guard let canvas = emptyDayCanvas(in: window) else {
            throw XCTSkip(
                "the calendar's timeline published no day canvas with a visible empty area, so there is nowhere a "
                + "drag-to-create could be made and no draft popover to read. Canvases on screen: "
                + ids(beginningWith: ID.timelineCanvasPrefix)
            )
        }

        let visible = canvas.frame.intersection(window)
        let pressPoint = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.3)
        let releasePoint = CGPoint(x: pressPoint.x, y: pressPoint.y + Self.draftDragDistance)
        let attempts = dragAttempts(from: pressPoint, to: releasePoint)

        // **The skip T-1844 asked for, if it comes to that.** A gesture XCUITest cannot deliver is a
        // full result, provided it is reported as a measurement rather than as a red line or a
        // deleted test — `windowreal` settled that shape for the sidebar reorder. What makes this
        // one a measurement is the canvas: the press and the release are both inside a rectangle
        // this run read off the tree, so "the draft did not appear" cannot be "the drag landed
        // somewhere else on the screen".
        let draftBlock = probe(ID.draftBlock)
        let draftAnchor = probe(ID.draftAnchor)
        let anchorArrived = draftAnchor.exists || draftBlock.exists
        guard anchorArrived || draftAnchor.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            throw XCTSkip(
                """
                \(attempts.count) different XCUITest drag APIs — \(attempts.joined(separator: ", ")) — \
                each dragging \(Int(Self.draftDragDistance))pt from \
                (\(Int(pressPoint.x)), \(Int(pressPoint.y))) to (\(Int(releasePoint.x)), \(Int(releasePoint.y))), \
                both inside the live canvas \(rect(canvas.frame)) clipped to the window \(rect(window)) at \
                \(rect(visible)), produced neither `\(ID.draftBlock)` nor `\(ID.draftAnchor)`. So no drag this \
                target can synthesize reaches `TimelineCreateGridLayer`'s `DragGesture(minimumDistance: 8)`, \
                and T-1844's site cannot be driven from here. **That is the measurement, not a defect in the \
                placement it was asked about** — the question T-1844 poses about where the draft popover \
                lands is still open, and it is open because the gesture is undrivable rather than because \
                anything was found wrong. Popovers on screen: \(panelFrames()); \
                timeline identifiers: \(ids(beginningWith: "timeline."))
                """
            )
        }

        // Both rectangles, because they are two different claims. The block is what a person sees;
        // the anchor is what the popover is attached to, and T-1844 asserts from source that it is
        // the full canvas width. Neither is taken on trust.
        let blockFrame = draftBlock.exists ? draftBlock.frame : CGRect.null
        let anchorFrame = anchorArrived ? draftAnchor.frame : blockFrame
        let container = blockFrame.isNull ? anchorFrame : blockFrame

        guard let panel = settledPanel(named: "Timeline draft") else {
            XCTFail(
                "the drag made a draft — block \(rect(blockFrame)), anchor \(rect(anchorFrame)) — but no popover "
                + "opened from it, so the placement is still unmeasured"
            )
            return
        }

        XCTContext.runActivity(
            named: "measured — window \(rect(window)); canvas \(rect(canvas.frame)) visible \(rect(visible)); "
            + "draft block \(rect(blockFrame)); draft ANCHOR \(rect(anchorFrame)) "
            + "(\(spansIt(anchorFrame, canvas.frame) ? "spans" : "pinned inside") the canvas) ;; "
            + line(named: "Timeline draft", anchor: anchorFrame, panel: panel, spans: spansIt(anchorFrame, container))
        ) { _ in }

        assertPanelIsClear(of: container, panel: panel, anchor: anchorFrame, named: "Timeline draft")
        dismissPanel(panel, named: "Timeline draft")
    }

    // MARK: - The assertion

    /// **The product requirement, as a relation between rectangles that are all on screen.**
    ///
    ///     the panel covers none of the content it was opened from,
    ///     unless the display itself has run out of room for it — and then it covers no more of it
    ///     than the panel is already spilling past the window's own edge.
    ///
    /// The anchor is reported and never asserted. On the board that is forced: an attachment anchor
    /// is not published by the accessibility tree, and the first cut of the sweep this follows let
    /// a mutation through precisely by believing the source about one. On the timeline the anchor
    /// is addressable, and it is still only reported — the requirement is about what a person can
    /// see covered, and a spanning anchor is an explanation for a clear panel rather than a
    /// substitute for measuring one.
    ///
    /// The second clause is a relation and not an exemption. A popover is its own window and can
    /// extend past the app's; when it does, the platform has pulled it back over whatever is
    /// behind it because the display ran out of room, and no anchor can undo that. The spill
    /// **bounds** it: a panel pushed back further than it is spilling was pushed by something else.
    private func assertPanelIsClear(
        of container: CGRect,
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
            + "\(Int(spill))pt past the window \(rect(window)), so the display's edge accounts for at most that "
            + "much of it. Its anchor reads x ∈ [\(Int(anchor.minX)), \(Int(anchor.maxX))]."
        )
    }

    // MARK: - Opening, reading and dismissing

    /// A panel as two rectangles: the element's box and **what it draws inside it**.
    ///
    /// An `XCUIElement`'s frame for a popover includes chrome the window does not draw into —
    /// established on the inspector sweep, where a click 6pt inside a popover's top edge landed
    /// outside it. The board sweep then measured the two rectangles coming out byte-identical for
    /// all six of its readings, so the chrome is vertical only on that Mac at that Xcode. The pair
    /// is kept because that is a reading and not a guarantee, and a run where they diverge should
    /// say so in the log rather than quietly change what the assertion means.
    private struct Panel {
        let box: CGRect
        let content: CGRect
    }

    private func panelOpened(by control: XCUIElement, named name: String) -> Panel? {
        control.click()
        return settledPanel(named: name)
    }

    private func settledPanel(named name: String) -> Panel? {
        let popover = app.popovers.firstMatch
        guard popover.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            XCTFail("\(name) opened no popover. On screen: \(panelFrames())")
            return nil
        }
        let frames = app.popovers.allElementsBoundByIndex.map(\.frame)
        guard let frame = frames.first else {
            XCTFail("\(name)'s popover exists but has no frame")
            return nil
        }
        XCTAssertEqual(frames.count, 1, "more than one popover is open, so the \(name) reading is ambiguous: \(panelFrames())")
        return Panel(box: frame, content: drawnContent(of: popover, named: "\(name) panel"))
    }

    /// **What a container actually draws**, as the union of the frames of the elements it
    /// publishes — and this is the rectangle every assertion here is about.
    ///
    /// Not the container's own box. A board card pads its trailing edge by 16pt, so a panel hung
    /// flush off the trailing-most chip overlaps the **box** while covering nothing at all; the
    /// sweep this follows measured exactly that and would have reported a 16pt defect over empty
    /// padding. A guard that cries at padding is a guard someone turns off.
    private func drawnContent(of container: XCUIElement, named name: String) -> CGRect {
        let box = container.frame
        let frames = container.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.width > 0 && $0.height > 0 && box.intersects($0) }
            .map { $0.intersection(box) }
        guard let first = frames.first else {
            // Not a failure here, unlike on a card: the timeline's draft ghost is one drawn
            // rectangle with nothing addressable inside it, and its own box IS what it draws.
            return box
        }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Dismiss with a click **outside the panel and inside the window**, at a point derived from
    /// the two live frames.
    ///
    /// **Not Escape.** T-1742: measured three times on the inspector's panels, the panel was still
    /// on screen a full 5s after `app.typeKey(.escape)` with its frame unchanged.
    ///
    /// A fixed point is a point that lands on the panel exactly when the panel is where it should
    /// not be — which is the run where the reading matters most — so the point is the middle of
    /// whichever horizontal gap the panel leaves inside the window, low in the window. **Not the
    /// window's own bottom edge**: an element's frame includes chrome the window does not draw
    /// into, so a click a few points inside an edge can land outside it.
    private func dismissPanel(_ panelReading: Panel, named name: String) {
        let panel = panelReading.box
        let windowFrame = app.windows.firstMatch.frame
        let trailingGap = windowFrame.maxX - panel.maxX
        let leadingGap = panel.minX - windowFrame.minX
        let x = trailingGap >= leadingGap
            ? (max(panel.maxX, windowFrame.minX) + windowFrame.maxX) / 2
            : (windowFrame.minX + min(panel.minX, windowFrame.maxX)) / 2
        let y = windowFrame.maxY - 60
        point(CGPoint(x: x, y: y)).click()

        XCTAssertTrue(
            app.popovers.firstMatch.waitForNonExistence(timeout: CadenceUITestBounds.settle),
            "the \(name) panel did not close on a click at (\(Int(x)), \(Int(y))), inside the window and clear of the "
            + "panel. On screen: \(panelFrames())"
        )
    }

    // MARK: - Navigation

    /// The sidebar's Calendar row, with the blank-launch control in front of it.
    ///
    /// **The control, and the reason it is here** (T-1954, refuted by `seedrace` in `acd36856`).
    /// `sidebar.destination.today` is a STATIC sidebar row — `SidebarView` builds it from
    /// `destination.rawValue` and no seed creates it — so it is present in any launch that drew a
    /// sidebar at all. Roughly 2 in 40 launches draw no UI whatsoever (T-2020), and a suite that
    /// waits only on a seeded row files those as a defect in whatever it was looking for. That is
    /// exactly how T-1954 was mis-filed.
    private func openCalendar() throws {
        XCTAssertTrue(
            probe(ID.todayDestinationControl).waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the sidebar drew no static Today row, so this launch drew no UI at all — nothing below is "
            + "evidence about the seed, the seam, or any popover. See T-2020."
        )
        XCTAssertTrue(
            probe(ID.seededAreaRow).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the stock seed's sidebar lists never appeared, so the scenario seed cannot be trusted either. "
            + "On screen: \(ids(beginningWith: "sidebar."))"
        )
        let calendar = probe(ID.calendarDestination)
        guard calendar.waitForExistence(timeout: CadenceUITestBounds.firstPaint) else {
            throw NotAddressable(
                message: "the sidebar has no Calendar row (\(ID.calendarDestination)). "
                + "On screen: \(ids(beginningWith: "sidebar.")). TREE: \(treeDump())"
            )
        }
        calendar.click()
    }

    private func openCalendarBoard() throws {
        try openCalendar()
        // A plain labelled button in the calendar's own header, with no identifier of its own and
        // no need for one: "Board" is a single word on a control whose text is not a field's value.
        let board = app.buttons["Board"]
        guard board.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            throw NotAddressable(message: "the calendar page offers no Board control; buttons: \(buttonLabels())")
        }
        board.click()
    }

    /// The timeline is the calendar page's **default** presentation
    /// (`CalendarPageView.presentation = .timeline`), so arriving on the page is arriving on it.
    /// Nothing is clicked, and that is checked rather than assumed: a canvas has to show up.
    private func openCalendarTimeline() throws {
        try openCalendar()
        let anyCanvas = app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifiers(beginningWith: ID.timelineCanvasPrefix))
            .firstMatch
        guard anyCanvas.waitForExistence(timeout: CadenceUITestBounds.firstPaint) else {
            throw NotAddressable(
                message: "the calendar page drew no timeline day canvas; identifiers: \(ids(beginningWith: "timeline."))"
            )
        }
    }

    /// A day column with **nothing on it**, chosen from the live tree rather than from a date this
    /// test computed.
    ///
    /// The scenario seeds a scheduled task and a block on today, and
    /// `TimelineCreateGridLayer.shouldHandle` refuses a drag that starts inside a drawn block — so
    /// a press on today's column can silently produce no draft and the run would report T-1844's
    /// site as undrivable when what it hit was its own fixture. Picking the emptiest visible column
    /// avoids that without needing the two processes to agree on a time zone or on which side of
    /// midnight they are.
    ///
    /// The intersection with the window is not tidiness either: the canvas is a full 24 hours tall
    /// inside a scroll view, so most of its frame is off screen, and a normalized offset into it
    /// would press at a coordinate the window never draws.
    private func emptyDayCanvas(in window: CGRect) -> XCUIElement? {
        let canvases = app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifiers(beginningWith: ID.timelineCanvasPrefix))
            .allElementsBoundByIndex
        let usable = canvases.filter { canvas in
            let visible = canvas.frame.intersection(window)
            let box = canvas.frame
            return !visible.isNull
                && box.width >= Self.minimumUsableCanvasWidth
                && visible.width >= box.width - Self.tolerance
                && visible.height >= Self.draftDragDistance * 3
        }
        // Fewest children first — an empty day — and the **wider** of two equally empty ones,
        // because a column the scroll view has clipped to a sliver is the emptiest thing on
        // screen and is exactly what the first version of this chooser picked.
        return usable.min { lhs, rhs in
            let lhsCount = lhs.descendants(matching: .any).count
            let rhsCount = rhs.descendants(matching: .any).count
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return lhs.frame.intersection(window).width > rhs.frame.intersection(window).width
        }
    }

    private struct NotAddressable: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    // MARK: - Small helpers

    /// Predicate-backed, via `CadenceUITestQuery` (T-1725): the string subscript caps identifiers
    /// at 128 characters and raises rather than failing to match.
    private func probe(_ identifier: String) -> XCUIElement {
        app.descendant(identified: identifier)
    }

    /// **Every drag this target can synthesize, tried in turn, and named.**
    ///
    /// Returns the APIs it ran. A single failing spelling says nothing — XCUITest has three, they
    /// deliver different event streams, and a SwiftUI `DragGesture(minimumDistance: 8)` is
    /// sensitive to how many moves arrive between the press and the release. `click(forDuration:
    /// thenDragTo:)` is first because it is the **macOS** spelling; the two `press` forms are the
    /// iOS ones, and the four-argument one is the one that takes a velocity and a trailing hold.
    ///
    /// Each attempt is skipped once a draft exists, so a run that works on the first API does not
    /// then drag three more times across the canvas and leave the surface somewhere else.
    private func dragAttempts(from start: CGPoint, to end: CGPoint) -> [String] {
        var ran: [String] = []

        func attempt(_ name: String, _ body: () -> Void) {
            guard !draftExists() else { return }
            ran.append(name)
            body()
            _ = probe(ID.draftAnchor).waitForExistence(timeout: 1)
        }

        attempt("click(forDuration:thenDragTo:)") {
            point(start).click(forDuration: 0.3, thenDragTo: point(end))
        }
        attempt("press(forDuration:thenDragTo:)") {
            point(start).press(forDuration: 0.3, thenDragTo: point(end))
        }
        attempt("press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)") {
            point(start).press(
                forDuration: 0.3,
                thenDragTo: point(end),
                withVelocity: .slow,
                thenHoldForDuration: 0.6
            )
        }
        return ran
    }

    private func draftExists() -> Bool {
        probe(ID.draftAnchor).exists || probe(ID.draftBlock).exists
    }

    /// A screen point as something clickable, derived from the window's own live frame.
    private func point(_ location: CGPoint) -> XCUICoordinate {
        let window = app.windows.firstMatch
        let frame = window.frame
        return window.coordinate(
            withNormalizedOffset: CGVector(
                dx: (location.x - frame.minX) / max(frame.width, 1),
                dy: (location.y - frame.minY) / max(frame.height, 1)
            )
        )
    }

    private func spansIt(_ anchor: CGRect, _ container: CGRect) -> Bool {
        anchor.minX <= container.minX + Self.tolerance && anchor.maxX >= container.maxX - Self.tolerance
    }

    /// One line of the run log: where the panel is attached, where it actually came out, and which
    /// side of that attachment it took. **Reported, never asserted.**
    private func line(named name: String, anchor: CGRect, panel: Panel, spans: Bool) -> String {
        let side = panel.content.midX < anchor.midX ? "leading" : "trailing"
        return "\(name): anchor \(rect(anchor)) (\(spans ? "spans" : "pinned inside") the content) "
            + "→ panel box \(rect(panel.box)) drawing \(rect(panel.content)) off its \(side) edge"
    }

    private func panelFrames() -> String {
        let frames = app.popovers.allElementsBoundByIndex.map { rect($0.frame) }
        return frames.isEmpty ? "no popovers at all" : frames.joined(separator: " ;; ")
    }

    /// What the surface is actually publishing, for a failure message. "No such element" and "an
    /// element whose identifier is not the one this test computed" are different findings with the
    /// same symptom.
    private func ids(beginningWith prefix: String) -> String {
        app.identifiers(beginningWith: prefix)
    }

    /// The window's own accessibility tree, truncated. The `BEGINSWITH` diagnostic above has been
    /// seen to answer "none at all" in a run where a `sidebar.…` identifier had just resolved, so
    /// it is not on its own a reading of what is on screen; this is.
    private func treeDump() -> String {
        String(app.windows.firstMatch.debugDescription.prefix(4000))
    }

    private func buttonLabels() -> String {
        let found = app.buttons.allElementsBoundByIndex.prefix(40).map(\.label)
        return found.isEmpty ? "none at all" : found.joined(separator: " ;; ")
    }

    private func rect(_ value: CGRect) -> String {
        guard !value.isNull else { return "(none)" }
        return "(\(Int(value.minX)), \(Int(value.minY)), \(Int(value.width)), \(Int(value.height)))"
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
#endif
