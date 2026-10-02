#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The commit the Calendar Board's Unscheduled rail makes, counted, and refusable on demand.
///
/// `TasksListDropCommitRateTests` has the same seam for the same reason one surface over
/// ([[T-1580]]): an in-memory container cannot be made to refuse a `save()`, so every reading would
/// come out the same whether the path commits once, twice or never, and the `.refused` branch would
/// be unreachable from any test. `commit:` is the seam, and the refusing and taking configurations
/// below are this file's pair — no assertion here is worth anything unless the two readings differ.
private final class CountingRailDropCommit {
    /// What the store answers. `true` is the refusal that cannot be provoked any other way.
    var refuses = false

    private(set) var commitCount = 0

    struct Refused: Error {}

    func commit(_ modelContext: ModelContext) throws {
        commitCount += 1
        if refuses { throw Refused() }
        try modelContext.save()
    }
}

/// **T-1952.** `CalendarPageBoardSupportViews.unschedule` ended `try? modelContext.save()` and then
/// `return true`, and that `true` is what `.dropDestination` reads to decide whether the dragged
/// card stays on the Unscheduled rail. A drop the store refused was accepted, drawn where it was
/// released and reverted at the next launch with nothing to retry — the sibling of the All Tasks
/// drop T-1580 fixed, listed beside it under one T-636(b) comment in
/// `CadenceSaveCommitRule.reportExemptions`.
///
/// **It was the harder half, and this suite is where that shows.** T-1580's `assignTask` writes
/// nothing but task fields; this drop changes *existence* one frame earlier, because a card dragged
/// off a block runs `SchedulingActions.removeTaskFromBundle` — which empties the task out of
/// `TaskBundle.tasks`, nils its `bundle` and renumbers every remaining member through
/// `normalizeBundleOrder`. Answering `.refused` over T-1580's undo as it stood would have left the
/// card out of a block it was still being drawn in while saying "Nothing was changed", so
/// `CadenceTaskFieldSnapshot` carries `bundle`/`bundleOrder` now and the block's other members ride
/// in `alsoRestoring:`. The test that would stay green over the defect is "the drop moves the
/// card"; the discriminating case is the one the store **refuses**.
@MainActor
struct CalendarBoardUnscheduleCommitTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    /// A block on 2026-06-01 holding three members in a known order, plus a second block holding
    /// one, which is the control the one-candidate trap asks for: nothing about this drop may touch
    /// a block the card was never in.
    private struct BoardFixture {
        let modelContext: ModelContext
        let dragged: AppTask
        let siblings: [AppTask]
        let block: TaskBundle
        let bystander: AppTask
        let otherBlock: TaskBundle
        var allTasks: [AppTask] { [dragged] + siblings + [bystander] }
    }

    private func fixture(in modelContainer: ModelContainer) throws -> BoardFixture {
        let modelContext = ModelContext(modelContainer)
        let block = TaskBundle(title: "Morning block", dateKey: "2026-06-01", startMin: 600, durationMinutes: 30)
        let otherBlock = TaskBundle(title: "Evening block", dateKey: "2026-06-02", startMin: 1_200, durationMinutes: 30)
        modelContext.insert(block)
        modelContext.insert(otherBlock)

        let dragged = AppTask(title: "Dragged to the backlog")
        let firstSibling = AppTask(title: "Stays in the block")
        let secondSibling = AppTask(title: "Also stays in the block")
        let bystander = AppTask(title: "In the other block entirely")
        for task in [dragged, firstSibling, secondSibling, bystander] {
            modelContext.insert(task)
        }
        SchedulingActions.addTask(dragged, to: block)
        SchedulingActions.addTask(firstSibling, to: block)
        SchedulingActions.addTask(secondSibling, to: block)
        SchedulingActions.addTask(bystander, to: otherBlock)
        dragged.scheduledStartMin = 600
        try modelContext.save()

        // The fixture is only a fixture if it starts where the assertions below say it does.
        #expect(dragged.bundleOrder == 0)
        #expect(firstSibling.bundleOrder == 1)
        #expect(secondSibling.bundleOrder == 2)

        return BoardFixture(
            modelContext: modelContext,
            dragged: dragged,
            siblings: [firstSibling, secondSibling],
            block: block,
            bystander: bystander,
            otherBlock: otherBlock
        )
    }

    private func payload(for task: AppTask) -> [String] {
        [TaskDragPayload.string(for: task.id)]
    }

    // MARK: - The refusal, against its own control

    /// The whole ticket in one test, and it needs both readings: a refused drop and a taken drop
    /// over **identical** fixtures, each the other's control. A suite that only asserted the taken
    /// one passes with `try? save(); return true` still in the file.
    @Test func aboardUnscheduleRefusedByTheStoreKeepsTheCardOnItsDayAndInItsBlock() throws {
        let modelContainer = try container()

        let refusing = try fixture(in: modelContainer)
        let refusingCommit = CountingRailDropCommit()
        refusingCommit.refuses = true
        let refusedOutcome = CalendarPageBoardDropSupport.unschedule(
            payload(for: refusing.dragged),
            in: refusing.allTasks,
            modelContext: refusing.modelContext,
            reconciler: .inert,
            commit: refusingCommit.commit
        )

        #expect(refusedOutcome == .refused)
        #expect(refusingCommit.commitCount == 1, "the drop resolved, so it must have been offered")
        #expect(refusing.dragged.scheduledDate == "2026-06-01", "the do date came back")
        #expect(refusing.dragged.scheduledStartMin == 600, "and so did the timeline slot")
        #expect(refusing.dragged.bundle?.id == refusing.block.id, "and so did the block membership")
        #expect(refusing.dragged.bundleOrder == 0)
        #expect(
            refusing.block.sortedTasks.count == 3,
            "the block still holds all three, so the card is drawn where the notice says it is"
        )
        #expect(
            refusing.siblings.map(\.bundleOrder) == [1, 2],
            "the detach renumbered the members that stayed; the undo put the numbering back"
        )
        #expect(refusing.bystander.bundle?.id == refusing.otherBlock.id)
        #expect(refusing.bystander.bundleOrder == 0, "a block this drop never touched is untouched")

        let taking = try fixture(in: modelContainer)
        let takingCommit = CountingRailDropCommit()
        let appliedOutcome = CalendarPageBoardDropSupport.unschedule(
            payload(for: taking.dragged),
            in: taking.allTasks,
            modelContext: taking.modelContext,
            reconciler: .inert,
            commit: takingCommit.commit
        )

        #expect(appliedOutcome == .applied)
        #expect(takingCommit.commitCount == 1)
        #expect(taking.dragged.scheduledDate == "")
        #expect(taking.dragged.scheduledStartMin == -1)
        #expect(taking.dragged.bundle == nil)
        #expect(taking.block.sortedTasks.count == 2)

        // The same number of commits over identical fixtures, and the two stores do not agree —
        // which is the shape a count assertion needs to be worth anything.
        #expect(refusingCommit.commitCount == takingCommit.commitCount)
        #expect(
            refusing.dragged.scheduledDate != taking.dragged.scheduledDate,
            "a refused drop and a taken drop that read the same prove nothing"
        )
        #expect((refusing.dragged.bundle == nil) != (taking.dragged.bundle == nil))
    }

    /// The reading the user's next launch makes, taken from a **second `ModelContext` on the same
    /// container**: a live object answers whatever was last assigned to it, so only the store can
    /// say whether a refused drop left anything behind.
    @Test func therefusedBoardUnscheduleIsInvisibleToASecondContext() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)
        let refusingCommit = CountingRailDropCommit()
        refusingCommit.refuses = true

        let outcome = CalendarPageBoardDropSupport.unschedule(
            payload(for: board.dragged),
            in: board.allTasks,
            modelContext: board.modelContext,
            reconciler: .inert,
            commit: refusingCommit.commit
        )
        #expect(outcome == .refused)

        let draggedID = board.dragged.id
        let stored = ModelContext(modelContainer)
        let storedTask = try #require(
            try stored.fetch(FetchDescriptor<AppTask>()).first { $0.id == draggedID }
        )
        #expect(storedTask.scheduledDate == "2026-06-01", "the store never took the clear")
        #expect(storedTask.scheduledStartMin == 600)
        #expect(storedTask.bundle != nil, "nor the detach")

        let storedBlocks = try stored.fetch(FetchDescriptor<TaskBundle>())
        let storedBlock = try #require(storedBlocks.first { $0.dateKey == "2026-06-01" })
        #expect(storedBlock.sortedTasks.count == 3)
        #expect(storedBlock.sortedTasks.map(\.bundleOrder) == [0, 1, 2])
    }

    // MARK: - The resolution happens before anything is written

    /// A payload this board cannot place must never reach `commit`, because the app has one
    /// `ModelContext` and committing over a drop that moved nothing commits whatever unrelated
    /// pending work it happens to be holding. The two readings are asserted to **differ**, so a
    /// path that simply never commits cannot pass this.
    @Test func aboardUnscheduleThatNamesNoTaskNeverReachesTheCommit() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)

        // A real task, dragged from a surface this board is not holding: the payload parses, and
        // the lookup is what fails. `"not-a-payload"` is the other half — the parse failing.
        let strangerID = UUID()
        let unresolvable = CountingRailDropCommit()
        #expect(
            CalendarPageBoardDropSupport.unschedule(
                [TaskDragPayload.string(for: strangerID)],
                in: board.allTasks,
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: unresolvable.commit
            ) == .resolvedNothing
        )
        #expect(
            CalendarPageBoardDropSupport.unschedule(
                ["not-a-payload"],
                in: board.allTasks,
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: unresolvable.commit
            ) == .resolvedNothing
        )
        #expect(
            CalendarPageBoardDropSupport.unschedule(
                [],
                in: board.allTasks,
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: unresolvable.commit
            ) == .resolvedNothing
        )
        #expect(unresolvable.commitCount == 0)

        let resolvable = CountingRailDropCommit()
        #expect(
            CalendarPageBoardDropSupport.unschedule(
                payload(for: board.dragged),
                in: board.allTasks,
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: resolvable.commit
            ) == .applied
        )
        #expect(resolvable.commitCount == 1)
        #expect(
            unresolvable.commitCount != resolvable.commitCount,
            "three unplaceable drops and one placeable one must not commit the same number of times"
        )
    }

    /// One drop is one commit, and six drops are six: the detach and the date clear are one unit of
    /// work, not two. The shipping defect's second half one surface over ([[T-1580]]) was exactly a
    /// gesture that committed twice with no undo between the halves.
    @Test func oneboardUnscheduleIsOneCommitAndSixAreSix() throws {
        let modelContainer = try container()
        let counter = CountingRailDropCommit()

        for _ in 0..<6 {
            let board = try fixture(in: modelContainer)
            #expect(
                CalendarPageBoardDropSupport.unschedule(
                    payload(for: board.dragged),
                    in: board.allTasks,
                    modelContext: board.modelContext,
                    reconciler: .inert,
                    commit: counter.commit
                ) == .applied
            )
        }

        #expect(counter.commitCount == 6)
    }

    // MARK: - What the surface does with the three answers

    /// The commit is only half of it: this board drew **no** failure notice at all before T-1952,
    /// which is why the ticket was a surface decision on top of a commit rather than the commit
    /// alone. A `.refused` nobody can see is the same silence the `true` was.
    @Test func theCalendarBoardNamesARefusedRailDropOnScreen() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        )

        // Two declarations, deliberately named apart: `unschedule` is the unit that commits, and
        // `handleUnscheduleDrop` is the view's mapping of its three answers onto the one `Bool`
        // `.dropDestination` reads. `declarationBody(named:)` asserts there is exactly one of each,
        // so a second copy of either cannot hide behind the name.
        let unschedule = try CadenceCommitSurfaceScan.declarationBody(named: "unschedule", in: source)
        #expect(
            !unschedule.contains("try? "),
            "the swallowed commit is back in the unit that commits"
        )
        #expect(
            unschedule.contains("CadenceTaskFieldEditCommit.commit("),
            "and the one commit is still the undoing one"
        )
        #expect(
            unschedule.contains("alsoRestoring: blockSiblings"),
            "with the block members the detach renumbers snapshotted alongside the card"
        )

        let handler = try CadenceCommitSurfaceScan.declarationBody(
            named: "handleUnscheduleDrop",
            in: source
        )
        #expect(
            !handler.contains("try? modelContext.save()"),
            "the swallowed commit is back in the drop handler"
        )
        #expect(
            handler.contains(
                "dropFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil"
            ),
            "the view maps .refused onto the board's notice slot"
        )
        #expect(
            handler.contains("return outcome == .applied"),
            "and only .applied is reported to .dropDestination as an accepted drop"
        )
        #expect(
            source.contains("CadenceInlineFailureNotice(text: dropFailureNotice)"),
            "the board draws the slot it now fills"
        )
        // `.resolvedNothing` says nothing, which is T-591's refusal: a header whose task this board
        // is not holding is the user's aim, not a failure. So there is exactly one assignment to
        // the notice and it is the ternary above.
        #expect(CadenceSourceScan.matchCount(#"dropFailureNotice = "#, in: source) == 1)
    }

    /// The exemption left by being fixed, not by being edited — which is what
    /// `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` makes the only safe way out.
    /// Asserted here as well because that test can only fail on a *stale* entry: a widened one, or
    /// a new entry added under cover of this file's name, would pass it.
    @Test func thesaveDisciplineSweepNoLongerExemptsTheCalendarBoard() throws {
        let path = "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        #expect(CadenceSaveCommitRule.reportExemptions[path] == nil)
        #expect(CadenceSaveCommitRule.indirectReportExemptions[path] == nil)
        #expect(CadenceSaveCommitRule.existenceExemptions[path] == nil)
        #expect(CadenceSaveCommitRule.commitReachExemptions[path] == nil)

        // Non-vacuity: the table is read from the same type the sweep reads, and it is not empty of
        // everything — the existence list still has entries, so a lookup that always answered `nil`
        // could not pass this.
        #expect(!CadenceSaveCommitRule.existenceExemptions.isEmpty)
    }
}
#endif
