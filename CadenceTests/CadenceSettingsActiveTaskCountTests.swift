import Foundation
import Testing
@testable import Cadence

/// [[T-14291]]: the iOS Settings "Active tasks" tile counts open work in active lists — the number
/// the Tasks page's header states — not every open task in the store.
///
/// The view half is pinned by reading the source, because `Cadence/iOS/` is inside `#if os(iOS)`
/// and invisible to this macOS-built target.
struct CadenceSettingsActiveTaskCountTests {
    private func task(done: Bool = false, area: Area? = nil, project: Project? = nil) -> AppTask {
        let task = AppTask(title: "Task")
        if done { task.status = .done }
        task.area = area
        task.project = project
        return task
    }

    private var fixture: [AppTask] {
        let activeArea = Area(name: "Work")
        let archivedArea = Area(name: "Old")
        archivedArea.statusRaw = "archived"
        let activeProject = Project(name: "Launch")
        let finishedProject = Project(name: "Shipped")
        finishedProject.status = .done
        return [
            task(),                              // open, inbox
            task(done: true),                    // finished, inbox
            task(area: activeArea),              // open, active area
            task(project: activeProject),        // open, active project
            task(area: archivedArea),            // open, archived area
            task(project: finishedProject),      // open, done project
        ]
    }

    @Test func countsOpenWorkInActiveListsOnly() {
        #expect(CadenceTaskQuerySupport.activeTaskCount(from: fixture) == 3)
        // Non-vacuity: the fixture really holds open work in inactive lists for the filter to drop.
        #expect(CadenceTaskQuerySupport.openTaskCount(from: fixture) == 5)
    }

    @Test func agreesWithTheTasksPageHeader() {
        let header = CadenceTaskQuerySupport.tasksPageHeaderCount(
            scope: .all, tasks: fixture, reminderCount: 4, drawsReminders: true
        )
        #expect(CadenceTaskQuerySupport.activeTaskCount(from: fixture) == header)
    }

    @Test func theIOSSettingsTileReadsTheSharedCount() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("private var activeTaskCount: Int", in: source),
            "the Settings active-task count has moved — this pin is unanchored"
        )
        #expect(body.contains("CadenceTaskQuerySupport.activeTaskCount(from: tasks)"), "got: \(body)")
        #expect(!body.contains("openTaskCount("), "the tile counts open work in inactive lists again")
        // Non-vacuity: this count is the one the Local Data grid draws.
        #expect(source.contains("activeTaskCount: activeTaskCount"))
    }

    // MARK: - [[T-15101]] The All Tasks rows are the scope the badge counts

    /// The rows All Tasks draws and the number its header states come from one scope: every open
    /// row is counted and every counted task has a row. Before T-15101 iOS drew rows from the
    /// whole store, so the open task in the done project (and the one in the archived area) was a
    /// row nobody counted.
    @Test func theAllTasksOpenRowsAreExactlyWhatTheHeaderCounts() {
        let tasks = fixture
        let rows = CadenceTaskQuerySupport.activeTasks(
            from: CadenceTaskQuerySupport.allTasksScope(from: tasks),
            sortField: .date,
            sortDirection: .ascending
        )
        let header = CadenceTaskQuerySupport.tasksPageHeaderCount(
            scope: .all, tasks: tasks, reminderCount: 0, drawsReminders: false
        )
        #expect(rows.count == header, "rows \(rows.count) vs header \(header)")
        #expect(rows.filter { !$0.isInActiveContainer }.isEmpty)
        // Non-vacuity: the whole store holds open work the scope must drop.
        #expect(CadenceTaskQuerySupport.activeTasks(from: tasks, sortField: .date, sortDirection: .ascending).count > header)
    }

    /// The finished half follows the same scope, as the Mac's Completed section does: a finished
    /// task in a done project is not an All Tasks row either.
    @Test func theAllTasksCompletedRowsShareTheScope() {
        let finishedProject = Project(name: "Shipped")
        finishedProject.status = .done
        let inScope = task(done: true)
        let outOfScope = task(done: true, project: finishedProject)
        let rows = CadenceTaskQuerySupport.completedTasks(
            from: CadenceTaskQuerySupport.allTasksScope(from: [inScope, outOfScope])
        )
        #expect(rows.map(\.id) == [inScope.id])
    }

    /// Both platforms' All Tasks pages read the one scope. `Cadence/iOS/` is behind `#if os(iOS)`,
    /// so its half is a source reading; the Mac's `TasksListView` is the second caller.
    @Test func bothAllTasksPagesReadTheSharedScope() throws {
        let phone = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionViews.swift")
        )
        let open = try #require(
            CadenceSourceScan.declarationBody("private var activeTasks: [AppTask]", in: phone),
            "iOSAllTasksView.activeTasks has moved — this pin is unanchored"
        )
        let finished = try #require(
            CadenceSourceScan.declarationBody("private var completedTasks: [AppTask]", in: phone),
            "iOSAllTasksView.completedTasks has moved — this pin is unanchored"
        )
        for body in [open, finished] {
            #expect(body.contains("CadenceTaskQuerySupport.allTasksScope(from: allTasks)"), "got: \(body)")
        }

        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksListView.swift")
        )
        let universe = try #require(
            CadenceSourceScan.declarationBody("private var visibleTaskUniverse: [AppTask]", in: mac),
            "TasksListView.visibleTaskUniverse has moved — this pin is unanchored"
        )
        #expect(universe.contains("case .all: return CadenceTaskQuerySupport.allTasksScope(from: allTasks)"), "got: \(universe)")
    }
}
