import Foundation
import SwiftData
import Testing
@testable import Cadence

// [[T-11614]] group (1): the iOS list and column wind-downs report a refused commit.
//
// `ModelContext.windDownList` / `windDownColumn` / `reopenColumn` ended in `try? save()`, so a
// refused write left a whole list or column -- and every task it settled -- pending in the app's
// one context while the confirmation closed and the list left the page. They now commit through
// `CadencePendingChangePersistence.commitEdit` and throw. These tests refuse the commit and assert
// both halves of "Nothing was changed": the call throws, and the snapshot put the list, the
// column and the tasks back. The extensions are iOS-only, so this runs on the iOS leg; the
// source half (`CadenceSaveCommitDisciplineTests.theWindDownSettlesCommitThroughTheSpineAndThrow`)
// runs on both.

#if os(iOS)
@Suite @MainActor
struct iOSWindDownRefusalTests {
    private struct Refused: Error {}

    // Every test keeps its `ModelContainer` in a local: a context whose container was a discarded
    // temporary traps on its first fetch, which reads as a crash in the code under test.

    private func refuse(_ context: ModelContext) throws {
        throw Refused()
    }

    private func task(_ title: String, section: String = TaskSectionDefaults.defaultName) -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        return task
    }

    /// An area with a `Doing` column, holding `tasks`, committed.
    private func board(_ tasks: [AppTask], in context: ModelContext) throws -> Area {
        let area = Area(name: "Board")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
        ]
        context.insert(area)
        for task in tasks {
            task.area = area
            context.insert(task)
        }
        area.tasks = tasks
        try context.save()
        return area
    }

    private func doing(_ area: Area) throws -> TaskSectionConfig {
        try #require(area.sectionConfigs.first { $0.name == "Doing" })
    }

    // MARK: - The list

    @Test(arguments: [iOSListWindDownAction.archive, .complete])
    func aRefusedListWindDownThrowsAndPutsTheListAndItsTasksBack(_ action: iOSListWindDownAction) throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = task("open")
        let area = try board([open], in: context)

        #expect(throws: Refused.self) {
            try context.windDownList(.area(area, action), commit: refuse)
        }
        #expect(area.status == .active, "the list still reads \(area.status) after a refused \(action)")
        #expect(open.status == .todo, "the open task was settled to \(open.status) by a refused \(action)")
        #expect(open.completedAt == nil)
    }

    /// A refused project wind-down, the other list kind, through the menu decision every host
    /// asks: nothing to confirm, so it winds down at once and must forward the throw.
    @Test func aRefusedImmediateProjectWindDownThrowsFromTheMenuDecision() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let project = Project(name: "Empty")
        context.insert(project)
        try context.save()

        #expect(throws: Refused.self) {
            _ = try context.windDownListUnlessConfirmationIsNeeded(.project(project, .archive), commit: refuse)
        }
        #expect(project.status == .active)
    }

    /// [[T-12532]]: the refusal alert names the kind the control named -- "Archive Project" is
    /// refused as "Couldn't Archive Project", never "Couldn't Archive List".
    @Test func aRefusedListWindDownIsTitledWithTheListsOwnNoun() {
        let area = Area(name: "Home")
        let project = Project(name: "Empty")
        #expect(iOSListWindDownTarget.area(area, .archive).failureAlertTitle == "Couldn't Archive Area")
        #expect(iOSListWindDownTarget.area(area, .complete).failureAlertTitle == "Couldn't Complete Area")
        #expect(iOSListWindDownTarget.project(project, .archive).failureAlertTitle == "Couldn't Archive Project")
        #expect(iOSListWindDownTarget.project(project, .complete).failureAlertTitle == "Couldn't Complete Project")
    }

    @Test func anAcceptedListWindDownSettlesAndCommits() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = task("open")
        let area = try board([open], in: context)

        try context.windDownList(.area(area, .archive))
        #expect(!context.hasChanges, "the wind-down landed in the context but was never committed")
        #expect(area.status == .archived)
        #expect(open.status == .cancelled)
    }

    // MARK: - The list editor's one commit ([[T-12020]])

    /// `settledTasks` is the set `settleListWindDown` writes -- for an area, its child projects'
    /// open tasks too -- so a snapshot handed it puts every settled task back.
    @Test func anAreasSettledTasksReachItsChildProjects() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let direct = task("direct")
        let area = try board([direct], in: context)
        let child = Project(name: "Child")
        context.insert(child)
        child.area = area
        let nested = task("nested")
        nested.project = child
        context.insert(nested)
        try context.save()

        let settled = iOSListWindDownTarget.area(area, .archive).settledTasks
        #expect(Set(settled.map(\.id)) == Set([direct.id, nested.id]))

        #expect(throws: Refused.self) {
            try context.windDownList(.area(area, .archive), commit: refuse)
        }
        #expect(nested.status == .todo, "a refused archive left the child project's task \(nested.status)")
    }

    /// The editor's shape: a rename and the settle under one snapshot and one commit. Refused,
    /// both are undone -- so `editFailureNotice`'s "Nothing was changed" is true; accepted, both
    /// land in that one commit.
    @Test(arguments: [iOSListWindDownAction.archive, .complete])
    func aRenameAndItsWindDownLandOrAreUndoneTogether(_ action: iOSListWindDownAction) throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = task("open")
        let area = try board([open], in: context)
        let target = iOSListWindDownTarget.area(area, action)

        func renameAndSettle(commit: (ModelContext) throws -> Void) throws {
            let undo = CadenceListEditSnapshot(
                area,
                tasks: CadenceTaskMutationSupport.inheritedContextTargets(area: area) + target.settledTasks
            )
            area.name = "Renamed"
            context.settleListWindDown(target)
            try CadencePendingChangePersistence.commitEdit(in: context, commit: commit, undo: undo.restore)
        }

        #expect(throws: Refused.self) { try renameAndSettle(commit: refuse) }
        #expect(area.name == "Board", "the rename survived a refused \(action)")
        #expect(area.status == .active)
        #expect(open.status == .todo)

        var commits = 0
        try renameAndSettle(commit: { commits += 1; try $0.save() })
        #expect(commits == 1)
        #expect(!context.hasChanges)
        #expect(area.name == "Renamed")
        #expect(area.status == (action == .archive ? .archived : .done))
        #expect(open.status == (action == .archive ? .cancelled : .done))
    }

    // MARK: - The column

    @Test(arguments: [iOSColumnWindDownAction.archive, .complete])
    func aRefusedColumnWindDownThrowsAndPutsTheColumnAndItsTasksBack(_ action: iOSColumnWindDownAction) throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = task("open", section: "Doing")
        let area = try board([open], in: context)
        let target = iOSColumnWindDownTarget(config: try doing(area), area: area, project: nil, action: action)

        #expect(throws: Refused.self) {
            try context.windDownColumn(target, commit: refuse)
        }
        let column = try doing(area)
        #expect(!column.isArchived && !column.isCompleted, "the column kept a refused \(action)")
        #expect(open.status == .todo, "the column's open task was settled to \(open.status) by a refused \(action)")
    }

    @Test func aRefusedColumnReopenThrowsAndLeavesTheColumnArchived() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let area = try board([], in: context)
        area.sectionConfigs = area.sectionConfigs.map { config in
            var config = config
            if config.name == "Doing" { config.isArchived = true }
            return config
        }
        try context.save()

        #expect(throws: Refused.self) {
            try context.reopenColumn(try doing(area), area: area, project: nil, commit: refuse)
        }
        #expect(try doing(area).isArchived, "a refused reopen still put the column back on the board")
    }

    @Test func anAcceptedColumnWindDownSettlesAndCommits() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = task("open", section: "Doing")
        let area = try board([open], in: context)

        try context.windDownColumn(.init(config: try doing(area), area: area, project: nil, action: .complete))
        #expect(!context.hasChanges)
        #expect(try doing(area).isCompleted)
        // [[T-15722]]: completing a column archives it, as the Mac's countdown does.
        #expect(try doing(area).isArchived)
        #expect(open.status == .done)
    }
}
#endif
