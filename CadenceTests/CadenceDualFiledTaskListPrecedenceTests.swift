import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-15553]] — a task holding both an `area` and a `project` is named, coloured, chipped and
/// opened as the PROJECT's, on every surface.**
///
/// [[T-15431]] / [[T-13853]] settled the filing rule — such a row belongs to the project
/// (`CadenceTaskQuerySupport.tasks(for:project:in:)`, `listGroupKey(for:)`), and Cmd+K's pick
/// opens the project. But `AppTask.containerName` / `containerColor` and
/// `CadenceBoardCardMetadata.listTitle(for:)` read the area first, so a search row said "Home"
/// while Return landed on "Kitchen Reno", the list field did not answer to the project's name,
/// and the list chip drew the project's glyph beside the area's name. One seeded dual-filed task
/// is read through every one of those here.
@MainActor
struct CadenceDualFiledTaskListPrecedenceTests {

    private struct Seed {
        let context: ModelContext
        let area: Area
        let project: Project
        let task: AppTask
    }

    private func seed() throws -> Seed {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let area = Area(name: "Home", colorHex: "#aa3311", icon: "house.fill")
        let project = Project(name: "Kitchen Reno", colorHex: "#1177cc")
        project.icon = "hammer.fill"
        let task = AppTask(title: "Order cabinets")
        context.insert(area)
        context.insert(project)
        context.insert(task)
        task.area = area
        task.project = project
        try context.save()
        return Seed(context: context, area: area, project: project, task: task)
    }

    @Test func theFixtureReallyHoldsBothListsWithDistinctNamesColoursAndIcons() throws {
        let s = try seed()
        #expect(s.task.area?.id == s.area.id)
        #expect(s.task.project?.id == s.project.id)
        #expect(s.area.name != s.project.name)
        #expect(s.area.colorHex != s.project.colorHex)
        #expect(s.area.icon != s.project.icon)
        // The filing rule this test holds every name to.
        #expect(CadenceTaskQuerySupport.tasks(for: nil, project: s.project, in: [s.task]).map(\.id) == [s.task.id])
        #expect(CadenceTaskQuerySupport.tasks(for: s.area, project: nil, in: [s.task]).isEmpty)
    }

    @Test func theTasksListNameAndColourAreTheProjects() throws {
        let s = try seed()
        #expect(s.task.containerName == "Kitchen Reno")
        #expect(s.task.containerColor == "#1177cc")
    }

    @Test func theSearchSubtitleAndListFieldNameTheProject() throws {
        let s = try seed()
        #expect(CadenceTaskSearchSupport.containerLabel(for: s.task) == "Kitchen Reno")
        #expect(CadenceTaskSearchSupport.resultSubtitle(for: s.task) == "Kitchen Reno")
        #expect(CadenceTaskSearchSupport.searchFields(for: s.task).contains("Kitchen Reno"))
        #expect(CadenceSearchMatcher.matchScore(
            query: "kitchen reno",
            fields: CadenceTaskSearchSupport.searchFields(for: s.task)
        ) != nil, "typing the project's name does not find the task through its list field")
    }

    @Test func theListChipsTextIconAndColourAreAllTheProjects() throws {
        let s = try seed()
        let chip = CadenceBoardCardMetadata.listChip(for: s.task)
        #expect(chip.text == "Kitchen Reno")
        #expect(chip.icon == "hammer.fill")
        #expect(chip.listColorHex == "#1177cc")
        #expect(CadenceBoardCardMetadata.listTitle(for: s.task) == "Kitchen Reno")
    }

    @Test func thePickerBadgeSelectionIsTheProject() throws {
        let s = try seed()
        #expect(CadenceTaskComposerSupport.container(of: s.task) == .project(s.project.id))
    }

    // MARK: - [[T-15561]]: the placement readers

    /// Gives the two lists disjoint columns and files the task under one only the PROJECT has, in
    /// the wrong case -- so an area-first reader normalises it to the area's column (or rejects
    /// it) and a project-first one answers the project's spelling.
    private func seedWithColumns() throws -> Seed {
        let s = try seed()
        s.area.sectionNames = ["Errands"]
        s.project.sectionNames = ["Planning", "Build"]
        s.task.sectionName = "build"
        try s.context.save()
        return s
    }

    @Test func theFiledAreaOfADualFiledTaskIsNone() throws {
        let s = try seed()
        #expect(s.task.filedArea == nil)
        let inArea = AppTask(title: "Water plants")
        inArea.area = s.area
        #expect(inArea.filedArea?.id == s.area.id)
    }

    /// The schedule panel opens a dual-filed task on its project's list and column, so Save
    /// cannot re-file it under the area.
    @Test func theScheduleDraftOpensOnTheProjectAndItsColumn() throws {
        let s = try seedWithColumns()
        let draft = CadenceScheduleDraft(editing: s.task)
        #expect(draft.listToken == CadenceTaskComposerSupport.token(for: .project(s.project.id)))
        #expect(CadenceScheduleDraft.containerToken(of: s.task) == draft.listToken)
        #expect(draft.sectionName == "Build", "the draft opened on column \(draft.sectionName)")
    }

    /// `update_task` with only a section matches it against the PROJECT's columns.
    @Test func theMCPWriteServiceMatchesASectionAgainstTheProjectsColumns() throws {
        let s = try seedWithColumns()
        let write = CadenceWriteService(context: s.context, preparesStore: false)
        let detail = try write.updateTask(options: .init(taskId: s.task.id.uuidString, sectionName: "build"))
        #expect(detail.summary.sectionName == "Build")
        #expect(s.task.project?.id == s.project.id)
    }

    /// `get_task` reports the project as the task's container -- the list its search subtitle names.
    @Test func theMCPReadServiceReportsTheProjectAsTheContainer() throws {
        let s = try seed()
        let read = CadenceReadService(context: s.context, performsMigrations: false)
        let detail = try read.getTask(taskID: s.task.id.uuidString)
        let container = try #require(detail.summary.container)
        #expect(container.kind == "project")
        #expect(container.id == s.project.id.uuidString)
        #expect(container.name == "Kitchen Reno")
    }

    /// A single-list task is unchanged by the precedence — the area-only and project-only halves.
    @Test func aTaskInOneListStillNamesThatList() {
        let area = Area(name: "Home", colorHex: "#aa3311", icon: "house.fill")
        let inArea = AppTask(title: "Water plants")
        inArea.area = area
        #expect(inArea.containerName == "Home")
        #expect(inArea.containerColor == "#aa3311")
        #expect(CadenceBoardCardMetadata.listTitle(for: inArea) == "Home")
        #expect(CadenceTaskComposerSupport.container(of: inArea) == .area(area.id))

        let unfiled = AppTask(title: "Loose")
        #expect(unfiled.containerName == "")
        #expect(CadenceBoardCardMetadata.listTitle(for: unfiled) == CadenceBoardCardMetadata.inboxLabel)
    }

    #if os(macOS)
    /// Cmd+K's row and its pick agree: the row names and tints the project, and Return opens it.
    @Test func cmdKsRowAndItsPickNameTheSameList() throws {
        let s = try seed()
        let row = GlobalSearchIndexSupport.taskResult(for: s.task, todayKey: "2026-11-10")
        #expect(row.subtitle.hasPrefix("Kitchen Reno"), "the Cmd+K row reads \(row.subtitle)")
        #expect(row.tintHex == "#1177cc")

        let navigation = ListNavigationManager.shared
        navigation.request = nil
        defer { navigation.request = nil }
        var selections: [SidebarItem] = []
        RootCommandActionSupport.handleTaskSelection(
            s.task.id,
            modelContext: s.context,
            listNavigationManager: navigation,
            setSelection: { selections.append($0) },
            presentTaskInspector: { _ in }
        )
        #expect(selections == [.project(s.project.id)])
        #expect(navigation.request?.projectID == s.project.id)
    }
    #endif
}
