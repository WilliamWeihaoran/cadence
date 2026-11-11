import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-16401]]: a list moved into another context from a list editor goes to the END of its new
/// sidebar section, and the section keeps the order the user dragged.
///
/// The editors used to write the new context and keep the old `order`. A number carried in from
/// another section is one the destination's rows usually already hold, and
/// `CadenceSidebarLists.sorted` keeps a dragged interleaving only while every row's `order` is
/// distinct -- so the destination fell back to areas-first and the moved list landed wherever its
/// old number fell.
///
/// The fixture is that shape: Work holds a project the user dragged above an area (`Plan` 0,
/// `Ops` 1, dense from a renumber); Home holds `Errands` at 0, the number `Plan` holds.
@MainActor
struct CadenceSidebarListRefileTests {
    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let work: Context
        let home: Context
        let ops: Area
        let plan: Project
        let errands: Area
        let chores: Project
    }

    private func fixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let ops = Area(name: "Ops", context: work)
        ops.order = 1
        let plan = Project(name: "Plan", context: work)
        plan.order = 0
        let errands = Area(name: "Errands", context: home)
        errands.order = 0
        let chores = Project(name: "Chores", context: home)
        chores.order = 1
        for model in [work, home] { modelContext.insert(model) }
        for model in [ops, errands] { modelContext.insert(model) }
        for model in [plan, chores] { modelContext.insert(model) }
        try modelContext.save()
        return Fixture(
            container: container, modelContext: modelContext, work: work, home: home,
            ops: ops, plan: plan, errands: errands, chores: chores
        )
    }

    /// Work's section as the sidebar draws it, read from a second context on the same container so
    /// it is what the store holds, not what is pending.
    private func workSection(_ f: Fixture) throws -> [String] {
        let reader = ModelContext(f.container)
        let workID = f.work.id
        let items = try reader.fetch(FetchDescriptor<Area>()).map(CadenceSidebarLists.Item.init)
            + reader.fetch(FetchDescriptor<Project>()).map(CadenceSidebarLists.Item.init)
        return CadenceSidebarLists.sorted(items.filter { $0.contextID == workID }).map(\.name)
    }

    @Test func anAreaMovedIntoAnotherContextGoesLastAndTheSectionKeepsItsDraggedOrder() throws {
        let f = try fixture()
        #expect(try workSection(f) == ["Plan", "Ops"])

        CadenceSidebarLists.refile(f.errands, into: f.work)
        try f.modelContext.save()

        #expect(f.errands.order == 2, "the moved area was not numbered past Work's rows")
        #expect(try workSection(f) == ["Plan", "Ops", "Errands"], "Work dropped its dragged order")
    }

    @Test func aProjectMovedIntoAnotherContextGoesLastAndTheSectionKeepsItsDraggedOrder() throws {
        let f = try fixture()
        // Chores holds 1, the number Ops holds in Work.
        CadenceSidebarLists.refile(f.chores, into: f.work)
        try f.modelContext.save()

        #expect(f.chores.order == 2)
        #expect(try workSection(f) == ["Plan", "Ops", "Chores"])
    }

    /// An edit that leaves the context alone -- a rename, a colour -- must not renumber anything.
    @Test func anEditThatKeepsTheContextKeepsTheNumber() throws {
        let f = try fixture()
        CadenceSidebarLists.refile(f.ops, into: f.work)
        CadenceSidebarLists.refile(f.plan, into: f.work)
        #expect(f.ops.order == 1)
        #expect(f.plan.order == 0)
    }

    /// The pure rule on its own: the same context keeps the number even where the section's
    /// highest is far past it; a different one takes one past that section's highest.
    @Test func thePureRuleRenumbersOnlyAcrossContexts() {
        let work = UUID()
        let home = UUID()
        let areas: [CadenceSidebarLists.OrderSlot] = [(work, 4), (home, 9)]
        let projects: [CadenceSidebarLists.OrderSlot] = [(work, 6)]
        #expect(CadenceSidebarLists.orderAfterRefiling(
            currentOrder: 4, from: work, to: work, areas: areas, projects: projects
        ) == 4)
        #expect(CadenceSidebarLists.orderAfterRefiling(
            currentOrder: 9, from: home, to: work, areas: areas, projects: projects
        ) == 7)
    }

    /// Unfiling ("None") is a move too: the list goes last among the unfiled lists.
    @Test func aListMovedToNoContextIsNumberedAmongTheUnfiledLists() throws {
        let f = try fixture()
        let loose = Area(name: "Loose", context: nil)
        loose.order = 0
        f.modelContext.insert(loose)
        try f.modelContext.save()

        CadenceSidebarLists.refile(f.plan, into: nil)
        #expect(f.plan.order == 1)
        #expect(f.plan.context == nil)
    }

    /// A refused save puts the number back with the context (`CadenceListEditSnapshot`).
    @Test func theEditSnapshotRestoresTheOrderARefileWrote() throws {
        let f = try fixture()
        let undo = CadenceListEditSnapshot(f.errands)
        CadenceSidebarLists.refile(f.errands, into: f.work)
        #expect(f.errands.order == 2)
        undo.restore()
        #expect(f.errands.order == 0)
        #expect(f.errands.context?.id == f.home.id)
    }

    /// iOS's editor is not compiled into the macOS test bundle, so its wiring is checked from
    /// source: every editor writes a list's context through the shared refile, never bare.
    @Test func everyListEditorWritesAListsContextThroughTheSharedRefile() throws {
        for path in ["Cadence/iOS/iOSListEditorViews.swift", "Cadence/macOS/Sheets/EditListSheet.swift"] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(CadenceSourceScan.matchCount("CadenceSidebarLists\\.refile\\(", in: code) == 2, "\(path)")
            #expect(CadenceSourceScan.matchCount("(area|project)\\.context = ", in: code) == 0, "\(path)")
        }
    }
}
