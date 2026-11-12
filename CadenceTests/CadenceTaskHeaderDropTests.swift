import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-16654]] — a task row dragged onto a group heading re-files it, through one write.**
///
/// The Mac's All Tasks and Inbox headings have re-filed a dropped row since T-591; the iPhone's and
/// iPad's took only the new-task `+`, because the write lived in `#if os(macOS)` code. It is
/// `CadenceTaskHeaderDrop` in `Shared/` now, and this suite has no platform guard, so the same
/// assertions run on both legs: which key each heading hands out, and what a drop on it writes.
/// Every write is read back through a SECOND `ModelContext`, so only committed state counts.
@MainActor
struct CadenceTaskHeaderDropTests {
    private struct CommitRefused: Error {}

    private static let todayKey = "2026-11-11"

    @Test("Every grouping hands its heading the key its bucket means, and nil where it means none")
    func everyGroupingHandsItsHeadingTheKeyItsBucketMeans() {
        let project = Project(name: "Garden")
        let filed = AppTask(title: "Filed, high")
        filed.project = project
        filed.priority = .high
        let overdue = AppTask(title: "Overdue")
        overdue.dueDate = "2026-11-01"
        let leftover = AppTask(title: "Leftover")
        leftover.scheduledDate = "2026-11-10"
        let today = AppTask(title: "Today")
        today.scheduledDate = Self.todayKey
        let later = AppTask(title: "Later")
        later.scheduledDate = "2026-12-01"
        let loose = AppTask(title: "Loose")
        let tasks = [filed, overdue, leftover, today, later, loose]

        func keys(_ mode: TaskGroupingMode) -> [String: String?] {
            let groups = CadenceTaskQuerySupport.displayGroups(from: tasks, mode: mode, todayKey: Self.todayKey, contexts: [])
            return Dictionary(uniqueKeysWithValues: groups.map { ($0.id, CadenceTaskHeaderDrop.dropKey(forDisplayGroup: $0)) })
        }

        let byDate = keys(.byDate)
        #expect(byDate.count == 5, "non-vacuity: the date fixture spans five buckets, read \(byDate.keys.sorted())")
        #expect(byDate["do-today"] == "date:today")
        #expect(byDate["scheduled"] == "date:scheduled")
        #expect(byDate["unscheduled"] == "date:unscheduled")
        #expect(byDate["overdue"] == .some(nil), "a day already gone by is not a place to file a task")
        #expect(byDate["past-do"] == .some(nil))

        let byPriority = keys(.byPriority)
        #expect(byPriority["priority-high"] == "priority:high")
        #expect(byPriority["priority-none"] == "priority:none")

        let byList = keys(.byList)
        let gardenKey = "list:" + CadenceTaskDropSupport.containerKey(for: .project(project.id))
        #expect(byList.values.contains(gardenKey), "the Garden heading hands out no list key: \(byList)")
        #expect(byList.values.allSatisfy { $0?.hasPrefix("list:") == true })

        let ungrouped = keys(.none)
        #expect(Array(ungrouped.keys) == ["tasks"])
        #expect(ungrouped["tasks"] == .some(nil), "the ungrouped heading has nothing to file a row under")
    }

    @Test("A row dropped on a list, priority or date heading is filed under it, committed")
    func aRowDroppedOnAHeadingIsFiledUnderIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Garden")
        let resident = AppTask(title: "Already in Garden, high")
        resident.project = project
        resident.priority = .high
        let dragged = AppTask(title: "Dragged")
        let bystander = AppTask(title: "Bystander")
        context.insert(project)
        [resident, dragged, bystander].forEach(context.insert)
        try context.save()
        let page = [resident, dragged, bystander]
        let payload = TaskDragPayload.string(for: dragged.id)

        func drop(_ mode: TaskGroupingMode, onto groupID: (CadenceTaskDisplayGroup) -> Bool) -> TasksPanelDropOutcome? {
            let groups = CadenceTaskQuerySupport.displayGroups(from: page, mode: mode, todayKey: Self.todayKey, contexts: [])
            guard let group = groups.first(where: groupID),
                  let key = CadenceTaskHeaderDrop.dropKey(forDisplayGroup: group) else { return nil }
            return CadenceTaskHeaderDrop.dropTask(
                payload: payload,
                onHeaderKeyed: key,
                among: page,
                todayKey: Self.todayKey,
                modelContext: context,
                reconciler: .inert
            )
        }

        #expect(drop(.byList) { $0.tasks.contains { $0.id == resident.id } } == .applied)
        #expect(drop(.byPriority) { $0.id == "priority-high" } == .applied)
        #expect(drop(.byDate) { $0.id == "unscheduled" } != nil, "non-vacuity: the fixture draws Unscheduled")

        // Do Today is drawn only once a row is in it, and none is, so its heading's key is named.
        #expect(CadenceTaskHeaderDrop.dropTask(
            payload: payload,
            onHeaderKeyed: "date:today",
            among: page,
            todayKey: Self.todayKey,
            modelContext: context,
            reconciler: .inert
        ) == .applied)

        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<AppTask>())
        let readDragged = try #require(stored.first { $0.id == dragged.id })
        #expect(readDragged.project?.id == project.id)
        #expect(readDragged.priority == .high)
        #expect(readDragged.scheduledDate == Self.todayKey)
        let readBystander = try #require(stored.first { $0.id == bystander.id })
        #expect(readBystander.project == nil && readBystander.priority == .none && readBystander.scheduledDate.isEmpty)
    }

    @Test("A payload naming nothing on the page, or nothing at all, writes nothing")
    func aPayloadTheHeadingCannotNameWritesNothing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let onPage = AppTask(title: "On the page")
        let elsewhere = AppTask(title: "Somewhere else")
        context.insert(onPage)
        context.insert(elsewhere)
        try context.save()

        for payload in [TaskDragPayload.string(for: elsewhere.id), "plain text from another app"] {
            let outcome = CadenceTaskHeaderDrop.dropTask(
                payload: payload,
                onHeaderKeyed: "priority:high",
                among: [onPage],
                todayKey: Self.todayKey,
                modelContext: context,
                reconciler: .inert
            )
            #expect(outcome == .resolvedNothing)
        }
        #expect(elsewhere.priority == .none && onPage.priority == .none)
    }

    @Test("A drop the store refuses answers refused and leaves every field as it was")
    func aRefusedHeaderDropIsUndone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Refused")
        context.insert(task)
        try context.save()

        let outcome = CadenceTaskHeaderDrop.dropTask(
            payload: TaskDragPayload.string(for: task.id),
            onHeaderKeyed: "priority:high|date:today",
            among: [task],
            todayKey: Self.todayKey,
            modelContext: context,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        )
        #expect(outcome == .refused)
        #expect(task.priority == .none)
        #expect(task.scheduledDate.isEmpty)
    }
}
