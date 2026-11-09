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

    /// **[[T-6581]]: `0` is "no estimate" and is stored as itself.** The five-minute floor is for a
    /// length too short to draw; it used to turn the Estimate row's None into five minutes on every
    /// composer that offers None. A one-minute estimate still floors (the test above).
    @Test func insertTaskStoresAnEstimateOfNoneAsZero() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let draft = TaskCreationDraft(
            title: "No estimate",
            notes: "",
            priority: .none,
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "2026-06-18",
            subtaskTitles: [],
            tags: [],
            scheduledStartMin: 600,
            estimatedMinutes: 0
        )
        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))
        try modelContext.save()
        #expect(task.estimatedMinutes == 0)
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

    // MARK: - [[T-14522]]: a new task lands last in its own list under Custom order

    private func draft(_ title: String, into container: TaskContainerSelection) -> TaskCreationDraft {
        TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: container,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
    }

    /// A drag renumbers a list `0...n-1`. A new task left at `order` `0` tied the top row and the
    /// `createdAt` tie-break put it second; it must sort last, in a list and in the Inbox alike,
    /// and take its own list's next order rather than the app-wide one.
    @Test func aNewTaskSortsLastUnderCustomOrderAfterAListWasRenumbered() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Home")
        let project = Project(name: "Elsewhere")
        modelContext.insert(area)
        modelContext.insert(project)

        func existing(_ title: String, order: Int, area: Area? = nil, project: Project? = nil) {
            let task = AppTask(title: title)
            task.order = order
            task.area = area
            task.project = project
            modelContext.insert(task)
        }
        // As a drag leaves them: the list and the Inbox each renumbered from 0.
        existing("A0", order: 0, area: area)
        existing("A1", order: 1, area: area)
        existing("A2", order: 2, area: area)
        existing("I0", order: 0)
        existing("I1", order: 1)
        // Another list's high order, which a global allocation would max over.
        existing("Other", order: 90, project: project)
        try modelContext.save()

        let service = TaskCreationService(areas: [area], projects: [project])
        let inArea = try #require(try service.createTask(from: draft("New in area", into: .area(area.id)), into: modelContext))
        let inInbox = try #require(try service.createTask(from: draft("New in inbox", into: .inbox), into: modelContext))

        #expect(inArea.order == 3, "the area's new task did not take that list's next order")
        #expect(inInbox.order == 2, "the Inbox's new task did not take the Inbox's next order")

        let all = try modelContext.fetch(FetchDescriptor<AppTask>())
        let areaRows = all.filter { $0.area?.id == area.id }.taskSorted(by: .custom, direction: .ascending)
        let inboxRows = all.filter { $0.area == nil && $0.project == nil }.taskSorted(by: .custom, direction: .ascending)
        #expect(areaRows.map(\.title) == ["A0", "A1", "A2", "New in area"])
        #expect(inboxRows.map(\.title) == ["I0", "I1", "New in inbox"])
    }

    /// `AIActionService.applyTaskDrafts` inserts several drafts before one commit; each must see
    /// the one inserted before it, so the batch lands last and in the order given.
    @Test func uncommittedInsertionsIntoOneListTakeSuccessiveOrders() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        let top = AppTask(title: "Top")
        top.order = 5
        top.project = project
        modelContext.insert(top)
        try modelContext.save()

        let service = TaskCreationService(areas: [], projects: [project])
        let first = try #require(service.insertion(from: draft("First", into: .project(project.id)), into: modelContext))
        let second = try #require(service.insertion(from: draft("Second", into: .project(project.id)), into: modelContext))
        #expect([first.task.order, second.task.order] == [6, 7])
    }
}
