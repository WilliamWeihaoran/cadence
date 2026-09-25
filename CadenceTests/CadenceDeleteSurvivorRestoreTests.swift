import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-1336, extended by T-1376 and T-1377: a delete that also edits rows which **survive** it owes
/// those rows an undo, and the undo has to land before the rollback rather than after it.
///
/// **Three families, one construction.** [[T-1336]] is the task tree — the shared delete core, the
/// block delete and the rollover. [[T-1376]] is the tracking tree: `deleteGoal` severs a surviving
/// habit's and a surviving task's `goal` and empties a surviving parent's `subGoals`, and
/// `deleteHabit`'s two filing writes land on the doomed row but have a **surviving far end** —
/// `Goal.habits` and `Context.habits`. [[T-1377]] is the delete that makes no commit at all: a
/// cascade's refusal belongs to `commitCascade` two frames up, so the undo travels there in
/// `CadenceDeferredDeleteEffects` and is run before its `rollback()`.
///
/// **What is asserted strictly, and what is not.** The *contract* is fair game: the store is
/// unchanged by a refused delete, nothing is left pending, and the rows the user is looking at read
/// the values the store holds. The *reference visibility* underneath it — whether
/// `ModelContext.rollback()` alone would have refreshed an already-materialised reference — is
/// empirical, this repository builds on two Xcode majors that answer it differently ([[T-1279]],
/// [[T-1296]]), and nothing here pins either answer. The fix is written so that the answer does not
/// matter: `CadenceDeleteSurvivorSnapshot.restore()` runs inside `commitDelete`'s `commit:`, so a
/// toolchain that refreshes the reference refreshes it to the store's value and a toolchain that
/// leaves it at whatever was written last finds the original there.
///
/// That construction is also why `!modelContext.hasChanges` below is safe to assert on both: the
/// restore writes into a context that is already dirty, and the rollback settles it.
///
/// **The snapshot unit is tested directly, because behaviour through the helpers cannot see it on
/// the toolchain this was written on.** On Xcode 27 `rollback()` restores the references by itself,
/// so a helper-level assertion is green with or without the fix; the unit test below and the source
/// scan at the bottom are what actually go red when the fix is removed.
@MainActor
struct CadenceDeleteSurvivorRestoreTests {

    private struct CommitRefused: Error {}
    private let refuseTheCommit: (ModelContext) throws -> Void = { _ in throw CommitRefused() }

    private func makeContainer() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - The snapshot unit

    /// Capture, scribble over every field the delete helpers scribble over, restore, and find the
    /// row exactly as it was. No store, no commit, no rollback — this is the undo on its own.
    @Test func theSurvivorSnapshotPutsBackEveryFieldADeleteRewrites() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-09-24", startMin: 540, durationMinutes: 60)
        let task = AppTask(title: "Renew the domain")
        task.bundle = bundle
        task.bundleOrder = 3
        task.scheduledDate = "2026-09-24"
        task.scheduledStartMin = 555
        task.calendarEventID = "legacy-event"
        bundle.tasks = [task]
        modelContext.insert(bundle)
        modelContext.insert(task)
        try modelContext.save()

        var survivors = CadenceDeleteSurvivorSnapshot()
        survivors.captureSlot(of: task)
        survivors.captureMembership(of: bundle)
        #expect(!survivors.isEmpty)

        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = "2026-09-25"
        task.scheduledStartMin = -1
        task.calendarEventID = ""
        bundle.tasks = []

        survivors.restore()

        #expect(task.bundle?.id == bundle.id, "the block the row was unbundled from was not put back")
        #expect(task.bundleOrder == 3, "the row's place in the block was not put back")
        #expect(task.scheduledDate == "2026-09-24", "the day the row was parked on was not put back")
        #expect(task.scheduledStartMin == 555, "the minute the row started at was not put back")
        #expect(task.calendarEventID == "legacy-event", "the legacy calendar link was not put back")
        #expect((bundle.tasks ?? []).map(\.id) == [task.id], "the block's member list was not put back")
    }

    /// The other two kinds, which only `deleteTasks` writes: the containers a doomed row is filtered
    /// out of, and the recurrence pointer a surviving *predecessor* carries.
    @Test func theSurvivorSnapshotPutsBackContainerMembershipAndARecurrencePointer() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let goal = Goal(title: "Ship v2")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        task.goal = goal
        area.tasks = [task]
        goal.tasks = [task]
        let predecessor = AppTask(title: "Renew the domain (last month)")
        predecessor.recurrenceSpawnedTaskID = task.id
        for model in [area, goal, task, predecessor] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        var survivors = CadenceDeleteSurvivorSnapshot()
        survivors.captureContainers(of: task)
        survivors.captureRecurrencePointer(of: predecessor)

        area.tasks = []
        goal.tasks = []
        predecessor.recurrenceSpawnedTaskIDRaw = ""

        survivors.restore()

        #expect((area.tasks ?? []).map(\.id) == [task.id], "the area's list was not put back")
        #expect((goal.tasks ?? []).map(\.id) == [task.id], "the goal's contributing tasks were not put back")
        #expect(
            predecessor.recurrenceSpawnedTaskID == task.id,
            "the predecessor's pointer at its successor was not put back, so the series still reads as stalled"
        )
    }

    /// A field the delete never touched is never rewritten, which is what lets the restore run
    /// inside a commit that may yet land without making a no-op edit out of every capture.
    @Test func theSurvivorSnapshotLeavesAFieldNobodyChangedAlone() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Untouched")
        task.scheduledDate = "2026-09-24"
        modelContext.insert(task)
        try modelContext.save()

        var survivors = CadenceDeleteSurvivorSnapshot()
        survivors.captureSlot(of: task)
        survivors.restore()

        #expect(!modelContext.hasChanges, "restoring a row nothing changed left a pending edit")
        #expect(task.scheduledDate == "2026-09-24")
    }

    /// The tracking tree's four, added by [[T-1376]]: the goal a habit names, the goal a task
    /// contributes to, the context a habit is filed under, and a goal's place under its parent.
    @Test func theSurvivorSnapshotPutsBackTheTrackingTreesFilingAndItsNesting() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let direction = Goal(title: "Finish thesis", context: context)
        let milestone = Goal(title: "Chapter 1", context: context)
        milestone.parentGoal = direction
        direction.subGoals = [milestone]
        let habit = Habit(title: "Write daily", context: context, goal: direction)
        direction.habits = [habit]
        context.habits = [habit]
        let task = AppTask(title: "Draft")
        task.goal = milestone
        milestone.tasks = [task]
        for model in [context, direction, milestone, habit, task] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        var survivors = CadenceDeleteSurvivorSnapshot()
        survivors.captureGoalAssignment(of: habit)
        survivors.captureContextAssignment(of: habit)
        survivors.captureGoalAssignment(of: task)
        survivors.captureNesting(of: milestone)
        #expect(!survivors.isEmpty)

        // Everything `deleteGoal` and `deleteHabit` write, in one scribble.
        habit.goal = nil
        habit.context = nil
        task.goal = nil
        milestone.parentGoal = nil
        direction.habits = []
        direction.subGoals = []
        context.habits = []
        milestone.tasks = []

        survivors.restore()

        #expect(habit.goal?.id == direction.id, "the habit was not put back on the goal it tracks")
        #expect(habit.context?.id == context.id, "the habit was not put back in its context")
        #expect(task.goal?.id == milestone.id, "the task was not put back on the milestone it contributes to")
        #expect(milestone.parentGoal?.id == direction.id, "the milestone was promoted to a direction nobody created")
        #expect((direction.habits ?? []).map(\.id) == [habit.id], "the goal's habit list was not put back")
        #expect((direction.subGoals ?? []).map(\.id) == [milestone.id], "the direction's milestone list was not put back")
        #expect((context.habits ?? []).map(\.id) == [habit.id], "the context's habit list was not put back")
        #expect((milestone.tasks ?? []).map(\.id) == [task.id], "the milestone's contributing tasks were not put back")
    }

    /// The other half of [[T-1377]], on its own: a queue that holds undos runs them once, in the
    /// order they were captured, and forgets them.
    ///
    /// Toolchain-free, and the only place the refusal bucket can be watched without a store that
    /// refuses a save.
    @Test func theDeferredQueueRunsEveryUndoOnceInCaptureOrder() {
        let effects = CadenceDeferredDeleteEffects()
        let order = Trace()
        effects.holdUndo { order.append("first") }
        effects.holdUndo { order.append("second") }
        #expect(effects.heldUndoCount == 2)

        effects.undo()
        effects.undo()

        #expect(order.value == ["first", "second"], "the undos ran out of order, or more than once")
        #expect(effects.heldUndoCount == 0, "the queue still holds an undo it has already run")
    }

    /// And the two buckets are independent: releasing the success half does not run an undo, and
    /// running the undo half does not release a success-only effect.
    @Test func theTwoBucketsOfTheDeferredQueueDoNotRunEachOther() {
        let releaseOnly = CadenceDeferredDeleteEffects()
        let ran = Trace()
        releaseOnly.hold(taskIDs: [], habitIDs: []) { ran.append("effect") }
        releaseOnly.holdUndo { ran.append("undo") }

        releaseOnly.release()
        #expect(ran.value == ["effect"], "releasing a landed commit also ran the undo for a refusal")
        #expect(releaseOnly.heldUndoCount == 1, "release() drained the refusal bucket")

        let undoOnly = CadenceDeferredDeleteEffects()
        let other = Trace()
        let taskID = UUID()
        undoOnly.hold(taskIDs: [taskID], habitIDs: []) { other.append("effect") }
        undoOnly.holdUndo { other.append("undo") }

        undoOnly.undo()
        #expect(other.value == ["undo"], "undoing a refusal also ran a success-only effect")
        #expect(
            undoOnly.pendingTaskIDs == [taskID],
            "undo() drained the success bucket, so a commit that lands afterwards would cancel nothing"
        )
        #expect(undoOnly.releasedTaskIDs.isEmpty, "undo() released a success-only effect")
    }

    // MARK: - Through the helpers

    /// A refused block delete leaves the block, its members, and the members' slots exactly as the
    /// user left them — in the store and on the rows the screen is holding.
    @Test func arefusedBlockDeleteLeavesItsMembersStillBundledAndStillScheduled() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-09-24", startMin: 540, durationMinutes: 90)
        let first = AppTask(title: "Renew the domain")
        first.bundle = bundle
        first.bundleOrder = 0
        first.scheduledDate = "2026-09-24"
        first.scheduledStartMin = 540
        let second = AppTask(title: "Write the release notes")
        second.bundle = bundle
        second.bundleOrder = 1
        second.scheduledDate = "2026-09-24"
        second.scheduledStartMin = 570
        bundle.tasks = [first, second]
        for model in [bundle, first, second] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadenceTaskMutationSupport.deleteBundle(
                bundle,
                modelContext: modelContext,
                commit: refuseTheCommit
            )
        }

        #expect(!modelContext.hasChanges, "the refused block delete was left pending in the context")

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<TaskBundle>()).map(\.title) == ["Morning block"])
        let stored = try store.fetch(FetchDescriptor<AppTask>()).sorted { $0.bundleOrder < $1.bundleOrder }
        #expect(stored.map(\.scheduledStartMin) == [540, 570], "the store lost the members' start minutes")
        #expect(stored.allSatisfy { $0.bundle != nil }, "the store unbundled the members over a delete that was refused")

        // The rows the timeline is holding, read back without a refetch. This is the reading the
        // notice "Nothing was removed." is making a promise about.
        #expect(first.bundle?.id == bundle.id, "a refused block delete left the first row unbundled on screen")
        #expect(second.bundle?.id == bundle.id, "a refused block delete left the second row unbundled on screen")
        #expect(first.scheduledStartMin == 540, "a refused block delete cleared the first row's start minute")
        #expect(second.scheduledStartMin == 570, "a refused block delete cleared the second row's start minute")
        #expect((bundle.tasks ?? []).count == 2, "a refused block delete emptied the block on screen")
    }

    /// The same for the rollover, whose delete is two frames down: the block it may dispose of is
    /// the existence change, and every task it moves is a survivor.
    @Test func arefusedRolloverLeavesYesterdaysPlansOnYesterday() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let bundle = TaskBundle(title: "Yesterday's block", dateKey: "2026-09-24", startMin: 540, durationMinutes: 60)
        let rolling = AppTask(title: "Renew the domain")
        rolling.bundle = bundle
        rolling.bundleOrder = 0
        rolling.scheduledDate = "2026-09-24"
        rolling.scheduledStartMin = 540
        bundle.tasks = [rolling]
        for model in [bundle, rolling] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            _ = try CadenceTodayRolloverSupport.rollOver(
                [rolling],
                todayKey: "2026-09-25",
                modelContext: modelContext,
                commit: refuseTheCommit
            )
        }

        #expect(!modelContext.hasChanges, "the refused roll was left pending in the context")

        let store = ModelContext(container)
        let stored = try #require(try store.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.scheduledDate == "2026-09-24", "the store took a roll that was refused")
        #expect(try store.fetch(FetchDescriptor<TaskBundle>()).count == 1)

        #expect(
            rolling.scheduledDate == "2026-09-24",
            "a refused roll moved the row onto today anyway, under a banner that says nothing changed"
        )
        #expect(rolling.scheduledStartMin == 540, "a refused roll cleared the row's start minute")
        #expect(rolling.bundle?.id == bundle.id, "a refused roll unbundled the row")
    }

    /// And for the task delete: the containers a row is filtered out of are the lists, boards and
    /// chips the user is looking at while the alert is up.
    @Test func arefusedTaskDeleteLeavesItsContainersAndItsSeriesIntact() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let goal = Goal(title: "Ship v2")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        task.goal = goal
        area.tasks = [task]
        goal.tasks = [task]
        let predecessor = AppTask(title: "Renew the domain (last month)")
        predecessor.recurrenceSpawnedTaskID = task.id
        for model in [area, goal, task, predecessor] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(
            CadenceTaskMutationSupport.delete(task, modelContext: modelContext, commit: refuseTheCommit) == false,
            "a delete whose commit was refused reported success"
        )

        #expect(!modelContext.hasChanges, "the refused delete was left pending in the context")

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 2)

        #expect((area.tasks ?? []).map(\.id) == [task.id], "a refused delete emptied the area's list on screen")
        #expect((goal.tasks ?? []).map(\.id) == [task.id], "a refused delete emptied the goal's contributions on screen")
        #expect(
            predecessor.recurrenceSpawnedTaskID == task.id,
            "a refused delete stalled the series it was repairing links for"
        )
    }

    /// [[T-1376]]: a refused goal delete leaves the direction it was filed under still holding it,
    /// and leaves the habits and tasks it organised still naming it — on the rows the Goals page is
    /// holding while the alert is up.
    @Test func arefusedGoalDeleteLeavesItsMilestoneNestedAndItsWorkStillAssigned() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let direction = Goal(title: "Finish thesis", context: context)
        let milestone = Goal(title: "Chapter 1", context: context)
        milestone.parentGoal = direction
        direction.subGoals = [milestone]
        let habit = Habit(title: "Write daily", context: context, goal: milestone)
        milestone.habits = [habit]
        let task = AppTask(title: "Draft")
        task.goal = milestone
        milestone.tasks = [task]
        for model in [context, direction, milestone, habit, task] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try modelContext.deleteGoal(milestone, commit: refuseTheCommit)
        }

        #expect(!modelContext.hasChanges, "the refused goal delete was left pending in the context")

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Goal>()).count == 2)
        #expect(try store.fetch(FetchDescriptor<Habit>()).first?.goal?.id == milestone.id)

        // The rows the two Goals pages are drawing, read back without a refetch.
        #expect(
            (direction.subGoals ?? []).map(\.id) == [milestone.id],
            "a refused goal delete took the milestone out of the direction it is drawn under"
        )
        #expect(milestone.parentGoal?.id == direction.id, "a refused goal delete promoted the milestone")
        #expect(habit.goal?.id == milestone.id, "a refused goal delete unlinked a habit it did not remove")
        #expect(task.goal?.id == milestone.id, "a refused goal delete severed a task it did not remove")
        #expect((milestone.habits ?? []).map(\.id) == [habit.id], "the goal came back with no habits")
        #expect((milestone.tasks ?? []).map(\.id) == [task.id], "the goal came back with no contributions")
    }

    /// The habit half, which the ticket expected to need nothing: the write lands on the doomed
    /// row, but the **far** end of it is a surviving goal and a surviving context, and
    /// `Goal.habits` / `Context.habits` are what those two pages count.
    @Test func arefusedHabitDeleteLeavesItInItsGoalsAndItsContextsLists() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Health")
        let goal = Goal(title: "Get healthy", context: context)
        let habit = Habit(title: "Run", context: context, goal: goal)
        goal.habits = [habit]
        context.habits = [habit]
        for model in [context, goal, habit] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try modelContext.deleteHabit(habit, commit: refuseTheCommit)
        }

        #expect(!modelContext.hasChanges, "the refused habit delete was left pending in the context")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Habit>()).map(\.title) == ["Run"])

        #expect(
            (goal.habits ?? []).map(\.id) == [habit.id],
            "a refused habit delete emptied the goal's habit list on screen"
        )
        #expect(
            (context.habits ?? []).map(\.id) == [habit.id],
            "a refused habit delete emptied the context's habit list on screen"
        )
        #expect(habit.goal?.id == goal.id, "the habit came back unlinked from the goal it tracks")
        #expect(habit.context?.id == context.id, "the habit came back with no context")
    }

    // MARK: - The deferred half, whose refusal is two frames up

    /// [[T-1377]]: a list cascade makes no commit of its own, so the undo for what it wrote on rows
    /// it is not removing has to travel to `commitCascade` — and run before its `rollback()`.
    ///
    /// The survivors of a cascade are the **free** relationships, because deleting an area takes
    /// its containers with it: a goal in another context, and a recurrence predecessor in another
    /// list.
    @Test func arefusedListCascadeLeavesAfreeGoalAndAseriesIntact() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let goal = Goal(title: "Ship v2")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        task.goal = goal
        area.tasks = [task]
        goal.tasks = [task]
        let predecessor = AppTask(title: "Renew the domain (last month)")
        predecessor.recurrenceSpawnedTaskID = task.id
        for model in [area, goal, task, predecessor] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        let effects = CadenceDeferredDeleteEffects()
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: modelContext,
                commit: refuseTheCommit,
                effects: effects,
                cascade: { modelContext.deleteArea(area) }
            )
        }

        #expect(!modelContext.hasChanges, "the refused cascade was left pending in the context")
        #expect(effects.heldUndoCount == 0, "the cascade's undo never ran")

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 2)
        #expect(try store.fetch(FetchDescriptor<Goal>()).count == 1)

        #expect(
            (goal.tasks ?? []).map(\.id) == [task.id],
            "a refused list delete emptied a goal in another context on screen"
        )
        #expect(task.goal?.id == goal.id, "a refused list delete severed the task from its goal")
        #expect(
            predecessor.recurrenceSpawnedTaskID == task.id,
            "a refused list delete stalled a series whose predecessor it never touched"
        )
    }

    /// The same for the goals a **context** cascade severs by hand rather than through the task
    /// sweep — a task or a habit filed elsewhere that names a goal in the doomed context.
    @Test func arefusedContextCascadeLeavesWorkFiledElsewhereStillNamingItsGoal() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let doomed = Context(name: "Work")
        let elsewhere = Context(name: "Life")
        let goal = Goal(title: "Ship v2", context: doomed)
        doomed.goals = [goal]
        let task = AppTask(title: "Renew the domain")
        task.context = elsewhere
        task.goal = goal
        let habit = Habit(title: "Stand up", context: elsewhere, goal: goal)
        goal.tasks = [task]
        goal.habits = [habit]
        for model in [doomed, elsewhere, goal, task, habit] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: modelContext,
                commit: refuseTheCommit,
                cascade: { modelContext.deleteContext(doomed) }
            )
        }

        #expect(!modelContext.hasChanges, "the refused context cascade was left pending")
        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Context>()).count == 2)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 1)

        #expect(
            task.goal?.id == goal.id,
            "a refused context delete severed a task filed in another context from its goal"
        )
        #expect(
            habit.goal?.id == goal.id,
            "a refused context delete severed a habit filed in another context from its goal"
        )
        #expect((goal.tasks ?? []).map(\.id) == [task.id], "the goal came back with no contributions")
        #expect((goal.habits ?? []).map(\.id) == [habit.id], "the goal came back with no habits")
    }

    /// Non-vacuity for both cascade tests: a commit that lands still removes everything, so the
    /// deferred undo is an undo rather than a suppression.
    @Test func acommittedListCascadeStillRemovesTheListAndItsTasks() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let goal = Goal(title: "Ship v2")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        task.goal = goal
        area.tasks = [task]
        goal.tasks = [task]
        for model in [area, goal, task] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        try CadencePendingChangePersistence.commitCascade(in: modelContext) {
            modelContext.deleteArea(area)
        }

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Goal>()).count == 1, "the cascade took a goal it was not aimed at")
    }
    // MARK: - The source rule

    /// Behaviour cannot hold this on the toolchain it was written on.
    ///
    /// On Xcode 27 `ModelContext.rollback()` restores an already-materialised reference by itself,
    /// so every assertion above stays green with the survivor undo deleted — and goes on staying
    /// green right up until somebody builds on Xcode 26, which is what CI does. So the composition
    /// itself is pinned: each of the three helpers commits its delete through `commitDelete`, and
    /// hands `commitDelete` a `commit:` that is a `commitEdit` carrying the survivor undo. A site
    /// reverted to a bare `commitDelete` fails here by name.
    @Test func everyDeleteThatEditsASurvivorCommitsThroughTheSurvivorUndo() throws {
        let sites: [(path: String, function: String)] = [
            ("Cadence/Shared/CadenceTaskMutationSupport.swift", "deleteTasks"),
            ("Cadence/Shared/CadenceTaskMutationSupport.swift", "deleteBundle"),
            ("Cadence/Shared/CadenceTodayRolloverSupport.swift", "rollOver"),
            ("Cadence/Shared/TrackingDeleteHelpers.swift", "deleteGoal"),
            ("Cadence/Shared/TrackingDeleteHelpers.swift", "deleteHabit")
        ]

        for site in sites {
            let raw = try CadenceSourceScan.sourceFile(site.path)
            #expect(raw.count > 400, "\(site.path) read as \(raw.count) characters")
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "the comment stripper removed nothing from \(site.path)")

            let body = try #require(
                CadenceSourceScan.functionBody(named: site.function, in: stripped),
                "could not read the body of \(site.function) in \(site.path)"
            )
            #expect(
                body.contains("CadenceDeleteSurvivorSnapshot()"),
                "\(site.function) no longer captures what it writes on rows that survive it (T-1336)"
            )
            #expect(
                body.contains("undo: survivors.restore"),
                "\(site.function) commits without the survivor undo, so a refused delete can leave a surviving row reading as severed (T-1336)"
            )
            #expect(
                CadenceSourceScan.matchCount(#"commitEdit\(in: \$0, commit: commit, undo: survivors\.restore\)"#, in: body) >= 1,
                "\(site.function) no longer nests the survivor undo inside commitDelete's commit, so the restore lands after the rollback instead of before it (T-1336)"
            )
        }
    }

    /// The deferred sites, which have no commit of their own to nest anything inside.
    ///
    /// The same argument, one frame up ([[T-1377]]): the undo is captured before the first write
    /// and handed to the ambient queue, and `commitCascade` is what runs it. Behaviour cannot hold
    /// this either — on Xcode 27 `rollback()` restores the references by itself — and it has a
    /// second blind spot behaviour cannot see at all: whether the undo runs **before** the
    /// rollback or after it, which is the whole of the construction.
    @Test func everyCascadeThatEditsASurvivorHandsItsUndoToTheCommitThatOwnsIt() throws {
        let deferring: [(path: String, function: String)] = [
            ("Cadence/Shared/CadenceTaskMutationSupport.swift", "deleteTasks"),
            ("Cadence/Services/CadenceListDeleteHelpers.swift", "deleteContext")
        ]

        for site in deferring {
            let raw = try CadenceSourceScan.sourceFile(site.path)
            #expect(raw.count > 400, "\(site.path) read as \(raw.count) characters")
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "the comment stripper removed nothing from \(site.path)")

            let body = try #require(
                CadenceSourceScan.functionBody(named: site.function, in: stripped),
                "could not read the body of \(site.function) in \(site.path)"
            )
            #expect(
                body.contains("CadenceDeleteSurvivorSnapshot()"),
                "\(site.function) no longer captures what it writes on rows that survive it (T-1377)"
            )
            #expect(
                body.contains("CadenceDeferredDeleteEffects.current?.holdUndo(survivors.restore)"),
                "\(site.function) no longer hands its survivor undo to the commit that owns it (T-1377)"
            )
        }

        // And the scope that runs them, where the order is decided.
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadencePendingChangePersistence.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing from the persistence spine")
        let cascade = try #require(
            CadenceSourceScan.functionBody(named: "commitCascade", in: stripped),
            "commitCascade is no longer a function"
        )
        let undoThenRollback = #"effects\.undo\(\)\s*modelContext\.rollback\(\)"#
        #expect(
            CadenceSourceScan.matchCount(undoThenRollback, in: cascade) == 1,
            "a cascade that could not finish rolls back before it puts back what it wrote on the rows it was not deleting (T-1377)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"commitEdit\(in: \$0, commit: commit, undo: effects\.undo\)"#, in: cascade) == 1,
            "commitCascade commits without the deferred survivor undo, so a refused list delete leaves a surviving row reading as severed (T-1377)"
        )
        // Non-vacuity for the ordering needle, against the inversion it exists to reject.
        #expect(
            CadenceSourceScan.matchCount(
                undoThenRollback,
                in: "modelContext.rollback()\n                effects.undo()"
            ) == 0,
            "the ordering needle passes on a cascade that restores after the rollback"
        )
    }
}

/// An ordered, append-only record, because the queue's buckets are plain closures and a captured
/// `var` in a `@Test` body is not `Sendable`.
private final class Trace: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var value: [String] { lock.withLock { entries } }

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }
}
