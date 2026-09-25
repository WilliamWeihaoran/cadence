import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-1336: a delete that also edits rows which **survive** it owes those rows an undo, and the
/// undo has to land before the rollback rather than after it.
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
            ("Cadence/Shared/CadenceTodayRolloverSupport.swift", "rollOver")
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
}
