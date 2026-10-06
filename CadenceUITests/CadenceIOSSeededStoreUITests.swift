// **The iOS half of this target, and until T-2074/T-2075 there was none.** Everything else here
// reaches AppKit, `rightClick()` or identifiers only the desktop publishes, so it is all behind
// `#if os(macOS)`; this file is behind the other half of the same question.
#if os(iOS)
import XCTest

/// **Proof that an iOS launch can be handed a store and that the app comes up showing it**
/// ([[T-2075]], and the first half of [[T-2074]]).
///
/// Both tickets are one defect seen from two sides. `CadenceUITestSupport.prepareAppState` — the
/// only caller of `CadenceUITestScenarioSeed.seedIfRequested` — was reached from exactly one place
/// in the app, `Cadence/macOS/macOSRootView.swift:115`. So `CADENCE_UI_TEST_MODE=1` plus
/// `CADENCE_UI_TEST_SCENARIO=…` on a simulator launch seeded **nothing**, and the three scenarios
/// were macOS-only in practice while reading as app-wide.
///
/// **The shape that made it dangerous is why this suite asserts on CONTENT and not on wiring.**
/// `CADENCE_UI_TEST_STORE_ID` kept working the whole time, because `CadenceUITestStoreDirectory`
/// resolves it before any view exists — so a seeded iOS launch produced a store that was private,
/// correctly isolated from the signed-in person's, and completely empty. A test asking *was the
/// call site reachable* would be green on the broken tree and on the fixed one alike. The only
/// question that separates them is whether something the seed wrote is on screen.
///
/// **What the fixed build actually draws, measured on 2026-10-06 by hand before this suite was
/// written** — `simctl launch` with these five variables, screenshotted through the simulator
/// panel, on both standing devices:
///
/// - `Cadence-iPhone15` (compact): the Tasks tab's **index** — `Today 2`, `Tasks 7`, and the stock
///   seed's own section `UI TEST WORKSPACE` over `Alpha Area 7` / `Beta Project` / `Gamma Area`.
///   The scenario's task titles are one tap away, behind the `Today` row.
/// - `Cadence-iPadPro11` (regular): Today itself, with `Rollover One/Two/Three` in the rollover
///   notice, `Overdue One/Two`, `Today One/Two`, and `UI Test Daily Note` in the notes pane.
///
/// The same launch with `CADENCE_UI_TEST_MODE` unset drew `No lists yet` and no counts, and so did
/// a seeded launch against a build with the new `onAppear` removed — which is the mutation this
/// suite is the standing version of.
///
/// **The two shells therefore differ in whether the titles need a tap, and this suite does not
/// hard-code which it is on.** `revealTodayIfNeeded()` taps the index's Today row only when the
/// titles are not already up, so one body covers the iPhone and the iPad. Asserting the stock seed
/// *first* is not belt-and-braces either: `Alpha Area` is `prepareAppState`'s own seed and the
/// task titles are `seedIfRequested`'s, and the two were separately dead.
@MainActor
final class CadenceIOSSeededStoreUITests: XCTestCase {

    /// The scenario this suite asks for, and the strings it expects back.
    ///
    /// Spelled as literals because the UI-test target cannot import the app module.
    /// `CadenceUITestScenarioSeedLiteralDriftTests` in `CadenceTests` holds them against
    /// `CadenceUITestScenarioSeed.Fixture` and `CadenceUITestSupport` from the side that *can*
    /// import them, so a rename there reddens a test rather than quietly leaving this suite
    /// asserting about strings nothing writes.
    private enum Fixture {
        static let scenario = "today-geometry"
        /// `CadenceUITestSupport.seedDataIfNeeded`'s first list. The **stock** seed, which is the
        /// half of `prepareAppState` that runs whether or not a scenario was named.
        static let stockSeedListName = "Alpha Area"
        /// `CadenceUITestScenarioSeed.Fixture.todayTaskNames` — planned for **today**.
        static let todayTaskTitles = ["Today One", "Today Two"]
        /// The compact index row that opens Today. Also Today's own title once it is open, which is
        /// why `revealTodayIfNeeded` checks the task titles rather than this to decide.
        static let todayRowLabel = "Today"
        /// The compact bar item the shell always draws. The control for *did any UI appear at
        /// all* — without it, "the seed did not run" and "the app drew nothing" are the same red
        /// line, which is the confusion [[T-563]]/[[T-1890]] cost a day of.
        static let tasksTabLabel = "Tasks"
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// **The acceptance bar for both tickets: a known store in front of the app, asserted on.**
    func testASeededLaunchShowsTheStockListsAndTheScenariosTasks() throws {
        launchApp(scenario: Fixture.scenario)

        XCTAssertTrue(
            element(labelled: Fixture.tasksTabLabel).waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the shell never drew its Tasks affordance, so nothing below is about the seed. "
            + surfaceReport()
        )

        // `prepareAppState`'s own seed. T-2075 in one assertion: this is what an iOS launch could
        // not get, however many UI-test variables it carried.
        XCTAssertTrue(
            element(labelled: Fixture.stockSeedListName).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
            "'\(Fixture.stockSeedListName)' is not on screen, so CadenceUITestSupport.prepareAppState "
            + "did not run on this launch even though the private store was honoured. " + surfaceReport()
        )

        // And `CadenceUITestScenarioSeed`'s, which is the half T-2074 filed.
        revealTodayIfNeeded()
        for title in Fixture.todayTaskTitles {
            XCTAssertTrue(
                element(labelled: title).waitForExistence(timeout: CadenceUITestBounds.sidebarRow),
                "'\(title)' is not on Today, so the '\(Fixture.scenario)' scenario did not seed. "
                + surfaceReport()
            )
        }
    }

    /// **The control.** The same launch with no UI-test mode shows none of it, so the reading above
    /// is a comparison rather than strings that happen to be in the app.
    ///
    /// Measured by hand on 2026-10-06: that launch draws `No lists yet` where the three seeded
    /// rows are, and no count beside Today or Tasks.
    func testAnUnseededLaunchShowsNeitherSeed() throws {
        launchApp(scenario: nil, uiTestMode: false)

        XCTAssertTrue(
            element(labelled: Fixture.tasksTabLabel).waitForExistence(timeout: CadenceUITestBounds.firstPaint),
            "the shell never drew its Tasks affordance, so this control measures nothing. "
            + surfaceReport()
        )
        XCTAssertFalse(
            element(labelled: Fixture.stockSeedListName).waitForExistence(timeout: CadenceUITestBounds.settle),
            "'\(Fixture.stockSeedListName)' is on screen on a launch that asked for no UI-test mode, "
            + "so the seeded reading in this suite proves nothing. " + surfaceReport()
        )
        for title in Fixture.todayTaskTitles {
            XCTAssertFalse(
                element(labelled: title).exists,
                "'\(title)' is on screen on an unseeded launch. " + surfaceReport()
            )
        }
    }

    // MARK: - Launching

    /// One construction, one isolation call, exactly as every other launch site in this target —
    /// see `CadenceAgentDefaultsIsolationTests.bothMacOSLaunchersAskForAPrivatePreferencesSuite`,
    /// which counts them.
    ///
    /// `CADENCE_RESET_STORE` is not decoration: every seed here is idempotent on a store that
    /// already holds tasks, so a launch against a surviving store would seed nothing and the suite
    /// would be reading the previous run's fixture.
    private func launchApp(scenario: String?, uiTestMode: Bool = true) {
        app = XCUIApplication()
        if uiTestMode {
            app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        }
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "ios-\(name)-\(UUID().uuidString)")
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        if let scenario {
            app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = scenario
        }
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
    }

    // MARK: - Reading the surface

    /// Open Today when this shell did not launch onto it.
    ///
    /// The iPad's regular shell comes up on Today and needs no tap; the iPhone's compact shell
    /// comes up on the Tasks **index**, whose first row opens it. Deciding by whether the task
    /// titles are already up rather than by size class keeps the decision on the thing the test
    /// actually needs, so a later change to either shell's landing screen does not silently make
    /// this a test of the index.
    private func revealTodayIfNeeded() {
        guard let first = Fixture.todayTaskTitles.first else { return }
        guard !element(labelled: first).waitForExistence(timeout: CadenceUITestBounds.settle) else { return }
        let todayRow = element(labelled: Fixture.todayRowLabel)
        guard todayRow.waitForExistence(timeout: CadenceUITestBounds.sidebarRow) else { return }
        todayRow.tap()
    }

    /// Any element carrying this exact string, in the label **or** the value.
    ///
    /// Not `app.staticTexts[…]`: a SwiftUI row on iOS may publish its title on the row's own
    /// accessibility element rather than on a static text beneath it, and the two spellings have
    /// the same symptom and different fixes — the lesson T-2022 wrote down one platform over.
    private func element(labelled string: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", string, string))
            .firstMatch
    }

    /// What the app is actually showing, because `XCTAssertTrue failed` on a launch-and-look test
    /// cannot tell an empty store from an app on a different screen from an app that drew nothing.
    private func surfaceReport() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex
            .prefix(24)
            .map(\.label)
            .filter { !$0.isEmpty }
        return "the app's first static texts: "
            + (texts.isEmpty ? "none at all" : texts.joined(separator: " | "))
    }
}
#endif
