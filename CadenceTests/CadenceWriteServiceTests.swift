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
            from: CadenceTestTimeZones.pinnedCalendar().date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
        #expect(byDueRange.items.map(\.title) == ["In range"])

        let byScheduledDay = try fixture.readService.listTasks(options: .init(scheduledDate: "2026-8-20"))
        #expect(byScheduledDay.items.map(\.title) == ["In range"])
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
        #expect(try CadenceMCPAuditLogger.recentEntries(limit: 2, logURL: auditURL).items.map(\.tool) == [
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

    // MARK: - T-308: a wrong section name is not a missing one

    @Test func createTaskRejectsASectionNameTheListDoesNotHave() throws {
        let fixture = try Fixture()

        let error = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createTask(options: .init(
                title: "Typo lands somewhere else",
                containerKind: "project",
                containerId: fixture.project.id.uuidString,
                sectionName: "Buildd"
            ))
        }

        #expect(error?.errorDescription == "Invalid sectionName: Buildd. Expected one of: Default, Build.")
        // The whole point: before this, the task existed, in "Default", and the call said success.
        #expect(try fixture.modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    @Test func updateTaskRejectsAWrongSectionNameWithoutTouchingTheTask() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Original")
        task.project = fixture.project
        task.sectionName = "Build"
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let error = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.updateTask(options: .init(
                taskId: task.id.uuidString,
                title: "Renamed",
                sectionName: "Backlogg"
            ))
        }

        #expect(error?.errorDescription == "Invalid sectionName: Backlogg. Expected one of: Default, Build.")
        let detail = try fixture.readService.getTask(taskID: task.id.uuidString)
        #expect(detail.summary.sectionName == "Build")
        #expect(detail.summary.title == "Original")
    }

    @Test func anAbsentSectionNameStillFallsBackToTheListDefault() throws {
        let fixture = try Fixture()

        let detail = try fixture.writeService.createTask(options: .init(
            title: "No section asked for",
            containerKind: "project",
            containerId: fixture.project.id.uuidString
        ))

        #expect(detail.summary.sectionName == TaskSectionDefaults.defaultName)
        #expect(detail.summary.container?.id == fixture.project.id.uuidString)
    }

    @Test func aSectionNameMatchesTheListSpellingRegardlessOfCase() throws {
        let fixture = try Fixture()

        let detail = try fixture.writeService.createTask(options: .init(
            title: "Case insensitive",
            containerKind: "project",
            containerId: fixture.project.id.uuidString,
            sectionName: "  bUiLd "
        ))

        #expect(detail.summary.sectionName == "Build")
    }

    @Test func anInboxTaskAcceptsOnlyTheDefaultSectionName() throws {
        let fixture = try Fixture()

        let error = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createTask(options: .init(title: "Inbox", sectionName: "Build"))
        }
        #expect(error?.errorDescription == "Invalid sectionName: Build. An inbox task has no sections.")

        let detail = try fixture.writeService.createTask(options: .init(title: "Inbox", sectionName: "default"))
        #expect(detail.summary.sectionName == TaskSectionDefaults.defaultName)
        #expect(detail.summary.container == nil)
    }

    // MARK: - T-799: minting the container a task can be filed into

    /// The whole point of the ticket, end to end: before this, `create_task` took a `containerId`
    /// the MCP surface had no way to produce, so seeding a kanban board had to be clicked.
    ///
    /// The last two assertions are what make this behavioural rather than decorative.
    /// `createTask` refuses a `sectionName` the target list does not carry, so a card landing in
    /// "In Progress" proves the columns reached the *store* and not merely the response — and the
    /// refusal names all four columns, Default included, which is the normaliser's doing.
    @Test func aBoardCanBeSeededEndToEndAndTasksFiledIntoItsColumns() throws {
        let fixture = try Fixture()

        let context = try fixture.writeService.createContext(options: .init(name: "  Seeded  "))
        #expect(context.context.name == "Seeded")

        let board = try fixture.writeService.createContainer(options: .init(
            containerKind: "project",
            name: "Launch board",
            description: "Seeded from MCP.",
            contextId: context.context.id,
            sectionNames: ["Backlog", "In Progress", "Shipped"]
        ))

        #expect(board.container.kind == "project")
        #expect(board.container.name == "Launch board")
        #expect(board.container.contextId == context.context.id)
        #expect(board.sections.map(\.name) == ["Default", "Backlog", "In Progress", "Shipped"])

        let card = try fixture.writeService.createTask(options: .init(
            title: "First card",
            containerKind: "project",
            containerId: board.container.id,
            sectionName: "in progress"
        ))
        #expect(card.summary.sectionName == "In Progress")
        #expect(card.summary.container?.id == board.container.id)

        let error = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createTask(options: .init(
                title: "Stray card",
                containerKind: "project",
                containerId: board.container.id,
                sectionName: "Nowhere"
            ))
        }
        #expect(error?.errorDescription == "Invalid sectionName: Nowhere. Expected one of: Default, Backlog, In Progress, Shipped.")
    }

    /// An area declares neither an owning area nor a due date, so a request carrying one is a
    /// misunderstanding of the shape. It is refused rather than dropped for the reason
    /// `normalizedSectionName` gives about a mistyped section: the caller sees only "success".
    ///
    /// Both refusals fire on the *requested text*, before resolution — the `areaId` here names an
    /// area that really exists, and the answer is still about the shape and not about the id.
    @Test func anAreaRefusesTheTwoArgumentsOnlyAProjectHas() throws {
        let fixture = try Fixture()
        let owner = try fixture.writeService.createContainer(options: .init(
            containerKind: "area",
            name: "Owner"
        ))

        let nested = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "area",
                name: "Nested",
                areaId: owner.container.id
            ))
        }
        #expect(nested?.errorDescription == "areaId applies to a project; an area cannot be filed inside another area.")

        let dated = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "area",
                name: "Dated",
                dueDate: "2026-04-30"
            ))
        }
        #expect(dated?.errorDescription == "dueDate applies to a project; an area is ongoing and carries no due date.")

        // Neither refusal left a half-made list behind.
        let containers = try fixture.readService.listContainers(limit: 200)
        #expect(containers.items.map(\.name).sorted() == ["Cadence MCP", "Owner"])

        // The same two arguments are accepted on a project, which is what makes the refusal a
        // rule about the kind rather than about the arguments being unsupported anywhere.
        let project = try fixture.writeService.createContainer(options: .init(
            containerKind: "project",
            name: "Nested project",
            areaId: owner.container.id,
            dueDate: "2026-04-30"
        ))
        #expect(project.container.kind == "project")
        let stored = try #require(try fixture.modelContext.fetch(FetchDescriptor<Project>()).first { $0.name == "Nested project" })
        #expect(stored.area?.id.uuidString == owner.container.id)
        #expect(stored.dueDate == "2026-04-30")
    }

    /// `Area.normalizedSectionConfigs` drops a blank column name and a case-insensitive duplicate
    /// silently — correct for a setter that has to survive the legacy `sectionNamesRaw` fallback,
    /// and wrong as an answer to an API request. A caller asking for four columns and getting
    /// three back under a "success" has been told nothing.
    @Test func blankAndDuplicateColumnNamesAreRefusedRatherThanSilentlyDropped() throws {
        let fixture = try Fixture()

        let blank = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "project",
                name: "Blank column",
                sectionNames: ["Backlog", "   "]
            ))
        }
        #expect(blank?.errorDescription == "Section names must not be empty.")

        let duplicate = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "project",
                name: "Duplicate column",
                sectionNames: ["Backlog", " backlog "]
            ))
        }
        #expect(duplicate?.errorDescription == "Duplicate section name: backlog. Section names must be unique within one list.")

        let containers = try fixture.readService.listContainers(limit: 200)
        #expect(containers.items.map(\.name) == ["Cadence MCP"])
    }

    /// `TagSupport.normalizedColorHex` falls back, which is right beside a colour well the user
    /// watches. MCP has no swatch, so the same grammar has to answer a bad value the other way.
    @Test func anUnparseableColorHexIsRefusedInsteadOfFallingBackToADefault() throws {
        let fixture = try Fixture()

        let error = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createContext(options: .init(name: "Bad colour", colorHex: "#GGGGGG"))
        }
        #expect(error?.errorDescription == "Invalid colorHex: #GGGGGG. Expected a six-digit hex colour such as #4a9eff.")

        // The same grammar as the tag editors: a missing `#` is accepted and the result is
        // lower-cased, so the two surfaces cannot disagree about what a colour is.
        let created = try fixture.writeService.createContext(options: .init(name: "Good colour", colorHex: " 4A9EFF "))
        #expect(created.context.colorHex == "#4a9eff")

        // Omitted entirely leaves the model's own default rather than a value restated here.
        let plain = try fixture.writeService.createContext(options: .init(name: "Plain"))
        #expect(plain.context.colorHex == Context(name: "probe").colorHex)
        #expect(plain.context.icon == Context(name: "probe").icon)
    }

    /// `CadenceMCPOrdering.precedes` breaks an `order` tie on the *name*, so a new row left at the
    /// model default of 0 interleaves alphabetically with everything already at 0 instead of
    /// landing at the end. Areas and projects share one sequence per context, and `nil == nil` is
    /// the unfiled bucket — `CreateListSheet.nextListOrder` spells the same rule.
    @Test func newContextsAndListsNumberThemselvesPastTheirSiblings() throws {
        let fixture = try Fixture()
        fixture.context.order = 4
        fixture.project.order = 7
        try fixture.modelContext.save()

        let context = try fixture.writeService.createContext(options: .init(name: "Second context"))
        #expect(context.context.order == 5)

        let filed = try fixture.writeService.createContainer(options: .init(
            containerKind: "area",
            name: "Filed area",
            contextId: fixture.context.id.uuidString
        ))
        let filedArea = try #require(try fixture.modelContext.fetch(FetchDescriptor<Area>()).first { $0.name == "Filed area" })
        #expect(filedArea.order == 8)
        #expect(filed.container.contextId == fixture.context.id.uuidString)

        // The unfiled bucket numbers from its own siblings, not from the filed ones.
        let unfiled = try fixture.writeService.createContainer(options: .init(containerKind: "project", name: "Unfiled project"))
        let unfiledProject = try #require(try fixture.modelContext.fetch(FetchDescriptor<Project>()).first { $0.name == "Unfiled project" })
        #expect(unfiledProject.order == 0)
        #expect(unfiled.container.contextId == nil)
    }

    /// The audit log is the write path's only record, and the smoke test fails a write tool that
    /// mutates without landing in it. `entityType` is the container's own kind rather than a flat
    /// "container", so the log distinguishes an area from a project the way every other MCP
    /// surface does.
    @Test func creatingAContextAndAContainerIsAudited() throws {
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-mcp-create-audit-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: auditURL) }
        let fixture = try Fixture(auditLogger: CadenceMCPAuditLogger(logURL: auditURL))

        let context = try fixture.writeService.createContext(options: .init(name: "Audited context"))
        let area = try fixture.writeService.createContainer(options: .init(containerKind: "area", name: "Audited area"))
        _ = try fixture.writeService.createContainer(options: .init(containerKind: "project", name: "Audited project"))

        let entries = try readAuditEntries(from: auditURL)
        #expect(entries.map(\.tool) == ["create_context", "create_container", "create_container"])
        #expect(entries.map(\.summary) == [
            "Created context: Audited context",
            "Created area: Audited area",
            "Created project: Audited project",
        ])
        #expect(entries.map(\.entityType) == ["context", "area", "project"])
        #expect(entries[0].entityId == context.context.id)
        #expect(entries[1].entityId == area.container.id)
    }

    /// An unknown `contextId` or `areaId` is the container's own not-found error, one level up
    /// from `create_task`'s — and nothing is inserted on the way to raising it.
    @Test func anUnknownParentIsRefusedBeforeAnythingIsInserted() throws {
        let fixture = try Fixture()
        let missing = UUID().uuidString

        let unknownContext = #expect(throws: CadenceReadError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "area",
                name: "Orphan",
                contextId: missing
            ))
        }
        #expect(unknownContext?.errorDescription == "No context found with id \(missing).")

        let unknownArea = #expect(throws: CadenceReadError.self) {
            try fixture.writeService.createContainer(options: .init(
                containerKind: "project",
                name: "Orphan",
                areaId: missing
            ))
        }
        #expect(unknownArea?.errorDescription == "No area found with id \(missing).")

        let containers = try fixture.readService.listContainers(limit: 200)
        #expect(containers.items.map(\.name) == ["Cadence MCP"])
    }

    // MARK: - T-307: an unreadable tag table is a failure, not "no tags"

    @Test func unreadableTagsFailTheWriteInsteadOfSilentlyChangingNothing() throws {
        let resolvedTag = Cadence.Tag(name: "bug", slug: "bug")

        #expect(try CadenceMCPServiceSupport.requiredTags([resolvedTag]).map(\.slug) == ["bug"])
        #expect(try CadenceMCPServiceSupport.requiredTags([]).isEmpty)

        let error = #expect(throws: CadenceWriteError.self) {
            try CadenceMCPServiceSupport.requiredTags(nil)
        }
        #expect(error?.errorDescription == "Tags could not be read, so nothing was written.")
    }

    @Test func aTagOnlyUpdateReplacesTheTagsItReportsBack() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Tag me")
        fixture.modelContext.insert(task)
        try fixture.modelContext.save()

        let first = try fixture.writeService.updateTask(options: .init(
            taskId: task.id.uuidString,
            tagNames: ["bug", "Feature"]
        ))
        #expect(first.summary.tags.map(\.slug) == ["bug", "feature"])

        let cleared = try fixture.writeService.updateTask(options: .init(
            taskId: task.id.uuidString,
            tagNames: []
        ))
        #expect(cleared.summary.tags.isEmpty)
    }

    // MARK: - update_container_columns (T-1095)

    /// **A renamed column takes its cards with it, and that is the half of this tool that is not
    /// about columns at all.** `AppTask.sectionName` is a plain string, so nothing in SwiftData
    /// re-points a card when the column it names is renamed. Without
    /// `CadenceSectionEditingSupport.applySectionNameChanges` the card would be left naming a
    /// column no list has, and `CadenceReadService.sectionSummaries` would answer it back as a
    /// *phantom* column beside the renamed one — which is why this asserts the whole name list and
    /// not just that "Doing" appeared.
    @Test func renamingAColumnReFilesTheCardsThatNameIt() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()
        let card = try fixture.writeService.createTask(options: .init(
            title: "Card",
            containerKind: "project",
            containerId: board.container.id,
            sectionName: "In Progress"
        ))

        let renamed = try fixture.writeService.updateContainerColumns(options: .init(
            containerKind: "project",
            containerId: board.container.id,
            columnName: "in progress",
            newName: "  Doing  ",
            colorHex: "f2a65a"
        ))

        #expect(renamed.sections.map(\.name) == ["Default", "Backlog", "Doing", "Shipped"])
        let doing = try #require(renamed.sections.first { $0.name == "Doing" })
        #expect(doing.colorHex == "#f2a65a")
        #expect(doing.taskCount == 1)
        #expect(try fixture.readService.getTask(taskID: card.summary.id).summary.sectionName == "Doing")
    }

    /// Every one of these is a value `Area.normalizedSectionConfigs` or the merge would have
    /// swallowed — a blank name dropped, a duplicate dropped, a lifecycle flag on Default
    /// discarded, a rename to the name already held written as a byte-identical blob. Beside a UI
    /// that is right; as the answer to an API request it is "success" over nothing done.
    @Test func theColumnEditsAListWouldHaveSwallowedAreRefusedInstead() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()

        func refusal(_ options: CadenceUpdateContainerColumnsOptions) -> String? {
            #expect(throws: CadenceWriteError.self) {
                try fixture.writeService.updateContainerColumns(options: options)
            }?.errorDescription
        }
        func options(_ mutate: (inout CadenceUpdateContainerColumnsOptions) -> Void) -> CadenceUpdateContainerColumnsOptions {
            var value = CadenceUpdateContainerColumnsOptions(
                containerKind: "project",
                containerId: board.container.id
            )
            mutate(&value)
            return value
        }

        #expect(refusal(options { _ in }) == "No valid changes were provided.")
        #expect(refusal(options { $0.columnName = "Backlog" }) != nil)
        #expect(refusal(options { $0.newName = "Orphan" }) != nil)
        #expect(
            refusal(options { $0.columnName = "Backlog"; $0.newName = "   " })
                == "Section names must not be empty."
        )
        #expect(
            refusal(options { $0.columnName = "Backlog"; $0.newName = "shipped" })
                == "Duplicate section name: shipped. Section names must be unique within one list."
        )
        #expect(
            refusal(options { $0.columnName = "Nowhere"; $0.newName = "Somewhere" })
                == "No column named Nowhere on this list. Expected one of: Default, Backlog, In Progress, Shipped."
        )
        #expect(refusal(options { $0.addColumns = ["Backlog"] }) != nil)
        #expect(refusal(options { $0.addColumns = ["Blocked", "blocked"] }) != nil)
        #expect(refusal(options { $0.addColumns = ["   "] }) == "Section names must not be empty.")
        #expect(refusal(options { $0.columnName = "Backlog"; $0.colorHex = "#GGGGGG" }) != nil)
        #expect(
            refusal(options { $0.columnName = "Backlog"; $0.dueDate = "2026-04-30"; $0.clearDueDate = true })
                == "dueDate and clearDueDate cannot both be sent for one column."
        )
        // A request the list would store byte-identically is not a success with no effect. The
        // trim happens first, so this is the *same* name and `mutateSectionConfigs` declines it.
        #expect(
            refusal(options { $0.columnName = "Backlog"; $0.newName = "  Backlog  " })
                == "No valid changes were provided."
        )
        // Nothing survived any of it.
        #expect(try fixture.readService.containerSummary(kind: "project", id: board.container.id)
            .sections.map(\.name) == ["Default", "Backlog", "In Progress", "Shipped"])
    }

    /// The Default column is not one the user made: the list synthesises it, forces it to index 0,
    /// forces both lifecycle flags false, and `AppTask.resolvedSectionName` funnels every
    /// sectionless task into it. So a rename would leave *two* columns and a lifecycle flag would
    /// be discarded — both refused rather than performed and reported.
    @Test func theDefaultColumnRefusesTheThreeThingsTheListWouldUndoAnyway() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()

        func refusal(_ mutate: (inout CadenceUpdateContainerColumnsOptions) -> Void) -> String? {
            var options = CadenceUpdateContainerColumnsOptions(
                containerKind: "project",
                containerId: board.container.id,
                columnName: TaskSectionDefaults.defaultName
            )
            mutate(&options)
            return #expect(throws: CadenceWriteError.self) {
                try fixture.writeService.updateContainerColumns(options: options)
            }?.errorDescription
        }

        #expect(refusal { $0.newName = "Inbox" }?.contains("cannot be renamed") == true)
        #expect(refusal { $0.isArchived = true }?.contains("carries no isCompleted or isArchived") == true)
        #expect(refusal { $0.isCompleted = true }?.contains("carries no isCompleted or isArchived") == true)
        // A colour is not one of the three: the list keeps it.
        let recoloured = try fixture.writeService.updateContainerColumns(options: .init(
            containerKind: "project",
            containerId: board.container.id,
            columnName: TaskSectionDefaults.defaultName,
            colorHex: "#123456"
        ))
        #expect(recoloured.sections.first?.colorHex == "#123456")
    }

    /// Adding and reordering in one call, and the two refusals that keep a reorder from being
    /// guessed at: a partial order, and a Default the list would move back to the front anyway.
    @Test func columnsAreAddedAndReorderedInOneWriteOrNotAtAll() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()

        let reshaped = try fixture.writeService.updateContainerColumns(options: .init(
            containerKind: "project",
            containerId: board.container.id,
            addColumns: ["Blocked"],
            columnOrder: ["Default", "Blocked", "In Progress", "Backlog", "Shipped"]
        ))
        #expect(reshaped.sections.map(\.name) == ["Default", "Blocked", "In Progress", "Backlog", "Shipped"])

        let partial = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.updateContainerColumns(options: .init(
                containerKind: "project",
                containerId: board.container.id,
                columnOrder: ["Default", "Blocked"]
            ))
        }
        #expect(partial?.errorDescription?.contains("left out In Progress, Backlog, Shipped") == true)

        let misplacedDefault = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.updateContainerColumns(options: .init(
                containerKind: "project",
                containerId: board.container.id,
                columnOrder: ["Blocked", "Default", "In Progress", "Backlog", "Shipped"]
            ))
        }
        #expect(misplacedDefault?.errorDescription?.contains("must start with Default") == true)
        #expect(try fixture.readService.containerSummary(kind: "project", id: board.container.id)
            .sections.map(\.name) == ["Default", "Blocked", "In Progress", "Backlog", "Shipped"])
    }

    /// Archiving is the reversible thing this tool offers in place of removal: the column stays in
    /// the blob with its colour and its cards, and only drops out of `sectionNames` — which is the
    /// list `create_task` validates a `sectionName` against.
    @Test func archivingAColumnHidesItFromNewCardsWithoutLosingIt() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()
        _ = try fixture.writeService.createTask(options: .init(
            title: "Shipped card",
            containerKind: "project",
            containerId: board.container.id,
            sectionName: "Shipped"
        ))

        let archived = try fixture.writeService.updateContainerColumns(options: .init(
            containerKind: "project",
            containerId: board.container.id,
            columnName: "Shipped",
            isArchived: true
        ))
        let shipped = try #require(archived.sections.first { $0.name == "Shipped" })
        #expect(shipped.isArchived)
        #expect(shipped.taskCount == 1)

        let refused = #expect(throws: CadenceWriteError.self) {
            try fixture.writeService.createTask(options: .init(
                title: "Another",
                containerKind: "project",
                containerId: board.container.id,
                sectionName: "Shipped"
            ))
        }
        #expect(refused?.errorDescription == "Invalid sectionName: Shipped. Expected one of: Default, Backlog, In Progress.")

        // An archived column is still addressable, which is the only way back.
        let restored = try fixture.writeService.updateContainerColumns(options: .init(
            containerKind: "project",
            containerId: board.container.id,
            columnName: "Shipped",
            isArchived: false
        ))
        #expect(try #require(restored.sections.first { $0.name == "Shipped" }).isArchived == false)
    }

    /// **The undo this side of the MCP boundary has never had.** The write service holds one
    /// long-lived `ModelContext`, so a refused `save()` used to leave the mutation pending for the
    /// next tool call's `save()` to commit — a rename the caller was told had failed, landing
    /// later, from a call that never mentioned it. Both halves go back: the columns, and the cards
    /// the rename re-filed.
    @Test func aRefusedCommitPutsTheColumnsAndTheCardsBack() throws {
        let fixture = try Fixture()
        let board = try fixture.seedBoard()
        let card = try fixture.writeService.createTask(options: .init(
            title: "Card",
            containerKind: "project",
            containerId: board.container.id,
            sectionName: "In Progress"
        ))

        let refusing = CadenceWriteService(
            context: fixture.modelContext,
            preparesStore: false,
            commit: { _ in throw CommitRefused() }
        )
        #expect(throws: CommitRefused.self) {
            try refusing.updateContainerColumns(options: .init(
                containerKind: "project",
                containerId: board.container.id,
                columnName: "In Progress",
                newName: "Doing"
            ))
        }

        let after = try fixture.readService.containerSummary(kind: "project", id: board.container.id)
        #expect(after.sections.map(\.name) == ["Default", "Backlog", "In Progress", "Shipped"])
        #expect(try fixture.readService.getTask(taskID: card.summary.id).summary.sectionName == "In Progress")
    }

    private struct CommitRefused: Error {}

    private func readAuditEntries(from url: URL) throws -> [TestAuditEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try content
            .split(separator: "\n")
            .map { try JSONDecoder().decode(TestAuditEntry.self, from: Data($0.utf8)) }
    }

    private struct TestAuditEntry: Decodable {
        let timestamp: String
        let tool: String
        /// Decoded since T-799, so `create_container`'s "area" / "project" is checked rather than
        /// assumed. Every existing entry carries one — `CadenceMCPAuditEntry` declares it
        /// non-optional — so making it non-optional here narrows nothing.
        let entityType: String
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

        /// A project with the three named columns plus the synthesised `Default`, minted over the
        /// same surface a caller would use.
        func seedBoard() throws -> CadenceContainerSummary {
            try writeService.createContainer(options: .init(
                containerKind: "project",
                name: "Launch board",
                sectionNames: ["Backlog", "In Progress", "Shipped"]
            ))
        }
    }
}
