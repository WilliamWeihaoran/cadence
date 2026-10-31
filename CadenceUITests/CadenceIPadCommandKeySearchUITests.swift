// **[[T-8801]]: Cmd+K on the iPad, driven rather than reasoned about.**
//
// [[T-8766]] gave the iOS root a zero-size `Button("Search")` carrying
// `.keyboardShortcut("k", modifiers: .command)`; [[T-8791]] made it *request* focus through
// `CadenceSearchFocusRequest`, so Cmd+K lands on Search with the field live while reaching Search
// any other way leaves the keyboard down. Both landed from source and from unit tests. Neither has
// ever been driven.
//
// **Why this file and not another transport.** Agent `ipadkeys2120` measured the gap on
// 2026-10-30: the simulator tool's `press_key` is a fixed enum — return, delete, forward_delete,
// four arrows, home/end/page_up/page_down, select_all, undo, redo — with **no "k"**. The modifier
// path is not the gap (`select_all` is Cmd+A and it worked through the app); the key list is.
// `xcrun simctl` has no key-injection subcommand, `idb` is not installed, and the host Simulator
// app's Hardware menu is off-limits. `XCUIElement.typeKey(_:modifierFlags:)` is the only API on
// this device that can synthesize an arbitrary chord, and it exists on iOS
// (`XCUIAutomation.framework/Headers/XCUIElement.h:127`).
//
// **What "focused" means here, and it is a measurement rather than an inspection.** Nothing
// reports a SwiftUI `@FocusState` to a UI test. What a focused field does is *take characters*, so
// each case types and reads the field's value back — which is exactly the reading `ipadkeys2120`
// took by hand when a sidebar-magnifier tap swallowed six characters and a tap on the field itself
// did not.
#if os(iOS)
import UIKit
import XCTest

@MainActor
final class CadenceIPadCommandKeySearchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// **[[T-8791]]'s claim, on screen: Cmd+K lands on Search AND the field takes characters.**
    func testCommandKeyOpensSearchWithTheFieldReadyToType() throws {
        try launchOnTheIPad()
        attach("cmd-k-before")

        app.typeKey(Search.key, modifierFlags: .command)

        let field = searchField
        XCTAssertTrue(
            field.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "Cmd+K did not land on Search. " + surfaceReport()
        )
        attach("cmd-k-after")

        app.typeText(Search.typed)
        XCTAssertEqual(
            field.value as? String, Search.typed,
            """
            Cmd+K reached Search but the field did not take the characters typed straight \
            afterwards, so T-8791's focus request is not arriving. Field value: \
            \(String(describing: field.value)). \(app.debugDescription)
            """
        )
        attach("cmd-k-typed")
    }

    /// **The control for the test above, and [[T-8791]]'s other half.** Reaching Search by the
    /// sidebar's own magnifier must NOT focus the field — otherwise "the field took the
    /// characters" above says nothing about Cmd+K, and on an iPhone every tap on Search would
    /// raise the soft keyboard unasked.
    ///
    /// **Read through `hasFocus`, not by typing.** Typing was the first shape of this and it is
    /// the wrong instrument: with nothing focused, `typeText` does not quietly go nowhere, it
    /// fails the test with *"Failed to synthesize event: Neither element nor any descendant has
    /// keyboard focus"* — which is the right answer arriving as an error. `hasFocus` is a
    /// first-class `XCUIElementAttributes` property on iOS, so it is read straight off the element
    /// rather than through a predicate.
    ///
    /// The second half is what makes the first mean anything: the SAME field, in the SAME launch,
    /// takes focus the moment Cmd+K asks. So the absence above is a real absence and not a dead
    /// channel — the distinction agent `ipadkeys2120` drew by hand on 2026-10-30.
    func testTheSidebarMagnifierOpensSearchUnfocusedUntilCommandKeyAsks() throws {
        try launchOnTheIPad()
        try revealTheColumn()
        let magnifier = headerGlyph()
        XCTAssertTrue(
            magnifier.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the sidebar header has no magnifier to tap. " + surfaceReport()
        )
        magnifier.tap()

        let field = searchField
        XCTAssertTrue(
            field.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the sidebar magnifier did not land on Search. " + surfaceReport()
        )
        attach("magnifier-after")
        XCTAssertFalse(
            field.hasFocus,
            """
            A sidebar-magnifier tap focused the search field. T-8791 made focus a REQUEST exactly             so this route would not raise the keyboard, and with it focused the Cmd+K reading in             this suite would be measuring nothing. \(app.debugDescription)
            """
        )

        app.typeKey(Search.key, modifierFlags: .command)
        app.typeText(Search.typed)
        attach("magnifier-then-cmd-k")
        XCTAssertEqual(
            field.value as? String, Search.typed,
            """
            Cmd+K did not focus the Search that the magnifier had already opened, so the             unfocused reading above measures a dead channel rather than a real absence of focus.             Field value: \(String(describing: field.value)). \(app.debugDescription)
            """
        )
    }

    /// **Unseen since [[T-8766]]: Cmd+K on a Search that is already up.**
    ///
    /// `CadenceSearchFocusRequest.take()` honours a request once, and `iOSSearchView` honours it
    /// on appear *or* on a generation change. A Search that is already on screen never appears
    /// again, so the second press is the one that tests the generation path — and the one a user
    /// makes by reflex. Focus is dropped in between by tapping a result row, which is what a user
    /// does between presses.
    func testCommandKeyOnASearchThatIsAlreadyUpRefocusesTheField() throws {
        try launchOnTheIPad()
        app.typeKey(Search.key, modifierFlags: .command)

        let field = searchField
        XCTAssertTrue(
            field.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "Cmd+K did not land on Search. " + surfaceReport()
        )
        app.typeText(Search.typed)
        XCTAssertEqual(field.value as? String, Search.typed, "the first press did not focus the field")

        // Drop focus without leaving Search: the keyboard's own dismiss key, which exists whenever
        // a hardware keyboard is not driving the on-screen one, else a tap on the page body.
        app.typeText(XCUIKeyboardKey.escape.rawValue)
        attach("second-cmd-k-before")

        app.typeKey(Search.key, modifierFlags: .command)
        XCTAssertTrue(
            field.waitForExistence(timeout: CadenceUITestBounds.settle),
            "the second Cmd+K took Search off screen. " + surfaceReport()
        )
        app.typeText(Search.typedAgain)
        attach("second-cmd-k-after")
        XCTAssertEqual(
            field.value as? String, Search.typed + Search.typedAgain,
            """
            A second Cmd+K on a Search that was already up did not leave the field taking \
            characters. CadenceSearchFocusRequest's generation path is the only thing that can \
            honour it there — iOSSearchView never appears a second time. Field value: \
            \(String(describing: field.value)). \(app.debugDescription)
            """
        )
    }

    /// **Also unseen since [[T-8766]]: Cmd+K while something is presented over the page.**
    ///
    /// The shortcut's button lives in the root's `.background`, below every presentation, and
    /// T-8766 itself flagged that it "may reach through the presentation and move the page behind
    /// it". The capture card is the presentation this suite uses: it is reachable from any page by
    /// one identified control, it holds keyboard focus in its own title field, and losing a
    /// half-typed capture to a reflex keystroke is the user-visible form of the hazard.
    ///
    /// Two things must hold, and the second is the one the ticket is about: the card stays up with
    /// what was typed in it, and the page underneath is still the page the user left.
    func testCommandKeyOverAPresentedCaptureCardLeavesBothTheCardAndThePageAlone() throws {
        try launchOnTheIPad()
        let plus = app.buttons.matching(NSPredicate(format: "label == %@", Capture.plusLabel)).firstMatch
        XCTAssertTrue(
            plus.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "no capture control to present over the page. " + surfaceReport()
        )
        plus.tap()

        let title = app.textFields.element(identified: Capture.titleIdentifier)
        XCTAssertTrue(
            title.waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the capture card did not open. " + surfaceReport()
        )
        title.tap()
        title.typeText(Capture.typed)
        XCTAssertEqual(title.value as? String, Capture.typed, "the capture card's field did not take the text")
        attach("sheet-cmd-k-before")

        app.typeKey(Search.key, modifierFlags: .command)
        attach("sheet-cmd-k-after")

        XCTAssertTrue(
            title.exists,
            "Cmd+K over a presented capture card took the card down. " + surfaceReport()
        )
        XCTAssertEqual(
            title.value as? String, Capture.typed,
            "Cmd+K over a presented capture card lost what was typed in it. " + surfaceReport()
        )

        app.buttons.element(identified: Capture.cancelIdentifier).tap()
        XCTAssertFalse(
            searchField.waitForExistence(timeout: CadenceUITestBounds.settle),
            """
            Cmd+K reached through the presentation: the card was still up, but the page behind it \
            had already been moved to Search. The root's zero-size shortcut button fires below \
            every presentation. \(app.debugDescription)
            """
        )
        attach("sheet-cmd-k-dismissed")
    }

    // MARK: - The column

    /// `magnifyingglass` **type-agnostically**: folded, this column publishes the identifier on
    /// the BUTTON; unfolded, on the `Image` inside it, so an `app.buttons` lookup works in one
    /// state and raises `No matches found` in the other ([[T-8925]], measured 2026-10-31).
    private func headerGlyph() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifying(Search.sidebarGlyphIdentifier))
            .firstMatch
    }

    /// Unfold the column, decided by GEOMETRY. A folded column publishes "Hide Sidebar" and
    /// "Show Sidebar" at the same time with every row at negative x, so asking which control
    /// exists never unfolds anything ([[T-8925]]).
    private func revealTheColumn() throws {
        XCTAssertTrue(
            headerGlyph().waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the shell drew no sidebar header at all. " + surfaceReport()
        )
        guard headerGlyph().frame.minX < 0 else { return }
        let show = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", Search.expandLabel))
            .firstMatch
        XCTAssertTrue(
            show.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the column is folded and there is no '\(Search.expandLabel)' control. " + surfaceReport()
        )
        show.tap()
        let deadline = Date().addingTimeInterval(CadenceUITestBounds.firstPaint)
        var settled = false
        while Date() < deadline {
            let current = headerGlyph()
            if current.exists, current.frame.minX >= 0 { settled = true; break }
            _ = current.waitForExistence(timeout: 0.25)
        }
        XCTAssertTrue(settled, "the column did not unfold. " + surfaceReport())
    }

    // MARK: - Reading Search

    /// `.searchable(prompt:)` publishes its prompt as the field's label or placeholder and leaves
    /// the identifier empty, so this matches on all three — and never through a string subscript,
    /// which `CadenceUITestIdentifierLookupTests` refuses over anything but a literal.
    private var searchField: XCUIElement {
        app.searchFields
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@ OR placeholderValue == %@",
                Search.prompt, Search.prompt, Search.prompt
            ))
            .firstMatch
    }

    // MARK: - Fixtures

    /// Spelled as literals because the UI-test target cannot import the app module.
    /// `iOSSearchView.swift:358` owns the prompt; `iOSRootView.swift:142` owns the key.
    private enum Search {
        static let key = "k"
        static let prompt = "Tasks, lists, notes, events"
        /// The magnifier in `iOSSidebarHeader`. Addressed by identifier, not by the label
        /// `Search`: the root's own zero-size shortcut button carries that label too, and a
        /// `firstMatch` on it picks the invisible one.
        static let sidebarGlyphIdentifier = "magnifyingglass"
        static let expandLabel = "Show Sidebar"
        static let typed = "Polish"
        static let typedAgain = "ed"
    }

    private enum Capture {
        static let plusLabel = "New Task"
        static let titleIdentifier = "capture-title"
        static let cancelIdentifier = "capture-cancel"
        static let typed = "Half typed capture"
    }

    // MARK: - Launching

    private func launchOnTheIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("T-8801 is the iPad's hardware-keyboard shortcut; the phone has no Cmd+K.")
        }
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "ios-\(name)-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
        XCTAssertTrue(
            headerGlyph().waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the iPad shell drew no sidebar column, folded or open. " + surfaceReport()
        )
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
