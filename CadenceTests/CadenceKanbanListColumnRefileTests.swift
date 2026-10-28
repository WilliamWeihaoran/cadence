// macOS only: `KanbanBoardSupport` and the section board are macOS app types.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **The Tasks page's Kanban (Lists) board refiles a card the way a list drop does ([[T-8061]],
/// [[T-8064]]).**
///
/// - [[T-8061]]: a column's `onAssignTask` wrote `area`/`project`/`context` and kept the card's
///   old `sectionName`, so a card dragged from a project's "Doing" column onto an area that has
///   only Default matched no column of that area's section board and vanished from it. It now
///   goes through `CadenceTaskMutationSupport.assignContainer`, as [[T-5353]]'s list-row drop does.
/// - [[T-8064]]: a blank-named area or project drew a title-less column header; the titles now use
///   the same "Untitled Area" / "Untitled Project" fallback as Cmd+K.
@MainActor
struct CadenceKanbanListColumnRefileTests {
    private func columns(areas: [Area], projects: [Project], tasks: [AppTask]) -> [KanbanListColumnModel] {
        KanbanBoardSupport.listColumns(
            areas: areas,
            projects: projects,
            activeTasks: tasks,
            sortField: .custom,
            sortDirection: .ascending
        )
    }

    @Test func aCardDroppedOnASectionlessAreaTakesDefaultAndAppearsOnThatAreasSectionBoard() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let home = Area(name: "Home")
        let launch = Project(name: "Launch")
        launch.sectionNames = [TaskSectionDefaults.defaultName, "Doing"]
        let card = AppTask(title: "Write copy")
        card.project = launch
        card.sectionName = "Doing"
        card.order = 7
        for model in [home, launch, card] as [any PersistentModel] { modelContext.insert(model) }
        try modelContext.save()
        #expect(home.sectionNames == [TaskSectionDefaults.defaultName])

        let homeColumn = try #require(
            columns(areas: [home], projects: [launch], tasks: [card]).first { $0.container == .area(home.id) }
        )
        homeColumn.onAssignTask(card)

        #expect(card.area?.id == home.id)
        #expect(card.project == nil)
        #expect(card.sectionName == TaskSectionDefaults.defaultName)
        // `reorder` numbers the card into the column; the refile must not renumber it first.
        #expect(card.order == 7)

        let board = ListSectionsKanbanView.columnCards(
            from: [card],
            sections: home.sectionConfigs,
            sortField: .custom,
            direction: .ascending
        )
        #expect(board.values.reduce(0) { $0 + $1.count } == 1)
        #expect(board[TaskSectionDefaults.defaultName]?.count == 1)
    }

    @Test func aCardKeepsItsSectionWhenTheNewListHasOneOfThatName() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let source = Project(name: "Source")
        source.sectionNames = [TaskSectionDefaults.defaultName, "Doing"]
        let target = Project(name: "Target")
        target.sectionNames = [TaskSectionDefaults.defaultName, "Doing"]
        let card = AppTask(title: "Card")
        card.project = source
        card.sectionName = "doing"
        for model in [source, target, card] as [any PersistentModel] { modelContext.insert(model) }
        try modelContext.save()

        let targetColumn = try #require(
            columns(areas: [], projects: [source, target], tasks: [card]).first { $0.container == .project(target.id) }
        )
        targetColumn.onAssignTask(card)

        #expect(card.project?.id == target.id)
        #expect(card.sectionName == "Doing")
    }

    @Test func aCardDroppedOnInboxLeavesItsListAndItsSection() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let launch = Project(name: "Launch")
        launch.sectionNames = [TaskSectionDefaults.defaultName, "Doing"]
        let card = AppTask(title: "Card")
        card.project = launch
        card.sectionName = "Doing"
        for model in [launch, card] as [any PersistentModel] { modelContext.insert(model) }
        try modelContext.save()

        let inbox = try #require(columns(areas: [], projects: [launch], tasks: [card]).first)
        #expect(inbox.container == .inbox)
        inbox.onAssignTask(card)

        #expect(card.project == nil)
        #expect(card.area == nil)
        #expect(card.context == nil)
        #expect(card.sectionName == TaskSectionDefaults.defaultName)
    }

    @Test func blankNamedListsGetTheUntitledFallbackTitle() {
        let blankArea = Area(name: "   ")
        let blankProject = Project(name: "\n\t")
        let namedArea = Area(name: "  Home ")

        let titles = columns(areas: [blankArea, namedArea], projects: [blankProject], tasks: []).map(\.title)

        #expect(titles == [
            "Inbox",
            CadenceTitleNormalization.defaultAreaName,
            "Home",
            CadenceTitleNormalization.defaultProjectName,
        ])
    }
}
#endif
