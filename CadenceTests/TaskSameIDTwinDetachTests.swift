import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-6483]]: two `AppTask` rows can share an `id` until repair merges them -- a sync race, or a
/// launch that has not repaired yet -- and every user-facing delete, roll or un-block can reach
/// either copy in the meantime. Each must take out exactly the object it was handed. The shared
/// helpers used to filter the inverse arrays by `id`, which took the twin out along with it.
@MainActor
struct TaskSameIDTwinDetachTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// Two rows that share an `id`, both filed in the same block.
    private func sameIDTwinsInABlock(_ modelContext: ModelContext) throws -> (survivor: AppTask, copy: AppTask, bundle: TaskBundle) {
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-08-19", startMin: 600, durationMinutes: 30)
        let survivor = AppTask(title: "Survivor")
        let copy = AppTask(title: "Copy")
        copy.id = survivor.id
        modelContext.insert(bundle)
        modelContext.insert(survivor)
        modelContext.insert(copy)
        survivor.bundle = bundle
        copy.bundle = bundle
        copy.bundleOrder = 1
        try modelContext.save()
        try #require((bundle.tasks ?? []).count == 2, "fixture: both copies must start in the block")
        return (survivor, copy, bundle)
    }

    /// Detaching one copy leaves its twin in every container both were filed in. The `id` filter
    /// this replaced emptied all six arrays, so the twin lost its list, project, context, goal,
    /// block and tags while still pointing at each of them.
    @Test func detachingOneOfTwoSameIDTasksLeavesItsTwinInEveryContainer() throws {
        let modelContext = try makeContext()
        let context = Context(name: "Work")
        let area = Area(name: "Home", context: context)
        let project = Project(name: "Move", context: context)
        let goal = Goal(title: "Settle in", context: context)
        let tag = Tag(name: "errand")
        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)
        modelContext.insert(tag)
        let (survivor, copy, bundle) = try sameIDTwinsInABlock(modelContext)
        for task in [survivor, copy] {
            task.area = area
            task.project = project
            task.context = context
            task.goal = goal
            task.tags = [tag]
        }
        try modelContext.save()
        try #require((area.tasks ?? []).count == 2, "fixture: both copies must start in the area")
        try #require((project.tasks ?? []).count == 2)
        try #require((context.tasks ?? []).count == 2)
        try #require((goal.tasks ?? []).count == 2)
        try #require((tag.tasks ?? []).count == 2)

        CadenceTaskMutationSupport.detachRelationships(for: copy)

        func holdsOnlyTheSurvivor(_ tasks: [AppTask]?) -> Bool {
            let tasks = tasks ?? []
            return tasks.count == 1 && tasks.first === survivor
        }
        #expect(holdsOnlyTheSurvivor(area.tasks), "the twin lost its area")
        #expect(holdsOnlyTheSurvivor(project.tasks), "the twin lost its project")
        #expect(holdsOnlyTheSurvivor(context.tasks), "the twin lost its context")
        #expect(holdsOnlyTheSurvivor(goal.tasks), "the twin lost its goal")
        #expect(holdsOnlyTheSurvivor(bundle.tasks), "the twin lost its block")
        #expect(holdsOnlyTheSurvivor(tag.tasks), "the twin lost its tag")
        #expect(copy.area == nil && copy.bundle == nil && (copy.tags ?? []).isEmpty)
    }

    /// Rolling one copy over to today leaves its twin in the block. With the `id` filter the
    /// block read as empty, so the settled-block disposal deleted it out from under the twin.
    @Test func rollingOverOneOfTwoSameIDTasksLeavesItsTwinInTheBlock() throws {
        let modelContext = try makeContext()
        let (survivor, copy, bundle) = try sameIDTwinsInABlock(modelContext)

        CadenceTaskMutationSupport.rollOverTaskToToday(copy, todayKey: "2026-08-20", modelContext: modelContext)

        #expect(copy.bundle == nil)
        #expect((bundle.tasks ?? []).count == 1 && bundle.tasks?.first === survivor, "the twin left the block")
        #expect(survivor.bundle === bundle)
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1, "the block was disposed of")
    }

    /// The shared "take this task out of its block", which has no caller today but is still the
    /// spelling a new one would reach for.
    @Test func removingOneOfTwoSameIDTasksFromABlockLeavesItsTwinThere() throws {
        let modelContext = try makeContext()
        let (survivor, copy, bundle) = try sameIDTwinsInABlock(modelContext)

        CadenceTaskMutationSupport.removeTaskFromBundle(copy, modelContext: modelContext)

        #expect(copy.bundle == nil)
        #expect((bundle.tasks ?? []).count == 1 && bundle.tasks?.first === survivor, "the twin left the block")
    }
}
