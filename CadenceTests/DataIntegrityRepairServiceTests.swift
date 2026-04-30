import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct DataIntegrityRepairServiceTests {
    @Test func duplicateContextsAreMergedWithoutDroppingListsOrTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let oldWork = Context(name: "Work", colorHex: "#4ECB71", icon: "briefcase.fill")
        oldWork.order = 0
        let restoredWork = Context(name: "Work", colorHex: "#22c55e", icon: "briefcase.fill")
        restoredWork.order = 0

        let sharedProjectID = UUID()
        let oldProject = Project(name: "POPSA", context: oldWork)
        oldProject.id = sharedProjectID
        let restoredProject = Project(name: "POPSA", context: restoredWork)
        restoredProject.id = sharedProjectID

        let oldTask = AppTask(title: "Old task")
        oldTask.project = oldProject
        oldTask.context = oldWork
        let restoredTask = AppTask(title: "Restored task")
        restoredTask.project = restoredProject
        restoredTask.context = restoredWork

        let restoredArea = Area(name: "General", context: restoredWork)
        let habit = Habit(title: "Ship", context: oldWork)
        let goal = Goal(title: "Outcome", context: oldWork)

        modelContext.insert(oldWork)
        modelContext.insert(restoredWork)
        modelContext.insert(oldProject)
        modelContext.insert(restoredProject)
        modelContext.insert(oldTask)
        modelContext.insert(restoredTask)
        modelContext.insert(restoredArea)
        modelContext.insert(habit)
        modelContext.insert(goal)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateContextsMerged == 1)
        #expect(report.duplicateProjectsMerged == 1)

        let contexts = try modelContext.fetch(FetchDescriptor<Context>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        let goals = try modelContext.fetch(FetchDescriptor<Goal>())
        let habits = try modelContext.fetch(FetchDescriptor<Habit>())

        #expect(contexts.count == 1)
        #expect(contexts.first?.name == "Work")
        #expect(projects.count == 1)
        #expect(projects.first?.id == sharedProjectID)
        #expect(areas.count == 1)
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.context === contexts.first })
        #expect(tasks.allSatisfy { $0.project === projects.first })
        #expect(areas.first?.context === contexts.first)
        #expect(goals.first?.context === contexts.first)
        #expect(habits.first?.context === contexts.first)
    }
}
