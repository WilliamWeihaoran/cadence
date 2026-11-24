// **SIGHTING HARNESS, not a regression suite** -- agent `sightipad1953`, sighting slot `slot1953`,
// 2026-11-24, on `Cadence-iPadPro11`.
//
// [[T-19756]] measured that iOS XCUITest sends arbitrary Cmd-chords inside the simulator, which the
// agent simulator tool's closed `press_key` enum never could. **Bare Escape it does NOT deliver**:
// this file measured that no Cadence binding hears `typeKey(.escape)`, while Cmd+. (iPadOS's cancel
// alias) closes the same drawer and sheets ([[T-19901]]); Cmd+Return is not heard in the `+`
// composer either ([[T-19902]]). The `testRun*` cases are those transport probes. Four sighting
// entries were parked on exactly that enum: [[T-18277]] (Cmd+, / Cmd+O / Cmd+\), [[T-18804]]
// (Cmd+Return's "Add a title first."), [[T-18917]] (Escape on the iOS sheets) and [[T-18920]]
// (Escape on Add Link, Cmd+Shift+[ / ]). This file presses those keys and ATTACHES A FRAME before and
// after each one. The verdicts are read from those frames by the agent, not from this file: a test
// here passing says only that the presses were sent.
//
// **Why the tests barely assert.** A sighting harness that fails on the first surprise stops before
// the frames that would say what the surprise was. So each step logs a `SIGHT1953:` line (read back
// from the test log) and attaches a screenshot plus the accessibility tree; a missing prerequisite
// is logged and the test returns. The suite therefore passes or skips cleanly (locked screen, or a
// non-iPad destination) and is safe to leave in the target.
//
// Element lookups never take `firstMatch` on a bare label: the zero-size `.accessibilityHidden`
// shortcut hosts answer label queries like the real control ([[T-8925]], [[T-19755]]), so every
// tap goes through `visible(_:)`, which demands a non-empty frame.
#if os(iOS)
import UIKit
import XCTest

@MainActor
final class CadenceIPadSightingSlot1953UITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("slot1953's iPad sighting harness; the phone has no hardware-keyboard shell here.")
        }
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        // The one device setting this file changes; restored on every exit path.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - [[T-18277]] Cmd+, / Cmd+O / Cmd+\

    func testT18277CommandKeysLandscape() throws {
        launch(landscape: true)
        pause(1.5)
        shot("18277-L-00-start")
        note("glyph minX at start: \(glyphMinX())")

        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-01-cmdO")
        note("glyph minX after Cmd+O #1: \(glyphMinX())")

        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-02-cmdO-again")
        note("glyph minX after Cmd+O #2: \(glyphMinX())")

        app.typeKey("\\", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-03-cmdBackslash")
        app.typeKey("\\", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-04-cmdBackslash-again")

        // Keys while the capture composer is up: Cmd+O must not move the page under the card.
        app.typeKey("n", modifierFlags: .command)
        pause(1.0)
        let title = app.textFields.element(identified: "capture-title")
        note("capture card up after Cmd+N: \(title.waitForExistence(timeout: CadenceUITestBounds.firstPaint))")
        title.typeText("Half typed")
        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-05-cmdO-over-composer")
        note("composer still up after Cmd+O over it: \(title.exists) value=\(String(describing: title.value))")
        app.typeKey(",", modifierFlags: .command)
        pause(1.0)
        shot("18277-L-06-cmdComma-over-composer")
        note("composer still up after Cmd+, over it: \(title.exists)")
        let cancel = app.buttons.element(identified: "capture-cancel")
        if cancel.exists { cancel.tap() }
        pause(1.0)
        shot("18277-L-07-composer-cancelled")

        app.typeKey(",", modifierFlags: .command)
        pause(1.5)
        shot("18277-L-08-cmdComma")
        note("Settings-ish texts after Cmd+,: \(texts(matching: "Settings|Appearance|Data Safety|Delete Account"))")
    }

    func testT18277CommandOPortraitDrawer() throws {
        launch(landscape: false)
        pause(1.5)
        shot("18277-P-00-start")
        note("drawer backdrop at start: \(drawerBackdropUp())")
        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("18277-P-01-cmdO")
        note("drawer backdrop after Cmd+O #1: \(drawerBackdropUp()) glyph minX \(glyphMinX())")
        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("18277-P-02-cmdO-again")
        note("drawer backdrop after Cmd+O #2: \(drawerBackdropUp()) glyph minX \(glyphMinX())")
    }

    // MARK: - [[T-18804]] Cmd+Return's no-name notice in the + composer

    func testT18804CommandReturnInTheComposer() throws {
        launch(landscape: true)
        pause(1.0)
        app.typeKey("n", modifierFlags: .command)
        let title = app.textFields.element(identified: "capture-title")
        guard title.waitForExistence(timeout: CadenceUITestBounds.firstPaint) else {
            note("Cmd+N opened no composer; stopping"); shot("18804-00-no-composer"); return
        }
        pause(0.8)
        shot("18804-00-composer-empty")
        note("title hasFocus at open: \(title.hasFocus)")

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: .command)
        pause(1.0)
        shot("18804-01-cmdReturn-empty")
        note("after Cmd+Return on empty: composer up=\(title.exists) notice=\(noticeShown())")

        // Control 1: another of the card's chords, Cmd+T (Do Today), from the same focus.
        app.typeKey("t", modifierFlags: .command)
        pause(1.0)
        shot("18804-02-cmdT-control")
        app.typeKey("t", modifierFlags: .command)
        pause(0.6)

        title.typeText("!!")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: .command)
        pause(1.0)
        shot("18804-03-cmdReturn-bangbang")
        note("after Cmd+Return on '!!': composer up=\(title.exists) notice=\(noticeShown())")

        // Control 2: plain Return, the field's own onSubmit, on the same '!!'.
        title.typeText("\n")
        pause(1.0)
        shot("18804-04-return-bangbang")
        note("after plain Return on '!!': composer up=\(title.exists) notice=\(noticeShown()) value=\(String(describing: title.value))")

        if title.exists {
            title.tap()
            title.typeText(" Call Sam")
        }
        pause(0.5)
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: .command)
        pause(1.5)
        shot("18804-05-cmdReturn-call-sam")
        note("after Cmd+Return on '!! Call Sam': composer up=\(title.exists) value=\(String(describing: title.value))")

        // Control 3: Escape, the card's other chord-layer key.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.2)
        shot("18804-06-escape")
        note("after Escape: composer up=\(title.exists)")

        // Control 4: a fresh composer, title typed, plain Return creates.
        app.typeKey("n", modifierFlags: .command)
        if title.waitForExistence(timeout: CadenceUITestBounds.firstPaint) {
            title.typeText("!! Return Sam\n")
            pause(1.5)
            shot("18804-07-return-creates")
            note("after plain Return on '!! Return Sam': composer up=\(title.exists); texts \(texts(matching: "Sam"))")
        }
    }

    // MARK: - [[T-18917]] Escape closes the iOS sheets as Cancel does

    func testT18917EscapeOnDeleteAccountAndData() throws {
        launch(landscape: true)
        pause(1.0)
        app.typeKey(",", modifierFlags: .command)
        pause(1.5)
        if let pane = visible("Data Safety") { pane.tap() } else { note("no visible Data Safety row") }
        pause(1.2)
        let label = "Delete Account & Data"
        var row = visible(label)
        var swipes = 0
        while row == nil, swipes < 8 {
            app.swipeUp()
            swipes += 1
            pause(0.6)
            row = visible(label)
        }
        guard let row else {
            note("no visible '\(label)' control in Settings after \(swipes) swipes"); shot("18917-A-00-missing"); return
        }
        row.tap()
        pause(1.2)
        shot("18917-A-01-sheet-up")
        note("reset sheet up: cancel visible=\(visible("Cancel") != nil)")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.2)
        shot("18917-A-02-after-escape")
        note("after Escape: cancel visible=\(visible("Cancel") != nil); sidebar still lists Alpha Area=\(visible("Alpha Area") != nil)")
    }

    func testT18917EscapeOnSidebarDeleteAndArchive() throws {
        launch(landscape: true)
        pause(1.0)
        revealSidebar()
        menuThenEscape(row: "Beta Project", item: "Delete Project", tag: "18917-B")
        menuThenEscape(row: "Alpha Area", item: "Archive Area", tag: "18917-C")
        menuThenEscape(row: "Alpha Area", item: "Complete Area", tag: "18917-D")
        menuThenEscape(row: "Gamma Area", item: "Delete Area", tag: "18917-E")
        shot("18917-Z-final-sidebar")
        note("final sidebar: Alpha=\(visible("Alpha Area") != nil) Beta=\(visible("Beta Project") != nil) Gamma=\(visible("Gamma Area") != nil)")
    }

    // MARK: - [[T-18920]] Add Link's Escape and the list page's Cmd+Shift+[ / ]

    func testT18920ListTabStepAndAddLinkEscape() throws {
        launch(landscape: true)
        pause(1.0)
        revealSidebar()
        guard let area = visible("Alpha Area") else {
            note("no visible Alpha Area row"); shot("18920-00-missing"); return
        }
        area.tap()
        pause(1.5)
        shot("18920-00-area-open")

        for step in 1...5 {
            app.typeKey("]", modifierFlags: [.command, .shift])
            pause(0.9)
            shot("18920-B-next-\(step)")
        }
        for step in 1...2 {
            app.typeKey("[", modifierFlags: [.command, .shift])
            pause(0.9)
            shot("18920-B-prev-\(step)")
        }
        // Two back from Tasks wraps to Completed, then Links. Leave and reopen the list.
        revealSidebar()
        if let other = visible("Gamma Area") { other.tap() }
        pause(1.2)
        revealSidebar()
        if let again = visible("Alpha Area") { again.tap() }
        pause(1.5)
        shot("18920-B-reopened")

        // (a) Add Link -- step to the Links tab by tapping its pill.
        if let links = visible("Links") { links.tap() }
        pause(1.0)
        guard let add = visible("Add Link") else {
            note("no visible Add Link"); shot("18920-A-missing"); return
        }
        add.tap()
        pause(0.8)
        let titleField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Title (optional)")).firstMatch
        let urlField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "URL")).firstMatch
        note("form fields exist: title=\(titleField.exists) url=\(urlField.exists)")
        if titleField.exists { titleField.tap(); titleField.typeText("Sighting link") }
        if urlField.exists { urlField.tap(); urlField.typeText("example.com/one") }
        pause(0.5)
        shot("18920-A-01-form-typed")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.0)
        shot("18920-A-02-after-escape")
        note("after Escape: url field exists=\(urlField.exists) Add Link visible=\(visible("Add Link") != nil)")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(0.8)
        shot("18920-A-03-escape-form-closed")
        if let addAgain = visible("Add Link") { addAgain.tap() }
        pause(0.8)
        shot("18920-A-04-reopened-form")
        note("reopened form values: title=\(String(describing: titleField.value)) url=\(String(describing: urlField.value))")

        // Save a link, then Edit Link + Escape must leave it unchanged.
        if urlField.exists { urlField.tap(); urlField.typeText("example.com/saved") }
        if let save = visible("Save Link") ?? visible("Save") { save.tap() }
        pause(1.2)
        shot("18920-A-05-saved")
        let rows = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "example.com/saved"))
        note("saved rows: \(rows.count)")
        if let row = rows.allElementsBoundByIndex.first(where: { $0.frame.width > 0 }) {
            row.press(forDuration: 1.2)
            pause(1.0)
            shot("18920-A-06-row-menu")
            if let edit = visible("Edit Link") {
                edit.tap()
                pause(1.0)
                if let focused = app.textFields.allElementsBoundByIndex.first(where: { $0.hasFocus }) {
                    focused.typeText("XYZ")
                } else {
                    note("Edit Link left no field focused; not typing")
                }
                shot("18920-A-07-edit-typed")
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
                pause(1.0)
                shot("18920-A-08-edit-after-escape")
            } else {
                note("row menu had no Edit Link")
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            }
        }
        note("rows containing XYZ: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "XYZ")).count)")
    }

    // MARK: - Run 3: Escape with and without a focused text field

    /// Control for the transport: the drawer's backdrop binds bare Escape and holds no text field.
    func testRun3EscapeClosesTheDrawer() throws {
        launch(landscape: false)
        pause(1.0)
        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("r3-drawer-01-open")
        note("drawer open: \(drawerBackdropUp())")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.0)
        shot("r3-drawer-02-after-escape")
        note("drawer after Escape: \(drawerBackdropUp())")
    }

    func testRun3EscapeOnDeleteAccountSheet() throws {
        launch(landscape: false)
        pause(1.0)
        app.typeKey(",", modifierFlags: .command)
        pause(1.5)
        if let pane = visible("Data Safety") { pane.tap() }
        pause(1.2)
        let label = "Delete Account & Data"
        func button() -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
                .first { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.isHittable }
        }
        var swipes = 0
        while button() == nil, swipes < 8 { app.swipeUp(); swipes += 1; pause(0.6) }
        guard let open = button() else { note("no reset button"); shot("r3-reset-00-missing"); return }
        open.tap()
        pause(1.5)
        shot("r3-reset-01-sheet")
        let field = app.textFields.allElementsBoundByIndex.first { $0.hasFocus }
        note("reset sheet: Cancel=\(visible("Cancel") != nil) focused field=\(field != nil)")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.2)
        shot("r3-reset-02-after-escape")
        note("reset after Escape (field focused): Cancel=\(visible("Cancel") != nil)")
        if let cancel = visible("Cancel") {
            cancel.tap()
            pause(1.0)
            shot("r3-reset-03-after-cancel-tap")
            note("reset after Cancel tap: Cancel=\(visible("Cancel") != nil)")
        }
    }

    func testRun3EscapeOnWindDownAndListEditor() throws {
        launch(landscape: false)
        pause(1.0)
        sheetThenEscape(row: "Beta Project", item: "Archive Project", tag: "r3-archive")
        sheetThenEscape(row: "Alpha Area", item: "Complete Area", tag: "r3-complete")
        sheetThenEscape(row: "Gamma Area", item: "Edit Area", tag: "r3-edit")
        app.typeKey("o", modifierFlags: .command)
        pause(1.0)
        shot("r3-final-sidebar")
        note("final rows: Alpha=\(visible("Alpha Area") != nil) Beta=\(visible("Beta Project") != nil) Gamma=\(visible("Gamma Area") != nil)")
    }

    private func sheetThenEscape(row label: String, item: String, tag: String) {
        if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
        guard let row = visible(label) else { note("\(tag): no visible row '\(label)'"); shot("\(tag)-00-norow"); return }
        row.press(forDuration: 1.2)
        pause(1.0)
        guard let entry = visible(item) else {
            note("\(tag): menu has no '\(item)'"); shot("\(tag)-00-nomenu")
            app.tap(); pause(0.8); return
        }
        entry.tap()
        pause(1.5)
        shot("\(tag)-01-sheet")
        let focused = app.textFields.allElementsBoundByIndex.first { $0.hasFocus } != nil
        note("\(tag): sheet up Cancel=\(visible("Cancel") != nil) focusedField=\(focused)")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.2)
        shot("\(tag)-02-after-escape")
        note("\(tag): after Escape Cancel=\(visible("Cancel") != nil)")
        if let cancel = visible("Cancel") { cancel.tap(); pause(1.0); note("\(tag): closed by Cancel tap instead") }
    }

    // MARK: - Run 4: which synthesized form of Escape / Cmd+Return, if any, the app hears

    func testRun4EscapeVariantsOnTheDrawer() throws {
        launch(landscape: false)
        pause(1.0)
        let variants: [(String, () -> Void)] = [
            ("typeKey-enum", { self.app.typeKey(.escape, modifierFlags: []) }),
            // `typeText("\u{1B}")` is not a variant: with no field focused it fails the test with
            // "Neither element nor any descendant has keyboard focus" (measured, run 4).
            ("backdrop-typeKey", {
                self.app.descendants(matching: .any)
                    .matching(CadenceUITestQuery.identifying("cadence.sidebar.drawerBackdrop")).firstMatch
                    .typeKey(.escape, modifierFlags: [])
            }),
            ("cmd-period", { self.app.typeKey(".", modifierFlags: .command) }),
            ("ctrl-bracket", { self.app.typeKey("[", modifierFlags: .control) }),
        ]
        for (tag, press) in variants {
            if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
            let before = drawerBackdropUp()
            press()
            pause(1.0)
            note("escape variant \(tag): drawer before=\(before) after=\(drawerBackdropUp())")
        }
        shot("r4-drawer-final")
    }

    func testRun4CommandReturnVariantsInTheComposer() throws {
        launch(landscape: false)
        pause(1.0)
        app.typeKey("n", modifierFlags: .command)
        let title = app.textFields.element(identified: "capture-title")
        guard title.waitForExistence(timeout: CadenceUITestBounds.firstPaint) else { note("no composer"); return }
        title.typeText("Variant Sam")
        let variants: [(String, () -> Void)] = [
            ("app-typeKey-enum-return", { self.app.typeKey(.return, modifierFlags: .command) }),
            ("field-typeKey-return", { title.typeKey(.return, modifierFlags: .command) }),
            ("app-typeKey-enter", { self.app.typeKey(.enter, modifierFlags: .command) }),
            ("app-typeKey-CR-string", { self.app.typeKey("\r", modifierFlags: .command) }),
        ]
        for (tag, press) in variants {
            guard title.exists else { break }
            press()
            pause(1.2)
            note("cmd-return variant \(tag): composer up after=\(title.exists) value=\(String(describing: title.value).replacingOccurrences(of: "\n", with: "⏎"))")
        }
        shot("r4-composer-final")
        note("Variant Sam texts: \(texts(matching: "Variant Sam"))")
    }

    // MARK: - Run 6: Cmd+. (iPadOS's alias of Escape, which run 5 measured the drawer answering)

    func testRun6CommandPeriodOnTheSheets() throws {
        launch(landscape: false)
        pause(1.0)
        let cancelChord = { self.app.typeKey(".", modifierFlags: .command) }

        // The + composer: its Escape layer is `.cancelAction`.
        app.typeKey("n", modifierFlags: .command)
        let title = app.textFields.element(identified: "capture-title")
        if title.waitForExistence(timeout: CadenceUITestBounds.firstPaint) {
            title.typeText("Half typed")
            cancelChord()
            pause(1.2)
            shot("r6-composer-after-cmdperiod")
            note("composer after Cmd+.: up=\(title.exists)")
            if title.exists, let cancel = app.buttons.matching(CadenceUITestQuery.identifying("capture-cancel")).allElementsBoundByIndex.first(where: { $0.frame.width > 0 }) { cancel.tap(); pause(0.8) }
        }

        // Settings > Data Safety > Delete Account & Data, phrase field focused on appear.
        app.typeKey(",", modifierFlags: .command)
        pause(1.5)
        if let pane = visible("Data Safety") { pane.tap() }
        pause(1.2)
        func resetButton() -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "label == %@", "Delete Account & Data")).allElementsBoundByIndex
                .first { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.isHittable }
        }
        var swipes = 0
        while resetButton() == nil, swipes < 8 { app.swipeUp(); swipes += 1; pause(0.6) }
        if let open = resetButton() {
            open.tap()
            pause(1.5)
            if let field = app.textFields.allElementsBoundByIndex.first(where: { $0.hasFocus }) { field.typeText("DEL") }
            shot("r6-reset-01-typed")
            note("reset sheet up: Cancel=\(visible("Cancel") != nil)")
            cancelChord()
            pause(1.2)
            shot("r6-reset-02-after-cmdperiod")
            note("reset after Cmd+.: Cancel=\(visible("Cancel") != nil)")
            if let cancel = visible("Cancel") { cancel.tap(); pause(1.0) }
        } else { note("no reset button") }

        // A sidebar list's Edit sheet.
        if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
        if let row = visible("Gamma Area") {
            row.press(forDuration: 1.2)
            pause(1.0)
            if let edit = visible("Edit Area") {
                edit.tap()
                pause(1.5)
                shot("r6-edit-01-sheet")
                cancelChord()
                pause(1.2)
                shot("r6-edit-02-after-cmdperiod")
                note("edit sheet after Cmd+.: Cancel=\(visible("Cancel") != nil)")
                if let cancel = visible("Cancel") { cancel.tap(); pause(1.0) }
            }
        }

        // Add Link on Alpha Area: Links tab by the chord, form opened, typed, Cmd+.
        if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
        if let area = visible("Alpha Area") {
            area.tap()
            pause(1.5)
            for _ in 0..<3 { app.typeKey("]", modifierFlags: [.command, .shift]); pause(0.6) }
            shot("r6-links-00-tab")
            if let add = visible("Add Link") {
                add.tap()
                pause(0.8)
                let urlField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "URL")).firstMatch
                if urlField.exists { urlField.tap(); urlField.typeText("example.com/r6") }
                shot("r6-links-01-typed")
                cancelChord()
                pause(1.0)
                shot("r6-links-02-after-cmdperiod")
                note("Add Link after Cmd+.: header Add Link visible=\(visible("Add Link") != nil) url field exists=\(urlField.exists)")
            }
            // Reopen-on-last-tab: leave to Today by the sidebar, come back to Alpha Area.
            if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
            if let today = visible("Today") { today.tap(); pause(1.2) }
            if !drawerBackdropUp() { app.typeKey("o", modifierFlags: .command); pause(1.0) }
            if let again = visible("Alpha Area") { again.tap(); pause(1.5) }
            shot("r6-links-03-reopened")
            let selected = app.buttons.matching(NSPredicate(format: "isSelected == true")).allElementsBoundByIndex
                .filter { $0.frame.minX >= 0 && ["Tasks", "Kanban", "Notes", "Links", "Completed"].contains($0.label) }.map(\.label)
            note("reopened list selected tab: \(selected)")
        }
    }

    // MARK: - Helpers

    private func menuThenEscape(row label: String, item: String, tag: String) {
        guard let row = visible(label) else { note("\(tag): no visible row '\(label)'"); return }
        row.press(forDuration: 1.2)
        pause(1.0)
        shot("\(tag)-01-menu")
        guard let entry = visible(item) else {
            note("\(tag): context menu has no '\(item)'; items: \(app.buttons.allElementsBoundByIndex.filter { $0.frame.width > 0 }.map(\.label).prefix(30))")
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            pause(0.8)
            return
        }
        entry.tap()
        pause(1.2)
        shot("\(tag)-02-sheet-up")
        note("\(tag): sheet up, Cancel visible=\(visible("Cancel") != nil)")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        pause(1.2)
        shot("\(tag)-03-after-escape")
        note("\(tag): after Escape Cancel visible=\(visible("Cancel") != nil); row '\(label)' still visible=\(visible(label) != nil)")
    }

    private func launch(landscape: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "ios-sight1953-\(UUID().uuidString)")
        app.launch()
        note("foreground: \(app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground))")
        _ = glyph().waitForExistence(timeout: CadenceUITestBounds.firstPaint)
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(2.0)
        note("orientation asked \(landscape ? "landscape" : "portrait"); device reports \(XCUIDevice.shared.orientation.rawValue); window \(app.windows.firstMatch.frame)")
    }

    /// Unfold the column (docked) or open the drawer by Cmd+O, which run 1 measured working.
    private func revealSidebar() {
        if glyph().exists, glyph().frame.minX < 0 {
            app.typeKey("o", modifierFlags: .command)
            pause(1.0)
        }
        note("sidebar revealed: glyph minX \(glyphMinX())")
    }

    /// First element with this label that has a real frame -- never a zero-size shortcut host.
    private func visible(_ label: String) -> XCUIElement? {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .allElementsBoundByIndex
            .first { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.minX >= 0 && $0.isHittable }
    }

    private func glyph() -> XCUIElement {
        app.descendants(matching: .any).matching(CadenceUITestQuery.identifying("magnifyingglass")).firstMatch
    }

    private func glyphMinX() -> String {
        let element = glyph()
        return element.exists ? "\(element.frame.minX)" : "absent"
    }

    private func drawerBackdropUp() -> Bool {
        app.descendants(matching: .any).matching(CadenceUITestQuery.identifying("cadence.sidebar.drawerBackdrop")).firstMatch.exists
    }

    private func noticeShown() -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Add a title first")).firstMatch.exists
    }

    private func texts(matching pattern: String) -> String {
        let found = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*(\(pattern)).*"))
            .allElementsBoundByIndex.prefix(12).map { "\($0.label)@\(Int($0.frame.minX)),\(Int($0.frame.minY))" }
        return found.isEmpty ? "none" : found.joined(separator: " | ")
    }

    private func pause(_ seconds: TimeInterval) {
        _ = app.wait(for: .unknown, timeout: seconds)
    }

    private func note(_ line: String) {
        print("SIGHT1953: [\(name)] \(line)")
    }

    private func shot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
#endif
