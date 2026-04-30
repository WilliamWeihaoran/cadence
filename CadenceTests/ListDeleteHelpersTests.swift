import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct ListDeleteHelpersTests {
    @Test func deleteContextRemovesDescendantsAndSavesCleanly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let project = Project(name: "Project", context: context, area: area)
        let goal = Goal(title: "Goal", context: context)
        let goalListLink = GoalListLink(goal: goal, area: area)
        let habit = Habit(title: "Habit", context: context, goal: goal)
        let habitCompletion = HabitCompletion(date: "2026-04-29", habit: habit)

        let contextTask = AppTask(title: "Context task")
        contextTask.context = context
        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        areaTask.context = context
        let projectTask = AppTask(title: "Project task")
        projectTask.project = project
        projectTask.context = context
        let goalTask = AppTask(title: "Goal task")
        goalTask.goal = goal
        goalTask.context = context

        let subtask = Subtask(title: "Nested")
        subtask.parentTask = goalTask

        let areaNote = Note(kind: .list, title: "Area doc")
        areaNote.area = area
        let projectNote = Note(kind: .list, title: "Project doc")
        projectNote.project = project
        let areaDocument = Document(title: "Area legacy document")
        areaDocument.area = area
        let projectDocument = Document(title: "Project legacy document")
        projectDocument.project = project
        let noteAsset = MarkdownImageAsset(
            data: Data([1, 2, 3]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
        areaNote.content = "![area](cadence-image://\(noteAsset.id.uuidString))"
        let areaLink = SavedLink(title: "Area link", url: "https://example.com/area")
        areaLink.area = area
        let projectLink = SavedLink(title: "Project link", url: "https://example.com/project")
        projectLink.project = project

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)
        modelContext.insert(goalListLink)
        modelContext.insert(habit)
        modelContext.insert(habitCompletion)
        modelContext.insert(contextTask)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        modelContext.insert(goalTask)
        modelContext.insert(subtask)
        modelContext.insert(areaNote)
        modelContext.insert(projectNote)
        modelContext.insert(areaDocument)
        modelContext.insert(projectDocument)
        modelContext.insert(noteAsset)
        modelContext.insert(areaLink)
        modelContext.insert(projectLink)
        try modelContext.save()

        modelContext.deleteContext(context)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<HabitCompletion>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Document>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<SavedLink>()).isEmpty)
    }

    @Test func deleteUnreferencedMarkdownImageAssetsKeepsAssetsStillReferencedElsewhere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let deletedAsset = MarkdownImageAsset(data: Data([1]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        let retainedAsset = MarkdownImageAsset(data: Data([2]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        let deletedNote = Note(kind: .list, title: "Deleted", content: "![gone](cadence-image://\(deletedAsset.id.uuidString))")
        let retainedNote = Note(kind: .permanent, title: "Retained", content: "![keep](cadence-image://\(retainedAsset.id.uuidString))")

        modelContext.insert(deletedAsset)
        modelContext.insert(retainedAsset)
        modelContext.insert(deletedNote)
        modelContext.insert(retainedNote)
        try modelContext.save()

        modelContext.delete(deletedNote)
        modelContext.deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: [deletedNote.id])
        try modelContext.save()

        let remainingAssets = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(remainingAssets.map(\.id) == [retainedAsset.id])
    }

    @Test func deleteTaskRemovesScheduledCompletedTaskAndSubtasksCleanly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let task = AppTask(title: "Scheduled")
        task.context = context
        task.scheduledDate = "2026-04-29"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 45
        task.calendarEventID = "test-event-id"
        task.status = .done
        task.completedAt = Date()

        let subtask = Subtask(title: "Nested")
        subtask.parentTask = task

        modelContext.insert(context)
        modelContext.insert(task)
        modelContext.insert(subtask)
        try modelContext.save()

        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
    }
}
