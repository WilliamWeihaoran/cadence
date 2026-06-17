import SwiftData
import Testing
@testable import Cadence

@MainActor
struct TaskCreationServiceTests {
    @Test func insertTaskAppliesContainerDefaultsAndDraftFields() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Operations", context: context)
        area.sectionNames = [TaskSectionDefaults.defaultName, "Review"]
        let tagA = Tag(name: "Deep Work")
        let tagB = Tag(name: "Admin")
        tagB.order = -1
        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(tagA)
        modelContext.insert(tagB)
        try modelContext.save()

        let draft = TaskCreationDraft(
            title: "!!! Draft launch note",
            notes: "  From markdown.  ",
            priority: .low,
            container: .area(area.id),
            sectionName: "review",
            dueDateKey: "2026-06-20",
            scheduledDateKey: "2026-06-18",
            subtaskTitles: [" First pass ", "", "Ship"],
            tags: [tagA, tagB],
            scheduledStartMin: 600,
            estimatedMinutes: 1
        )

        let task = try #require(TaskCreationService(areas: [area], projects: [])
            .insertTask(from: draft, into: modelContext))
        try modelContext.save()

        #expect(task.title == "Draft launch note")
        #expect(task.notes == "From markdown.")
        #expect(task.priority == .high)
        #expect(task.area?.id == area.id)
        #expect(task.project == nil)
        #expect(task.context?.id == context.id)
        #expect(task.sectionName == "Review")
        #expect(task.dueDate == "2026-06-20")
        #expect(task.scheduledDate == "2026-06-18")
        #expect(task.scheduledStartMin == 600)
        #expect(task.estimatedMinutes == 5)
        #expect(task.sortedTags.map(\.name) == ["Admin", "Deep Work"])
        #expect((task.subtasks ?? []).sorted { $0.order < $1.order }.map(\.title) == ["First pass", "Ship"])
    }

    @Test func insertTaskClearsTimeWhenTaskIsUnscheduled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let draft = TaskCreationDraft(
            title: "Inbox capture",
            notes: "",
            priority: .none,
            container: .inbox,
            sectionName: "Missing",
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: [],
            scheduledStartMin: 720,
            estimatedMinutes: 30
        )

        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.area == nil)
        #expect(task.project == nil)
        #expect(task.context == nil)
        #expect(task.sectionName == TaskSectionDefaults.defaultName)
        #expect(task.scheduledStartMin == -1)
    }
}
