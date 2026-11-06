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
        #expect(open.status == .done)
    }
}
#endif
