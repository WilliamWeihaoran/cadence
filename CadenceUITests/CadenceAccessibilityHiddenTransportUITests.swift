// **[[T-8925]]: XCUITest's element tree does NOT honour `.accessibilityHidden(true)` on iOS 26.5,
// and this file is the standing proof of it.**
//
// This started as [[T-8924]]'s answer. That ticket says the VoiceOver cursor looked like it landed
// on the iPad sidebar header's decorative mark, which [[T-8642]] hides, and proposed settling it
// from `app.debugDescription` on the reasoning that *that IS the accessibility tree*. It is not —
// it is an **automation** hierarchy, and the two disagree about hiding. So a UI test asking *is
// this element published* cannot tell a hidden view from an exposed one, and T-8924 is not
// answerable by this route at all. That is what this suite pins, so the next agent does not spend
// the run finding it again.
//
// **Measured 2026-10-31 on `Cadence-iPadPro11`, column UNFOLDED and fully on screen** (the first
// attempt read it folded, at negative x, which would have left the reading arguable):
//
//   Button  {{10.0, 112.0}, {244.0, 44.0}}  label: 'Tasks, 7 open tasks'
//     StaticText {{236.0, 126.8}, {8.0, 14.5}}  label: '7'      <- CadenceSidebarCountLabel, HIDDEN
//   Image   {{10.0, 20.0},  {28.0, 28.0}}  identifier: 'circle.hexagongrid.fill'   <- HIDDEN
//   Button  {{417.0, 595.0}, {0.0, 0.0}}   label: 'Search'                         <- HIDDEN
//
// Three `.accessibilityHidden(true)` sites, three authors, three purposes, all three published.
// The first is the decisive one: `CadenceSidebarCountLabel.swift:51` hides the numeral *because*
// `CadenceSidebarLayout.listRowAccessibilityLabel` already folds it into the row's own label, so a
// correct column says "Tasks, 7 open tasks" once — and the tree hands back the row label AND a
// bare `7` sitting inside it.
//
// **This suite therefore asserts the limitation, not the app.** Every assertion below is written
// to be GREEN while the limitation holds. If it reddens, that is good news and a real event: a
// toolchain has started honouring `accessibilityHidden`, and [[T-8924]] becomes answerable here
// again. Each message says so at the point it fires.
#if os(iOS)
import UIKit
import XCTest

@MainActor
final class CadenceAccessibilityHiddenTransportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testTheElementTreeDoesNotHonourAccessibilityHidden() throws {
        try launchAndRevealTheColumn()
        attach("accessibility-hidden-transport")

        // --- Site 1: the sidebar count badge. The decisive one, because the row's OWN label
        // proves the number is meant to be spoken exactly once.
        let counted = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", Fixture.countedRowSuffix))
            .allElementsBoundByIndex
            .filter { $0.label.contains(where: \.isNumber) }
        XCTAssertFalse(
            counted.isEmpty,
            "no sidebar row speaks a '…, N \(Fixture.countedRowSuffix)s' count, so this suite is "
            + "measuring nothing — the '\(Fixture.scenario)' scenario seeded no open tasks. "
            + surfaceReport()
        )

        let row = try XCTUnwrap(counted.first)
        let digits = String(row.label.filter(\.isNumber))

        // Geometric containment, not `row.staticTexts`: this column publishes its header flattened
        // in one state and nested in another (measured both ways on 2026-10-31), so a tree-scoped
        // query could answer "absent" about a badge that is merely parented elsewhere — a lie in
        // exactly the direction that matters here.
        let badges = app.staticTexts
            .matching(NSPredicate(format: "label == %@", digits))
            .allElementsBoundByIndex
            .filter { row.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        XCTAssertFalse(
            badges.isEmpty,
            """
            The hidden count badge is NO LONGER published inside '\(row.label)' \(row.frame). \
            That is good news: this toolchain has started honouring .accessibilityHidden(true), so \
            a UI test CAN now tell a hidden element from an exposed one. Re-open [[T-8924]] by this \
            route and re-read the sites below — they may be real defects after all.
            """
        )

        // --- Site 2: the iPad sidebar header's decorative mark ([[T-8642]], [[T-8924]]).
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(CadenceUITestQuery.identifying(Fixture.markSymbolName))
                .firstMatch
                .exists,
            """
            The header's decorative mark is no longer in the element tree. Either hiding is now \
            honoured here — see the badge assertion above — or the header stopped drawing its \
            mark. \(app.debugDescription)
            """
        )

        // --- Site 3: the root's zero-size Cmd+K target ([[T-8766]]). A third author, and the one
        // whose only reason to exist is a keyboard shortcut, so nothing about it is meant to be
        // reachable by a reader.
        let zeroSized = app.buttons
            .matching(NSPredicate(format: "label == %@", Fixture.shortcutButtonLabel))
            .allElementsBoundByIndex
            .filter { $0.frame.width == 0 && $0.frame.height == 0 }
        XCTAssertFalse(
            zeroSized.isEmpty,
            """
            The root's zero-size '\(Fixture.shortcutButtonLabel)' shortcut button is no longer \
            published. Same two readings as above. \(app.debugDescription)
            """
        )
    }

    // MARK: - Fixtures

    /// Spelled as literals because the UI-test target cannot import the app module.
    private enum Fixture {
        /// `CadenceSidebarLayout.listCount(openTaskCount:)`'s wording, which
        /// `listRowAccessibilityLabel` folds into the row's label.
        static let countedRowSuffix = "open task"
        /// The scenario that gives the column rows with counts. Without it this shell comes up on
        /// its "Need realistic rows?" empty state and there is nothing to read.
        static let scenario = "today-geometry"
        /// `iOSSidebarHeader`'s mark. An `Image(systemName:)` that reaches the tree publishes this
        /// string as its identifier AND its label, so a reader would say "circle hexagongrid fill".
        static let markSymbolName = "circle.hexagongrid.fill"
        /// `iOSRootView.swift:141-145` — `Button("Search")` at `.frame(width: 0, height: 0)`.
        static let shortcutButtonLabel = "Search"
        /// The header's glyphs. **Looked up type-agnostically**: folded, the column publishes the
        /// identifier on the BUTTON; unfolded, on the Image inside it. An `app.buttons` lookup
        /// finds the first and raises `No matches found` on the second.
        static let searchGlyphIdentifier = "magnifyingglass"
        static let expandLabel = "Show Sidebar"
    }

    // MARK: - Launching

    private func launchAndRevealTheColumn() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The counted sidebar column this reads is the iPad's regular shell.")
        }
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = Fixture.scenario
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "ios-\(name)-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
        try revealTheColumn()
    }

    /// **Decided by GEOMETRY, never by which control exists.** On a launch with
    /// `CADENCE_RESET_USER_DEFAULTS` this shell comes up FOLDED, and a folded column publishes
    /// `sidebar.leading` ("Hide Sidebar") and `chevron.right` ("Show Sidebar") **at the same
    /// time**, every row at negative x. An earlier version of this asked whether the collapse
    /// glyph existed, never unfolded anything, and read a column that was not on screen.
    private func revealTheColumn() throws {
        let glyph = { self.headerGlyph() }
        XCTAssertTrue(
            glyph().waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the shell drew no sidebar header at all. " + surfaceReport()
        )
        guard glyph().frame.minX < 0 else { return }

        let show = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", Fixture.expandLabel))
            .firstMatch
        XCTAssertTrue(
            show.waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "the column is folded and there is no '\(Fixture.expandLabel)' control to unfold it. "
            + surfaceReport()
        )
        show.tap()

        // The unfold is animated and the header is re-made during it, so the glyph goes away and
        // comes back. `.frame` on a query matching nothing RAISES rather than answering, so every
        // read here is guarded by `exists` first.
        let deadline = Date().addingTimeInterval(CadenceUITestBounds.firstPaint)
        var settled = false
        while Date() < deadline {
            let current = glyph()
            if current.exists, current.frame.minX >= 0 { settled = true; break }
            _ = current.waitForExistence(timeout: 0.25)
        }
        if !settled { attach("column-would-not-unfold") }
        XCTAssertTrue(
            settled,
            "the column did not unfold within \(CadenceUITestBounds.firstPaint)s of tapping "
            + "'\(Fixture.expandLabel)'. " + surfaceReport()
        )
    }

    private func headerGlyph() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(CadenceUITestQuery.identifying(Fixture.searchGlyphIdentifier))
            .firstMatch
    }

    // MARK: - Reporting

    private func surfaceReport() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(24).map(\.label).filter { !$0.isEmpty }
        return "the app's first static texts: " + (texts.isEmpty ? "none at all" : texts.joined(separator: " | "))
    }

    /// The evidence idiom this target already uses (`CadenceCapturePaletteUITests`): the frame and
    /// the tree, both kept, so a later reader can re-check the verdict instead of trusting it.
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
