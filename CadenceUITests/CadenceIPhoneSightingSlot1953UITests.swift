// SIGHTING HARNESS, not a regression suite (agent sightphone1953, slot slot1953, 2026-11-24).
//
// The scheduled sighting slot cannot use the simulator tap tool, so this file drives the iPhone
// through XCUITest instead ([[T-19756]]) and writes a frame at every step for a person or agent to
// LOOK at. A green run here is not a sighting; the frames under scratchpad/sightphone1953/frames
// are. The tests assert almost nothing on purpose: every step is tolerant, so one missing control
// costs one frame rather than the rest of the walk. They skip cleanly on a locked Mac through the
// shared unlocked-screen gate, and never touch the interactive opt-in.
#if os(iOS)
import UIKit
import Vision
import XCTest

@MainActor
final class CadenceIPhoneSightingSlot1953UITests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0
    private var prefix = "x"

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Walks

    /// [[T-13621]] iPhone leg: relaunch persistence of the Tasks tab's chips, the chips at a large
    /// text size, and (for [[T-11161]]) a long-press lift and a drag on a Kanban card.
    func test01ListSortRelaunchAndKanbanCard() throws {
        prefix = "sort"
        let store = "sp1953-sort-\(UUID().uuidString)"
        launch(storeID: store, reset: true, scenario: nil)
        seedSamples()
        tap("Tasks")
        tap("TestFlight Readiness", contains: true)
        tap("Group", contains: true)
        tap("By Section", contains: true)
        tap("Sort", contains: true)
        tap("Priority", contains: true)
        tap("Order", contains: true)
        tap("Descending", contains: true)
        look("before-relaunch")
        tap("Kanban")
        if let card = visible("Test Inbox capture", contains: true, timeout: 3) {
            record("kanban card: \(card.label) \(card.frame)")
            card.press(forDuration: 1.4)
            look("kanban-lift")
            dismissMenu()
            look("kanban-dismissed")
            if let again = visible("Test Inbox capture", contains: true, timeout: 3) {
                drag(again, by: CGVector(dx: -200, dy: 0), name: "kanban-drag")
            }
        } else {
            record("no kanban card")
        }
        tapHigh("Tasks")
        look("tasks-tab-again")
        app.terminate()
        launch(storeID: store, reset: false, scenario: nil)
        tap("Tasks")
        tap("TestFlight Readiness", contains: true)
        look("relaunch-landing")
        tapHigh("Tasks")
        look("relaunch-tasks-tab")
        app.terminate()
        launch(
            storeID: store, reset: false, scenario: nil,
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        )
        tap("Tasks")
        tap("TestFlight Readiness", contains: true)
        tapHigh("Tasks")
        look("ax-large-tasks-tab")
    }

    /// [[T-16689]]'s list-note route, searched in the store that holds the note.
    func test05bListNoteSearch() throws {
        prefix = "listsearch"
        let store = "sp1953-listsearch-\(UUID().uuidString)"
        launch(storeID: store, reset: true, scenario: "today-geometry")
        tap("Tasks")
        tap("Alpha Area", contains: true)
        tapHigh("Notes")
        tap("New note")
        tap("New Note")
        look("new-note")
        let editor = app.textViews.firstMatch
        if editor.waitForExistence(timeout: 8) {
            editor.tap()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText("# Kestrel list note\n\nA list-owned note.")
            look("typed")
            if !tap("Done", timeout: 2) { _ = tap("Close", timeout: 2) }
        }
        app.terminate()
        launch(storeID: store, reset: false, scenario: nil)
        tap("Search")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("Kestrel")
            look("search-kestrel")
            tap("Kestrel list note", contains: true)
            look("list-note-cover")
        }
    }

    /// [[T-12651]] (2): past, today and future do dates on All Tasks and a list, and the Today
    /// page drawing no do chip.
    func test02DoDateChips() throws {
        prefix = "dochip"
        launch(storeID: "sp1953-dochip-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("open tasks", contains: true)
        app.swipeUp()
        if let row = visible("Today Two", timeout: 3) {
            row.swipeRight()
            look("swipe-right")
            tap("Tomorrow")
        } else {
            record("Today Two not hittable")
        }
        look("alltasks-after")
        app.swipeUp()
        look("alltasks-after-scrolled")
        back()
        tap("Alpha Area", contains: true)
        look("list")
        app.swipeUp()
        look("list-scrolled")
        back()
        tap("overdue", contains: true)
        look("today")
        app.swipeUp()
        look("today-scrolled")
    }

    /// [[T-12661]]: Return inserts a line in the capture card's subtasks field, and a seventh line
    /// scrolls rather than growing the card.
    func test03CaptureSubtaskSeventhLine() throws {
        prefix = "capture"
        launch(storeID: "sp1953-capture-\(UUID().uuidString)", reset: true, scenario: nil)
        tap("Tasks")
        tap("Alpha Area", contains: true)
        tap("New Task")
        let field = app.textFields["capture-subtasks"]
        let view = app.textViews["capture-subtasks"]
        let target = field.exists ? field : view
        guard target.exists else { record("no capture-subtasks field"); return }
        target.tap()
        target.typeText("Line 1\nLine 2")
        look("two-lines")
        target.typeText("\nLine 3\nLine 4\nLine 5\nLine 6")
        look("six-lines")
        target.typeText("\nLine 7")
        look("seven-lines")
        record("after seven: \(String(describing: target.value))")
    }

    /// [[T-13201]]: a nested quoted checklist, Return on it, a box tap, the plain-quote control,
    /// and a quoted task first line in the notes list and in search.
    func test04QuotedNestedChecklist() throws {
        prefix = "quote"
        launch(storeID: "sp1953-quote-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("Notes")
        tap("Notepad")
        tap("New note")
        let editor = app.textViews["markdown.editor"]
        guard editor.waitForExistence(timeout: 10) else { look("no-editor"); return }
        editor.tap()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("> - [ ] todo\ntop\n")
        // Replace the continued line's prefix with the nested one, typed whole.
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeText(">   - [ ] nested")
        look("nested")
        record("nested source: \(String(describing: editor.value))")
        editor.typeText("\n")
        record("after-return source: \(String(describing: editor.value))")
        editor.typeText("deeper")
        look("after-return")
        record("deeper source: \(String(describing: editor.value))")
        if ocrTap("nested", in: editor, dxPoints: -60) {
            look("nested-box-tapped")
            record("after box tap: \(String(describing: editor.value))")
        }
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n\n\n")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeText(">   plain text")
        look("plain-control")
        record("final source: \(String(describing: editor.value))")
        tap("Done")
        look("list-row")
        tap("Tasks")
        tap("Search")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("todo")
            tap("Notes", contains: true)
            look("search-todo-notes")
        }
    }

    /// [[T-13201]]: a tap on the nested box flips only its own line.
    func test04QuotedNestedBoxTap() throws {
        prefix = "quotebox"
        launch(storeID: "sp1953-quote-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("Notes")
        tap("Notepad")
        tap("New note")
        let editor = app.textViews["markdown.editor"]
        guard editor.waitForExistence(timeout: 10) else { look("no-editor"); return }
        editor.tap()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("> - [ ] todo\ntop\n")
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        editor.typeText(">   - [ ] nested")
        tap("Done")
        tap("todo", contains: true)
        guard editor.waitForExistence(timeout: 6) else { look("no-editor-2"); return }
        look("reopened")
        record("before box tap: \(String(describing: editor.value))")
        if ocrTap("nested", in: editor, leadingPoints: -16) {
            look("nested-box-tapped")
            record("after nested box tap: \(String(describing: editor.value))")
        }
        if ocrTap("top", in: editor, leadingPoints: -16) {
            look("top-box-tapped")
            record("after top box tap: \(String(describing: editor.value))")
        }
    }

    /// [[T-16670]] route one with targets that exist (a daily note and a named note), and
    /// [[T-16689]]'s named-note route from Search.
    func test05ReferenceRoutes() throws {
        prefix = "ref"
        launch(storeID: "sp1953-ref-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("Notes")
        tap("Notepad")
        tap("New note")
        let editor = app.textViews["markdown.editor"]
        if editor.waitForExistence(timeout: 8) {
            editor.tap()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText("# Orchard plans\n\nA named target note.")
            tap("Done")
        }
        tap("Weekly")
        tap("This Week", contains: true)
        if editor.waitForExistence(timeout: 6) {
            editor.tap()
            editor.typeText("Day link [[\(todayKey())]] end\nName link [[Orchard plans]] end")
            look("weekly-links")
            record("weekly source: \(String(describing: editor.value))")
            editor.typeKey(.upArrow, modifierFlags: .command)
            if ocrTap("Orchard plans", in: editor) {
                look("name-link-tapped")
                record("after name tap, editor exists: \(editor.exists)")
                if !tap("Done", timeout: 2) { _ = tap("Close", timeout: 2) }
                look("after-name-close")
            }
            let dayLabels = [todayKey(), "Tuesday", "Nov 24"]
            if dayLabels.contains(where: { ocrTap($0, in: editor) }) {
                look("day-link-tapped")
            } else {
                record("no day link text found by OCR")
            }
        }
        app.terminate()
        launch(storeID: "sp1953-ref2-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("Notes")
        tap("Notepad")
        tap("New note")
        if editor.waitForExistence(timeout: 8) {
            editor.tap()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText("# Orchard plans\n\nA named target note.")
            tap("Done")
        }
        tap("Tasks")
        tap("Search")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("Orchard")
            look("search-orchard")
            tap("Orchard plans", contains: true)
            look("named-cover")
        }
    }

    /// [[T-11161]]: a hold-and-move drag on a Calendar Board card, short hold then slow move.
    func test06CalendarBoardDrag() throws {
        prefix = "board"
        launch(storeID: "sp1953-board-\(UUID().uuidString)", reset: true, scenario: "today-geometry")
        tap("Calendar")
        tap("Board")
        look("board")
        if let card = visible("Today One", contains: true, timeout: 4) {
            drag(card, by: CGVector(dx: 250, dy: 0), name: "board-drag")
        } else {
            record("board: no Today One card")
        }
    }

    /// [[T-12762]] half (2): a read-only event's Calendar row, and a writable one's choices.
    func test07ReadOnlyEventSheet() throws {
        prefix = "readonly"
        launch(storeID: "sp1953-ro-\(UUID().uuidString)", reset: true, scenario: "calendar-read-only")
        tap("Calendar")
        look("calendar", dump: true)
        let window = app.windows.firstMatch
        if ocrTap("Bank holiday", in: window) {
            look("bank-holiday", dump: true)
            app.swipeUp()
            look("bank-holiday-scrolled")
            if !tap("Done", timeout: 2) { _ = tap("Close", timeout: 2) }
        }
        tap("Month")
        look("month")
        if ocrTap("Design review", in: window) || ocrTap("Design", in: window) {
            look("design-review-tapped", dump: true)
            if ocrTap("Design review", in: window) {
                look("design-review", dump: true)
            }
        }
    }

    /// Settings > Account & Safety > Data Safety > Simulator Samples > Seed Tasks.
    private func seedSamples() {
        tap("More")
        tap("Settings")
        for _ in 0..<5 where visible("Data Safety", timeout: 1) == nil {
            app.swipeUp()
        }
        tap("Data Safety")
        for _ in 0..<8 where visible("Seed Tasks", timeout: 1) == nil {
            app.swipeUp()
        }
        look("seed")
        tap("Seed Tasks")
        look("seeded")
    }

    /// The page header's back chevron, else a swipe in from the leading edge.
    private func back() {
        if tap("Back", timeout: 1) { return }
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 280, dy: 0)))
        sleep(1)
    }

    /// Two hold-and-move attempts: a short hold so the drag can start before the context menu
    /// takes the touch, then a slower one. A frame after each.
    private func drag(_ element: XCUIElement, by offset: CGVector, name: String) {
        record("\(name) from: \(element.label) \(element.frame)")
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.35, thenDragTo: start.withOffset(offset),
            withVelocity: .slow, thenHoldForDuration: 0.6
        )
        look(name + "-short")
        if app.buttons.matching(NSPredicate(format: "label == %@", "Duplicate")).firstMatch.exists {
            dismissMenu()
        }
        guard let again = visible(element.label, timeout: 2) else { record("\(name): card gone after first drag"); return }
        let from = again.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            forDuration: 0.6, thenDragTo: from.withOffset(offset),
            withVelocity: 120, thenHoldForDuration: 0.8
        )
        look(name + "-slow")
    }

    /// Put a context menu away: Escape, then a tap on the dimmed edge beside it.
    private func dismissMenu() {
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)
        if app.buttons.matching(NSPredicate(format: "label == %@", "Duplicate")).firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            sleep(1)
        }
    }

    /// A label that is also a bar item (Tasks, Notes): only the copy in the page's own header band.
    private func tapHigh(_ label: String) {
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).allElementsBoundByIndex
        if let hit = all.first(where: { $0.frame.minY > 60 && $0.frame.minY < 300 && $0.isHittable }) {
            hit.tap()
            sleep(1)
        } else {
            record("no header control: \(label)")
        }
    }

    private func todayKey() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    /// Find `text` in what the element has drawn, and tap it (offset by `dxPoints`). Text views
    /// publish no per-run elements for an inline reference, so the drawn glyphs are the target.
    private func ocrTap(
        _ text: String, in element: XCUIElement, dxPoints: CGFloat = 0, leadingPoints: CGFloat? = nil
    ) -> Bool {
        guard let image = UIImage(data: element.screenshot().pngRepresentation)?.cgImage else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: image).perform([request])
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: text),
                  let box = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
            record("ocr hit '\(text)' in '\(candidate.string)' at \(box)")
            let anchorX = leadingPoints == nil ? box.midX : box.minX
            element.coordinate(withNormalizedOffset: CGVector(dx: anchorX, dy: 1 - box.midY))
                .withOffset(CGVector(dx: leadingPoints ?? dxPoints, dy: 0))
                .tap()
            sleep(2)
            return true
        }
        record("ocr miss '\(text)'")
        return false
    }

    // MARK: - Launching

    private func launch(storeID: String, reset: Bool, scenario: String?, extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: storeID)
        if reset {
            app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
            app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        }
        if let scenario {
            app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = scenario
        }
        app.launchArguments += extraArguments
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground)
        sleep(2)
    }

    // MARK: - Looking

    private var frameDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scratchpad/sightphone1953/frames", isDirectory: true)
    }

    /// One frame and one accessibility dump, numbered so the walk reads in order.
    private func look(_ name: String, dump: Bool = false) {
        sleep(1)
        step += 1
        let base = String(format: "%@-%02d-%@", prefix, step, name)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = base
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: frameDirectory.appendingPathComponent(base + ".png"))
        if dump {
            try? app.debugDescription.write(
                to: frameDirectory.appendingPathComponent(base + ".txt"), atomically: true, encoding: .utf8
            )
        }
    }

    /// The first on-screen element with this exact label: a zero-size accessibility-hidden host
    /// answers label queries like the real control ([[T-8925]]), so only a non-zero frame counts.
    private func visible(_ label: String, contains: Bool = false, timeout: TimeInterval = 4) -> XCUIElement? {
        let predicate = contains
            ? NSPredicate(format: "label CONTAINS %@", label)
            : NSPredicate(format: "label == %@", label)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let all = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
            if let hit = all.first(where: { $0.exists && $0.frame.width > 1 && $0.frame.height > 1 && $0.isHittable }) {
                return hit
            }
            usleep(250_000)
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func tap(_ label: String, contains: Bool = false, timeout: TimeInterval = 4) -> Bool {
        guard let hit = visible(label, contains: contains, timeout: timeout) else {
            record("missing control: \(label)")
            return false
        }
        hit.tap()
        sleep(1)
        return true
    }

    private func record(_ line: String) {
        let url = frameDirectory.appendingPathComponent("\(prefix)-log.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
