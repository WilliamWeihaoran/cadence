import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-7260]](a): iOS and iPadOS reorder lists within a context section, through the same commit
/// the Mac sidebar's drag makes. Before it only `ContextSection.reorderList` wrote `Area.order` /
/// `Project.order` after creation, so an iPad-only owner could not change list order at all.
///
/// Every store assertion is a fetch from a second context on the same container, so "moved" means
/// committed, not merely pending in the editing context.
@MainActor
struct CadenceSidebarListReorderTests {
    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let first: Area
        let middle: Project
        let last: Area
    }

    /// One context holding an area, a project and an area, ordered 0, 1, 2 — a section that mixes
    /// both kinds, since the renumber has to span the whole section rather than one model's rows.
    private func fixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let work = Context(name: "Work")
        let first = Area(name: "First", context: work)
        first.order = 0
        let middle = Project(name: "Middle", context: work)
        middle.order = 1
        let last = Area(name: "Last", context: work)
        last.order = 2
        modelContext.insert(work)
        modelContext.insert(first)
        modelContext.insert(middle)
        modelContext.insert(last)
        try modelContext.save()
        return Fixture(container: container, modelContext: modelContext, first: first, middle: middle, last: last)
    }

    private func section(_ f: Fixture) -> [CadenceSidebarLists.Item] {
        CadenceSidebarLists.sorted([
            CadenceSidebarLists.Item(f.last),
            CadenceSidebarLists.Item(f.first),
            CadenceSidebarLists.Item(f.middle)
        ])
    }

    /// The section as a fresh context reads it back from the store, in drawn order.
    private func storedNames(_ f: Fixture) throws -> [String] {
        let reader = ModelContext(f.container)
        let areas = try reader.fetch(FetchDescriptor<Area>()).map { CadenceSidebarLists.Item($0) }
        let projects = try reader.fetch(FetchDescriptor<Project>()).map { CadenceSidebarLists.Item($0) }
        return CadenceSidebarLists.sorted(areas + projects).map(\.name)
    }

    @Test func moveDownSwapsTheRowWithTheOneBelowItInTheStore() throws {
        let f = try fixture()
        let rows = section(f)
        #expect(rows.map(\.name) == ["First", "Middle", "Last"], "non-vacuity: the fixture is not drawn in order")

        let landed = CadenceSidebarListReorder.commitStep(
            moving: rows[0], by: 1, within: rows, in: f.modelContext
        )

        #expect(landed == true)
        #expect(try storedNames(f) == ["Middle", "First", "Last"], "Move Down did not move the row one place down")
    }

    @Test func moveUpSwapsTheRowWithTheOneAboveItInTheStore() throws {
        let f = try fixture()
        let rows = section(f)

        let landed = CadenceSidebarListReorder.commitStep(
            moving: rows[2], by: -1, within: rows, in: f.modelContext
        )

        #expect(landed == true)
        #expect(try storedNames(f) == ["First", "Last", "Middle"], "Move Up did not move the row one place up")
        let renumbered: [Int] = [f.first.order, f.last.order, f.middle.order]
        #expect(renumbered == [0, 1, 2], "the section was not renumbered from 0")
    }

    /// The ends of the section offer no move, and nothing is written for one.
    @Test func theEndsOfTheSectionMoveNothing() throws {
        let f = try fixture()
        let rows = section(f)
        struct Unexpected: Error {}

        #expect(CadenceSidebarListReorder.commitStep(
            moving: rows[0], by: -1, within: rows, in: f.modelContext, commit: { _ in throw Unexpected() }
        ) == nil)
        #expect(CadenceSidebarListReorder.commitStep(
            moving: rows[2], by: 1, within: rows, in: f.modelContext, commit: { _ in throw Unexpected() }
        ) == nil)
        #expect(CadenceSidebarListReorder.neighbourIndex(of: 0, by: -1, count: 3) == nil)
        #expect(CadenceSidebarListReorder.neighbourIndex(of: 2, by: 1, count: 3) == nil)
        #expect(CadenceSidebarListReorder.neighbourIndex(of: 1, by: 2, count: 3) == nil)
        #expect(CadenceSidebarListReorder.neighbourIndex(of: 1, by: -1, count: 3) == 0)
        #expect(CadenceSidebarListReorder.neighbourIndex(of: 1, by: 1, count: 3) == 2)
        #expect(try storedNames(f) == ["First", "Middle", "Last"])
    }

    /// A refused commit puts every order back — the store never held the new one — and answers
    /// `false`, which is the caller's cue to show `CadenceOrderCommit.failureNotice`.
    @Test func aRefusedMovePutsEveryOrderBack() throws {
        let f = try fixture()
        let rows = section(f)
        struct Refused: Error {}

        let landed = CadenceSidebarListReorder.commitStep(
            moving: rows[0], by: 1, within: rows, in: f.modelContext, commit: { _ in throw Refused() }
        )

        #expect(landed == false)
        let restored: [Int] = [f.first.order, f.middle.order, f.last.order]
        #expect(restored == [0, 1, 2], "a refused move left a row renumbered")
        #expect(try storedNames(f) == ["First", "Middle", "Last"])
    }

    /// One implementation: the Mac's drag and the iOS menu both reach `CadenceSidebarListReorder`,
    /// and it commits through `CadenceOrderCommit`, not a second renumber-and-save.
    @Test func bothPlatformsCommitThroughTheSharedReorder() throws {
        let shared = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceSidebarListReorder.swift")
        )
        let commit = try #require(CadenceSourceScan.functionBody(named: "commit", in: shared))
        #expect(commit.contains("CadenceOrderCommit.commit("))
        #expect(commit.contains("writeOrder: { $0.setOrder($1) }"))
        #expect(!commit.contains("save()"), "the shared reorder commits around CadenceOrderCommit")

        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarComponents.swift")
        )
        let reorder = try #require(CadenceSourceScan.functionBody(named: "reorderList", in: mac))
        #expect(reorder.contains("CadenceSidebarListReorder.commit(entries, moving: fromIndex, onto: toIndex, in: modelContext)"))

        let ios = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootSidebar.swift")
        )
        let move = try #require(CadenceSourceScan.functionBody(named: "move", in: ios))
        #expect(move.contains("CadenceSidebarListReorder.commitStep("))
        #expect(move.contains("within: section.items,"), "the move does not span the section it is drawn in")
        #expect(move.contains("orderFailureSectionID = landed ? nil : section.id"),
                "a refused iOS move is silent again")
        #expect(ios.contains("CadenceInlineFailureNotice(text: CadenceOrderCommit.failureNotice)"),
                "the iOS refusal does not read the Mac's sentence")
    }

    /// The row's context menu carries the move, disabled at the ends of its section.
    @Test func theIOSRowMenuOffersMoveUpAndMoveDown() throws {
        let ios = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootSidebar.swift")
        )
        #expect(ios.contains("onMove(-1)"))
        #expect(ios.contains("onMove(1)"))
        #expect(ios.contains(".disabled(!canMoveUp)"))
        #expect(ios.contains(".disabled(!canMoveDown)"))
        #expect(ios.contains("onMove: { offset in move(item, by: offset, in: section) }"))
    }
}
