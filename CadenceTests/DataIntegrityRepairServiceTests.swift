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

    @Test func duplicateCanonicalNotesAreMergedWithoutDroppingContentOrTags() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let area = Area(name: "Writing")
        let project = Project(name: "Review")
        let tagA = Tag(name: "daily", order: 1)
        let tagB = Tag(name: "review", order: 2)
        let older = Note(
            kind: .daily,
            title: "Untitled",
            content: "Morning plan",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            dateKey: "2026-04-29",
            area: area
        )
        older.tags = [tagA]
        let newer = Note(
            kind: .daily,
            title: "Daily Review",
            content: "Evening notes",
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 300),
            dateKey: "2026-04-29",
            project: project
        )
        newer.tags = [tagB]

        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(tagA)
        modelContext.insert(tagB)
        modelContext.insert(older)
        modelContext.insert(newer)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 1)
        #expect(notes.count == 1)
        #expect(notes.first?.dateKey == "2026-04-29")
        #expect(notes.first?.content.contains("Morning plan") == true)
        #expect(notes.first?.content.contains("Evening notes") == true)
        #expect(notes.first?.area === area)
        #expect(notes.first?.project === project)
        #expect(Set(notes.first?.tags?.map(\.slug) ?? []) == ["daily", "review"])
    }

    @Test func unkeyedMeetingNotesAreNotMerged() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let first = Note(kind: .meeting, title: "First", content: "One")
        let second = Note(kind: .meeting, title: "Second", content: "Two")

        modelContext.insert(first)
        modelContext.insert(second)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 0)
        #expect(notes.count == 2)
    }
}
