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

    // [[T-3170]] retired `aRunningBundleSessionIsRepointedToo`. It was the Block half of the
    // re-resolution, and `FocusManager.ActiveSession` has one case again; the task half above is
    // the whole of what the swap now has to re-point.

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

    // MARK: - T-5893: the focused task completed by another process (MCP)

    /// **T-5893.** `CadenceMCPServer` is a separate process with its own container on the same
    /// store file, so its `complete_task` reaches the app only through the swap: nothing mutates the
    /// app's copy of the row, and T-5310's `statusRaw` watch has nothing to fire on. Measured before
    /// the fix: the session came through the swap re-pointed at the live — already DONE — row, and
    /// stayed there, so the next ▶ timed a finished task. The adoption has to look at the row it
    /// adopted, the way the watch looks at an in-process write.
    ///
    /// The fixture is an on-disk store in this test's own temp directory, with two containers on it:
    /// the app's, and an "MCP" one that makes `CadenceWriteService.completeTask`'s mutation
    /// (`CadenceTaskRecurrenceWorkflowSupport.markDone`, then save) without its audit log or
    /// external-write marker, which would reach the real app group.
    @Test func aFocusedTaskCompletedByAnotherProcessReleasesTheSessionWhenTheSwapAdoptsIt() async throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T5893-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        func openStore() throws -> ModelContainer {
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "T5893Fixture", schema: CadenceSchema.schema,
                    url: storeURL, cloudKitDatabase: .none
                )
            )
        }

        let appContainer = try openStore()
        let appContext = ModelContext(appContainer)
        let project = Project(name: "Ledger")
        appContext.insert(project)
        let focused = AppTask(title: "Reconcile invoices")
        let next = AppTask(title: "File receipts")
        for task in [focused, next] {
            task.project = project
            appContext.insert(task)
        }
        try appContext.save()

        let clock = SwapTestClock()
        FocusManager.shared.clock = { clock.now }
        try FocusManager.shared.startFocus(task: focused, in: appContext)
        clock.now = clock.now.addingTimeInterval(30 * 60)

        // The other process: its own container, its own context, the same file.
        do {
            let mcpContainer = try openStore()
            let mcpContext = ModelContext(mcpContainer)
            let mcpCopy = try refetchTask(focused.id, in: mcpContext)
            _ = CadenceTaskRecurrenceWorkflowSupport.markDone(mcpCopy, in: mcpContext)
            try mcpContext.save()
        }
        #expect(focused.isDone == false, "the app's own copy of the row moved without a merge")

        // The app's merge path, as `macOSRootView.refreshAppData()` runs it.
        let live = CadenceModelContextRefresh.replacement(for: appContext)
        macOSRootDataRefreshSupport.adoptReplacementContext(
            live,
            focusManager: FocusManager.shared,
            hoveredTaskManager: HoveredTaskManager.shared
        )

        let deadline = Date().addingTimeInterval(10)
        while FocusManager.shared.activeTask?.id == focused.id, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(
            FocusManager.shared.activeTask?.id == next.id,
            "a task MCP completed is still the focus session after the swap adopted the write"
        )
        #expect(FocusManager.shared.activeTask?.modelContext === live)
        #expect(FocusManager.shared.elapsed == 0)
        let liveCopy = try refetchTask(focused.id, in: live)
        #expect(liveCopy.isDone)
        #expect(liveCopy.actualMinutes == 30, "the half hour was not banked against the finished task")
        #expect(live.hasChanges == false)
    }
}
#endif
