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
}
