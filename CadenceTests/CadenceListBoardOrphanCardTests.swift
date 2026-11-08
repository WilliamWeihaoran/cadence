import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-11222]] (b): a card whose section names no live column is drawn under Default on both list
/// boards, and nothing is written to it.**
///
/// The case is reachable from the UI, not only from sync: archiving a column cancels its open
/// work (`TaskContainerLifecycleService.cancelRemainingActiveTasks(in:area:project:in:)`), and
/// reopening one of those cards (`CadenceTaskMutationSupport.toggleCompletion`, i.e. `markTodo`)
/// leaves its `sectionName` on the archived column. Before the fix iOS appended a column for that
/// name -- the archived column came back on the live board -- and the Mac's `columnCards` matched
/// it to no column at all. `ListBoardCardFiling` is the one rule both read.
@MainActor
struct CadenceListBoardOrphanCardTests {
    private static let doing = "Doing"
    private static let gone = "Gone"

    /// A list with Default, a live "Next" and an archived "Doing".
    private func configs() -> [TaskSectionConfig] {
        [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Next"),
            TaskSectionConfig(name: Self.doing, isCompleted: false, isArchived: true),
        ]
    }

    private func task(_ section: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: "\(section) \(status)")
        task.sectionName = section
        task.status = status
        return task
    }

    // MARK: - The rule

    @Test func aLiveColumnKeepsItsCardsAndAnythingElseOpenFilesUnderDefault() throws {
        let filing = try #require(ListBoardCardFiling(configs: configs()))
        #expect(filing.sectionName(for: task("next")) == "next", "a live column matches case-insensitively")
        #expect(filing.sectionName(for: task("")) == TaskSectionDefaults.defaultName)
        #expect(filing.sectionName(for: task(Self.doing)) == TaskSectionDefaults.defaultName,
                "an open card in an archived column is drawn under Default")
        #expect(filing.sectionName(for: task(Self.gone)) == TaskSectionDefaults.defaultName,
                "an open card in an unconfigured column is drawn under Default")
    }

    @Test func aFinishedCardStaysWithItsArchivedColumnButNotWithADeletedOne() throws {
        let filing = try #require(ListBoardCardFiling(configs: configs()))
        #expect(filing.sectionName(for: task(Self.doing, status: .cancelled)) == Self.doing)
        #expect(filing.sectionName(for: task(Self.doing, status: .done)) == Self.doing)
        #expect(filing.sectionName(for: task(Self.gone, status: .done)) == TaskSectionDefaults.defaultName)
        #expect(filing.sectionName(for: task("Next", status: .done)) == "Next")
    }

    @Test func aListWithNoLiveColumnHasNoFiling() {
        #expect(ListBoardCardFiling(configs: []) == nil)
        let archivedOnly = TaskSectionConfig(name: Self.doing, isCompleted: false, isArchived: true)
        #expect(ListBoardCardFiling(configs: [archivedOnly]) == nil)
    }

    // MARK: - The iOS board's shared bucketing

    @Test func theSharedBoardDrawsNoOrphanColumnAndFilesTheCardUnderDefault() throws {
        let configs = configs()
        let filing = try #require(ListBoardCardFiling(configs: configs))
        let live = ListDetailKanbanBoard.visibleSectionConfigs(configs, showArchived: false).map(\.name)
        let orphan = task(Self.doing)
        let gone = task(Self.gone)
        let next = task("Next")

        let columns = ListDetailKanbanBoard.columns(tasks: [orphan, gone, next], sectionNames: live, filing: filing)
        #expect(columns.map(\.title) == [TaskSectionDefaults.defaultName, "Next"])
        #expect(columns[0].tasks.map(\.id) == [orphan.id, gone.id])
        #expect(columns[1].tasks.map(\.id) == [next.id])

        // Display only.
        #expect(orphan.sectionName == Self.doing)
        #expect(gone.sectionName == Self.gone)

        // Without a filing (the Show Archived board) a card matches its own name only.
        let archivedBoard = ListDetailKanbanBoard.columns(tasks: [orphan], sectionNames: [Self.doing])
        #expect(archivedBoard.first?.tasks.map(\.id) == [orphan.id])
    }

    @Test func theSharedBoardsFinishedHalfKeepsArchivedWorkOutOfDefault() throws {
        let configs = configs()
        let filing = try #require(ListBoardCardFiling(configs: configs))
        let live = ListDetailKanbanBoard.visibleSectionConfigs(configs, showArchived: false).map(\.name)
        let woundDown = task(Self.doing, status: .cancelled)
        let deleted = task(Self.gone, status: .done)

        let byColumn = ListDetailKanbanBoard.completedTasksByColumn(
            tasks: [woundDown, deleted],
            sectionNames: live,
            filing: filing
        )
        #expect(byColumn[TaskSectionDefaults.defaultName]?.map(\.id) == [deleted.id])
        #expect(byColumn.values.flatMap { $0 }.contains { $0.id == woundDown.id } == false)
    }

    // MARK: - The list's Tasks tab (By List) files the same way ([[T-12121]])

    /// The shared rule both Tasks tabs read: live headings only, the orphan under Default, and
    /// nothing written to it.
    @Test func theTasksTabDrawsNoOrphanHeadingAndFilesTheTaskUnderDefault() throws {
        let configs = configs()
        let live = ListDetailKanbanBoard.visibleSectionConfigs(configs, showArchived: false).map(\.name)
        let orphan = task(Self.doing)
        let gone = task(Self.gone)
        let next = task("Next")

        let groups = CadenceTaskQuerySupport.listSectionGroups(
            from: [orphan, gone, next],
            sectionNames: live,
            pageIsEmpty: false,
            filing: ListBoardCardFiling(configs: configs)
        )
        #expect(groups.map(\.title) == [TaskSectionDefaults.defaultName, "Next"])
        #expect(groups[0].tasks.map(\.id) == [orphan.id, gone.id])
        #expect(groups[1].tasks.map(\.id) == [next.id])
        #expect(groups.reduce(0) { $0 + $1.tasks.count } == 3, "every open task is drawn exactly once")
        #expect(orphan.sectionName == Self.doing)
        #expect(gone.sectionName == Self.gone)

        // Failing-first: without the filing the orphans sit under no heading.
        let unfiled = CadenceTaskQuerySupport.listSectionGroups(
            from: [orphan, gone, next], sectionNames: live, pageIsEmpty: false, filing: nil
        )
        #expect(unfiled.reduce(0) { $0 + $1.tasks.count } == 1)
    }

    #if os(macOS)
    /// End to end on an in-memory store, through the Mac tab's own helper: archive a column with
    /// open work, reopen its card, and the Tasks tab draws it under Default.
    @Test func aTaskReopenedInAnArchivedColumnIsDrawnUnderDefaultOnTheMacTasksTab() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let project = Project(name: "Site")
        project.sectionNames = [TaskSectionDefaults.defaultName, "Next", Self.doing]
        let card = AppTask(title: "Card")
        card.project = project
        card.sectionName = Self.doing
        context.insert(project)
        context.insert(card)
        try context.save()

        let doingConfig = try #require(project.sectionConfigs.first { $0.name == Self.doing })
        project.sectionConfigs = project.sectionConfigs.map { config in
            var config = config
            if config.uuid == doingConfig.uuid { config.isArchived = true }
            return config
        }
        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: doingConfig, area: nil, project: project, in: context)
        try context.save()
        try CadenceTaskMutationSupport.toggleCompletion(
            card,
            modelContext: context,
            widgetEffects: CadenceTaskReopenWidgetEffects { _ in }
        )
        #expect(card.status == .todo)
        #expect(card.sectionName == Self.doing)
        #expect(!project.sectionNames.contains(Self.doing))

        let groups = ListTasksSectionGroups.groups(
            from: [card],
            sectionNames: project.sectionNames,
            pageIsEmpty: false,
            filing: ListBoardCardFiling(configs: project.sectionConfigs)
        )
        #expect(groups.map(\.title) == [TaskSectionDefaults.defaultName, "Next"])
        #expect(groups.first?.tasks.map(\.id) == [card.id])
        #expect(card.sectionName == Self.doing, "drawing it under Default writes nothing")
    }

    /// Both Tasks tabs pass the filing, and iOS no longer appends a heading for a name only a task
    /// carries. Source pins: the call sites are `private` members of SwiftUI views.
    @Test func bothTasksTabsFileOrphansUnderDefault() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/ListDetailComponents.swift")
        let macLive = try #require(CadenceSourceScan.declarationBody("private var liveSectionGroups: [ListTasksGroup]", in: mac))
        #expect(macLive.contains(
            "filing: ListBoardCardFiling(configs: area?.sectionConfigs ?? project?.sectionConfigs ?? [])"
        ))
        let helper = try #require(CadenceSourceScan.declarationBody("enum ListTasksSectionGroups", in: mac))
        #expect(helper.contains("filing: filing"))

        let page = try read("Cadence/iOS/iOSListDetailView.swift")
        let groups = try #require(CadenceSourceScan.declarationBody("private var sectionGroups: [CadenceTaskDisplayGroup]", in: page))
        #expect(groups.contains("sectionNames: configuredSectionNames,"))
        #expect(groups.contains("sectionConfigs: sectionConfigs,"))
        // [[T-13561]]: the By Section arm lives in the shared switch, which passes the filing.
        let shared = try read("Cadence/Shared/CadenceListDetailSortControls.swift")
        let arms = try #require(CadenceSourceScan.declarationBody("static func taskGroups(", in: shared))
        #expect(arms.contains("filing: ListBoardCardFiling(configs: sectionConfigs)"))
        #expect(!page.contains("private var sectionNames: [String]"), "the appended-heading list is gone")
    }
    #endif

    // MARK: - Reachable from the UI, and both boards draw it

    #if os(macOS)
    @Test func aCardReopenedInAnArchivedColumnIsDrawnUnderDefaultOnTheMacBoard() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let area = Area(name: "Home")
        area.sectionNames = [TaskSectionDefaults.defaultName, Self.doing]
        let card = AppTask(title: "Card")
        card.area = area
        card.sectionName = Self.doing
        context.insert(area)
        context.insert(card)
        try context.save()

        // Archive "Doing" as the column editor does: flag it, then wind its open work down.
        let doingConfig = try #require(area.sectionConfigs.first { $0.name == Self.doing })
        area.sectionConfigs = area.sectionConfigs.map { config in
            var config = config
            if config.uuid == doingConfig.uuid { config.isArchived = true }
            return config
        }
        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: doingConfig, area: area, project: nil, in: context)
        try context.save()
        #expect(card.isCancelled)
        #expect(!area.sectionNames.contains(Self.doing))

        // Reopen it, as the completion circle does: `markTodo` leaves the section alone.
        try CadenceTaskMutationSupport.toggleCompletion(
            card,
            modelContext: context,
            widgetEffects: CadenceTaskReopenWidgetEffects { _ in }
        )
        #expect(card.status == .todo)
        #expect(card.sectionName == Self.doing, "the reachable state: an open card in an archived column")

        let live = ListDetailKanbanBoard.visibleSectionConfigs(area.sectionConfigs, showArchived: false)
        let unfiled = ListSectionsKanbanView.columnCards(
            from: [card], sections: live, sortField: .custom, direction: .ascending
        )
        #expect(unfiled.isEmpty, "failing-first: without the filing the card sits on no column")

        let board = ListSectionsKanbanView.columnCards(
            from: [card],
            sections: live,
            sortField: .custom,
            direction: .ascending,
            filing: ListBoardCardFiling(configs: area.sectionConfigs)
        )
        #expect(board[TaskSectionDefaults.defaultName]?.map(\.id) == [card.id])
        #expect(board.values.reduce(0) { $0 + $1.count } == 1)
        #expect(card.sectionName == Self.doing, "drawing it under Default writes nothing")

        // The iOS board, from the same list: no "Doing" column, the card under Default.
        let iosColumns = ListDetailKanbanBoard.columns(
            tasks: [card],
            sectionNames: area.sectionNames,
            filing: ListBoardCardFiling(configs: area.sectionConfigs)
        )
        #expect(iosColumns.map(\.title) == [TaskSectionDefaults.defaultName])
        #expect(iosColumns.first?.tasks.map(\.id) == [card.id])

        // Show Archived still draws the card in its own column.
        let archived = ListDetailKanbanBoard.visibleSectionConfigs(area.sectionConfigs, showArchived: true)
        let archivedBoard = ListSectionsKanbanView.columnCards(
            from: [card], sections: archived, sortField: .custom, direction: .ascending
        )
        #expect(archivedBoard[Self.doing]?.map(\.id) == [card.id])
    }

    // MARK: - Both boards pass the filing on their live board only

    @Test func bothBoardsFileOrphansOnTheLiveBoardOnly() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        let macBody = try #require(CadenceSourceScan.declarationBody("var body: some View", in: mac))
        #expect(macBody.contains(
            "filing: showArchivedBinding.wrappedValue ? nil : ListBoardCardFiling(configs: baseSectionConfigs)"
        ))
        #expect(mac.contains("let taskSectionName = filing?.sectionName(for: task) ?? task.resolvedSectionName"))

        let panel = try read("Cadence/iOS/iOSListSupportViews.swift")
        #expect(panel.contains("showsArchivedColumns ? nil : ListBoardCardFiling(configs: sectionConfigs)"))
        #expect(panel.contains("ListDetailKanbanBoard.columns(tasks: tasks, sectionNames: sectionNames, filing: liveFiling)"))
        #expect(panel.contains(
            "ListDetailKanbanBoard.completedTasksByColumn(tasks: completedTasks, sectionNames: sectionNames, filing: liveFiling)"
        ))

        // The live iOS board no longer appends a column for a name only a task carries.
        let page = try read("Cadence/iOS/iOSListDetailView.swift")
        let names = try #require(CadenceSourceScan.declarationBody("private var kanbanSectionNames: [String]", in: page))
        #expect(names.contains("guard showArchivedKanbanColumns else { return configuredSectionNames }"))
    }
    #endif
}
