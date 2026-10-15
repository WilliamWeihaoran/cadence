#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Focus-surface regressions found in the Focus audit: the two places that turn a stopwatch
/// reading into logged minutes, and the close button that used to strand the stopwatch.
@MainActor
struct FocusSessionSeedTests {

    /// The "Log session" popovers pre-fill from the same helper `FocusManager.commitElapsed`
    /// uses, so the number the sheet offers is the number the timer would have banked. They used
    /// to ceil (`(seconds + 59) / 60`): a 61-second session offered 2 minutes where the commit
    /// path logged 1, and a 20-second session offered a whole minute of work that never happened.
    @Test func logFieldSeedRoundsToNearestMinuteLikeTheCommitPath() {
        func seed(_ seconds: Int) -> [Int] {
            let value = FocusSessionSupport.logFieldSeed(elapsedSeconds: seconds)
            return [value.hours, value.minutes]
        }

        #expect(seed(61) == [0, 1])
        #expect(seed(20) == [0, 0])
        #expect(seed(90) == [0, 2])
        #expect(seed(3660) == [1, 1])
        #expect(seed(0) == [0, 0])
    }

    /// Every seed must agree with `CadenceFocusSupport.minutes(fromElapsedSeconds:)`, which is the
    /// one definition of "how many minutes is this stopwatch worth".
    @Test func logFieldSeedTotalAlwaysMatchesTheSharedMinuteConversion() {
        for seconds in stride(from: 0, through: 7_200, by: 7) {
            let seed = FocusSessionSupport.logFieldSeed(elapsedSeconds: seconds)
            #expect(seed.hours * 60 + seed.minutes == CadenceFocusSupport.minutes(fromElapsedSeconds: seconds))
        }
    }
}

/// A hand-advanced clock for `FocusManager`, so a test can move time without a run loop and
/// without a single display tick — which is precisely the condition [[T-1103]] is about.
final class FocusManagerTestClock {
    /// An arbitrary fixed instant. Nothing here reads a calendar, so its value only has to be
    /// stable across the two readings a test takes.
    private(set) var now = Date(timeIntervalSince1970: 1_757_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// `FocusManager` is a singleton, so these mutate shared state and must not interleave.
@Suite(.serialized)
@MainActor
struct FocusManagerEndSessionTests {

    private func resetManager() {
        let manager = FocusManager.shared
        manager.activeSession = nil
        manager.reset()
        manager.wantsNavToFocus = false
        manager.clock = { Date() }
    }

    /// Hand the singleton a clock the test drives, and give it back.
    private func installedClock() -> FocusManagerTestClock {
        let clock = FocusManagerTestClock()
        FocusManager.shared.clock = { clock.now }
        return clock
    }

    /// Closing a running session banks its time against the task that earned it and stops the
    /// clock. Clearing `activeSession` directly left `isRunning == true` with no session, so
    /// `FocusView`'s timer kept counting into nothing and the next `startFocus` threw the minutes
    /// away on the `case nil` branch.
    @Test func closingASessionCommitsElapsedTimeAndStopsTheClock() throws {
        resetManager()
        defer { resetManager() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Ledger")
        let task = AppTask(title: "Reconcile invoices")
        task.project = project
        context.insert(project)
        context.insert(task)

        let manager = FocusManager.shared
        let clock = installedClock()
        try manager.startFocus(task: task, in: context)
        clock.advance(25 * 60)

        try manager.endSession(in: context)

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
        #expect(manager.activeSession == nil)
        #expect(manager.isRunning == false)
        #expect(manager.elapsed == 0)
    }

    // [[T-3170]] retired `closingABundleSessionDistributesTimeAndClearsSelection`. It pinned the
    // Block session's member distribution and the clearing of the hand-built selection; both went
    // with the feature. Closing a task session is pinned by the test above this note.
}

/// **T-1103.** Who owns the focus stopwatch.
///
/// The manager said a session was running; the only thing counting for it was a one-second
/// `onReceive` closure inside `FocusView` adding to `elapsed`, and `RootDetailContent` builds
/// `FocusView` only for `selection == .focus`. So Focus → Notes → Focus destroyed the subscriber,
/// left `isRunning == true`, and the minutes spent away were absent from the number banked into
/// `actualMinutes` and the list's `loggedMinutes`. Ordinary navigation; no failure condition and
/// no unusual data.
///
/// Every test here advances an injected clock and delivers **zero** ticks, which is the same thing
/// as the screen not being on stage.
@Suite(.serialized)
@MainActor
struct FocusManagerClockOwnershipTests {

    private func resetManager() {
        let manager = FocusManager.shared
        manager.activeSession = nil
        manager.reset()
        manager.wantsNavToFocus = false
        manager.clock = { Date() }
    }

    private func installedClock() -> FocusManagerTestClock {
        let clock = FocusManagerTestClock()
        FocusManager.shared.clock = { clock.now }
        return clock
    }

    private func makeTask(_ title: String) throws -> (AppTask, Project, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Ledger")
        let task = AppTask(title: title)
        task.project = project
        context.insert(project)
        context.insert(task)
        return (task, project, context)
    }

    /// The claim, stated once: 90 seconds pass with nothing subscribed, and the session is 90
    /// seconds old. Before the fix the clock read 0, because nothing had incremented it.
    @Test func aRunningSessionCountsTimeWithNoDisplayTicksAtAll() throws {
        resetManager()
        defer { resetManager() }

        let (task, _, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        #expect(manager.elapsed == 0)

        clock.advance(90)

        #expect(manager.isRunning)
        #expect(manager.elapsed == 90)
    }

    /// And the number that is banked is that number. Leaving the Focus screen for 25 minutes and
    /// closing the session from anywhere credits 25 minutes, not 0.
    @Test func timeSpentAwayFromTheFocusScreenStillReachesTheTaskAndItsList() throws {
        resetManager()
        defer { resetManager() }

        let (task, project, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        clock.advance(25 * 60)
        try manager.endSession(in: context)

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
    }

    /// A pause is still a pause. The clock is wall-clock now, so the thing to prove is that it
    /// stops reading it — otherwise "leaving counts" would have turned into "everything counts".
    @Test func aPausedClockDoesNotAdvanceWhileTimePasses() throws {
        resetManager()
        defer { resetManager() }

        let (task, _, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        clock.advance(60)
        manager.isRunning = false          // the pause button

        clock.advance(10 * 60)

        #expect(manager.isRunning == false)
        #expect(manager.elapsed == 60)

        manager.isRunning = true           // resume
        clock.advance(30)

        #expect(manager.elapsed == 90)
    }

    /// **The contract this ticket had to preserve, not change.** `MacTaskRow`'s hover ▶
    /// calls `startFocus` for whatever task the row belongs to — including the task already being
    /// focused — and before T-1103 that path wrote `isRunning = true` on an unchanged session and
    /// left `elapsed` alone. Moving the stopwatch into the manager made it easy to zero it there
    /// instead, which would silently discard minutes that were never banked: a data loss
    /// introduced while fixing a different one. So ▶ on the current task **resumes**.
    @Test func pressingPlayOnTheTaskAlreadyFocusedResumesInsteadOfDiscarding() throws {
        resetManager()
        defer { resetManager() }

        let (task, _, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        clock.advance(5 * 60)
        manager.isRunning = false          // the pause button
        clock.advance(10 * 60)

        try manager.startFocus(task: task, in: context)   // the row's hover ▶, same task

        #expect(manager.isRunning)
        #expect(manager.elapsed == 5 * 60, "restarting the current task's clock discarded its unbanked minutes")
        #expect(task.actualMinutes == 0, "an unchanged session must not bank on its own")

        clock.advance(60)
        #expect(manager.elapsed == 6 * 60)
    }

    // [[T-3170]] retired `reSelectingTheBundleAlreadyFocusedResumesInsteadOfDiscarding` — the
    // Block twin of the task test above it, and startFocus(bundle:) no longer exists.

    /// Starting a different task starts a different clock. `commitElapsed` returns early when
    /// there is nothing to bank, so the reset has to happen on the start path rather than only on
    /// the commit path.
    @Test func switchingTasksBanksTheOldSessionAndStartsTheNewClockAtZero() throws {
        resetManager()
        defer { resetManager() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Reconcile invoices")
        let second = AppTask(title: "Draft the note")
        context.insert(first)
        context.insert(second)

        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: first, in: context)
        clock.advance(10 * 60)
        try manager.startFocus(task: second, in: context)

        #expect(first.actualMinutes == 10)
        #expect(manager.elapsed == 0)

        clock.advance(60)
        #expect(manager.elapsed == 60)
        #expect(second.actualMinutes == 0)
    }

    /// **The other half of the policy.** A `Timer` does not fire while the Mac is asleep, so the
    /// old view-owned counter never credited a closed lid. A wall clock would, and eight hours of
    /// sleep offered as loggable focus time is a worse defect than the one being fixed — so sleep
    /// stops the session and waking starts it again.
    @Test func systemSleepDoesNotCreditTheHoursTheMacWasAsleep() throws {
        resetManager()
        defer { resetManager() }

        let (task, _, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        clock.advance(60)

        manager.handleSystemWillSleep()
        clock.advance(8 * 60 * 60)
        manager.handleSystemDidWake()

        clock.advance(30)

        #expect(manager.isRunning)
        #expect(manager.elapsed == 90)
    }

    /// Waking restarts only what sleep stopped. A session the user paused before closing the lid
    /// is still paused when the lid opens.
    @Test func wakingDoesNotRestartAClockTheUserHadPaused() throws {
        resetManager()
        defer { resetManager() }

        let (task, _, context) = try makeTask("Reconcile invoices")
        let manager = FocusManager.shared
        let clock = installedClock()

        try manager.startFocus(task: task, in: context)
        clock.advance(60)
        manager.isRunning = false

        manager.handleSystemWillSleep()
        clock.advance(8 * 60 * 60)
        manager.handleSystemDidWake()
        clock.advance(120)

        #expect(manager.isRunning == false)
        #expect(manager.elapsed == 60)
    }
}

// [[T-3170]] retired `FocusPickItemBundleOrderTests` whole — `upcomingBundlesSortByDayThenStartTime`
// and `bundleRanksOrderTodayThenUpcomingThenUndatedThenPast`. Both pinned `CadenceFocusPickItem`'s
// block date-rank comparator, which is gone with the feature: the picker lists ready tasks, and
// `readyTasks` owns their order.

#endif
