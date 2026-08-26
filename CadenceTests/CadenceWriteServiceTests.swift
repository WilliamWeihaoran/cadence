import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceWriteServiceTests {
    @Test func createTaskValidatesAndReturnsDetail() throws {
        let fixture = try Fixture()

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
            subtaskTitles: [" DTOs ", "", "Router"],
            tagNames: ["bug", "Feature"]
        ))

        #expect(detail.summary.title == "Ship write MCP")
        #expect(detail.summary.priority == "high")
        #expect(detail.summary.dueDate == "2026-04-30")
        #expect(detail.summary.scheduledDate == "2026-04-28")
        #expect(detail.summary.scheduledStartMin == 540)
        #expect(detail.summary.estimatedMinutes == 45)
        #expect(detail.summary.container?.id == fixture.project.id.uuidString)
        #expect(detail.summary.sectionName == "Build")
        #expect(detail.summary.tags.map(\.slug) == ["bug", "feature"])
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
        // T-202: a cancellation is timestamped like a completion, so the MCP task DTO reports one.
        // The response *shape* is unchanged — `completedAt` was always an optional string — but the
        // value a cancelled task carries is new.
        #expect(cancelled.completedAt != nil)
    }

    /// T-202 regression guard. Both cancel guards used to read
    /// `status != .cancelled || completedAt != nil`, which was "not already in the canonical
    /// cancelled state" only while that state had a nil timestamp. Now that a cancellation is
    /// timestamped, the second clause is true of every cancelled task, so an unfixed guard would
    /// re-stamp `completedAt` and append a second audit entry on every repeat call.
    ///
    /// **T-228: the re-stamp half is asserted on the stored `Date`, not on the DTO string.**
    /// `CadenceReadService` formats `completedAt` through a default `ISO8601DateFormatter`, which
    /// is second-precision, so a re-stamp microseconds later serialises to an identical string and
    /// a DTO comparison sees nothing. That left the guard's two halves unevenly covered: a mutation
    /// that re-stamped *and* re-audited was caught by the audit assertions, and one that only
    /// re-stamped was not caught at all.
    @Test func cancellingAnAlreadyCancelledTaskChangesAndAuditsNothing() throws {
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-cancel-idempotent-\(UUID().uuidString)")
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: auditURL) }

        let fixture = try Fixture(auditLogger: CadenceMCPAuditLogger(logURL: auditURL))
        let task = AppTask(title: "MCP TEST abandon me")
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let first = try fixture.writeService.cancelTask(taskID: task.id.uuidString)
        #expect(first.completedAt != nil)
        // The model's own `Date`, captured from the same context the write service mutates. This is
        // the assertion that can see a re-stamp; the DTO string below cannot.
        let stamp = try #require(task.completedAt)

        let second = try fixture.writeService.cancelTask(taskID: task.id.uuidString)

        #expect(task.completedAt == stamp)
        #expect(second.completedAt == first.completedAt)
        #expect(try readAuditEntries(from: auditURL).map(\.tool) == ["cancel_task"])

        // …and the same for the bulk path, which filters on the same guard. It still reports the
        // task as cancelled — that is its contract — but must neither re-stamp nor re-audit it.
        let bulk = try fixture.writeService.bulkCancelTasks(options: .init(taskIds: [task.id.uuidString]))
        #expect(bulk.cancelledTasks.map(\.title) == ["MCP TEST abandon me"])
        #expect(task.completedAt == stamp)
        #expect(try fixture.readService.getTask(taskID: task.id.uuidString).completedAt == first.completedAt)
        #expect(try readAuditEntries(from: auditURL).map(\.tool) == ["cancel_task"])
    }

    @Test func completeRecurringTaskSpawnsNextTaskWithoutCalendar() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Daily standup")
        task.recurrenceRule = .daily
        task.dueDate = DateFormatters.todayKey()
        task.scheduledDate = DateFormatters.todayKey()
        task.scheduledStartMin = 540
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let result = try fixture.writeService.completeTask(taskID: task.id.uuidString)

        let expectedNextDate = DateFormatters.dateKey(
            from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        #expect(result.task.summary.isDone)
        #expect(result.spawnedRecurringTask?.summary.title == "Daily standup")
        #expect(result.spawnedRecurringTask?.summary.dueDate == expectedNextDate)
        #expect(result.spawnedRecurringTask?.summary.scheduledDate == expectedNextDate)
        #expect(result.spawnedRecurringTask?.summary.scheduledStartMin == 540)
    }

    @Test func cancellingRecurringTaskViaWriteServiceSpawnsNextOccurrenceWithSeriesMetadata() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Daily standup")
        task.recurrenceRule = .daily
        task.scheduledDate = DateFormatters.todayKey()
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let cancelled = try fixture.writeService.cancelTask(taskID: task.id.uuidString)
        #expect(cancelled.summary.isCancelled)

        let spawnedID = try #require(task.recurrenceSpawnedTaskID)
        let next = try fixture.readService.getTask(taskID: spawnedID.uuidString)
        #expect(next.summary.status == "todo")
        #expect(next.summary.title == "Daily standup")
    }

    @Test func bulkCancellingRecurringTasksSpawnsNextOccurrenceWithSeriesMetadata() throws {
        // Regression test: bulkCancelTasks used to set status/completedAt directly instead of
        // routing through CadenceTaskRecurrenceWorkflowSupport.markCancelled, which meant a
        // bulk-cancelled recurring task never spawned its next occurrence and the whole future
        // series silently died -- unlike the single-task cancelTask path, which already handled
        // this correctly. bulk_cancel_tasks must behave the same way per task.
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-bulk-recurring-audit-\(UUID().uuidString)")
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: auditURL) }

        let fixture = try Fixture(auditLogger: CadenceMCPAuditLogger(logURL: auditURL))
        let recurring = AppTask(title: "MCP TEST daily standup")
        recurring.recurrenceRule = .daily
        recurring.scheduledDate = DateFormatters.todayKey()
        let nonRecurring = AppTask(title: "MCP TEST one-off cleanup")
        fixture.modelContext.insert(recurring)
        fixture.modelContext.insert(nonRecurring)
        try fixture.modelContext.save()

        let result = try fixture.writeService.bulkCancelTasks(options: .init(titlePrefix: "MCP TEST"))
        #expect(result.cancelledTasks.allSatisfy { $0.isCancelled })

        let spawnedID = try #require(recurring.recurrenceSpawnedTaskID)
        let spawned = try fixture.readService.getTask(taskID: spawnedID.uuidString)
        #expect(spawned.summary.status == "todo")
        #expect(spawned.summary.title == "MCP TEST daily standup")
        #expect(nonRecurring.recurrenceSpawnedTaskID == nil)

        let auditEntries = try readAuditEntries(from: auditURL)
        #expect(auditEntries.map(\.tool) == ["bulk_cancel_tasks", "bulk_cancel_tasks", "bulk_cancel_tasks"])
        #expect(auditEntries.contains { $0.summary == "Spawned recurring task from: MCP TEST daily standup" })
        #expect(auditEntries.contains { $0.entityId == spawnedID.uuidString })
    }

    @Test func cancelTaskAuditsSpawnedRecurringTask() throws {
        // Companion regression test for the single-task cancelTask path: it always spawned the
        // next occurrence via CadenceTaskRecurrenceWorkflowSupport.markCancelled, but the audit
        // log only recorded the "Cancelled task" entry, silently omitting that a new task row was
        // also created. completeTask already logs its spawn; cancelTask should match.
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-cancel-spawn-audit-\(UUID().uuidString)")
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: auditURL) }

        let fixture = try Fixture(auditLogger: CadenceMCPAuditLogger(logURL: auditURL))
        let task = AppTask(title: "Daily standup")
        task.recurrenceRule = .daily
        task.scheduledDate = DateFormatters.todayKey()
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        _ = try fixture.writeService.cancelTask(taskID: task.id.uuidString)
        let spawnedID = try #require(task.recurrenceSpawnedTaskID)

        let auditEntries = try readAuditEntries(from: auditURL)
        #expect(auditEntries.map(\.tool) == ["cancel_task", "cancel_task"])
        #expect(auditEntries.first?.summary == "Cancelled task: Daily standup")
        #expect(auditEntries.last?.summary == "Spawned recurring task from: Daily standup")
        #expect(auditEntries.last?.entityId == spawnedID.uuidString)
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

    /// MCP is the one door through which a date reaches the store from outside the app, and every
    /// write arm used to keep the caller's spelling verbatim after validating it by parsing. A task
    /// stored as `"2026-8-20"` is due before the 25th and sorts after it, so it misses "due today",
    /// overdue, grouping and sorting at once with nothing malformed on screen.
    ///
    /// Asserted against the **stored** `AppTask`, not the returned DTO, because the DTO could echo a
    /// normalized string while the model kept the raw one.
    @Test func externallySuppliedDatesAreStoredCanonicallyOnCreateUpdateAndSchedule() throws {
        let fixture = try Fixture()
        let created = try fixture.writeService.createTask(options: .init(
            title: "Lenient dates",
            dueDate: "2026-8-20",
            scheduledDate: "2026-8-2"
        ))
        let taskID = try #require(UUID(uuidString: created.summary.id))
        func stored() throws -> AppTask {
            let tasks = try fixture.modelContext.fetch(FetchDescriptor<AppTask>())
            return try #require(tasks.first { $0.id == taskID })
        }

        #expect(try stored().dueDate == "2026-08-20")
        #expect(try stored().scheduledDate == "2026-08-02")
        // The point of the padding: this comparison is `false` for the string that was sent.
        #expect(try stored().dueDate < "2026-08-25")

        _ = try fixture.writeService.updateTask(options: .init(taskId: created.summary.id, dueDate: "2026-9-1"))
        #expect(try stored().dueDate == "2026-09-01")

        _ = try fixture.writeService.scheduleTask(options: .init(
            taskId: created.summary.id,
            scheduledDate: "2026-9-3",
            scheduledStartMin: 540
        ))
        #expect(try stored().scheduledDate == "2026-09-03")
        #expect(try stored().scheduledStartMin == 540)

        // A two-digit year parses to the year 26 AD. That is a century the caller never chose, so
        // it is an error rather than a silent normalization, and nothing is written.
        #expect(throws: CadenceReadError.self) {
            try fixture.writeService.updateTask(options: .init(taskId: created.summary.id, dueDate: "26-9-2"))
        }
        #expect(try stored().dueDate == "2026-09-01")
    }

    /// The read half of the same defect: these filters compare the caller's text against stored
    /// keys, so an unnormalized bound silently matches nothing instead of failing loudly.
    @Test func listTaskFiltersNormalizeTheirDateBoundsBeforeComparing() throws {
        let fixture = try Fixture()
        _ = try fixture.writeService.createTask(options: .init(
            title: "In range",
            dueDate: "2026-08-20",
            scheduledDate: "2026-08-20"
        ))

        let byDueRange = try fixture.readService.listTasks(options: .init(
            dueDateFrom: "2026-8-1",
            dueDateTo: "2026-8-31"
        ))
        #expect(byDueRange.map(\.title) == ["In range"])

        let byScheduledDay = try fixture.readService.listTasks(options: .init(scheduledDate: "2026-8-20"))
        #expect(byScheduledDay.map(\.title) == ["In range"])
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

    @Test func auditLoggerRecordsSuccessfulWritesAndSkipsInvalidWrites() throws {
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-audit-\(UUID().uuidString)")
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: auditURL) }

        let logger = CadenceMCPAuditLogger(
            logURL: auditURL,
            clock: { Date(timeIntervalSince1970: 1) }
        )
        let fixture = try Fixture(auditLogger: logger)
        let created = try fixture.writeService.createTask(options: .init(title: "Audit me"))
        _ = try fixture.writeService.updateTask(options: .init(taskId: created.summary.id, notes: "Audited update"))
        _ = try fixture.writeService.scheduleTask(options: .init(
            taskId: created.summary.id,
            scheduledDate: "2026-04-28",
            scheduledStartMin: 600
        ))
        _ = try fixture.writeService.completeTask(taskID: created.summary.id)
        _ = try fixture.writeService.reopenTask(taskID: created.summary.id)
        _ = try fixture.writeService.cancelTask(taskID: created.summary.id)
        _ = try fixture.writeService.appendCoreNote(kind: "daily", content: "Audited note", dateKey: "2026-04-28")

        let entries = try readAuditEntries(from: auditURL)
        #expect(entries.map(\.tool) == [
            "create_task",
            "update_task",
            "schedule_task",
            "complete_task",
            "reopen_task",
            "cancel_task",
            "append_core_note",
        ])
        #expect(entries.allSatisfy { $0.timestamp == "1970-01-01T00:00:01Z" })
        #expect(entries.allSatisfy { !$0.entityId.isEmpty })
        #expect(entries.first?.summary == "Created task: Audit me")
        #expect(try CadenceMCPAuditLogger.recentEntries(limit: 2, logURL: auditURL).map(\.tool) == [
            "append_core_note",
            "cancel_task",
        ])

        #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.updateTask(options: .init(
                taskId: created.summary.id,
                priority: "urgent"
            ))
        }
        #expect(try readAuditEntries(from: auditURL).count == entries.count)
    }

    @Test func bulkCancelTasksRequiresSpecificScopeAndAuditsChangedTasks() throws {
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-bulk-audit-\(UUID().uuidString)")
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: auditURL) }

        let fixture = try Fixture(auditLogger: CadenceMCPAuditLogger(logURL: auditURL))
        let first = AppTask(title: "MCP TEST cleanup one")
        let second = AppTask(title: "MCP TEST cleanup two")
        let unrelated = AppTask(title: "Personal cleanup")
        fixture.modelContext.insert(first)
        fixture.modelContext.insert(second)
        fixture.modelContext.insert(unrelated)
        try fixture.modelContext.save()

        #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.bulkCancelTasks(options: .init(titlePrefix: "MCP"))
        }

        let result = try fixture.writeService.bulkCancelTasks(options: .init(titlePrefix: "MCP TEST"))
        #expect(result.cancelledTasks.map(\.title).sorted() == ["MCP TEST cleanup one", "MCP TEST cleanup two"])
        #expect(result.cancelledTasks.allSatisfy { $0.isCancelled })
        #expect(try fixture.readService.getTask(taskID: unrelated.id.uuidString).summary.isCancelled == false)

        let auditEntries = try readAuditEntries(from: auditURL)
        #expect(auditEntries.map(\.tool) == ["bulk_cancel_tasks", "bulk_cancel_tasks"])
        #expect(auditEntries.allSatisfy { $0.summary.hasPrefix("Bulk cancelled task: MCP TEST cleanup") })
    }

    private func readAuditEntries(from url: URL) throws -> [TestAuditEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try content
            .split(separator: "\n")
            .map { try JSONDecoder().decode(TestAuditEntry.self, from: Data($0.utf8)) }
    }

    private struct TestAuditEntry: Decodable {
        let timestamp: String
        let tool: String
        let entityId: String
        let summary: String
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let readService: CadenceReadService
        let writeService: CadenceWriteService
        let context: Context
        let project: Project

        init(auditLogger: CadenceMCPAuditLogger? = nil) throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)
            readService = CadenceReadService(context: modelContext)
            writeService = CadenceWriteService(context: modelContext, auditLogger: auditLogger)
            context = Context(name: "Work")
            project = Project(name: "Cadence MCP", context: context)
            project.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
            modelContext.insert(context)
            modelContext.insert(project)
            try modelContext.save()
        }
    }
}
