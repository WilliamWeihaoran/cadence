#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-7260]](b): a Mac sidebar list dropped onto a row of ANOTHER context's section moves into
/// that context. The drop used to reach `ContextSection.reorderList`, find the dragged row absent
/// from the section's `entries` and return, while `SidebarListDropDelegate.performDrop` answered
/// `true` -- an accepted drag that did nothing.
///
/// Every store assertion is a fetch from a second context on the same container, so "moved" means
/// committed, not merely pending in the editing context.
@MainActor
struct CadenceSidebarListContextMoveTests {
    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let work: Context
        let home: Context
        let moving: Area
        let movingTask: AppTask
        let homeArea: Area
        let homeProject: Project
    }

    private func fixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let moving = Area(name: "Moving", context: work)
        moving.order = 7
        let homeArea = Area(name: "Home area", context: home)
        homeArea.order = 0
        let homeProject = Project(name: "Home project", context: home)
        homeProject.order = 0
        let task = AppTask(title: "Filed in Moving")
        task.area = moving
        task.context = work
        for model in [work, home] { modelContext.insert(model) }
        for model in [moving, homeArea] { modelContext.insert(model) }
        modelContext.insert(homeProject)
        modelContext.insert(task)
        try modelContext.save()
        return Fixture(
            container: container,
            modelContext: modelContext,
            work: work,
            home: home,
            moving: moving,
            movingTask: task,
            homeArea: homeArea,
            homeProject: homeProject
        )
    }

    private func storedArea(_ id: UUID, in container: ModelContainer) throws -> Area? {
        try ModelContext(container).fetch(FetchDescriptor<Area>(predicate: #Predicate { $0.id == id })).first
    }

    /// The move: the list takes the target section's context, its task follows (T-559's
    /// re-point), and it lands directly above the row it was dropped on, in the store.
    @Test func aListDroppedOnAnotherContextsRowMovesIntoThatContextAboveTheRow() throws {
        let f = try fixture()
        let homeEntries: [SidebarListEntry] = [.area(f.homeArea), .project(f.homeProject)]

        let landed = SidebarListContextMove.commit(
            .area(f.moving),
            into: f.home,
            onto: 1,
            among: homeEntries,
            in: f.modelContext
        )

        #expect(landed)
        let stored = try #require(try storedArea(f.moving.id, in: f.container))
        #expect(stored.context?.id == f.home.id, "the dropped list did not move into the target context")
        let taskID = f.movingTask.id
        let storedTask = try #require(
            try ModelContext(f.container).fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == taskID })).first
        )
        #expect(storedTask.context?.id == f.home.id, "the list's task kept the old context (T-293)")
        #expect(f.homeArea.order == 0)
        #expect(f.moving.order == 1, "the list did not land above the row it was dropped on")
        #expect(f.homeProject.order == 2)
        // And the column draws it there: the section's own sort agrees with the write.
        let sorted = CadenceSidebarLists.sorted(
            [SidebarListEntry.area(f.homeArea), .project(f.homeProject), .area(f.moving)],
            item: { $0.sidebarListItem }
        ).map(\.id)
        #expect(sorted == [
            SidebarListEntry.area(f.homeArea).id,
            SidebarListEntry.area(f.moving).id,
            SidebarListEntry.project(f.homeProject).id
        ])
    }

    /// The catch-all section has no context: a list dropped there is filed under none.
    @Test func aListDroppedOnTheCatchAllSectionLeavesItsContext() throws {
        let f = try fixture()
        let landed = SidebarListContextMove.commit(
            .area(f.moving),
            into: nil,
            onto: 0,
            among: [.area(f.homeArea)],
            in: f.modelContext
        )
        #expect(landed)
        let stored = try #require(try storedArea(f.moving.id, in: f.container))
        #expect(stored.context == nil)
    }

    /// [[T-18566]]: a list dropped on a context with no lists lands as its only row, at 0
    /// among none, with its task re-pointed -- the drop the empty-context row now takes.
    @Test func aListDroppedOnAnEmptyContextMovesIntoIt() throws {
        let f = try makeEmptyContextFixture()
        let landed = SidebarListContextMove.commit(
            .area(f.base.moving),
            into: f.empty,
            onto: SidebarListDropPlacement.destinationIndex(draggedIndex: nil, targetIndex: nil, count: 0) ?? -1,
            among: [],
            in: f.base.modelContext
        )
        #expect(landed)
        let stored = try #require(try storedArea(f.base.moving.id, in: f.base.container))
        #expect(stored.context?.id == f.empty.id, "the list did not move into the empty context")
        #expect(stored.order == 0)
        let taskID = f.base.movingTask.id
        let storedTask = try #require(
            try ModelContext(f.base.container).fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == taskID })).first
        )
        #expect(storedTask.context?.id == f.empty.id, "the list's task kept the old context")
    }

    /// [[T-18566]]: a list dropped past another section's last row lands last there, so one drag
    /// does it rather than a second drag within the section.
    @Test func aListDroppedPastAnotherSectionsLastRowLandsLast() throws {
        let f = try fixture()
        let homeEntries: [SidebarListEntry] = [.area(f.homeArea), .project(f.homeProject)]
        let index = try #require(
            SidebarListDropPlacement.destinationIndex(draggedIndex: nil, targetIndex: nil, count: homeEntries.count)
        )

        let landed = SidebarListContextMove.commit(
            .area(f.moving), into: f.home, onto: index, among: homeEntries, in: f.modelContext
        )

        #expect(landed)
        #expect(f.homeArea.order == 0)
        #expect(f.homeProject.order == 1)
        #expect(f.moving.order == 2, "the list did not land last")
        let sorted = CadenceSidebarLists.sorted(
            [SidebarListEntry.area(f.moving), .area(f.homeArea), .project(f.homeProject)],
            item: { $0.sidebarListItem }
        ).map(\.id)
        #expect(sorted.last == SidebarListEntry.area(f.moving).id)
    }

    private func makeEmptyContextFixture() throws -> (base: Fixture, empty: Context) {
        let base = try fixture()
        let empty = Context(name: "Empty")
        base.modelContext.insert(empty)
        try base.modelContext.save()
        return (base, empty)
    }

    /// A refused commit puts the context, the task's context and every order back, and says so.
    @Test func aRefusedMovePutsEverythingBack() throws {
        let f = try fixture()
        struct Refused: Error {}

        let landed = SidebarListContextMove.commit(
            .area(f.moving),
            into: f.home,
            onto: 0,
            among: [.area(f.homeArea), .project(f.homeProject)],
            in: f.modelContext,
            commit: { _ in throw Refused() }
        )

        #expect(!landed)
        #expect(f.moving.context?.id == f.work.id, "a refused move left the list in the new context")
        #expect(f.movingTask.context?.id == f.work.id, "a refused move left the task re-pointed")
        #expect(f.moving.order == 7)
        #expect(f.homeArea.order == 0)
        #expect(f.homeProject.order == 0)
    }

    /// The drop resolves the dragged row from the store, since it is not in the target section.
    @Test func theDraggedRowIsResolvedFromTheStore() throws {
        let f = try fixture()
        let area = SidebarListEntry.resolve(SidebarListDragItem(kind: .area, id: f.moving.id), in: f.modelContext)
        #expect(area?.id == SidebarListEntry.area(f.moving).id)
        let project = SidebarListEntry.resolve(SidebarListDragItem(kind: .project, id: f.homeProject.id), in: f.modelContext)
        #expect(project?.id == SidebarListEntry.project(f.homeProject).id)
        // The kind is part of the lookup: an area's id named as a project resolves to nothing.
        #expect(SidebarListEntry.resolve(SidebarListDragItem(kind: .project, id: f.moving.id), in: f.modelContext) == nil)
    }

    /// The insertion line promises the place the move writes: directly above the target row.
    @Test func theInsertedRowLandsWhereTheLineIsDrawn() {
        let rows = ["A", "B", "C"]
        for to in rows.indices {
            let result = SidebarListDropPlacement.inserted("X", into: rows, at: to)
            #expect(SidebarListDropPlacement.indicatorEdge(draggedIndex: nil, targetIndex: to) == .top)
            #expect(result.firstIndex(of: "X")! + 1 == result.firstIndex(of: rows[to])!, "measured \(result)")
        }
        #expect(SidebarListDropPlacement.inserted("X", into: rows, at: 9) == ["A", "B", "C", "X"])
    }

    /// The section reaches the move: a dragged row missing from `entries` is handed to the
    /// context move, and the section is handed its own context by `SidebarView`.
    @Test func theSectionHandsAForeignRowToTheContextMove() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarComponents.swift")
        )
        let reorder = try #require(CadenceSourceScan.functionBody(named: "reorderList", in: source))
        #expect(reorder.contains("moveListIntoContext(dropped, onto: toIndex)"),
                "a list dropped from another section is dropped on the floor again")
        let move = try #require(CadenceSourceScan.functionBody(named: "moveListIntoContext", in: source))
        #expect(move.contains("SidebarListContextMove.commit("))
        #expect(move.contains("into: context,"))
        #expect(move.contains("reorderFailureNotice = landed ? nil : CadenceOrderCommit.failureNotice"))
        let view = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarView.swift")
        )
        #expect(view.contains("context: owner,"), "the section is not told which context it files under")
    }

    /// [[T-18566]]: the empty-context row and the strip under a populated section's last row both
    /// register a list drop past the end, through the same delegate as the rows.
    @Test func theEmptyContextRowAndTheEndStripTakeAListDrop() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarComponents.swift")
        )
        let section = try #require(CadenceSourceScan.declarationBody("struct ContextSection: View", in: source))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: section))
        let endDrop = "\\.onDrop\\(of: \\[UTType\\.text\\], delegate: SidebarListDropDelegate\\(\\s*target: \\.end,\\s*dragOverItem: \\$dragOverListItem,\\s*onDrop: reorderList"
        let emptyRow = "SidebarAddFirstListButton\\([\\s\\S]*?action: onAddList\\s*\\)\\s*\\.overlay\\(alignment: \\.top\\) \\{ endDropIndicator \\}\\s*" + endDrop
        #expect(CadenceSourceScan.matchCount(emptyRow, in: body) == 1, "the empty-context row takes no list drop")
        #expect(body.contains("endDropZone"), "the populated section draws no strip past its last row")
        let zone = try #require(CadenceSourceScan.declarationBody("private var endDropZone: some View", in: section))
        #expect(CadenceSourceScan.matchCount(endDrop, in: zone) == 1, "the strip past the last row takes no list drop")
        let reorder = try #require(CadenceSourceScan.functionBody(named: "reorderList", in: source))
        #expect(reorder.contains("SidebarListDropPlacement.destinationIndex("))
        #expect(reorder.contains("case .end:"))
    }
}
#endif
