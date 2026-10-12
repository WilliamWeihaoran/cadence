#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-3098: what `macOSRootView.refreshAppData()` owes the app-wide singletons when it swaps the
/// model context.
///
/// The swap is ordinary — the widget's `CompleteTaskIntent` and `CadenceModelContainerFactory`
/// both post the external-write marker, and `scheduleAppDataRefreshIfPossible` acts on it the
/// moment the app is active again. What made it a defect is that `dataRefreshID` rebuilds the two
/// subtrees and nothing re-runs the root's `.onAppear`, so `FocusManager.activeSession` and
/// `HoveredTaskManager.hoveredTask` were left holding rows from the context just retired.
///
/// Every test here stands up **two contexts over one in-memory container**, which is the swap: the
/// same row, two live object graphs, and a question about which one the app is pointing at.
/// A clock the test moves by hand, so 90 seconds pass with no wall clock and no display ticks.
@MainActor
private final class SwapTestClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
struct CadenceRootContextSwapAdoptionTests {

    private func resetSharedManagers() {
        FocusManager.shared.activeSession = nil
        FocusManager.shared.selectedBundleTaskIDs = []
        FocusManager.shared.reset()
        FocusManager.shared.clock = { Date() }
        HoveredTaskManager.shared.clear()
    }

    private func makeSwap() throws -> (retired: ModelContext, live: ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (ModelContext(container), ModelContext(container))
    }

    private func refetchTask(_ id: UUID, in context: ModelContext) throws -> AppTask {
        try #require(try context.fetch(FetchDescriptor<AppTask>()).first { $0.id == id })
    }

    // MARK: - FocusManager: re-resolved, never discarded

    /// The headline for the leg that matters most. A focus session is long-running and is usually
    /// stopped just after coming back to the app — the same moment the swap fires — so the session
    /// must come through the swap pointing at the *live* row, not at the retired one and not at
    /// nothing.
    @Test func aRunningTaskSessionIsRepointedAtTheReplacementContextsCopyOfItsRow() throws {
        let (retired, live) = try makeSwap()
        let seeded = AppTask(title: "Deep work")
        retired.insert(seeded)
        try retired.save()

        let resolved = try #require(
            macOSRootDataRefreshSupport.reresolvedSession(.task(seeded), in: live)
        )
        guard case .task(let adopted) = resolved else {
            Issue.record("a task session was re-resolved into something other than a task session")
            return
        }
        #expect(adopted.id == seeded.id)
        #expect(adopted !== seeded, "the session kept the retired context's copy of the row")

        // And the row it now points at is the one the rebuilt subtree reads: an edit made through
        // the live context is visible on the adopted object without a refetch.
        adopted.title = "Deeper work"
        let liveCopy = try refetchTask(seeded.id, in: live)
        #expect(liveCopy.title == "Deeper work")
    }

    /// The bundle half of the same session. `FocusManager.ActiveSession` has two cases and a fix
    /// that handled one of them would strand every bundle focus.
    @Test func aRunningBundleSessionIsRepointedToo() throws {
        let (retired, live) = try makeSwap()
        let seeded = TaskBundle(title: "Morning block", dateKey: "2026-08-04", startMin: 540, durationMinutes: 60)
        retired.insert(seeded)
        try retired.save()

        let resolved = try #require(
            macOSRootDataRefreshSupport.reresolvedSession(.bundle(seeded), in: live)
        )
        guard case .bundle(let adopted) = resolved else {
            Issue.record("a bundle session was re-resolved into something other than a bundle session")
            return
        }
        #expect(adopted.id == seeded.id)
        #expect(adopted !== seeded)
    }

    /// **The decision this leg turns on.** When the other process deleted the task, the row cannot
    /// be re-resolved — and the answer to that is to leave the session alone, not to end it.
    /// `nil` means "change nothing", so a user who was mid-session keeps their stopwatch and their
    /// banked minutes instead of losing them to a bookkeeping event they never saw.
    @Test func aSessionWhoseRowIsGoneFromTheStoreIsLeftAloneRatherThanCleared() throws {
        let (retired, live) = try makeSwap()
        let seeded = AppTask(title: "Deep work")
        retired.insert(seeded)
        try retired.save()

        let liveCopy = try refetchTask(seeded.id, in: live)
        live.delete(liveCopy)
        try live.save()

        #expect(
            macOSRootDataRefreshSupport.reresolvedSession(.task(seeded), in: live) == nil,
            "a session whose row the other process deleted was discarded instead of kept"
        )
    }

    /// No session, and a session already resolved against this context, both answer "change
    /// nothing" — so the refresh does not write an equal value into an `@Observable` property on
    /// every swap.
    @Test func thereIsNothingToAdoptWhenTheSessionIsAbsentOrAlreadyLive() throws {
        let (_, live) = try makeSwap()
        #expect(macOSRootDataRefreshSupport.reresolvedSession(nil, in: live) == nil)

        let task = AppTask(title: "Deep work")
        live.insert(task)
        try live.save()
        #expect(macOSRootDataRefreshSupport.reresolvedSession(.task(task), in: live) == nil)
    }

    // MARK: - The whole adoption, over the singletons the root actually holds

    /// `adoptReplacementContext` is what `refreshAppData()` calls, so it is asserted as a whole:
    /// the session is re-pointed, the stopwatch is untouched, and hover — which the `.id()` rebuild
    /// has already reset from the row's end — is cleared so the manager stops asserting a hover no
    /// row believes in.
    @Test func adoptingAReplacementContextRepointsTheSessionClearsHoverAndLeavesTheClockRunning() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let (retired, live) = try makeSwap()
        let seeded = AppTask(title: "Deep work")
        let hovered = AppTask(title: "Something else")
        retired.insert(seeded)
        retired.insert(hovered)
        try retired.save()

        let clock = SwapTestClock()
        FocusManager.shared.clock = { clock.now }
        try FocusManager.shared.startFocus(task: seeded, in: retired)
        clock.now = clock.now.addingTimeInterval(90)
        #expect(FocusManager.shared.isRunning)
        #expect(FocusManager.shared.elapsed == 90)

        HoveredTaskManager.shared.beginHovering(hovered, source: .list)
        #expect(HoveredTaskManager.shared.hoveredTask != nil)

        macOSRootDataRefreshSupport.adoptReplacementContext(
            live,
            focusManager: FocusManager.shared,
            hoveredTaskManager: HoveredTaskManager.shared
        )

        let adopted = try #require(FocusManager.shared.activeTask)
        #expect(adopted.id == seeded.id)
        #expect(adopted !== seeded, "the swap left the focus session on the retired context's row")

        // The stopwatch lives in `CadenceFocusTimerState`, not in `activeSession`, which is the
        // whole reason re-resolving the row is safe.
        #expect(FocusManager.shared.isRunning)
        #expect(FocusManager.shared.elapsed == 90)

        #expect(
            HoveredTaskManager.shared.hoveredTask == nil,
            "hover survived the rebuild that reset every row's own isHovered"
        )
        #expect(HoveredTaskManager.shared.hoveredSource == nil)
    }
}
#endif
