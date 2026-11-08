import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **Every surface that lays lists out side by side follows the sidebar's order ([[T-13851]]).**
///
/// The sidebar orders a context's lists through `CadenceSidebarLists.sorted`: while areas and
/// projects number from zero independently the kinds stay apart, but a sidebar drag renumbers the
/// whole context as one sequence and from then on they interleave by `order`. Two surfaces had
/// their own rule:
///
/// - `CadenceTaskQuerySupport.listGroupOrder` (Today's groups and All Tasks' by-list groups, both
///   platforms) put every area ahead of every project, so a project dragged above an area in the
///   sidebar stayed below it on both pages.
/// - `KanbanBoardSupport.listColumns` (the Mac's Tasks page as a board) ignored contexts entirely:
///   every area in `Area.order`, then every project in `Project.order`.
@MainActor
struct CadenceSidebarOrderedListSurfacesTests {
    private struct Fixture {
        let modelContext: ModelContext
        let work: Context
        let home: Context
        /// Work, order 1 — after Launch in the sidebar, because the two hold distinct orders.
        let admin: Area
        /// Work, order 0 — first in Work's section.
        let launch: Project
        /// Home, order 0 — would lead an `Area.order` walk that ignored contexts.
        let errands: Area
        /// No context — the sidebar's trailing "Other" section.
        let loose: Area
    }

    private func fixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let work = Context(name: "Work")
        work.order = 0
        let home = Context(name: "Home")
        home.order = 1
        let admin = Area(name: "Admin", context: work)
        admin.order = 1
        let launch = Project(name: "Launch", context: work)
        launch.order = 0
        let errands = Area(name: "Errands", context: home)
        errands.order = 0
        let loose = Area(name: "Loose")
        loose.order = 0
        for model in [work, home, admin, launch, errands, loose] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()
        return Fixture(
            modelContext: modelContext,
            work: work,
            home: home,
            admin: admin,
            launch: launch,
            errands: errands,
            loose: loose
        )
    }

    /// What the sidebar draws for the fixture, through the sidebar's own call — so the expected
    /// order below is the sidebar's by construction, not a sequence this test typed out.
    private func sidebarKeys(_ f: Fixture) -> [String] {
        CadenceSidebarLists.sections(
            contexts: [f.work, f.home].map { CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name) },
            items: [CadenceSidebarLists.Item(f.admin), CadenceSidebarLists.Item(f.errands), CadenceSidebarLists.Item(f.loose)]
                + [CadenceSidebarLists.Item(f.launch)]
        )
        .flatMap(\.items)
        .map { item in
            switch item.kind {
            case .area: return "a_\(item.id.uuidString)"
            case .project: return "p_\(item.id.uuidString)"
            }
        }
    }

    @Test func theSidebarItselfInterleavesAProjectAheadOfAnArea() throws {
        let f = try fixture()
        // Non-vacuity: the fixture is only a test of interleaving if the sidebar interleaves it.
        #expect(sidebarKeys(f) == [
            "p_\(f.launch.id.uuidString)",
            "a_\(f.admin.id.uuidString)",
            "a_\(f.errands.id.uuidString)",
            "a_\(f.loose.id.uuidString)",
        ])
    }

    @Test func listGroupOrderIsTheSidebarsOrderInsideAContext() throws {
        let f = try fixture()
        let order = CadenceTaskQuerySupport.listGroupOrder(contexts: [f.home, f.work])
        // The unfiled list is not reachable from a context; `todayListGroups` puts it on the tail.
        #expect(order == ["inbox"] + sidebarKeys(f).dropLast())
    }

    @Test func todaysGroupsComeOutInTheSidebarsOrder() throws {
        let f = try fixture()
        func task(_ title: String, area: Area? = nil, project: Project? = nil) -> AppTask {
            let task = AppTask(title: title)
            task.area = area
            task.project = project
            f.modelContext.insert(task)
            return task
        }
        let tasks = [
            task("Loose end", area: f.loose),
            task("Errand", area: f.errands),
            task("Admin work", area: f.admin),
            task("Launch work", project: f.launch),
            task("Unfiled"),
        ]
        let groups = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [f.work, f.home])
        #expect(groups.map(\.listKey) == ["inbox"] + sidebarKeys(f))
    }

    /// **[[T-14001]].** A blank-named project and a whitespace-named area head their Today / By List
    /// groups with the picker's "Untitled" names -- the words the sidebar and the Mac Tasks board
    /// print for the same lists -- and a named list keeps its name, trimmed.
    @Test func aBlankNamedListsGroupIsHeadedWithItsUntitledName() throws {
        let f = try fixture()
        f.launch.name = ""
        f.admin.name = "   "
        f.errands.name = "  Errands  "
        func task(_ title: String, area: Area? = nil, project: Project? = nil) -> AppTask {
            let task = AppTask(title: title)
            task.area = area
            task.project = project
            f.modelContext.insert(task)
            return task
        }
        let tasks = [
            task("Launch work", project: f.launch),
            task("Admin work", area: f.admin),
            task("Errand", area: f.errands),
        ]
        let groups = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [f.work, f.home])
        #expect(groups.map(\.listKey) == sidebarKeys(f).dropLast())
        #expect(groups.map(\.title) == [
            CadenceTitleNormalization.defaultProjectName,
            CadenceTitleNormalization.defaultAreaName,
            "Errands",
        ])
        // Non-vacuity: the two defaults are words, not the empty heading this replaced.
        #expect(groups.allSatisfy { !$0.title.isEmpty })

        // All Tasks' By List mode reads the same groups, so it says the same.
        let byList = CadenceTaskQuerySupport.displayGroups(
            from: tasks,
            mode: .byList,
            todayKey: "2026-11-08",
            contexts: [f.work, f.home]
        )
        #expect(byList.map(\.title) == groups.map(\.title))
    }

    /// An archived context's lists leave its place, as they leave it in the sidebar, and land on
    /// the tail with the other lists no live context owns.
    @Test func anArchivedContextsListsGoToTheTail() throws {
        let f = try fixture()
        f.work.isArchived = true
        let order = CadenceTaskQuerySupport.listGroupOrder(contexts: [f.work, f.home])
        #expect(order == ["inbox", "a_\(f.errands.id.uuidString)"])
    }

    #if os(macOS)
    /// **The Mac's Tasks board reads left to right as the sidebar reads top to bottom**: Inbox,
    /// then Work's lists in Work's order, then Home's, then the list with no context.
    @Test func theTasksBoardsListColumnsAreInTheSidebarsOrder() throws {
        let f = try fixture()
        let columns = KanbanBoardSupport.listColumns(
            contexts: [f.work, f.home],
            areas: [f.errands, f.loose, f.admin],
            projects: [f.launch],
            activeTasks: [],
            sortField: .custom,
            sortDirection: .ascending
        )
        let keys = columns.map { column -> String in
            switch column.container {
            case .inbox: return "inbox"
            case .area(let id): return "a_\(id.uuidString)"
            case .project(let id): return "p_\(id.uuidString)"
            }
        }
        #expect(keys == ["inbox"] + sidebarKeys(f))
    }

    @Test func theInboxScopeStillDrawsOnlyTheInboxColumn() throws {
        let f = try fixture()
        let columns = KanbanBoardSupport.listColumns(
            contexts: [f.work, f.home],
            areas: [f.errands, f.loose, f.admin],
            projects: [f.launch],
            activeTasks: [],
            sortField: .custom,
            sortDirection: .ascending,
            scope: .inbox
        )
        #expect(columns.map(\.title) == ["Inbox"])
    }
    #endif
}
