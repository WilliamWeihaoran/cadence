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
}
#endif
