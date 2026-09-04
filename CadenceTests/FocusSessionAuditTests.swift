#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Focus-surface regressions found in the Focus audit: the two places that turn a stopwatch
/// reading into logged minutes, the close button that used to strand the stopwatch, and the
/// bundle ordering in the idle picker.
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

/// `FocusManager` is a singleton, so these mutate shared state and must not interleave.
@Suite(.serialized)
@MainActor
struct FocusManagerEndSessionTests {

    private func resetManager() {
        let manager = FocusManager.shared
        manager.activeSession = nil
        manager.selectedBundleTaskIDs = []
        manager.reset()
        manager.wantsNavToFocus = false
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
        try manager.startFocus(task: task, in: context)
        manager.elapsed = 25 * 60

        try manager.endSession(in: context)

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
        #expect(manager.activeSession == nil)
        #expect(manager.isRunning == false)
        #expect(manager.elapsed == 0)
    }

    /// Same for a bundle session: the selected members receive the time, and the selection is
    /// cleared with the session rather than leaking into the next one.
    @Test func closingABundleSessionDistributesTimeAndClearsSelection() throws {
        resetManager()
        defer { resetManager() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Admin sweep", dateKey: "2026-08-12", startMin: 540, durationMinutes: 30)
        let first = AppTask(title: "Expenses")
        first.estimatedMinutes = 10
        first.bundle = bundle
        let second = AppTask(title: "Inbox zero")
        second.estimatedMinutes = 10
        second.bundle = bundle
        context.insert(bundle)
        context.insert(first)
        context.insert(second)

        let manager = FocusManager.shared
        try manager.startFocus(bundle: bundle, in: context)
        manager.elapsed = 20 * 60

        try manager.endSession(in: context)

        #expect(first.actualMinutes + second.actualMinutes == 20)
        #expect(manager.activeSession == nil)
        #expect(manager.selectedBundleTaskIDs.isEmpty)
        #expect(manager.isRunning == false)
        #expect(manager.elapsed == 0)
    }
}

/// The idle focus picker's bundle ordering.
@MainActor
struct FocusPickItemBundleOrderTests {
    private let todayKey = "2026-08-12"

    private func bundle(_ title: String, _ dateKey: String, startMin: Int, task: String) -> TaskBundle {
        let bundle = TaskBundle(title: title, dateKey: dateKey, startMin: startMin, durationMinutes: 30)
        let member = AppTask(title: task)
        member.bundle = bundle
        bundle.tasks = [member]
        return bundle
    }

    /// Two bundles in the same rank but on different days used to compare as equal — the day was
    /// never consulted and the `startMin` tie-break was never reached — so a bundle eight days out
    /// could render above tomorrow's, and the comparator was not a strict weak ordering.
    @Test func upcomingBundlesSortByDayThenStartTime() {
        let far = bundle("Far", "2026-08-20", startMin: 540, task: "a")
        let soon = bundle("Soon", "2026-08-13", startMin: 600, task: "b")
        let farEarly = bundle("Far early", "2026-08-20", startMin: 480, task: "c")

        let items = FocusPickItem.filtered(
            tasks: [],
            bundles: [far, soon, farEarly],
            query: "",
            todayKey: todayKey
        )

        #expect(items.map(\.id) == [soon, farEarly, far].map { "bundle-\($0.id.uuidString)" })
    }

    /// Today first, then upcoming, then undated, then past — and inside the past run the most
    /// recent day leads, so yesterday's leftovers are not buried under last year's.
    @Test func bundleRanksOrderTodayThenUpcomingThenUndatedThenPast() {
        let today = bundle("Today", todayKey, startMin: 540, task: "a")
        let upcoming = bundle("Upcoming", "2026-08-14", startMin: 540, task: "b")
        let undated = bundle("Undated", "", startMin: 540, task: "c")
        let yesterday = bundle("Yesterday", "2026-08-11", startMin: 540, task: "d")
        let ancient = bundle("Ancient", "2025-01-04", startMin: 540, task: "e")

        let items = FocusPickItem.filtered(
            tasks: [],
            bundles: [ancient, undated, upcoming, yesterday, today],
            query: "",
            todayKey: todayKey
        )

        #expect(
            items.map(\.id) == [today, upcoming, undated, yesterday, ancient]
                .map { "bundle-\($0.id.uuidString)" }
        )
    }
}
#endif
