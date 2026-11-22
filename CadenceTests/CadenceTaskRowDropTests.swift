import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-19100]]: on iPhone and iPad a task row dropped onto another row of Today, All Tasks or Inbox
/// does what the Mac's does -- files the row into the target's group, then renumbers it in front of
/// the target -- through `CadenceTaskRowDrop.drop`, which is the Mac's
/// `TasksPanelDropCoordinator.handleTaskDrop` with the touch pages' lookups. Driven against an
/// in-memory store and read back through a second context; the touch drag itself is a system drop
/// and is a sighting ([[T-19101]]).
@MainActor
struct CadenceTaskRowDropTests {
    private let todayKey = "2026-11-22"

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let home: Project
        let work: Project
    }

    private func fixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let home = Project(name: "Home")
        let work = Project(name: "Work")
        context.insert(home)
        context.insert(work)
        return Fixture(container: container, context: context, home: home, work: work)
    }

    private func row(_ title: String, _ order: Int, _ project: Project, in context: ModelContext) -> AppTask {
        let task = AppTask(title: title)
        task.order = order
        task.project = project
        context.insert(task)
        return task
    }

    private func drop(
        _ dragged: AppTask,
        onto target: AppTask,
        scope: [AppTask],
        dropKey: String?,
        page: [AppTask],
        context: ModelContext,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> ListTasksGroupDrop.HeaderDropOutcome {
        CadenceTaskRowDrop.drop(
            payload: TaskDragPayload.string(for: dragged.id),
            onto: target,
            scopeTasks: scope,
            dropKey: dropKey,
            among: page,
            todayKey: todayKey,
            modelContext: context,
            sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: .custom, direction: .ascending) },
            reconciler: .inert,
            commit: commit
        )
    }

    /// The store's rows of `project`, by `order`, read through a fresh context.
    private func storedOrder(of project: Project, in container: ModelContainer) throws -> [(title: String, order: Int)] {
        try ModelContext(container).fetch(FetchDescriptor<AppTask>())
            .filter { $0.project?.id == project.id }
            .sorted { $0.order < $1.order }
            .map { ($0.title, $0.order) }
    }

    /// **Today: a row from another list, let go over a row of a list group, joins that list on
    /// today and lands in front of the row.** The key is the group's own `list:p_<uuid>|date:today`.
    @Test func aTodayRowDropFilesIntoTheTargetListOnTodayAndLandsInFrontOfTheRow() throws {
        let f = try fixture()
        let moved = row("Moved", 0, f.home, in: f.context)
        let workA = row("Work A", 0, f.work, in: f.context)
        let workB = row("Work B", 1, f.work, in: f.context)
        let workC = row("Work C", 2, f.work, in: f.context)
        try f.context.save()
        let workGroup = [workA, workB, workC]
        let dropKey = try #require(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: "p_\(f.work.id.uuidString)", name: "Work"))
        )

        let outcome = drop(moved, onto: workB, scope: workGroup, dropKey: dropKey, page: [moved] + workGroup, context: f.context)

        #expect(outcome == .applied(notice: nil))
        let stored = try #require(try ModelContext(f.container).fetch(FetchDescriptor<AppTask>()).first { $0.id == moved.id })
        #expect(stored.project?.id == f.work.id, "the drop did not file the row into the target's list")
        #expect(stored.scheduledDate == todayKey, "the drop did not keep the row on today")
        #expect(try storedOrder(of: f.work, in: f.container).map(\.title) == ["Work A", "Moved", "Work B", "Work C"])
    }

    /// **All Tasks / Inbox By Priority: the row takes the target group's priority and lands in front
    /// of the row.** And the renumber spans the whole list, not the page ([[T-1175]]): a finished
    /// row the page does not hold keeps an `order` no open row shares.
    @Test func anAllTasksRowDropTakesTheGroupsKeyAndRenumbersOverTheWholeList() throws {
        let f = try fixture()
        let workA = row("Work A", 0, f.work, in: f.context)
        let done = row("Done", 1, f.work, in: f.context)
        done.status = .done
        let workB = row("Work B", 2, f.work, in: f.context)
        let moved = row("Moved", 3, f.work, in: f.context)
        workA.priority = .high
        workB.priority = .high
        moved.priority = .low
        try f.context.save()
        let open = [workA, workB, moved]
        let high = try #require(
            CadenceTaskQuerySupport.displayGroups(from: open, mode: .byPriority, todayKey: todayKey, contexts: [])
                .first { $0.id == "priority-high" }
        )

        let outcome = drop(
            moved,
            onto: workB,
            scope: high.tasks,
            dropKey: CadenceTaskHeaderDrop.dropKey(forDisplayGroup: high),
            page: open,
            context: f.context
        )

        #expect(outcome == .applied(notice: nil))
        #expect(moved.priority == .high, "the drop did not file the row into the High group")
        let stored = try storedOrder(of: f.work, in: f.container)
        let titles = stored.map(\.title).filter { $0 != "Done" }
        #expect(titles == ["Work A", "Moved", "Work B"], "the row did not land in front of its target: \(titles)")
        #expect(Set(stored.map(\.order)).count == stored.count, "a row the page does not hold now shares an order: \(stored)")
    }

    /// A refused re-file stops the drop: the refusal's sentence, and no renumber ([[T-17115]]).
    @Test func aRowDropWhoseRefileTheStoreRefusesReportsItAndRenumbersNothing() throws {
        struct Refused: Error {}
        let f = try fixture()
        let moved = row("Moved", 0, f.home, in: f.context)
        let workA = row("Work A", 0, f.work, in: f.context)
        let workB = row("Work B", 1, f.work, in: f.context)
        try f.context.save()

        let outcome = drop(
            moved,
            onto: workB,
            scope: [workA, workB],
            dropKey: "list:p_\(f.work.id.uuidString)",
            page: [moved, workA, workB],
            context: f.context,
            commit: { _ in throw Refused() }
        )

        #expect(outcome == .refused(notice: CadencePendingChangePersistence.editFailureNotice))
        #expect(moved.project?.id == f.home.id)
        #expect(try storedOrder(of: f.work, in: f.container).map(\.title) == ["Work A", "Work B"])
    }

    /// A refused renumber is reported with the order sentence, not as a drop that landed.
    @Test func aRowDropWhoseRenumberTheStoreRefusesReportsTheOrderNotice() throws {
        struct Refused: Error {}
        let f = try fixture()
        let workA = row("Work A", 0, f.work, in: f.context)
        let workB = row("Work B", 1, f.work, in: f.context)
        let moved = row("Moved", 2, f.work, in: f.context)
        try f.context.save()

        let outcome = drop(
            moved,
            onto: workA,
            scope: [workA, workB, moved],
            dropKey: nil,
            page: [workA, workB, moved],
            context: f.context,
            commit: { _ in throw Refused() }
        )

        #expect(outcome == .refused(notice: CadenceOrderCommit.failureNotice))
    }

    /// A payload the page does not hold, and a row let go over itself, write nothing and say
    /// nothing -- the row springing back is the whole report (T-591).
    @Test func aRowDropThePageDoesNotHoldOrOntoItselfResolvesNothing() throws {
        let f = try fixture()
        let stranger = row("Elsewhere", 0, f.home, in: f.context)
        let workA = row("Work A", 0, f.work, in: f.context)
        let workB = row("Work B", 1, f.work, in: f.context)
        try f.context.save()
        let key = "list:p_\(f.work.id.uuidString)"

        #expect(drop(stranger, onto: workB, scope: [workA, workB], dropKey: key, page: [workA, workB], context: f.context) == .resolvedNothing)
        #expect(stranger.project?.id == f.home.id)
        #expect(drop(workA, onto: workA, scope: [workA, workB], dropKey: key, page: [workA, workB], context: f.context) == .resolvedNothing)
        #expect(try storedOrder(of: f.work, in: f.container).map(\.title) == ["Work A", "Work B"])
    }

    /// **The touch pages hand their rows this drop.** `Cadence/iOS/` is invisible to the macOS leg
    /// of this target, so the wiring is pinned as source: All Tasks / Inbox hand it to both the
    /// ungrouped section and every group, Today to every list group, and both reach the shared
    /// drop rather than a copy of the decision.
    @Test func theTouchTaskPagesHandTheirRowsTheSharedRowDrop() throws {
        for (path, handOffs) in [
            ("Cadence/iOS/iOSTaskCollectionPage.swift", 2),
            ("Cadence/iOS/iOSTodayTaskSections.swift", 1)
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("iOSTaskGroupSection("), "non-vacuity: \(path) read nothing")
            #expect(
                CadenceSourceScan.matchCount(#"onDropTaskPayloadOnRow: rowTaskDrop\("#, in: source) == handOffs,
                "\(path) no longer hands its rows the row drop"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTaskRowDrop\.drop\("#, in: source) == 1,
                "\(path) no longer routes a row drop through CadenceTaskRowDrop"
            )
        }
    }
}
