// **[[T-3171]]'s seventh adoption slice, which has said NOT SEEN ON SCREEN since 2026-10-19.**
//
// The slice: the macOS Calendar's drag-to-create is the shared panel. `QuickCreateChoicePopover`
// held **zero** `CadenceSchedulePanel` references and now hosts it in create mode, with its own
// Task/Event tab strip, its second copy of the `~` list flow, and all 394 lines of
// `QuickCreateChoiceSupportViews.swift` deleted. It was computed and mutation-proven; nobody has
// ever watched it happen, because the gesture is a DRAG and `scripts/run-macos-app.sh` draws and
// captures a window but cannot click — [[T-3259]]'s limit (1).
//
// **What makes this checkable rather than a matter of opinion:** the shared panel's kind selector
// publishes `schedule-kind-task` and `schedule-kind-event`
// (`CadenceSchedulePanel.swift:1062`/`:1080`, `identifierPrefix` + `CadenceScheduleDraftKind`'s
// raw values). The popover's own deleted strip published nothing of the sort. So *the drag opened
// the shared panel* is one identifier lookup, not a judgement about how a form looks.
//
// Launch, window sizing and the windowless-launch skip are the same as
// `CadenceMacTodayAllDayBandUITests`' and documented there; the duplication is deliberate, since
// `CadenceAgentDefaultsIsolationTests` counts one `XCUIApplication()` against one
// `isolateStoreAndPreferences(` per file.
#if os(macOS)
import XCTest

@MainActor
final class CadenceMacCalendarDragCreateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testMacCalendarDragToCreateOpensTheSharedSchedulePanel() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: CadenceUITestBounds.firstPaint), "no main window")
        _ = resize(window, to: .fill)

        let calendar = app.buttons.element(identified: ID.calendarDestination)
        XCTAssertTrue(
            calendar.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the sidebar has no Calendar destination. " + surfaceReport()
        )
        calendar.click()

        // The fixture's own events are the proof the Calendar page actually drew its grid — an
        // empty page and a page that failed to load look identical to a drag.
        let anchor = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Fixture.timedEventTitle))
            .firstMatch
        XCTAssertTrue(
            anchor.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the Calendar page never drew the fixture's '\(Fixture.timedEventTitle)'. " + surfaceReport()
        )
        attach("mac-calendar")

        // ── THE DRAG. The grid is the tallest scroll view on the page; drag inside it, well below
        // the fixture's morning events, so the gesture lands on an empty slot rather than on a
        // block that would be dragged instead of creating one.
        let grid = try XCTUnwrap(
            app.scrollViews.allElementsBoundByIndex
                .filter { $0.frame.height > 0 && $0.frame.width > 0 }
                .max { $0.frame.height < $1.frame.height },
            "no scroll view on the Calendar page to drag in. " + surfaceReport()
        )
        // **Not `app.buttons.allElementsBoundByIndex`.** That read failed on 2026-11-04 with
        // `Failed to get matching snapshot: No matches found for Element at index 29`: the Calendar
        // page is still settling, so the button list shrinks between the index being taken and the
        // 29th element's `frame` being asked for, and the whole test dies on a staleness race that
        // has nothing to do with the drag. The fixture's own titles are a bounded, predicate-matched
        // query — the same shape `CadenceMacTodayAllDayBandUITests.timedBlocks()` uses.
        settle(Drag.settleBeforeReadingBlocks)
        let blocks = Fixture.timedEventTitles.compactMap { title in
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", title))
                .allElementsBoundByIndex
                .filter { $0.frame.width > 0 && $0.frame.height > 0 }
                .max { $0.frame.width < $1.frame.width }
        }.filter {
            grid.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        let lowestBlock = blocks.map(\.frame.maxY).max() ?? grid.frame.minY
        let startY = max(lowestBlock + Drag.clearanceBelowBlocks, grid.frame.midY)
        print(
            "MACDRAG grid=\(grid.frame) blocks=\(blocks.count) lowestBlockMaxY=\(lowestBlock) "
            + "startY=\(startY) labels=\(blocks.prefix(8).map(\.label))"
        )
        XCTAssertLessThan(
            startY + Drag.distance, grid.frame.maxY,
            "there is no clear room below the fixture's blocks to drag in. Grid \(grid.frame), "
            + "lowest block ends \(lowestBlock)."
        )

        // ── **FRONT-NESS, before the gesture rather than after the verdict.** Measured twice on
        // 2026-11-04: both failing runs dumped `Application … Disabled` with a foreign
        // `Dialog {{160.0, 183.0}, {280.0, 168.0}}` holding a `siri` button in front of the
        // window, and a disabled app receives no mouse events — so "the drag opened nothing" and
        // "the drag never reached the app" had the same symptom and different meanings. This
        // separates them: the state is printed, a stray dialog is dismissed, and the app is
        // clicked back to the front before anything is dragged.
        reportFront("before-front-restore")
        if app.dialogs.count > 0 {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            settle(Drag.settleBeforeReadingBlocks)
        }
        do {
            // A click on the page's own title text is inert — it selects nothing and navigates
            // nowhere — so it buys the front without changing what is on screen. Unconditional:
            // it was gated on `!app.isEnabled`, which is always true here (T-11472), so this is
            // the behaviour every measured run already had.
            app.descendants(matching: .staticText)
                .matching(NSPredicate(format: "value == %@", Fixture.pageTitle))
                .firstMatch
                .click()
            settle(Drag.settleBeforeReadingBlocks)
        }
        reportFront("after-front-restore")
        // **`app.isEnabled` is NOT a frontness signal for this app, and asserting on it cost a
        // run.** Measured 2026-11-04: the third run read `enabled=false windows=1 dialogs=0` with
        // nothing in front at all, and aborted here before dragging anything — while the
        // `CadenceMacRoundPlateHitAndHoverUITests` click flow, driving the same build in the same
        // hour, clicked the sidebar, the floating button and a date chip successfully against an
        // Application element that also reported `Disabled` in its tree dump. So the attribute is
        // reported and is NOT a precondition; what a run can say about the drag is decided from
        // `dialogs`, which IS meaningful, and from the gesture's own result.

        let start = grid.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: grid.frame.width * Drag.columnFraction, dy: startY - grid.frame.minY))
        let end = grid.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: grid.frame.width * Drag.columnFraction, dy: startY - grid.frame.minY + Drag.distance))
        start.press(forDuration: Drag.press, thenDragTo: end)
        settle(Drag.settle)
        attach("mac-calendar-after-drag")

        // ── THE SHARED PANEL, by the identifiers only it publishes.
        let taskChoice = app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifying(ID.scheduleKindTask))
            .firstMatch
        let created = taskChoice.waitForExistence(timeout: CadenceUITestBounds.firstPaint)

        // ── **THE NEGATIVE CONTROL, before any verdict is read from `created`.**
        //
        // A drag that creates nothing and a transport that cannot drag at all have the same
        // symptom, and on 2026-11-05 the run that removed the only other explanation — a foreign
        // dialog, dismissed here and confirmed gone — still saw nothing created. So before this
        // is reported as the product's behaviour, the SAME gesture is asked to do something the
        // app certainly supports: move an existing block. `XCUICoordinate.press(forDuration:
        // thenDragTo:)` synthesises a down, a wait, a move and an up, and whether SwiftUI's
        // `DragGesture` sees enough intermediate movement in that is exactly what is unknown.
        //
        // If the block MOVES and nothing was created, the transport drags and drag-create is the
        // finding. If the block does NOT move either, this transport cannot answer the question
        // and the run says so instead of blaming the code.
        let controlBlock = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Fixture.timedEventTitle))
            .allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
            .max { $0.frame.width < $1.frame.width }
        var controlMoved = false
        var controlBefore = CGRect.zero
        var controlAfter = CGRect.zero
        if let controlBlock {
            controlBefore = controlBlock.frame
            let from = controlBlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = controlBlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: Drag.controlDistance))
            from.press(forDuration: Drag.press, thenDragTo: to)
            settle(Drag.settle)
            controlAfter = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", Fixture.timedEventTitle))
                .allElementsBoundByIndex
                .filter { $0.frame.width > 0 && $0.frame.height > 0 }
                .max { $0.frame.width < $1.frame.width }?
                .frame ?? controlBefore
            controlMoved = abs(controlAfter.minY - controlBefore.minY) > Drag.controlMovedThreshold
        }
        print(
            "MACDRAG created=\(created) control block before=\(controlBefore) after=\(controlAfter) "
            + "moved=\(controlMoved) by=\(controlAfter.minY - controlBefore.minY)pt"
        )
        attach("mac-calendar-after-control-drag")

        if !created && !controlMoved {
            throw XCTSkip(
                """
                NOT ESTABLISHABLE WITH THIS TRANSPORT, and deliberately not reported as a defect. \
                The empty-slot drag created nothing AND the negative control — the same \
                `press(forDuration:thenDragTo:)` asked to move the fixture's \
                '\(Fixture.timedEventTitle)' block \(Drag.controlDistance)pt down — moved it \
                \(controlAfter.minY - controlBefore.minY)pt, i.e. not at all. So XCUITest's \
                synthesised drag does not reach this grid's gestures and says nothing about \
                drag-to-create. Block \(controlBefore) -> \(controlAfter).
                """
            )
        }

        XCTAssertTrue(
            created,
            """
            The drag did not open the shared CadenceSchedulePanel: nothing publishes \
            '\(ID.scheduleKindTask)'. Either the drag landed somewhere that creates nothing, or \
            QuickCreateChoicePopover is back to a form of its own. \(app.debugDescription)
            """
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(CadenceUITestQuery.identifying(ID.scheduleKindEvent))
                .firstMatch
                .exists,
            "the panel offers '\(ID.scheduleKindTask)' but not '\(ID.scheduleKindEvent)'"
        )
        attach("mac-calendar-shared-panel")
    }

    // MARK: - Fixtures

    private enum ID {
        /// `SidebarView.swift:345` — `"sidebar.destination.\(destination.rawValue)"`.
        static let calendarDestination = "sidebar.destination.calendar"
        /// `CadenceSchedulePanel`'s kind selector: `identifierPrefix` (`schedule-kind`) plus
        /// `CadenceScheduleDraftKind`'s raw values. The deleted popover form published neither.
        static let scheduleKindTask = "schedule-kind-task"
        static let scheduleKindEvent = "schedule-kind-event"
    }

    private enum Fixture {
        static let scenario = "calendar-hues"
        /// The earliest of the fixture's timed events, used only to prove the grid drew.
        static let timedEventTitle = "Deep red event"
        /// The Calendar page's own heading, clicked only to buy the front back. Inert.
        static let pageTitle = "Calendar"
        /// All three of the fixture's timed events on the staged day, so the lowest drawn block is
        /// found from a bounded query rather than from every button on the page.
        static let timedEventTitles = ["Deep red event", "Pure blue event", "Pale event"]
    }

    private enum Drag {
        /// Horizontal position inside the grid, as a fraction of its width. Mid-column rather than
        /// the edge, so the gesture cannot land on a divider or a scroll bar.
        static let columnFraction: CGFloat = 0.5
        /// How far below the lowest drawn block to start, so the press lands on empty time.
        static let clearanceBelowBlocks: CGFloat = 40
        /// Far enough to be a drag rather than a click, and about an hour on this ladder.
        static let distance: CGFloat = 70
        static let press: TimeInterval = 0.3
        /// **Not measured.** Let the Calendar page finish drawing before its blocks are read.
        static let settleBeforeReadingBlocks: TimeInterval = 1.5
        /// How far the negative control drags an existing block. A whole ladder hour, so a move
        /// cannot be confused with a jitter.
        static let controlDistance: CGFloat = 70
        /// A block counts as moved past this. Far above layout noise, far below the drag.
        static let controlMovedThreshold: CGFloat = 8
        static let settle: TimeInterval = 1.5
    }

    private enum Bounds {
        static let windowAppears: TimeInterval = 45
        static let launchAttempts = 3
        static let menuAppears: TimeInterval = 3
        static let resizeSettle: TimeInterval = 10
        static let paintAfterResize: TimeInterval = 1
    }

    // MARK: - Launching, and the windowless launch ([[T-8928]])

    private func launchApp() throws {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = Fixture.scenario
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "mac-drag-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )

        // [[T-8928]]: about half of macOS launches reach the foreground, own the menu bar and draw
        // no window at all. Seen twice in a row, so one relaunch is not enough; a skip is the
        // honest verdict for an inapplicable launch, and `scripts/xcb.sh` refuses a run that
        // executed nothing (T-552), so it cannot rot into a suite that skips for ever.
        for attempt in 1...Bounds.launchAttempts {
            if app.windows.firstMatch.waitForExistence(timeout: Bounds.windowAppears) {
                print("MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew a window")
                return
            }
            print(
                "MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew NO window in "
                + "\(Bounds.windowAppears)s (windows=\(app.windows.count) state=\(app.state.rawValue))"
            )
            guard attempt < Bounds.launchAttempts else { break }
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: CadenceUITestBounds.settle)
            app.launch()
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
                "relaunch \(attempt + 1) did not reach the foreground; state is \(app.state.rawValue)"
            )
        }
        throw XCTSkip(
            """
            The macOS app reached the foreground \(Bounds.launchAttempts) times and drew no window \
            any of them — [[T-8928]]. The same build draws immediately under \
            scripts/run-macos-app.sh, so this is the XCUITest launch path and not the code under \
            test. Nothing below ran.
            """
        )
    }

    // MARK: - Window control ([[T-3259]]'s limit 2)

    private enum WindowSize {
        case fill

        var menuItemTitle: String { "Fill" }
    }

    /// Through macOS's own Window ▸ Move & Resize, for the reasons measured in
    /// `CadenceMacTodayAllDayBandUITests`: View ▸ Enter Full Screen does not take, and a corner
    /// drag does nothing to a window macOS has already zoomed.
    @discardableResult
    private func resize(_ window: XCUIElement, to size: WindowSize) -> CGRect {
        let before = window.frame
        let windowMenu = app.menuBars.menuBarItems["Window"]
        guard windowMenu.waitForExistence(timeout: CadenceUITestBounds.settle) else {
            XCTFail("the app has no Window menu to resize through")
            return before
        }
        windowMenu.click()
        let moveAndResize = app.menuItems["Move & Resize"]
        if moveAndResize.waitForExistence(timeout: Bounds.menuAppears) {
            moveAndResize.click()
        }
        let item = app.menuItems
            .matching(NSPredicate(format: "title == %@ OR label == %@", size.menuItemTitle, size.menuItemTitle))
            .firstMatch
        guard item.waitForExistence(timeout: Bounds.menuAppears) else {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTFail("no '\(size.menuItemTitle)' item under Window ▸ Move & Resize")
            return window.frame
        }
        item.click()

        let deadline = Date().addingTimeInterval(Bounds.resizeSettle)
        var previous = before
        while Date() < deadline {
            settle(0.25)
            let current = window.frame
            if current != before, current == previous { break }
            previous = current
        }
        settle(Bounds.paintAfterResize)
        return window.frame
    }

    /// What is in front of the app. Not `isEnabled`, which reads false here even when a click
    /// lands (T-11472); `dialogs` is the signal that tracks a gesture going nowhere.
    private func reportFront(_ stage: String) {
        let dialogs = app.dialogs.allElementsBoundByIndex.map { "\($0.frame)" }
        print(
            "MACDRAG front[\(stage)] windows=\(app.windows.count) "
            + "dialogs=\(app.dialogs.count) \(dialogs.joined(separator: " "))"
        )
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "settle")], timeout: seconds)
    }

    // MARK: - Reporting

    private func surfaceReport() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(24).map(\.label).filter { !$0.isEmpty }
        return "the app's first static texts: " + (texts.isEmpty ? "none at all" : texts.joined(separator: " | "))
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
