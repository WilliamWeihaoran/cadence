// macOS only: `ListTasksGroupDrop` and `TasksListView` are macOS app types.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5358]] — on a list's own Tasks tab, a row dropped onto a row of ANOTHER group joins that
/// group.** Before this the drop only renumbered, so a task dragged from "Documents" onto a row
/// under "Later" sprang back under Documents with nothing said, while All Tasks and the section
/// board refile on the same gesture.
///
/// The refiling is asked of `ListTasksGroupDrop` and read back through a second `ModelContext`, so
/// "it moved" means the store took it, not that an object was mutated. The one source pin is for
/// the call site, a `private` member of a SwiftUI view.
@MainActor
struct ListTasksGroupDropTests {

    private struct Refused: Error {}

    private static let todayKey = DateFormatters.todayKey()

    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    private func seeded(
        _ titles: [(String, String)],
        in modelContext: ModelContext
    ) throws -> [AppTask] {
        let project = Project(name: "Website")
        project.sectionNames = ["Documents", "Later"]
        modelContext.insert(project)
        let tasks = titles.enumerated().map { index, pair -> AppTask in
            let task = AppTask(title: pair.0)
            task.project = project
            task.sectionName = pair.1
            task.order = index
            modelContext.insert(task)
            return task
        }
        try modelContext.save()
        return tasks
    }

    private func sectionGroups(_ tasks: [AppTask]) -> [ListTasksGroup] {
        CadenceTaskQuerySupport.sectionGroups(from: tasks, sectionNames: ["Documents", "Later"])
            .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
    }

    private func storedTask(_ id: UUID, in container: ModelContainer) throws -> AppTask? {
        try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == id }
    }

    @Test func aRowDroppedOnARowOfAnotherSectionIsFiledUnderThatSection() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Later")], in: modelContext)
        let (dropped, target) = (tasks[0], tasks[1])
        let laterGroup = try #require(sectionGroups(tasks).first { $0.title == "Later" })

        let refiling = ListTasksGroupDrop.refiling(
            dropping: dropped,
            onto: target,
            in: laterGroup,
            groupingMode: .byList
        )
        #expect(refiling == .section("Later"), "a cross-section drop names no section to move into")

        let landed = ListTasksGroupDrop.refile(
            dropped,
            try #require(refiling),
            todayKey: Self.todayKey,
            modelContext: modelContext
        )
        #expect(landed)
        #expect(try storedTask(dropped.id, in: container)?.resolvedSectionName == "Later",
                "the store still files the dropped task under its old section")
    }

    @Test func aDropInsideItsOwnSectionIsAPlainReorder() throws {
        let (_, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Outline", "Documents")], in: modelContext)
        let documents = try #require(sectionGroups(tasks).first { $0.title == "Documents" })

        #expect(ListTasksGroupDrop.refiling(
            dropping: tasks[0],
            onto: tasks[1],
            in: documents,
            groupingMode: .byList
        ) == nil)
    }

    @Test func aRefusedSectionMoveLeavesTheTaskWhereItWas() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Later")], in: modelContext)

        let landed = ListTasksGroupDrop.refile(
            tasks[0],
            .section("Later"),
            todayKey: Self.todayKey,
            modelContext: modelContext,
            commit: { _ in throw Refused() }
        )
        #expect(!landed)
        #expect(tasks[0].resolvedSectionName == "Documents", "a refused move left the object refiled")
        #expect(try storedTask(tasks[0].id, in: container)?.resolvedSectionName == "Documents")
    }

    @Test func aRowDroppedIntoAnotherPriorityTakesThatPriority() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Documents")], in: modelContext)
        tasks[1].priority = .high
        try modelContext.save()
        let groups = CadenceTaskQuerySupport.priorityDisplayGroups(from: tasks)
            .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
        let high = try #require(groups.first { $0.id == "priority-high" })

        let refiling = try #require(ListTasksGroupDrop.refiling(
            dropping: tasks[0],
            onto: tasks[1],
            in: high,
            groupingMode: .byPriority
        ))
        #expect(ListTasksGroupDrop.refile(tasks[0], refiling, todayKey: Self.todayKey, modelContext: modelContext))
        #expect(try storedTask(tasks[0].id, in: container)?.priority == .high)
    }

    @Test func dateGroupsMoveExactlyAsAllTasksDoes() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Documents")], in: modelContext)
        let doToday = ListTasksGroup(id: "do-today", title: "Do Today", tasks: [tasks[1]])
        let overdue = ListTasksGroup(id: "overdue", title: "Overdue", tasks: [tasks[1]])

        #expect(ListTasksGroupDrop.refiling(
            dropping: tasks[0], onto: tasks[1], in: overdue, groupingMode: .byDate
        ) == nil, "Overdue has no assignment that makes a task late; All Tasks only reorders there")

        let refiling = try #require(ListTasksGroupDrop.refiling(
            dropping: tasks[0], onto: tasks[1], in: doToday, groupingMode: .byDate
        ))
        #expect(refiling == .dropKey("date:today"))
        #expect(ListTasksGroupDrop.refile(tasks[0], refiling, todayKey: Self.todayKey, modelContext: modelContext))
        #expect(try storedTask(tasks[0].id, in: container)?.scheduledDate == Self.todayKey)
    }

    /// **[[T-5840]]** — a drop on another group's HEADER is answered as a drop on that group's first
    /// row, so it refiles exactly as a row drop does and lands at the top of the group.
    @Test func aDropOnAnotherSectionsHeaderJoinsThatSectionAtItsTop() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Later"), ("Launch", "Later")], in: modelContext)
        let later = try #require(sectionGroups(tasks).first { $0.title == "Later" })

        let targetID = try #require(
            ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: later),
            "the Later header refuses a task from Documents"
        )
        #expect(targetID == later.tasks.first?.id, "a header drop does not aim at the group's first row")
        let target = try #require(tasks.first { $0.id == targetID })
        let refiling = try #require(ListTasksGroupDrop.refiling(
            dropping: tasks[0], onto: target, in: later, groupingMode: .byList
        ))
        #expect(ListTasksGroupDrop.refile(tasks[0], refiling, todayKey: Self.todayKey, modelContext: modelContext))
        #expect(try storedTask(tasks[0].id, in: container)?.resolvedSectionName == "Later")
    }

    @Test func aHeaderRefusesItsOwnRowsAndGroupsThatNameNoMove() throws {
        let (_, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Documents")], in: modelContext)
        tasks[1].priority = .high
        tasks[1].dueDate = "2000-01-01"
        try modelContext.save()
        let documents = try #require(sectionGroups(tasks).first { $0.title == "Documents" })
        let priority = CadenceTaskQuerySupport.priorityDisplayGroups(from: tasks)
            .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
        let dates = CadenceTaskQuerySupport.dateDisplayGroups(from: [tasks[1]], todayKey: Self.todayKey)
            .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
        let high = try #require(priority.first { $0.id == "priority-high" })
        let overdue = try #require(dates.first { $0.id == "overdue" })
        let doToday = ListTasksGroup(id: "do-today", title: "Do Today", tasks: [tasks[1]])
        let ungrouped = ListTasksGroup(id: "all", title: "Tasks", tasks: [tasks[1]])

        #expect(ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: documents) == nil,
                "a header takes a drop from its own group")
        #expect(ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: overdue) == nil,
                "Overdue has no assignment that makes a task late")
        #expect(ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: ungrouped) == nil)
        #expect(ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: high) == tasks[1].id)
        #expect(ListTasksGroupDrop.headerDropTarget(droppedID: tasks[0].id, in: doToday) == tasks[1].id)
    }

    /// The header's call site: it hands its drop to the same row path, aimed at the first row.
    @Test func theListTabsHeaderHandsItsDropToTheRowPath() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailSupportViews.swift")
        let start = try #require(source.range(of: "struct ListTasksGroupSectionView: View"))
        let end = try #require(source.range(of: "struct ListTasksCompletedSectionView: View"))
        let body = String(source[start.upperBound..<end.lowerBound])
        let header = try #require(body.range(of: "TaskListGroupHeader("))
        let rows = try #require(body.range(of: "ForEach(group.tasks)"))
        let drop = try #require(body.range(of: ".dropDestination(for: String.self)"), "the header has no drop target")
        #expect(header.lowerBound < drop.lowerBound && drop.lowerBound < rows.lowerBound,
                "the drop target is not on the header")
        #expect(body.contains("ListTasksGroupDrop.headerDropTarget(droppedID: droppedID, in: group)"))
        #expect(body.contains("return onReorderTask(droppedID, targetID)"))
    }

    /// The call site: the tab's row drop asks for the refiling before it renumbers, and does not
    /// renumber over a refused one.
    @Test func theListTabsRowDropRefilesBeforeItReorders() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailComponents.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "dropTask", in: source)

        #expect(source.contains("onReorderTask: { dropTask(droppedID: $0, targetID: $1, into: group) }"),
                "the group rows still hand their drop straight to the renumber")
        let refile = try #require(body.range(of: "ListTasksGroupDrop.refile("), "the drop never refiles")
        let reorder = try #require(body.range(of: "return reorderTask(droppedID: droppedID, targetID: targetID)"))
        #expect(refile.lowerBound < reorder.lowerBound, "the renumber runs before the refile")
        #expect(body.contains("return false"), "a refused refile still falls through to the renumber")
    }
}
#endif
