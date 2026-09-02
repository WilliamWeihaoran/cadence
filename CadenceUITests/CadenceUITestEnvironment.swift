import CoreGraphics
import XCTest

/// The one environmental condition under which nothing in this target can pass, and the reason it
/// must be *stated* rather than discovered.
///
/// **A UI test cannot activate an app while the Mac's screen is locked.** `loginwindow` owns the
/// foreground, so the app XCUITest launches stays `Running Background` for ever. `XCUIApplication`'s
/// launch sequence keeps asking for the front, gives up after about a minute, and reports
///
///     Failed to activate application 'com.haoranwei.Cadence at …/Debug/Cadence.app'
///     (current state: Running Background)
///
/// as a **test failure on whichever line called `launch()`**. Nothing downstream of the launch runs,
/// so the failure is attributed to whatever the test was about to assert — which is how this cost
/// [[T-562]] a whole ticket chasing a sidebar that was never in question.
///
/// Measured 2026-09-02, on one machine, in one afternoon, either side of a single lock event at
/// 17:48:12: **20 runs / 40 launches before it, zero activation failures**, worst time-to-foreground
/// 3.12s against a 10s bound; **every run after it failed, both tests, ~61s each, 100%.** That is
/// the whole of the "flakes about 1 run in 5" this target was documented as having. It is not a
/// rate. It is a switch, and what flickers is whether the user has stepped away.
///
/// So this skips instead of failing. A skip is the honest verdict — the test is inapplicable, not
/// broken — and it cannot rot into a suite that silently skips for ever, because `scripts/xcb.sh`
/// refuses a test run that executed nothing (T-552) and names this condition when it does.
enum CadenceUITestEnvironment {

    /// Read from the window server's session dictionary, which is the same place `loginwindow`
    /// publishes it and what `ioreg`'s `IOConsoleUsers` shows.
    ///
    /// Absent rather than `false` when there is no GUI session at all, and absence is deliberately
    /// **not** treated as locked: a probe that guesses would skip the whole suite on a machine it
    /// simply could not read, which is the failure mode this type exists to prevent, inverted.
    static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// The skip message names the fix, because the reader of a skipped UI run is an agent who has
    /// just been told its end-to-end check did not run and needs to know that is not its change.
    static func requireAnUnlockedScreen() throws {
        guard screenIsLocked else { return }
        throw XCTSkip(
            """
            The Mac's screen is locked, so loginwindow owns the foreground and no launched app can \
            reach it. Every test in this target would fail inside app.launch() after about a \
            minute with "Failed to activate application … (current state: Running Background)", \
            and none of those failures would be about the code. Unlock the screen and re-run.
            """
        )
    }
}

/// Every bound this target waits on, and — separately — whether anyone has measured it.
///
/// The point of naming them is not tidiness. A timeout nobody can defend is a timeout nobody can
/// believe when it fires, and that is how this target came to be documented as *"not by itself
/// evidence of a regression"*. Each constant below says which of the two it is, and an unmeasured
/// one says so rather than borrowing the credibility of the measured one.
enum CadenceUITestBounds {

    /// **Measured.** 40 launches on 2026-09-02 under the test-host lock, screen unlocked: the app
    /// was already `.runningForeground` the instant `launch()` returned **40 times out of 40**,
    /// worst 3.12s, median 0.91s, and not one intermediate `.runningBackground` observation.
    ///
    /// So this is not waiting for the app to start. `launch()` is synchronous and its contract
    /// (`XCUIApplication.h`) is that on return the app is already running; this only absorbs the lag
    /// in `state`, which the same header calls *"inherently asynchronous"*. 10s is 3.2x the worst
    /// launch seen. **Do not raise it to chase a red run.** The failure this target actually has
    /// happens *inside* `launch()` on the line above and never reaches this wait — see
    /// `CadenceUITestEnvironment`, where the measurement that established that is written down.
    static let foreground: TimeInterval = 10

    /// **Not measured.** The value the test was written with, kept because raising a bound with no
    /// distribution behind it is how a real regression gets hidden.
    ///
    /// It is not idle either: on 2026-09-02, 4 of 20 runs with the screen *unlocked* and the app
    /// in the foreground failed here, on `sidebar.list.area.alpha-area` — the seeded rows had not
    /// appeared within 5s. Whether they are late or absent is the open question, filed as
    /// [[T-710]]; until someone times it, this stays where it was.
    static let sidebarRow: TimeInterval = 5

    /// **Not measured**, same as `sidebarRow`. First element queried after a launch, so it carries
    /// whatever the window takes to paint.
    static let firstPaint: TimeInterval = 8

    /// **Not measured.** How long something already on screen may take to finish moving, or a
    /// terminated app to stop running. Neither has ever been seen to fire.
    static let settle: TimeInterval = 5
}
