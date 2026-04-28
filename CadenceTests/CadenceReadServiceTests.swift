import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceReadServiceTests {
    @Test func coreNotesDoesNotCreateMissingNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let service = CadenceReadService(container: container)

        let snapshot = try service.coreNotes(dateKey: "2026-04-28")

        #expect(snapshot.dateKey == "2026-04-28")
        #expect(snapshot.dailyNote == nil)
        #expect(snapshot.weeklyNote == nil)
        #expect(snapshot.permanentNote == nil)
    }

    @Test func listTasksFiltersByScheduleContainerAndCompletion() throws {
        let fixture = try Fixture()
        let todayTask = AppTask(title: "Write MCP bridge")
        todayTask.project = fixture.project
        todayTask.context = fixture.context
        todayTask.scheduledDate = "2026-04-28"
        todayTask.scheduledStartMin = 600
        fixture.modelContext.insert(todayTask)

        let doneTask = AppTask(title: "Old completed task")
        doneTask.project = fixture.project
        doneTask.context = fixture.context
        doneTask.status = .done
        doneTask.scheduledDate = "2026-04-28"
        fixture.modelContext.insert(doneTask)
        try fixture.modelContext.save()

        let results = try fixture.service.listTasks(options: .init(
            scheduledDate: "2026-04-28",
            containerKind: "project",
            containerId: fixture.project.id.uuidString,
            textQuery: "bridge",
            limit: 50
        ))

        #expect(results.map(\.title) == ["Write MCP bridge"])
    }

    @Test func blockedTasksExposeUnresolvedDependencies() throws {
        let fixture = try Fixture()
        let blocker = AppTask(title: "Decide DTO names")
        let blocked = AppTask(title: "Implement tools")
        blocked.dependencyTaskIDs = [blocker.id]
        fixture.modelContext.insert(blocker)
        fixture.modelContext.insert(blocked)
        try fixture.modelContext.save()

        let blockedTasks = try fixture.service.blockedTasks()

        #expect(blockedTasks.count == 1)
        #expect(blockedTasks.first?.task.title == "Implement tools")
        #expect(blockedTasks.first?.unresolvedDependencies.first?.title == "Decide DTO names")
    }

    @Test func containerSummaryCountsTasksAndDocuments() throws {
        let fixture = try Fixture()
        let active = AppTask(title: "Active")
        active.project = fixture.project
        let complete = AppTask(title: "Complete")
        complete.project = fixture.project
        complete.status = .done
        let doc = Document(title: "Spec")
        doc.project = fixture.project

        fixture.modelContext.insert(active)
        fixture.modelContext.insert(complete)
        fixture.modelContext.insert(doc)
        try fixture.modelContext.save()

        let summary = try fixture.service.containerSummary(kind: "project", id: fixture.project.id.uuidString)

        #expect(summary.activeTaskCount == 1)
        #expect(summary.completedTaskCount == 1)
        #expect(summary.documents.map(\.title) == ["Spec"])
    }

    @Test func searchHonorsScopes() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Deep work block")
        let doc = Document(title: "Deep research notes")
        doc.content = "Long-form thinking about MCP"
        fixture.modelContext.insert(task)
        fixture.modelContext.insert(doc)
        try fixture.modelContext.save()

        let taskHits = try fixture.service.search(query: "deep", scopes: ["tasks"])
        let docHits = try fixture.service.search(query: "deep", scopes: ["documents"])

        #expect(taskHits.map(\.entityType) == ["task"])
        #expect(docHits.map(\.entityType) == ["document"])
    }

    @Test func invalidEnumsAndPartialContainerFiltersThrow() throws {
        let fixture = try Fixture()

        #expect(throws: CadenceReadError.self) {
            try fixture.service.search(query: "cadence", scopes: ["events"])
        }

        #expect(throws: CadenceReadError.self) {
            try fixture.service.listTasks(options: .init(statuses: ["not-a-status"]))
        }

        #expect(throws: CadenceReadError.self) {
            try fixture.service.listDocuments(containerKind: "project")
        }
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let service: CadenceReadService
        let context: Context
        let project: Project

        init() throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)
            service = CadenceReadService(container: container)
            context = Context(name: "Work")
            project = Project(name: "Cadence MCP", context: context)
            modelContext.insert(context)
            modelContext.insert(project)
            try modelContext.save()
        }
    }
}
