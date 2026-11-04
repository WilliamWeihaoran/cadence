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

    override func tearDownWithError() throws {
        app?.terminate()
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
        plate: CGRect
    ) -> Wash {
        var wash = Wash()
        guard cold.width == warm.width, cold.height == warm.height else { return wash }
        let scale = cold.scale
        let radius = min(plate.width, plate.height) / 2
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
                let dx = px - localCentre.x
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

    // MARK: - Fixtures

    private enum ID {
        static let todayDestination = "sidebar.destination.today"
        /// `CadenceSchedulePanel`'s kind selector, `identifierPrefix` + `CadenceScheduleDraftKind`'s
        /// raw value. Spelled as a literal because the UI-test target cannot import the app module.
        static let scheduleKindTask = "schedule-kind-task"
    }

    private enum Fixture {
        static let scenario = "calendar-hues"
        /// `FloatingNewTaskButton`'s `.cadenceControlLabel("New Task")` ([[T-10230]]).
        static let newTaskLabel = "New Task"
        /// `CreateTaskSheet`'s own strings — the title field's placeholder and the subtask row —
        /// used because the composer publishes no identifier of its own. Today draws neither.
        static let composerStrings = ["What needs doing?", "Add Subtask"]
    }

    private enum Bounds {
        /// **Not measured.** Generous for the same reason `CadenceMacTodayAllDayBandUITests`' is:
        /// a cold UI-test launch seeds the store before it draws ([[T-8928]]).
        static let windowAppears: TimeInterval = 45
        static let launchAttempts = 3
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
    }

    // MARK: - Launching

    private func launchApp() throws {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = Fixture.scenario
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "mac-roundplate-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
        for attempt in 1...Bounds.launchAttempts {
            if app.windows.firstMatch.waitForExistence(timeout: Bounds.windowAppears) {
                print("MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew a window")
                return
            }
            print("MACWINDOW launch \(attempt) of \(Bounds.launchAttempts) drew NO window in \(Bounds.windowAppears)s")
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
            any of them — see [[T-8928]]. Nothing below ran.
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
