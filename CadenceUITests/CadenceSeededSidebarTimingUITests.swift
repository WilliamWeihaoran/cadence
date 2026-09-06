import XCTest

/// **T-710's instrument: how long the seeded sidebar rows actually take to arrive.**
///
/// `CadenceUITests.testLaunchesToTodayWithSeededSidebarLists` waits
/// `CadenceUITestBounds.sidebarRow` (5s) for `sidebar.list.area.alpha-area` and, on
/// 2026-09-02, failed there in 4 of 20 runs with the screen unlocked and the app confirmed in
/// the foreground. `sidebar.destination.today` on the line above passed every time, so the
/// window was up and the accessibility tree was live; it is the *seeded* rows specifically.
///
/// **The 5s is not a measured bound.** It is the number the test was written with, and nothing
/// has ever asked what the distribution behind it looks like. That matters because the two
/// possible explanations need opposite fixes:
///
/// - **Late.** The rows arrive, sometimes past 5s. Then the bound moves and
///   `CadenceUITestBounds.sidebarRow` finally gets a number it can defend.
/// - **Never.** The rows do not arrive at all in those runs. Then it is a seeding or `@Query`
///   refresh bug — `CadenceUITestSupport.seedDataIfNeeded` inserts under `onAppear` and commits
///   with `try? modelContext.save()` — and the bound is irrelevant.
///
/// The existing test cannot tell them apart: it sets `continueAfterFailure = false`, so a run
/// that misses 5s stops on that line and never asks whether the row shows up at 6s or at all.
///
/// So this one **waits far past the bound and records the time**, rather than asserting it. It
/// launches the app `CADENCE_T710_RUNS` times (default 20 — the sample size the original
/// observation used), waits up to 60s per launch, and prints one line per run plus a summary.
/// The only assertion is the question the ticket asks: **did the rows arrive at all**. A run
/// where they arrive at 7s fails nothing here and is reported as a number; a run where they
/// never arrive fails, because that is the finding.
///
/// **Opt-in, and it has to be.** Twenty launches of a real `Cadence.app` take over the machine
/// for minutes; nothing that runs on every UI pass should do that. It uses the same marker as
/// the other interactive tests — see `CadenceUITestEnvironment.interactiveOptInMarkerPath`,
/// whose skip message prints the exact `touch` command.
///
/// **Read the run, not the verdict.** Even an all-green run of this test is only interesting
/// for the numbers it printed. Search its output for `T710`.
@MainActor
final class CadenceSeededSidebarTimingUITests: XCTestCase {

    /// How long a run may wait for the seeded rows. Twelve times the bound under investigation,
    /// so "late" and "never" are distinguishable rather than collapsed into one timeout.
    private static let observationWindow: TimeInterval = 60

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        try CadenceUITestEnvironment.requireInteractiveUITests()
        // Deliberately `true`: a launch that fails must not stop the remaining runs, because a
        // partial distribution is what this test exists to avoid producing.
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSeededSidebarRowsArriveAndHowLongTheyTake() throws {
        let runs = Int(ProcessInfo.processInfo.environment["CADENCE_T710_RUNS"] ?? "") ?? 20
        var arrivals: [TimeInterval] = []
        var misses = 0

        for run in 1...runs {
            let storeID = "t710-\(UUID().uuidString)"
            app = XCUIApplication()
            app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
            app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
            app.launchEnvironment["CADENCE_UI_TEST_STORE_ID"] = storeID
            app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
            app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"

            let launchStart = Date()
            app.launch()
            let launched = Date().timeIntervalSince(launchStart)

            // The clock for the rows starts when the app is in the foreground, which is the point
            // the original failure was measured from.
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
                "run \(run): app did not reach the foreground; state is \(app.state.rawValue)"
            )
            let foregroundAt = Date()

            let today = firstSeen("sidebar.destination.today", after: foregroundAt)
            let alpha = firstSeen("sidebar.list.area.alpha-area", after: foregroundAt)
            let beta = firstSeen("sidebar.list.project.beta-project", after: foregroundAt)
            let gamma = firstSeen("sidebar.list.area.gamma-area", after: foregroundAt)

            print(
                "T710 run \(run)/\(runs) launch=\(fmt(launched)) today=\(fmt(today)) "
                + "alpha=\(fmt(alpha)) beta=\(fmt(beta)) gamma=\(fmt(gamma))"
            )

            if let alpha {
                arrivals.append(alpha)
                // Recorded, not asserted: whether it beat 5s is the question, not the requirement.
                if alpha > CadenceUITestBounds.sidebarRow {
                    print("T710   ^ past the \(CadenceUITestBounds.sidebarRow)s bound this ticket is about")
                }
            } else {
                misses += 1
                XCTFail(
                    "run \(run): the seeded sidebar rows never appeared within "
                    + "\(Self.observationWindow)s. They are ABSENT, not late — T-710 is a seeding "
                    + "or @Query refresh bug and CadenceUITestBounds.sidebarRow is irrelevant."
                )
            }

            app.terminate()
            _ = app.wait(for: .notRunning, timeout: CadenceUITestBounds.settle)
            app = nil
        }

        let sorted = arrivals.sorted()
        let summary: String
        if sorted.isEmpty {
            summary = "no run ever saw the rows"
        } else {
            let median = sorted[sorted.count / 2]
            let overBound = sorted.filter { $0 > CadenceUITestBounds.sidebarRow }.count
            summary = "n=\(sorted.count) min=\(fmt(sorted.first)) median=\(fmt(median)) "
                + "max=\(fmt(sorted.last)) over-\(CadenceUITestBounds.sidebarRow)s=\(overBound)"
        }
        print("T710 SUMMARY runs=\(runs) never-arrived=\(misses) \(summary)")
    }

    /// When `identifier` first exists, measured from `origin`, or `nil` if it never does inside
    /// the observation window.
    ///
    /// Polls rather than using `waitForExistence`, because the answer wanted is *when*, and a
    /// `waitForExistence` that returns `true` says only "sometime before the timeout".
    private func firstSeen(_ identifier: String, after origin: Date) -> TimeInterval? {
        let element = app.buttons[identifier]
        let deadline = origin.addingTimeInterval(Self.observationWindow)
        while Date() < deadline {
            if element.exists { return Date().timeIntervalSince(origin) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    private func fmt(_ value: TimeInterval?) -> String {
        guard let value else { return "ABSENT" }
        return String(format: "%.2fs", value)
    }
}
