import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceWriteServiceTests {
    @Test func createTaskValidatesAndReturnsDetail() throws {
        let fixture = try Fixture()
        let blocker = AppTask(title: "Unblock me")
        fixture.modelContext.insert(blocker)
        try fixture.modelContext.save()

        let detail = try fixture.writeService.createTask(options: .init(
            title: "  Ship write MCP  ",
            notes: "Carefully",
            priority: "high",
            dueDate: "2026-04-30",
            scheduledDate: "2026-04-28",
            scheduledStartMin: 540,
            estimatedMinutes: 45,
            containerKind: "project",
            containerId: fixture.project.id.uuidString,
            sectionName: "Build",
            dependencyTaskIds: [blocker.id.uuidString],
            subtaskTitles: [" DTOs ", "", "Router"]
        ))

        #expect(detail.summary.title == "Ship write MCP")
        #expect(detail.summary.priority == "high")
        #expect(detail.summary.dueDate == "2026-04-30")
        #expect(detail.summary.scheduledDate == "2026-04-28")
        #expect(detail.summary.scheduledStartMin == 540)
        #expect(detail.summary.estimatedMinutes == 45)
        #expect(detail.summary.container?.id == fixture.project.id.uuidString)
        #expect(detail.summary.sectionName == "Build")
        #expect(detail.dependencyTaskIds == [blocker.id.uuidString])
        #expect(detail.subtasks.map(\.title) == ["DTOs", "Router"])
    }

    @Test func updateTaskRejectsInvalidInputWithoutPartialMutation() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Original")
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.updateTask(options: .init(
                taskId: task.id.uuidString,
                title: "Changed",
                priority: "urgent"
            ))
        }

        let detail = try fixture.readService.getTask(taskID: task.id.uuidString)
        #expect(detail.summary.title == "Original")
        #expect(detail.summary.priority == "none")
    }

    @Test func updateTaskCanClearDueDateAndMoveToInbox() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Move me")
        task.project = fixture.project
        task.context = fixture.context
        task.sectionName = "Build"
        task.dueDate = "2026-04-30"
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let detail = try fixture.writeService.updateTask(options: .init(
            taskId: task.id.uuidString,
            clearDueDate: true,
            clearContainer: true
        ))

        #expect(detail.summary.dueDate == "")
        #expect(detail.summary.container == nil)
        #expect(detail.summary.sectionName == TaskSectionDefaults.defaultName)
    }

    @Test func scheduleCompleteReopenAndCancelTask() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Lifecycle")
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let scheduled = try fixture.writeService.scheduleTask(options: .init(
            taskId: task.id.uuidString,
            scheduledDate: "2026-04-28",
            scheduledStartMin: 600,
            estimatedMinutes: 50
        ))
        #expect(scheduled.summary.scheduledDate == "2026-04-28")
        #expect(scheduled.summary.scheduledStartMin == 600)
        #expect(scheduled.summary.estimatedMinutes == 50)

        let completed = try fixture.writeService.completeTask(taskID: task.id.uuidString)
        #expect(completed.task.summary.isDone)
        #expect(completed.spawnedRecurringTask == nil)

        let reopened = try fixture.writeService.reopenTask(taskID: task.id.uuidString)
        #expect(reopened.summary.status == "todo")
        #expect(reopened.completedAt == nil)

        let cancelled = try fixture.writeService.cancelTask(taskID: task.id.uuidString)
        #expect(cancelled.summary.isCancelled)
        #expect(cancelled.completedAt == nil)
    }

    @Test func completeRecurringTaskSpawnsNextTaskWithoutCalendar() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Daily standup")
        task.recurrenceRule = .daily
        task.dueDate = "2026-04-28"
        task.scheduledDate = "2026-04-28"
        task.scheduledStartMin = 540
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let result = try fixture.writeService.completeTask(taskID: task.id.uuidString)

        #expect(result.task.summary.isDone)
        #expect(result.spawnedRecurringTask?.summary.title == "Daily standup")
        #expect(result.spawnedRecurringTask?.summary.dueDate == "2026-04-29")
        #expect(result.spawnedRecurringTask?.summary.scheduledDate == "2026-04-29")
        #expect(result.spawnedRecurringTask?.summary.scheduledStartMin == 540)
    }

    @Test func scheduleTaskClearAndInvalidTime() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Clear schedule")
        task.scheduledDate = "2026-04-28"
        task.scheduledStartMin = 600
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.scheduleTask(options: .init(
                taskId: task.id.uuidString,
                scheduledDate: "2026-04-29",
                scheduledStartMin: 1440
            ))
        }

        let cleared = try fixture.writeService.scheduleTask(options: .init(
            taskId: task.id.uuidString,
            clearScheduledDate: true
        ))
        #expect(cleared.summary.scheduledDate == "")
        #expect(cleared.summary.scheduledStartMin == -1)
    }

    @Test func writeServiceAcceptsNormalizedDateAndDurationInputs() throws {
        let fixture = try Fixture()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowKey = DateFormatters.dateKey(from: tomorrow)
        let task = try fixture.writeService.createTask(options: .init(
            title: "Natural-ish service inputs",
            scheduledDate: tomorrowKey,
            estimatedMinutes: 60
        ))

        #expect(task.summary.scheduledDate == tomorrowKey)
        #expect(task.summary.estimatedMinutes == 60)
    }

    @Test func appendCoreNoteCreatesMissingAndAppendsExistingNotes() throws {
        let fixture = try Fixture()

        let first = try fixture.writeService.appendCoreNote(kind: "daily", content: "First", dateKey: "2026-04-28")
        #expect(first.dailyNote?.content == "First")

        let second = try fixture.writeService.appendCoreNote(kind: "daily", content: "Second", dateKey: "2026-04-28", separator: "\n")
        #expect(second.dailyNote?.content == "First\nSecond")

        let weekly = try fixture.writeService.appendCoreNote(kind: "weekly", content: "Week", dateKey: "2026-04-28")
        #expect(weekly.weeklyNote?.key == "2026-W18")
        #expect(weekly.weeklyNote?.content == "Week")

        let permanent = try fixture.writeService.appendCoreNote(kind: "permanent", content: "Forever", dateKey: "2026-04-28")
        #expect(permanent.permanentNote?.content == "Forever")
    }

    @Test func readCoreNotesStillDoesNotCreateMissingNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let readService = CadenceReadService(container: container)

        let snapshot = try readService.coreNotes(dateKey: "2026-04-28")

        #expect(snapshot.dailyNote == nil)
        #expect(snapshot.weeklyNote == nil)
        #expect(snapshot.permanentNote == nil)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let readService: CadenceReadService
        let writeService: CadenceWriteService
        let context: Context
        let project: Project

        init() throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)
            readService = CadenceReadService(context: modelContext)
            writeService = CadenceWriteService(context: modelContext)
            context = Context(name: "Work")
            project = Project(name: "Cadence MCP", context: context)
            project.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
            modelContext.insert(context)
            modelContext.insert(project)
            try modelContext.save()
        }
    }
}
