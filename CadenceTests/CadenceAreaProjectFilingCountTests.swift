import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-15431]]: a task holding both an `area` and a `project` is the project's — on the list
/// pages and in the sidebar's list counts, as it already is on Today, All Tasks and the Mac Tasks
/// board ([[T-13853]]).
///
/// The state is not one `TaskCreationService` writes, but a field-wise sync merge of two moves
/// (one device files the task under an area, another under a project) leaves exactly it. Before
/// this, the area's sidebar row counted it, the area's page listed it, and the project's did too:
/// one open task, two sidebar figures, two pages.
@MainActor
struct CadenceAreaProjectFilingCountTests {
    private struct Fixture {
        let context: ModelContext
        let area: Area
        let project: Project
        let tasks: [AppTask]
    }

    /// One area-only task, one project-only task, and one holding both. Inserted into a real store
    /// so `area.tasks` / `project.tasks` — the inverses the sidebar rows read — are populated.
    private func fixture() throws -> Fixture {
        let context = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        let project = Project(name: "Launch")
        context.insert(area)
        context.insert(project)

        let areaOnly = AppTask(title: "Area only")
        let projectOnly = AppTask(title: "Project only")
        let both = AppTask(title: "Both")
        for task in [areaOnly, projectOnly, both] { context.insert(task) }
        areaOnly.area = area
        projectOnly.project = project
        both.area = area
        both.project = project
        try context.save()
        return Fixture(context: context, area: area, project: project, tasks: [areaOnly, projectOnly, both])
    }

    @Test func theAreaRowDoesNotCountATaskFiledUnderAProject() throws {
        let f = try fixture()
        // Non-vacuity: the relationship really holds the dual-filed task.
        #expect((f.area.tasks ?? []).count == 2)
        #expect(CadenceTaskQuerySupport.openTaskCount(for: f.area) == 1)
        #expect(CadenceTaskQuerySupport.openTaskCount(for: f.project) == 2)
    }

    @Test func theListRowsTogetherCountEachOpenTaskOnce() throws {
        let f = try fixture()
        let rows = CadenceTaskQuerySupport.openTaskCount(for: f.area)
            + CadenceTaskQuerySupport.openTaskCount(for: f.project)
        let filed = CadenceTaskQuerySupport.openTaskCount(
            from: f.tasks.filter { $0.area != nil || $0.project != nil }
        )
        #expect(rows == filed)
    }

    @Test func theAreaPageListsOnlyItsOwnTasks() throws {
        let f = try fixture()
        let areaPage = CadenceTaskQuerySupport.tasks(for: f.area, project: nil, in: f.tasks)
        let projectPage = CadenceTaskQuerySupport.tasks(for: nil, project: f.project, in: f.tasks)
        #expect(areaPage.map(\.title) == ["Area only"])
        #expect(Set(projectPage.map(\.title)) == ["Project only", "Both"])
        // The relationship-backed form the Mac page reads answers the same.
        #expect(CadenceTaskQuerySupport.listedTasks(for: f.area).map(\.title) == ["Area only"])
    }

    @Test func theAreaPageAndItsRowAgree() throws {
        let f = try fixture()
        let page = CadenceTaskQuerySupport.tasks(for: f.area, project: nil, in: f.tasks)
        #expect(CadenceTaskQuerySupport.openTaskCount(from: page) == CadenceTaskQuerySupport.openTaskCount(for: f.area))
    }

    /// The Mac list page holds the area, not the store, so it reads the relationship form; the
    /// view is pinned by source because nothing else reaches `ListDetailChromeView.tasks`.
    @Test func theMacListPageReadsTheSharedAreaRule() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailView.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("private var tasks: [AppTask]", in: source),
            "the Mac list page's task source has moved -- this pin is unanchored"
        )
        #expect(body.contains("CadenceTaskQuerySupport.listedTasks(for: area)"), "got: \(body)")
        #expect(!body.contains("area?.tasks"), "the Mac area page reads the raw relationship again")
    }
    /// [[T-15434]]: the MCP container summary is a separate target that cannot call
    /// `CadenceTaskQuerySupport`, so it restates the rule; this holds the two to one answer over the
    /// dual-filed fixture, for both the area and the project.
    @Test func theMCPContainerSummaryCountsLikeTheApp() throws {
        let f = try fixture()
        let service = CadenceReadService(context: f.context, performsMigrations: false)
        let areaSummary = try service.containerSummary(kind: "area", id: f.area.id.uuidString)
        let projectSummary = try service.containerSummary(kind: "project", id: f.project.id.uuidString)
        // Non-vacuity: the area edge really reaches the dual-filed task.
        #expect((f.area.tasks ?? []).count == 2)
        #expect(areaSummary.activeTaskCount == CadenceTaskQuerySupport.openTaskCount(for: f.area))
        #expect(areaSummary.activeTaskCount == 1)
        #expect(projectSummary.activeTaskCount == CadenceTaskQuerySupport.openTaskCount(for: f.project))
        #expect(projectSummary.activeTaskCount == 2)
    }

    /// The same container edge feeds `list_tasks`' container filter, so an area-scoped listing
    /// names exactly what the area page lists.
    @Test func theMCPAreaTaskListingMatchesTheAreaPage() throws {
        let f = try fixture()
        let service = CadenceReadService(context: f.context, performsMigrations: false)
        let page = try service.listTasks(options: CadenceTaskListOptions(containerKind: "area", containerId: f.area.id.uuidString))
        #expect(page.items.map(\.title) == CadenceTaskQuerySupport.listedTasks(for: f.area).map(\.title))
        #expect(page.items.map(\.title) == ["Area only"])
    }

    /// [[T-15512]]: `update_container_columns` re-files the cards a renamed column names, and on an
    /// area it walks the area edge -- which still reaches the dual-filed task the app lists under
    /// its project. Renaming the area's column must leave that task's `sectionName` alone, or the
    /// rename moves a card on the project's board.
    @Test func renamingAnAreaColumnLeavesADualFiledTasksSectionAlone() throws {
        let f = try fixture()
        let write = CadenceWriteService(context: f.context, preparesStore: false)
        _ = try write.updateContainerColumns(options: .init(
            containerKind: "area",
            containerId: f.area.id.uuidString,
            addColumns: ["Doing"]
        ))
        let areaOnly = try #require(f.tasks.first { $0.title == "Area only" })
        let both = try #require(f.tasks.first { $0.title == "Both" })
        areaOnly.sectionName = "Doing"
        both.sectionName = "Doing"
        try f.context.save()

        _ = try write.updateContainerColumns(options: .init(
            containerKind: "area",
            containerId: f.area.id.uuidString,
            columnName: "Doing",
            newName: "Done"
        ))

        // Non-vacuity: the area's own card did move, so the rename really re-filed cards.
        #expect(areaOnly.sectionName == "Done")
        #expect(both.sectionName == "Doing")
    }

    /// [[T-15531]]: the iOS list editor's Save re-files the cards of a renamed column through
    /// `refileColumnCards`. On an area that must be the cards on the area's board -- the
    /// dual-filed task is the project's, and renaming the area's column must not move it.
    @Test func theListEditorsAreaColumnRenameLeavesADualFiledTasksSectionAlone() throws {
        let f = try fixture()
        let doing = TaskSectionConfig(name: "Doing")
        var renamed = doing
        renamed.name = "Done"
        let areaOnly = try #require(f.tasks.first { $0.title == "Area only" })
        let both = try #require(f.tasks.first { $0.title == "Both" })
        areaOnly.sectionName = "Doing"
        both.sectionName = "Doing"

        let moved = CadenceSectionEditingSupport.refileColumnCards(
            base: [doing],
            merged: [renamed],
            area: f.area,
            project: nil
        )

        // Non-vacuity: the area's own card did move, so the rename really re-filed cards.
        #expect(moved == 1)
        #expect(areaOnly.sectionName == "Done")
        #expect(both.sectionName == "Doing")
    }

    /// [[T-15531]]: the project arm still reaches the dual-filed task -- it is the project's card.
    @Test func theListEditorsProjectColumnRenameMovesTheDualFiledTask() throws {
        let f = try fixture()
        let doing = TaskSectionConfig(name: "Doing")
        var renamed = doing
        renamed.name = "Done"
        let both = try #require(f.tasks.first { $0.title == "Both" })
        both.sectionName = "Doing"

        CadenceSectionEditingSupport.refileColumnCards(base: [doing], merged: [renamed], area: nil, project: f.project)

        #expect(both.sectionName == "Done")
    }

    /// [[T-15660]]: archiving or completing an area's column settles the cards on the area's board
    /// -- the confirmation counts them, the settle closes them -- and leaves the dual-filed task,
    /// which is a card on the project's board, open.
    @Test func anAreaColumnWindDownLeavesADualFiledTaskOpen() throws {
        let f = try fixture()
        for task in f.tasks { task.sectionName = "Doing" }
        let doing = TaskSectionConfig(name: "Doing")
        let areaOnly = try #require(f.tasks.first { $0.title == "Area only" })
        let both = try #require(f.tasks.first { $0.title == "Both" })

        let counted = CadenceContainerWindDownSummary.forColumn(doing, area: f.area, project: nil, outcome: .done)
        #expect(counted.openTasks == 1)

        TaskContainerLifecycleService.completeRemainingActiveTasks(
            in: doing,
            area: f.area,
            project: nil,
            in: f.context,
            reconciler: .inert
        )
        // Non-vacuity: the area's own card really was settled.
        #expect(areaOnly.status == .done)
        #expect(both.status == .todo)
    }

    /// [[T-15660]]: the project's column still reaches the dual-filed task -- it is that board's card.
    @Test func aProjectColumnWindDownSettlesTheDualFiledTask() throws {
        let f = try fixture()
        for task in f.tasks { task.sectionName = "Doing" }
        let doing = TaskSectionConfig(name: "Doing")
        let both = try #require(f.tasks.first { $0.title == "Both" })

        #expect(CadenceContainerWindDownSummary.forColumn(doing, area: nil, project: f.project, outcome: .cancelled).openTasks == 2)
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: doing,
            area: nil,
            project: f.project,
            in: f.context,
            reconciler: .inert
        )
        #expect(both.status == .cancelled)
    }

#if os(macOS)
    /// [[T-15531]]: the Mac board column's rename and delete re-file `tasksMoving`'s cards. On an
    /// area's board that walk must skip the dual-filed task, which sits on the project's board.
    @Test func theMacAreaColumnMoveSkipsADualFiledTask() throws {
        let f = try fixture()
        for task in f.tasks { task.sectionName = "Doing" }

        let moving = KanbanSectionStateSupport.tasksMoving(
            universeTasks: f.tasks,
            area: f.area,
            project: nil,
            from: "Doing"
        )
        // Non-vacuity: the walk is not empty -- the area's own card is in it.
        #expect(moving.map(\.title) == ["Area only"])

        KanbanSectionStateSupport.moveTasks(
            universeTasks: f.tasks,
            area: f.area,
            project: nil,
            from: "Doing",
            to: "Done"
        )
        let both = try #require(f.tasks.first { $0.title == "Both" })
        #expect(both.sectionName == "Doing")
        // The project's board still owns it.
        let projectMoving = KanbanSectionStateSupport.tasksMoving(
            universeTasks: f.tasks,
            area: nil,
            project: f.project,
            from: "Doing"
        )
        #expect(Set(projectMoving.map(\.title)) == ["Project only", "Both"])
    }
#endif
}
