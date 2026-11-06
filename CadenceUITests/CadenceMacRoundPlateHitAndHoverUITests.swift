// **[[T-10803]]'s macOS half and [[T-11322]]'s macOS counterpart, asked of ONE control.**
//
// [[T-9601]] moved ten round-plated buttons onto `.cadencePlain(.circle)` / `.capsule`, whose body
// is `configuration.label.contentShape(plate.hitShape)` plus a `Circle()` wash and a
// `Circle().strokeBorder` (`Cadence/Shared/CadenceHoverStyles.swift:73-89`). Two separate claims
// ride on that one line, and `CadencePlainPlateRadiusTests` can prove NEITHER, because it reads
// the SOURCE shape and not the region the window server hit-tests:
//
//   (a) **the hit region shrinks to the plate.** [[T-11322]] measured this FALSE on iOS twice
//       (iPhone 393pt, iPad 1210pt): a tap 4.54pt / 8.9pt outside the drawn circle still selected
//       the day, so the region is still the layout RECTANGLE. The macOS branch is a different
//       branch of the same `#if`, so iOS's answer carries no weight here either way.
//   (b) **the hover wash is drawn in the plate's shape**, with its edge meeting the plate and no
//       rounded-rectangle corners outside it. Hover exists only on macOS; this is the only place
//       the question can be asked at all.
//
// **The control: the root floating New Task button** (`macOSRootSupportViews.swift:306`,
// `FloatingNewTaskButton`), which is [[T-10803]]'s clause (6). It is chosen over the other nine
// because it needs NO navigation — `TodayView.swift:42` overlays it on the default destination —
// and because its geometry is literal rather than computed: a 54pt square frame holding a
// `clipShape(Circle())`, so the inscribed circle's radius is exactly 27pt and a frame corner sits
// 27·√2 = 38.18pt from the centre, **11.18pt outside the drawn circle and still inside the frame**.
// That is the measurement [[T-11322]] had to derive from a compressed `LazyVGrid`; here it is
// fixed by two constants in the source.
//
// **How a click's verdict is read, and why it is not "did something happen".** The centre click is
// a POSITIVE CONTROL first: it must open the composer, which is `taskCreationManager.present(...)`
// and which publishes the shared panel's kind selector `schedule-kind-task`
// (`CadenceSchedulePanel.swift:1083`). Only once that has been seen to open and close is the
// corner click's verdict meaningful. Underneath the button's bottom-trailing corner is the 24pt
// `edgeInset` of page background, so a corner click that opens the composer can only have come
// from the button itself.
//
// **What this does NOT cover, said rather than implied:** the other five hovers [[T-10803]] names
// (the date-picker day cell and its quick pill, the Focus overlay close button, the inbox
// completion circle, the Settings tag swatch) are each behind navigation and are untouched here.
#if os(macOS)
import XCTest

@MainActor
final class CadenceMacRoundPlateHitAndHoverUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    /// **Terminate AND WAIT.** `terminate()` is asynchronous, and five of these tests launching
    /// back to back in one process is enough for the next `launch()` to collide with the last
    /// app's teardown. Measured 2026-11-05: run each test alone and all five pass; run the suite
    /// and four fail on the environment rather than on a measurement — `app did not reach the
    /// foreground; state is 3` (still `runningBackground`), `No matches found for ... Descendants
    /// matching type Window`, and twice `the app's first static texts: none at all` from a handle
    /// that resolved during `launchApp()` and was stale a line later. None of those is about the
    /// plate being measured, which is exactly why the wait belongs here and not in a bound
    /// somewhere downstream.
    override func tearDownWithError() throws {
        if let app {
            app.terminate()
            let stopped = app.wait(for: .notRunning, timeout: CadenceUITestBounds.settle)
            if !stopped {
                print("MACWINDOW teardown: app still \(app.state.rawValue) after \(CadenceUITestBounds.settle)s")
            }
        }
        app = nil
    }

    func testTheFloatingNewTaskButtonsRoundPlateHitRegionAndHoverWash() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp()
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: Bounds.windowAppears) else {
            attach("mac-no-window")
            XCTFail("no main window after \(Bounds.windowAppears)s. \(surfaceReport())")
            return
        }

        let today = app.buttons.element(identified: ID.todayDestination)
        XCTAssertTrue(
            today.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the sidebar never drew its Today destination. " + surfaceReport()
        )
        today.click()

        let plus = app.buttons
            .matching(NSPredicate(format: "label == %@ OR title == %@", Fixture.newTaskLabel, Fixture.newTaskLabel))
            .allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let button = plus.max(by: { $0.frame.minY < $1.frame.minY }) else {
            attach("mac-no-floating-button")
            XCTFail("Today drew no '\(Fixture.newTaskLabel)' button at all. " + surfaceReport())
            return
        }
        let frame = button.frame
        print("ROUNDPLATE floating button frame=\(frame)")

        // ── GEOMETRY, measured off the element rather than assumed from the source constants.
        // The frame is the style's plate: a square, because `FloatingNewTaskButton` sets
        // `.frame(width: 54, height: 54)` on its label and the style adds no padding.
        XCTAssertEqual(
            frame.width, frame.height, accuracy: Bounds.squareTolerance,
            "the floating button's frame \(frame) is not square, so there is no inscribed circle to "
            + "measure a corner against"
        )
        let radius = min(frame.width, frame.height) / 2
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        // The corner of the frame, pulled in by `cornerInset` so the probe is unambiguously INSIDE
        // the frame and cannot be read as a miss by one point of rounding.
        let probeDX = frame.width / 2 - Bounds.cornerInset
        let probeDY = frame.height / 2 - Bounds.cornerInset
        let probeDistance = (probeDX * probeDX + probeDY * probeDY).squareRoot()
        let outsideBy = probeDistance - radius
        print(
            "ROUNDPLATE radius=\(radius)pt centre=\(centre) probeOffset=(\(probeDX), \(probeDY)) "
            + "probeDistance=\(probeDistance)pt outsideCircleBy=\(outsideBy)pt"
        )
        XCTAssertGreaterThan(
            outsideBy, Bounds.minimumMargin,
            """
            the corner probe is only \(outsideBy)pt outside the \(radius)pt circle, which is not \
            enough margin to call a hit either way. Frame \(frame).
            """
        )

        // ── (b) THE HOVER WASH. Taken as a pixel DIFFERENCE between the same rectangle unhovered
        // and hovered, so nothing has to be known about the palette. The pointer is parked far from
        // the button first: a run that inherits the pointer already over it would diff two hovered
        // shots and report no wash at all.
        parkPointer(away: frame, in: window)
        let cold = try XCTUnwrap(shot(of: window), "could not read the window as pixels, unhovered")
        button.hover()
        settle(Bounds.hoverSettle)
        let warm = try XCTUnwrap(shot(of: window), "could not read the window as pixels, hovered")
        attach("mac-floating-hovered")

        let wash = changedPixels(cold: cold, warm: warm, window: window.frame, plate: frame)
        print(
            "ROUNDPLATE hover changed \(wash.count) px inside the plate; "
            + "insideCircle=\(wash.insideCircle) outsideCircle=\(wash.outsideCircle) "
            + "maxRadiusChanged=\(wash.maximumRadius)pt plateRadius=\(radius)pt"
        )
        // Stated as a RELATION, never as a colour or a count: what the ticket asks is whether the
        // wash's edge MEETS the plate, i.e. whether anything lit outside the circle the style says
        // it paints. `outsideCircle` counts pixels that changed beyond `radius + tolerance`.
        XCTAssertGreaterThan(
            wash.count, 0,
            """
            hovering the floating New Task button changed NOTHING in its own \(frame) plate. Either \
            the hover wash does not fire for this control or it is invisible behind the opaque blue \
            circle the button already draws — both are findings, and neither is what [[T-10803]] \
            clause (6) asks to see. \(surfaceReport())
            """
        )
        XCTAssertEqual(
            wash.outsideCircle, 0,
            """
            \(wash.outsideCircle) pixel(s) lit OUTSIDE the \(radius)pt circle the style says it \
            paints (furthest \(wash.maximumRadius)pt from centre), so the wash is not the plate's \
            shape — rounded-rectangle corners are showing. Frame \(frame).
            """
        )

        // ── (a) THE HIT REGION. Positive control first.
        parkPointer(away: frame, in: window)
        settle(Bounds.hoverSettle)
        XCTAssertFalse(
            composerIsOpen(),
            "the composer was already open before the positive control clicked anything"
        )
        button.click()
        let centreOpened = waitForComposer()
        attach("mac-centre-click")
        XCTAssertTrue(
            centreOpened,
            """
            the POSITIVE CONTROL failed: clicking the floating New Task button at its centre did \
            not open the composer within \(Bounds.composerAppears)s, so a corner click's verdict \
            would mean nothing. \(surfaceReport())
            """
        )
        guard centreOpened else { return }
        dismissComposer()
        XCTAssertFalse(
            composerIsOpen(),
            "the composer did not close on Escape, so the corner probe cannot be read"
        )

        // The corner: inside the square frame, `outsideBy`pt outside the drawn circle.
        let corner = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: probeDX, dy: probeDY))
        corner.click()
        let cornerOpened = waitForComposer()
        attach("mac-corner-click")
        print(
            "ROUNDPLATE corner click at centre+(\(probeDX), \(probeDY)) — "
            + (cornerOpened ? "OPENED the composer: the hit region is the RECTANGLE"
                            : "did NOT open the composer: the circle is honoured")
        )
        if cornerOpened { dismissComposer() }

        XCTAssertFalse(
            cornerOpened,
            """
            `.cadencePlain(.circle)`'s `contentShape(plate.hitShape)` is NOT honoured on macOS \
            either: a click \(probeDistance)pt from the centre — \(outsideBy)pt OUTSIDE the \
            \(radius)pt circle the button draws and clips to, and inside its \(frame.width)pt \
            square frame — opened the composer. That is [[T-11322]]'s iOS signature repeating on \
            the desktop branch. Frame \(frame).
            """
        )
    }

    /// **[[T-10803]] clauses (1) and (2), on the control [[T-11322]] is actually about.**
    ///
    /// The floating button answers the style; this answers the `CadenceDatePicker` day cell and its
    /// quick pill, which are the SHARED component iOS failed on twice. Reached without navigation
    /// beyond the composer: `CreateTaskSheet.swift:103` binds Cmd+Shift+T to `showDoPicker = true`,
    /// so one keystroke opens the picker the entry names.
    ///
    /// Three things are measured here and each is stated as a relation, never as a pinned size:
    /// the day cell's hover wash is drawn in a circle that meets its plate; a CLICK on the cell's
    /// corner, outside that circle, is or is not honoured; and the quick pill's wash is drawn in a
    /// capsule that meets the pill.
    func testTheDatePickersDayCellAndQuickPillPlatesOnMacOS() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp()
        // **No second `app.windows.firstMatch.waitForExistence` here.** `launchApp()` already
        // loops until a window draws and skips if none ever does ([[T-8928]]), and re-asking cost
        // a run on 2026-11-05: the log reads `MACWINDOW launch 1 of 3 drew a window` and then the
        // very next line failed with `no main window after 45.0s`, so the handle went stale
        // between the two reads rather than the window going away. Nothing below this test needs
        // the main window anyway -- every measurement is taken of the picker's POPOVER -- so the
        // real readiness check is the sidebar row, which is asked for next.
        let today = app.buttons.element(identified: ID.todayDestination)
        XCTAssertTrue(today.waitForExistence(timeout: Bounds.windowAppears), surfaceReport())
        today.click()

        let plus = app.buttons
            .matching(NSPredicate(format: "label == %@ OR title == %@", Fixture.newTaskLabel, Fixture.newTaskLabel))
            .allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let button = plus.max(by: { $0.frame.minY < $1.frame.minY }) else {
            attach("picker-no-floating-button")
            XCTFail("Today drew no '\(Fixture.newTaskLabel)' button. " + surfaceReport())
            return
        }
        button.click()
        guard waitForComposer() else {
            attach("picker-no-composer")
            XCTFail("the composer did not open, so the date picker cannot be reached. " + surfaceReport())
            return
        }

        // **The chip, not the shortcut.** `CreateTaskSheet.swift:103` does bind Cmd+Shift+T to
        // `showDoPicker = true`, and sending it with `typeKey` drew **0** day cells on 2026-11-04
        // — the keystroke does not reach the composer's hidden zero-sized shortcut button from
        // here. `TaskDateChip` (`CreateTaskSheetSupportViews.swift:222`) is a real Button carrying
        // `.cadenceControlLabel("Do Date")` whose action toggles the same popover, so it is
        // clicked instead.
        let chip = app.buttons
            .matching(NSPredicate(format: "label == %@ OR title == %@", Fixture.doDateLabel, Fixture.doDateLabel))
            .allElementsBoundByIndex
            .first { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let chip = chip else {
            attach("picker-no-chip")
            XCTFail(
                "the composer drew no '\(Fixture.doDateLabel)' chip to open the picker with. "
                + app.debugDescription
            )
            return
        }
        chip.click()
        var drawnCells: [XCUIElement] = []
        let deadline = Date().addingTimeInterval(Bounds.composerAppears)
        while Date() < deadline {
            drawnCells = dayCells()
            if drawnCells.count >= Bounds.minimumDayCells { break }
            settle(0.25)
        }
        guard drawnCells.count >= Bounds.minimumDayCells else {
            attach("picker-not-open")
            XCTFail(
                "clicking '\(Fixture.doDateLabel)' \(chip.frame) drew \(drawnCells.count) day cell(s); "
                + "a month grid has at least \(Bounds.minimumDayCells). " + app.debugDescription
            )
            return
        }
        attach("picker-open")

        // A cell from the middle of the grid, so every neighbour exists and the corner probe has
        // somewhere to land wrongly if the region is a rectangle.
        let probe = drawnCells[drawnCells.count / 2]
        let cell = probe.frame
        print("DAYCELL frame=\(cell) label='\(probe.label)' cells=\(drawnCells.count)")
        XCTAssertEqual(
            cell.width, cell.height, accuracy: Bounds.squareTolerance,
            "the day cell's frame \(cell) is not square"
        )
        let radius = min(cell.width, cell.height) / 2

        // ── (1) THE DAY CELL'S WASH.
        let popoverElement = try XCTUnwrap(pickerPopoverElement(), "the picker's popover vanished")
        let popoverFrame = popoverElement.frame
        parkPointer(insidePopover: popoverElement, away: cell)
        XCTAssertTrue(
            popoverElement.exists && popoverElement.frame.height > 0,
            "parking the pointer closed the picker's popover, so there is nothing to diff"
        )
        let cold = try XCTUnwrap(shot(of: popoverElement), "could not read the popover as pixels, unhovered")
        probe.hover()
        settle(Bounds.hoverSettle)
        let warm = try XCTUnwrap(shot(of: popoverElement), "could not read the popover as pixels, hovered")
        let wash = changedPixels(cold: cold, warm: warm, window: popoverFrame, plate: cell)
        print(
            "DAYCELL hover changed \(wash.count) px; inside=\(wash.insideCircle) "
            + "outside=\(wash.outsideCircle) maxRadius=\(wash.maximumRadius)pt plateRadius=\(radius)pt"
        )
        attach("picker-day-hovered")
        XCTAssertGreaterThan(wash.count, 0, "hovering the day cell \(cell) changed nothing at all")
        XCTAssertEqual(
            wash.outsideCircle, 0,
            """
            \(wash.outsideCircle) pixel(s) lit OUTSIDE the \(radius)pt circle (furthest \
            \(wash.maximumRadius)pt), so the day cell's wash is not its plate's shape. Cell \(cell).
            """
        )

        // ── (2) THE QUICK PILL'S WASH, measured against a CAPSULE rather than a circle.
        let pills = quickPills()
        guard let pill = pills.max(by: { $0.frame.width < $1.frame.width }) else {
            XCTFail("the picker drew none of \(Fixture.quickPillLabels) to measure. " + app.debugDescription)
            return
        }
        let pillFrame = pill.frame
        print("QUICKPILL frame=\(pillFrame) label='\(pill.label)' pills=\(pills.count)")
        XCTAssertGreaterThan(
            pillFrame.width, pillFrame.height,
            "the quick pill \(pillFrame) is not wider than it is tall, so it is not a capsule"
        )
        let pillPopover = try XCTUnwrap(pickerPopoverElement(), "the picker's popover vanished before the pill")
        let pillPopoverFrame = pillPopover.frame
        parkPointer(insidePopover: pillPopover, away: pillFrame)
        let pillCold = try XCTUnwrap(shot(of: pillPopover), "could not read the popover as pixels, pill unhovered")
        pill.hover()
        settle(Bounds.hoverSettle)
        let pillWarm = try XCTUnwrap(shot(of: pillPopover), "could not read the popover as pixels, pill hovered")
        let pillWash = changedPixels(
            cold: pillCold, warm: pillWarm, window: pillPopoverFrame, plate: pillFrame, isCapsule: true
        )
        let pillRadius = pillFrame.height / 2
        print(
            "QUICKPILL hover changed \(pillWash.count) px; inside=\(pillWash.insideCircle) "
            + "outside=\(pillWash.outsideCircle) maxDistanceToSpine=\(pillWash.maximumRadius)pt "
            + "capsuleRadius=\(pillRadius)pt"
        )
        attach("picker-pill-hovered")
        XCTAssertGreaterThan(pillWash.count, 0, "hovering the quick pill \(pillFrame) changed nothing at all")
        XCTAssertEqual(
            pillWash.outsideCircle, 0,
            """
            \(pillWash.outsideCircle) pixel(s) lit outside the pill's capsule (furthest \
            \(pillWash.maximumRadius)pt from its spine against a \(pillRadius)pt radius), so the \
            wash is not the capsule's shape. Pill \(pillFrame).
            """
        )

        // ── THE HIT REGION, on the same control [[T-11322]] measured on two iOS devices.
        //
        // **Last, because it closes the popover**, and read from the `Do Date` chip's
        // accessibility VALUE rather than from the grid. `dayCells().filter(\.isSelected)` was
        // tried on 2026-11-05 and died with `Failed to get matching snapshot: No matches found
        // for Element at index 103`: re-querying every button in the app after a click races the
        // popover's teardown. The chip is ONE element, it is outside the popover, and
        // `TaskDateChip.displayLabel` makes its value the chosen date — so a selection that moved
        // is one string comparison.
        let chipValueBefore = chip.value as? String ?? ""
        let probeDX = cell.width / 2 - Bounds.cornerInset
        let probeDY = cell.height / 2 - Bounds.cornerInset
        let probeDistance = (probeDX * probeDX + probeDY * probeDY).squareRoot()
        let outsideBy = probeDistance - radius
        XCTAssertGreaterThan(
            outsideBy, Bounds.minimumMargin,
            "the corner probe is only \(outsideBy)pt outside the \(radius)pt circle — not decisive"
        )
        probe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: probeDX, dy: probeDY))
            .click()
        settle(Bounds.composerAppears / 3)
        let chipValueAfter = chip.value as? String ?? ""
        let cornerSelected = chipValueAfter != chipValueBefore
        print(
            "DAYCELL corner click at centre+(\(probeDX), \(probeDY)) = \(probeDistance)pt, "
            + "\(outsideBy)pt outside the \(radius)pt circle — chip '\(chipValueBefore)' -> "
            + "'\(chipValueAfter)' changed=\(cornerSelected) (cell was '\(probe.label)')"
        )
        attach("picker-corner-click")
        XCTAssertFalse(
            cornerSelected,
            """
            a click \(probeDistance)pt from the day cell's centre — \(outsideBy)pt OUTSIDE its \
            \(radius)pt drawn circle and inside its \(cell.width)pt square — moved the Do Date \
            chip from '\(chipValueBefore)' to '\(chipValueAfter)'. That is [[T-11322]]'s iOS \
            signature on macOS, on the same shared control. Cell \(cell), '\(probe.label)'.
            """
        )
    }

    /// **[[T-10803]] clause (3): the Focus overlay's close button.**
    ///
    /// Reached without leaving Today. `TasksPanelComponents.swift:424` draws the start-focus play
    /// button at `.opacity(isHovered ? 1 : 0)` with `.allowsHitTesting(isHovered)`, so the row has
    /// to be hovered before the button is there to click at all — which is itself the pointer
    /// this entry has been waiting weeks for. The overlay it opens carries
    /// `.cadenceControlLabel("Close focus session")` on a 30pt `Image` clipped to a `Circle()`
    /// (`FocusChromeSupportViews.swift:29-37`), so the plate is 30pt and its circle 15pt.
    ///
    /// The overlay is part of the main window, not a popover, so this shoots the window and parks
    /// the pointer the ordinary way — the two popover traps in `parkPointer(insidePopover:away:)`
    /// do not apply.
    func testTheFocusOverlayCloseButtonsCirclePlateOnMacOS() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp()
        let today = app.buttons.element(identified: ID.todayDestination)
        XCTAssertTrue(today.waitForExistence(timeout: Bounds.windowAppears), surfaceReport())
        today.click()
        let window = app.windows.firstMatch

        // The seeded row, hovered so its focus button exists.
        let row = app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifiers(beginningWith: ID.todayTaskRowPrefix))
            .allElementsBoundByIndex
            .first { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let row else {
            attach("focus-no-row")
            XCTFail(
                "Today drew no '\(ID.todayTaskRowPrefix)…' row to start a focus session from. "
                + app.descendant(identified: "").identifiers(beginningWith: ID.todayTaskRowPrefix)
            )
            return
        }
        row.hover()
        settle(Bounds.hoverSettle)

        let start = app.buttons
            .matching(NSPredicate(format: "label == %@ OR title == %@", Fixture.startFocusLabel, Fixture.startFocusLabel))
            .allElementsBoundByIndex
            .first { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let start else {
            attach("focus-no-start-button")
            XCTFail(
                "hovering the row \(row.frame) did not reveal a '\(Fixture.startFocusLabel)' "
                + "button. " + surfaceReport()
            )
            return
        }
        print("FOCUS row=\(row.frame) startButton=\(start.frame)")
        start.click()

        let close = app.buttons
            .matching(NSPredicate(format: "label == %@ OR title == %@", Fixture.closeFocusLabel, Fixture.closeFocusLabel))
            .firstMatch
        guard close.waitForExistence(timeout: Bounds.composerAppears) else {
            attach("focus-no-overlay")
            XCTFail(
                "clicking '\(Fixture.startFocusLabel)' drew no '\(Fixture.closeFocusLabel)' "
                + "button, so no focus overlay opened. " + surfaceReport()
            )
            return
        }
        let plate = close.frame
        print("FOCUS close button frame=\(plate)")
        XCTAssertEqual(
            plate.width, plate.height, accuracy: Bounds.squareTolerance,
            "the close button's frame \(plate) is not square"
        )
        let radius = min(plate.width, plate.height) / 2
        attach("focus-overlay")

        parkPointer(away: plate, in: window)
        let cold = try XCTUnwrap(shot(of: window), "could not read the window as pixels, unhovered")
        close.hover()
        settle(Bounds.hoverSettle)
        let warm = try XCTUnwrap(shot(of: window), "could not read the window as pixels, hovered")
        let wash = changedPixels(cold: cold, warm: warm, window: window.frame, plate: plate)
        print(
            "FOCUS hover changed \(wash.count) px; inside=\(wash.insideCircle) "
            + "outside=\(wash.outsideCircle) maxRadius=\(wash.maximumRadius)pt plateRadius=\(radius)pt"
        )
        attach("focus-close-hovered")
        XCTAssertGreaterThan(
            wash.count, 0,
            "hovering the focus overlay's close button \(plate) changed nothing at all. " + surfaceReport()
        )
        XCTAssertEqual(
            wash.outsideCircle, 0,
            """
            \(wash.outsideCircle) pixel(s) lit OUTSIDE the \(radius)pt circle (furthest \
            \(wash.maximumRadius)pt), so the close button's wash is not its plate's shape. A \
            rounded-rectangle corner would sit at \(radius * 1.41421356)pt. Plate \(plate).
            """
        )

        // Leave no focus session running on the owner's machine.
        close.click()
        settle(Bounds.hoverSettle)
    }

    /// **[[T-10803]] clause (5): the Settings tag colour swatch — the last of the six a pointer
    /// can reach.**
    ///
    /// Reached without a menu or a rail click: `CadenceUITestLaunchPage` takes
    /// `CADENCE_UI_TEST_PAGE=settings` and `CadenceUITestSettingsCategory` takes
    /// `CADENCE_UI_TEST_SETTINGS_CATEGORY=tags`, both gated on `CADENCE_UI_TEST_MODE=1`
    /// ([[T-3200]], [[T-11451]]). The strip is in the always-visible "Create Tag" section
    /// (`SettingsTagsSection.swift:64`), so no tag has to exist first.
    ///
    /// The plate is the smallest of the six by a wide margin — `Circle().frame(width: 18, height:
    /// 18)`, so a **9pt** radius against the floating button's 27 — which is the case most likely
    /// to show a corner if the style ever stopped honouring its shape, because 9 * sqrt(2) is only
    /// 3.7pt further out than 9.
    func testTheSettingsTagColourSwatchesCirclePlateOnMacOS() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp(page: Fixture.settingsPage, settingsCategory: Fixture.tagsCategory)
        let window = app.windows.firstMatch

        // **Wait for the strip BEFORE enumerating it.** `allElementsBoundByIndex` followed by a
        // `.frame` on each raced Settings' paint on 2026-11-05 and died in 7.8s with `Failed to
        // get matching snapshot` — the same staleness that cost a run on the Calendar page. The
        // query is bounded by a label predicate, so the wait costs one lookup.
        let swatchQuery = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", Fixture.unselectedSwatchLabel, Fixture.selectedSwatchLabel
        ))
        guard swatchQuery.firstMatch.waitForExistence(timeout: Bounds.windowAppears) else {
            attach("tags-no-swatch")
            XCTFail(
                "Settings > Tags never drew a '\(Fixture.unselectedSwatchLabel)' swatch. "
                + surfaceReport()
            )
            return
        }
        settle(Bounds.hoverSettle)
        let swatches = swatchQuery
            .allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
        guard swatches.count >= Bounds.minimumSwatches else {
            attach("tags-not-open")
            XCTFail(
                "Settings > Tags drew \(swatches.count) colour swatch(es); "
                + "`TagSupport.colorOptions` gives at least \(Bounds.minimumSwatches). "
                + surfaceReport()
            )
            return
        }
        // An UNSELECTED one: the selected swatch carries a 2pt `strokeBorder` of its own, and a
        // wash measured over that would be measuring two shapes.
        let swatch = swatches.first { $0.label == Fixture.unselectedSwatchLabel } ?? swatches[0]
        let plate = swatch.frame
        print("SWATCH frame=\(plate) label='\(swatch.label)' swatches=\(swatches.count)")
        XCTAssertEqual(
            plate.width, plate.height, accuracy: Bounds.squareTolerance,
            "the swatch's frame \(plate) is not square"
        )
        let radius = min(plate.width, plate.height) / 2
        attach("tags-open")

        parkPointer(away: plate, in: window)
        let cold = try XCTUnwrap(shot(of: window), "could not read the window as pixels, unhovered")
        swatch.hover()
        settle(Bounds.hoverSettle)
        let warm = try XCTUnwrap(shot(of: window), "could not read the window as pixels, hovered")
        let wash = changedPixels(cold: cold, warm: warm, window: window.frame, plate: plate)
        print(
            "SWATCH hover changed \(wash.count) px; inside=\(wash.insideCircle) "
            + "outside=\(wash.outsideCircle) maxRadius=\(wash.maximumRadius)pt plateRadius=\(radius)pt "
            + "cornerWouldBeAt=\(radius * 1.41421356)pt"
        )
        attach("tags-swatch-hovered")
        XCTAssertGreaterThan(
            wash.count, 0,
            "hovering the tag colour swatch \(plate) changed nothing at all. " + surfaceReport()
        )
        XCTAssertEqual(
            wash.outsideCircle, 0,
            """
            \(wash.outsideCircle) pixel(s) lit OUTSIDE the \(radius)pt circle (furthest \
            \(wash.maximumRadius)pt), so the swatch's wash is not its plate's shape. A \
            rounded-rectangle corner would sit at \(radius * 1.41421356)pt. Plate \(plate).
            """
        )
    }

    /// **[[T-8553]]'s UNIFY decision, SEEN on the Mac rather than counted in source — and that
    /// distinction is the whole point of this test.**
    ///
    /// The owner refused option (a) ("every chooser draws each list's own icon") on 2026-10-31 and
    /// chose one canonical glyph per list kind in every chooser on both platforms.
    /// [[T-10102]] found and fixed the four choosers the first pass missed, and was SEEN on an
    /// iPad. The Mac half is pinned only by `CadenceR67ParityTests
    /// .noChooserLabelsAListWithThatListsOwnIcon`, which is a SOURCE SWEEP: it can prove no glyph
    /// argument reads an `Area`'s own `icon`, and it cannot prove what the window actually drew.
    /// `CadencePlainPlateRadiusTests` passed the same way while a hit region was still a rectangle
    /// ([[T-11322]]), which is the failure this run exists to stop repeating.
    ///
    /// **What makes it readable**: `ContainerPickerRow` draws `Image(systemName: icon)`
    /// (`ContainerPickerSupportViews.swift:319`), and macOS XCUITest publishes an SF Symbol
    /// image's name as the element's IDENTIFIER — measured in this target's own trees, e.g.
    /// `Image, identifier: 'calendar.badge.plus'`. So "the area row draws folder.fill" is an
    /// identifier lookup, not a judgement about a picture.
    func testTheMacContainerPickerDrawsTheCanonicalListKindGlyphs() throws {
        try CadenceUITestEnvironment.requireInteractiveUITests()

        try launchApp()
        let today = app.buttons.element(identified: ID.todayDestination)
        XCTAssertTrue(today.waitForExistence(timeout: Bounds.windowAppears), surfaceReport())
        today.click()

        // The row's list chip, named once on the badge itself (T-594) so every surface that draws
        // it answers to the same label.
        let chipQuery = app.buttons.matching(NSPredicate(
            format: "label == %@ OR title == %@", Fixture.listChipLabel, Fixture.listChipLabel
        ))
        // **A SKIP, not a failure: this is a staging gap, not a defect.** Measured 2026-11-05 on
        // two runs that each launched cleanly and clicked Today — `MACWINDOW launch 1 of 3 drew a
        // window AND its sidebar`, the click synthesised at t=5.00s — and then waited the full
        // 45s with no `List` chip ever appearing. The `calendar-hues` fixture's Today row does not
        // draw one, so there is nothing here to open the picker with. Reporting that as red would
        // say the Mac picker is broken, which this run has no evidence for either way.
        guard chipQuery.firstMatch.waitForExistence(timeout: Bounds.windowAppears) else {
            attach("picker-no-list-chip")
            throw XCTSkip(
                """
                NOT STAGEABLE with the `\(Fixture.scenario)` fixture: Today drew no \
                '\(Fixture.listChipLabel)' chip, so the Mac container picker cannot be opened and \
                [[T-8553]]'s UNIFY decision stays unsighted on this platform. The app launched and \
                drew its sidebar, so this is the fixture, not the launch. What it needs: a scenario \
                whose Today row carries a list chip, or a different entry point to \
                `ContainerPickerPopoverContent` — it is also hosted from the Kanban card \
                (`KanbanCardMetaSupportViews.swift:20`), which this test does not reach.
                """
            )
        }
        settle(Bounds.hoverSettle)
        let chip = chipQuery.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 }
        guard let chip else {
            XCTFail("the '\(Fixture.listChipLabel)' chip has no drawn frame. " + surfaceReport())
            return
        }
        print("LISTPICKER chip=\(chip.frame) value='\(chip.value as? String ?? "")'")
        chip.click()

        guard let popover = pickerPopoverElement(), popover.frame.height > 0 else {
            attach("picker-no-popover")
            XCTFail("clicking the list chip opened no popover. " + app.debugDescription)
            return
        }
        settle(Bounds.hoverSettle)
        attach("list-picker-open")

        // Every SF Symbol drawn inside the popover, by identifier.
        let glyphs = app.descendants(matching: .image).allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
            .filter { popover.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .map(\.identifier)
            .filter { !$0.isEmpty }
        print("LISTPICKER popover=\(popover.frame) glyphs=\(glyphs)")

        // **Stated as the owner's rule, not as a count.** UNIFY says no chooser may label a list
        // with that list's OWN icon, so the test is: every glyph in this popover is one of the
        // canonical three (or the selected-state checkmark). A list wearing its own glyph — the
        // `iphone` the iPad showed for `[Sample] iOS Polish` — fails here by not being in the set.
        let allowed = Set(Fixture.canonicalListGlyphs + Fixture.pickerChromeGlyphs)
        let strays = glyphs.filter { !allowed.contains($0) }
        XCTAssertTrue(
            strays.isEmpty,
            """
            the Mac list picker draws \(strays) , which \(Fixture.canonicalListGlyphs) does not \
            contain — so a list is wearing its OWN icon in a chooser, which is exactly option (a) \
            the owner refused in [[T-8553]]. All glyphs seen: \(glyphs). Popover \(popover.frame).
            """
        )
        XCTAssertTrue(
            glyphs.contains(Fixture.canonicalListGlyphs[0]),
            "the picker drew no Inbox '\(Fixture.canonicalListGlyphs[0])' row at all: \(glyphs)"
        )
        XCTAssertTrue(
            glyphs.contains(Fixture.canonicalListGlyphs[1]) || glyphs.contains(Fixture.canonicalListGlyphs[2]),
            """
            the picker drew Inbox but neither an area '\(Fixture.canonicalListGlyphs[1])' nor a \
            project '\(Fixture.canonicalListGlyphs[2])' row, so this fixture proves nothing about \
            the two kinds the owner's decision is actually about. Glyphs: \(glyphs).
            """
        )
    }

    /// The month grid's day buttons, found by GEOMETRY rather than by label.
    ///
    /// **Not `label CONTAINS ", 2026"`.** That was tried on 2026-11-04 and matched **nothing**:
    /// `DateFormatters.longDate` renders a day cell as `Sunday, November 1`, with no year, and the
    /// picker's scroller holds three months at once (`September 2026`, `October 2026`,
    /// `November 2026` were all in the tree), so no single month name identifies the grid either.
    /// The cells are the only square ~`cellSide` buttons inside the popover, and that is what is
    /// asked for here.
    ///
    /// **Bounded to the popover's own subtree, NOT `app.buttons`** ([[T-11943]], trap 3 of
    /// [[T-11631]]). Indexing every button in the app re-resolves each index against a tree that
    /// the settling Calendar page behind the popover is still changing, and the `.filter`'s
    /// `element.frame` then throws `No matches found for Element at index N` — measured at index
    /// 29 on 2026-11-04 and at index 103 on 2026-11-05, where it reddened the whole suite while
    /// each test still passed alone. Descending from the popover element is the bounded form the
    /// trap asks for: far fewer elements, and they are resolved against the popover's own
    /// snapshot rather than the app's. `quickPills()` below was already bounded, by predicate,
    /// and never failed this way — which is the control for that diagnosis.
    private func dayCells() -> [XCUIElement] {
        guard let popoverElement = pickerPopoverElement() else { return [] }
        let popover = popoverElement.frame
        return popoverElement.descendants(matching: .button).allElementsBoundByIndex
            .filter { element in
                let f = element.frame
                guard f.width > 0, f.height > 0 else { return false }
                guard abs(f.width - f.height) <= Bounds.squareTolerance else { return false }
                guard f.width >= Bounds.dayCellMinimumSide, f.width <= Bounds.dayCellMaximumSide else { return false }
                return popover.contains(CGPoint(x: f.midX, y: f.midY))
            }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// The date picker's popover, which bounds every element this test measures.
    ///
    /// **It is returned as an ELEMENT, not just a rect, because the shot has to be taken OF it.**
    /// Measured 2026-11-05: hovering the day cell and diffing two `window.screenshot()`s reported
    /// **0 changed pixels** over a cell that was found, sized and hovered correctly. A macOS
    /// popover is its own window, so the main window's screenshot does not contain it and the
    /// diff was of two identical pictures of a surface the control is not on. Shooting the
    /// popover fixes it, and the plate is then offset by the popover's origin rather than the
    /// window's.
    private func pickerPopoverElement() -> XCUIElement? {
        app.descendants(matching: .popover).allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
            .max { $0.frame.height < $1.frame.height }
    }

    private func pickerPopover() -> CGRect? { pickerPopoverElement()?.frame }

    /// The quick pills under the grid — the capsule half of [[T-10803]] clause (2). By label,
    /// because `CadenceQuickDatePopover.quickPill` spells all three (`:533-536`) and they are the only
    /// controls in the popover that carry them.
    private func quickPills() -> [XCUIElement] {
        guard let popover = pickerPopover() else { return [] }
        return app.buttons
            .matching(NSPredicate(format: "label IN %@", Fixture.quickPillLabels))
            .allElementsBoundByIndex
            .filter { $0.frame.width > 0 && $0.frame.height > 0 && popover.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    // MARK: - The composer

    /// **The composer is an OVERLAY, not an `NSSheet`, and it does not host `CadenceSchedulePanel`.**
    /// Measured 2026-11-04: a centre click on the button opened something, and
    /// `app.sheets.count == 0` with no `schedule-kind-task` anywhere — `macOSRootView.swift:103`
    /// puts `CreateTaskPanelSurface` inside `macOSRootOverlayStack`
    /// (`macOSRootSupportViews.swift:405`), so it is a view in the window's own hierarchy. It is
    /// read here by `CreateTaskSheet`'s own strings instead: the title field's placeholder
    /// (`CreateTaskSheet.swift:123`) and the subtask row's label (`:221`), neither of which Today
    /// draws.
    private func composerIsOpen() -> Bool {
        if app.sheets.count > 0 { return true }
        if app.descendant(identified: ID.scheduleKindTask).exists { return true }
        for needle in Fixture.composerStrings {
            let found = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@ OR placeholderValue CONTAINS %@",
                    needle, needle, needle
                ))
                .firstMatch
            if found.exists { return true }
        }
        return false
    }

    private func waitForComposer() -> Bool {
        let deadline = Date().addingTimeInterval(Bounds.composerAppears)
        while Date() < deadline {
            if composerIsOpen() { return true }
            settle(0.2)
        }
        return false
    }

    private func dismissComposer() {
        let deadline = Date().addingTimeInterval(Bounds.composerAppears)
        while Date() < deadline, composerIsOpen() {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            settle(0.3)
        }
        settle(Bounds.hoverSettle)
    }

    // MARK: - Pixels

    private struct Wash {
        var count = 0
        var insideCircle = 0
        var outsideCircle = 0
        var maximumRadius: CGFloat = 0
    }

    private func shot(of window: XCUIElement) -> CadenceUITestPixel.Bitmap? {
        CadenceUITestPixel.Bitmap(screenshot: window.screenshot(), pointWidth: window.frame.width)
    }

    /// Every pixel of the plate that changed between the two shots, split by how far it sits from
    /// the plate's centre. `window` and `plate` are both in screen points; the bitmap is the
    /// window's own, so the plate is offset by the window's origin before being scaled.
    private func changedPixels(
        cold: CadenceUITestPixel.Bitmap,
        warm: CadenceUITestPixel.Bitmap,
        window: CGRect,
        plate: CGRect,
        isCapsule: Bool = false
    ) -> Wash {
        var wash = Wash()
        guard cold.width == warm.width, cold.height == warm.height else { return wash }
        let scale = cold.scale
        let radius = min(plate.width, plate.height) / 2
        let halfLength = isCapsule ? max(plate.width / 2 - radius, 0) : 0
        let localCentre = CGPoint(x: plate.midX - window.minX, y: plate.midY - window.minY)
        let x0 = Int(((plate.minX - window.minX) * scale).rounded(.down))
        let x1 = Int(((plate.maxX - window.minX) * scale).rounded(.up))
        let y0 = Int(((plate.minY - window.minY) * scale).rounded(.down))
        let y1 = Int(((plate.maxY - window.minY) * scale).rounded(.up))
        for y in max(0, y0)..<min(cold.height, y1) {
            for x in max(0, x0)..<min(cold.width, x1) {
                guard let a = cold.colour(x: x, y: y), let b = warm.colour(x: x, y: y) else { continue }
                guard a.distance(to: b) >= Bounds.channelThreshold else { continue }
                wash.count += 1
                let px = (CGFloat(x) + 0.5) / scale
                let py = (CGFloat(y) + 0.5) / scale
                // Distance to the plate's MEDIAL SEGMENT, which is the centre point for a
                // circle (`halfLength` 0) and the capsule's spine otherwise. One formula, so the
                // circle and the capsule are measured by the same rule rather than by two.
                let dx = max(abs(px - localCentre.x) - halfLength, 0)
                let dy = py - localCentre.y
                let r = (dx * dx + dy * dy).squareRoot()
                wash.maximumRadius = max(wash.maximumRadius, r)
                if r > radius + Bounds.washTolerance { wash.outsideCircle += 1 } else { wash.insideCircle += 1 }
            }
        }
        return wash
    }

    /// Put the pointer somewhere in the window that is nowhere near the plate, so the "unhovered"
    /// shot really is one. The window's top-leading corner is the sidebar header, which the plate
    /// — bottom-trailing by construction — can never reach.
    private func parkPointer(away plate: CGRect, in window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).hover()
        settle(Bounds.hoverSettle)
    }

    /// The same, for a plate that lives in a POPOVER — which must not be parked away from.
    ///
    /// **Parking on the main window dismissed the picker, and cost two runs.** Measured
    /// 2026-11-05: `parkPointer(away:in:)` hovers the window's top-leading corner, which is
    /// outside a transient macOS popover, so the popover closed; the "unhovered" shot and the
    /// "hovered" shot were then of the same dead surface and the diff reported **0 changed
    /// pixels** over a day cell that had been found, sized and hovered correctly. The pointer
    /// stays INSIDE the popover here, in whichever of its corners is furthest from the plate.
    private func parkPointer(insidePopover popover: XCUIElement, away plate: CGRect) {
        let f = popover.frame
        let centre = CGPoint(x: plate.midX, y: plate.midY)
        let corners: [CGVector] = [
            CGVector(dx: 0.06, dy: 0.04), CGVector(dx: 0.94, dy: 0.04),
            CGVector(dx: 0.06, dy: 0.96), CGVector(dx: 0.94, dy: 0.96)
        ]
        let furthest = corners.max { a, b in
            func distance(_ v: CGVector) -> CGFloat {
                let p = CGPoint(x: f.minX + f.width * v.dx, y: f.minY + f.height * v.dy)
                return ((p.x - centre.x) * (p.x - centre.x) + (p.y - centre.y) * (p.y - centre.y)).squareRoot()
            }
            return distance(a) < distance(b)
        } ?? CGVector(dx: 0.06, dy: 0.04)
        popover.coordinate(withNormalizedOffset: furthest).hover()
        settle(Bounds.hoverSettle)
    }

    // MARK: - Fixtures

    private enum ID {
        static let todayDestination = "sidebar.destination.today"
        /// `CadenceSchedulePanel`'s kind selector, `identifierPrefix` + `CadenceScheduleDraftKind`'s
        /// raw value. Spelled as a literal because the UI-test target cannot import the app module.
        static let scheduleKindTask = "schedule-kind-task"
        /// `CadenceAccessibilityIdentifiers`' Today task rows, e.g. `today.task.row.fixture-task`.
        static let todayTaskRowPrefix = "today.task.row."
    }

    private enum Fixture {
        static let scenario = "calendar-hues"
        /// `FloatingNewTaskButton`'s `.cadenceControlLabel("New Task")` ([[T-10230]]).
        static let newTaskLabel = "New Task"
        /// `CreateTaskSheet`'s own strings — the title field's placeholder and the subtask row —
        /// used because the composer publishes no identifier of its own. Today draws neither.
        static let composerStrings = ["What needs doing?", "Add Subtask"]
        /// Every day cell's `DateFormatters.longDate` label carries the year; the month name does
        /// not have to be guessed. 2026 is this run's year and the picker opens on the current
        /// month, so a cell can only be in it or in a neighbouring month of the same year.
        static let yearFragment = ", 2026"
        /// `TaskDateChip`'s `.cadenceControlLabel(label)` for the do-date row
        /// (`CreateTaskSheet.swift:252`).
        static let doDateLabel = "Do Date"
        /// `CadenceQuickDatePopover.quickPill`'s three labels (`CadenceDatePicker.swift:533-536`).
        static let quickPillLabels = ["Today", "Tomorrow", "This Weekend"]
        /// `CadenceTaskControlAccessibility.startFocus`
        /// (`CadenceTaskPresentationSupport.swift:320`) and `FocusChromeSupportViews.swift:38`.
        static let startFocusLabel = "Start focus session"
        static let closeFocusLabel = "Close focus session"
        /// `CadenceUITestLaunchPage.settings` and `CadenceSettingsCategoryKind.tags`.
        static let settingsPage = "settings"
        static let tagsCategory = "tags"
        /// `SettingsTagsSection.swift:536` — the name is what the control DOES, because a screen
        /// reader cannot verify a colour.
        static let unselectedSwatchLabel = "Use this color"
        static let selectedSwatchLabel = "Selected color"
        /// `CadenceTaskControlAccessibility.list` (`CadenceTaskPresentationSupport.swift:319`).
        static let listChipLabel = "List"
        /// `CadenceListKindIcon` (`CadenceScheduleDraftChoices.swift:6-8`), in the order
        /// inbox, area, project. Spelled as literals: the UI-test target cannot import the module.
        static let canonicalListGlyphs = ["tray.fill", "folder.fill", "square.stack.3d.up.fill"]
        /// Not list-kind glyphs: the row's selected tick and the search field's magnifier, both
        /// drawn by the picker itself rather than naming any list.
        static let pickerChromeGlyphs = ["checkmark", "checkmark.circle.fill", "magnifyingglass", "xmark.circle.fill"]
    }

    private enum Bounds {
        /// **Not measured.** Generous for the same reason `CadenceMacTodayAllDayBandUITests`' is:
        /// a cold UI-test launch seeds the store before it draws ([[T-8928]]).
        static let windowAppears: TimeInterval = 45
        static let launchAttempts = 3
        /// How long a launch gets to draw its sidebar before the attempt is written off as
        /// [[T-8928]]. Well above the 0.04-0.52s the seed arrival was timed at
        /// (`CadenceSeededSidebarTimingUITests`, 38 arrivals), and far below `windowAppears`, so
        /// a relaunch is cheap when it is needed.
        static let drawsUI: TimeInterval = 12
        /// The style animates the wash with `.easeOut(duration: 0.12)`; this is ~6x that, so a shot
        /// taken after it is of a settled wash and not of one mid-fade.
        static let hoverSettle: TimeInterval = 0.75
        /// **Not measured.** How long the composer takes to appear or to go.
        static let composerAppears: TimeInterval = 10
        /// Frame width and height may differ by sub-point rounding without the plate stopping being
        /// a square.
        static let squareTolerance: CGFloat = 1
        /// How far inside the frame's corner the probe sits.
        static let cornerInset: CGFloat = 2
        /// The probe must clear the circle by more than this or the measurement is not decisive.
        static let minimumMargin: CGFloat = 4
        /// A pixel counts as changed when one channel moves this far. 10/255 is well above the
        /// window server's dithering and far below an 8%-opacity blue wash over any background.
        static let channelThreshold = 10
        /// Antialiasing writes the shape's edge a fraction of a point proud of its radius, and a
        /// `strokeBorder` is drawn INSIDE the shape. One point absorbs both without being able to
        /// hide a rounded-rectangle corner, which at this radius lies 11pt out.
        static let washTolerance: CGFloat = 1
        /// A month grid draws 28 days at the very least; anything under this means the picker did
        /// not open rather than that it opened short.
        static let minimumDayCells = 28
        /// `CadenceDateSelectionMetrics.cellSide` is 34 at the default text size and is SCALED by
        /// `cellSide(at:)`, so this is a window round it rather than the number itself — the rule
        /// against pinning a point figure (T-1279).
        static let dayCellMinimumSide: CGFloat = 20
        static let dayCellMaximumSide: CGFloat = 70
        /// `TagSupport.colorOptions` is a fixed palette; this is a floor, not its count, so the
        /// palette can grow without reddening this.
        static let minimumSwatches = 4
    }

    // MARK: - Launching

    private func launchApp(page: String? = nil, settingsCategory: String? = nil) throws {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = Fixture.scenario
        // [[T-3200]] / [[T-11451]]: both are ignored outside `CADENCE_UI_TEST_MODE`, so a shipping
        // launch is unaffected and a steerable launch is an EventKit-disarmed one.
        if let page { app.launchEnvironment["CADENCE_UI_TEST_PAGE"] = page }
        if let settingsCategory {
            app.launchEnvironment["CADENCE_UI_TEST_SETTINGS_CATEGORY"] = settingsCategory
        }
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "mac-roundplate-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
        // **A window is not a drawn app, and treating it as one cost four runs on 2026-11-05.**
        // [[T-8928]] is documented as "reaches the foreground and holds no window", and the loop
        // below was written for that. The variant that actually strikes here is worse: the window
        // EXISTS, so the loop returns happily, and the accessibility tree is empty — every test
        // then fails on whichever element it asked for first, reporting `the app's first static
        // texts: none at all`. It hit roughly half the launches in this session. So an attempt
        // counts as good only when the app has drawn something a seeded launch always draws, and
        // the sidebar's Today destination is that: a static row no fixture creates or omits.
        for attempt in 1...Bounds.launchAttempts {
            if app.windows.firstMatch.waitForExistence(timeout: Bounds.windowAppears),
               app.buttons.element(identified: ID.todayDestination).waitForExistence(timeout: Bounds.drawsUI) {
                print("MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew a window AND its sidebar")
                return
            }
            print(
                "MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew no usable UI "
                + "(windows=\(app.windows.count) state=\(app.state.rawValue)) — [[T-8928]]"
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
            The macOS app reached the foreground \(Bounds.launchAttempts) times and drew no usable \
            UI any of them — no window, or a window with an empty accessibility tree. That is \
            [[T-8928]], not the code under test: the same build draws immediately under \
            scripts/run-macos-app.sh. Nothing below ran.
            """
        )
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "settle")], timeout: seconds)
    }

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
