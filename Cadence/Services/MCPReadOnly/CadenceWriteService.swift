import Foundation
import SwiftData

nonisolated enum CadenceWriteError: Error, LocalizedError, Sendable {
    case emptyTitle
    case emptyContent
    case emptyName
    case invalidColorHex(String)
    case emptySectionName
    case duplicateSectionName(String)
    case invalidPriority(String)
    case invalidNoteKind(String)
    case invalidScheduledStartMin(Int)
    case invalidEstimatedMinutes(Int)
    case invalidCombination(String)
    case noChanges
    case cannotCompleteCancelledTask(String)
    case sectionNotFound(String, [String])
    case tagsUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Task title must not be empty."
        case .emptyContent:
            return "Note content must not be empty."
        case .emptyName:
            return "Name must not be empty."
        case .invalidColorHex(let value):
            return "Invalid colorHex: \(value). Expected a six-digit hex colour such as #4a9eff."
        case .emptySectionName:
            return "Section names must not be empty."
        case .duplicateSectionName(let name):
            return "Duplicate section name: \(name). Section names must be unique within one list."
        case .invalidPriority(let value):
            return "Invalid priority value: \(value). Expected none, low, medium, or high."
        case .invalidNoteKind(let value):
            return "Invalid note kind: \(value). Expected daily, weekly, or permanent."
        case .invalidScheduledStartMin(let value):
            return "Invalid scheduledStartMin: \(value). Expected 0...1439."
        case .invalidEstimatedMinutes(let value):
            return "Invalid estimatedMinutes: \(value). Expected 1...1440."
        case .invalidCombination(let message):
            return message
        case .noChanges:
            return "No valid changes were provided."
        case .cannotCompleteCancelledTask(let id):
            return "Cancelled task \(id) cannot be completed."
        case .sectionNotFound(let name, let available):
            guard !available.isEmpty else {
                return "Invalid sectionName: \(name). An inbox task has no sections."
            }
            return "Invalid sectionName: \(name). Expected one of: \(available.joined(separator: ", "))."
        case .tagsUnavailable:
            return "Tags could not be read, so nothing was written."
        }
    }
}

nonisolated struct CadenceCreateTaskOptions: Sendable {
    var title: String
    var notes: String? = nil
    var priority: String? = nil
    var dueDate: String? = nil
    var scheduledDate: String? = nil
    var scheduledStartMin: Int? = nil
    var estimatedMinutes: Int? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var sectionName: String? = nil
    var subtaskTitles: [String]? = nil
    var tagNames: [String]? = nil
}

nonisolated struct CadenceUpdateTaskOptions: Sendable {
    var taskId: String
    var title: String? = nil
    var notes: String? = nil
    var priority: String? = nil
    var dueDate: String? = nil
    var clearDueDate: Bool = false
    var estimatedMinutes: Int? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var clearContainer: Bool = false
    var sectionName: String? = nil
    var tagNames: [String]? = nil
}

nonisolated struct CadenceScheduleTaskOptions: Sendable {
    var taskId: String
    var scheduledDate: String? = nil
    var scheduledStartMin: Int? = nil
    var estimatedMinutes: Int? = nil
    var clearScheduledDate: Bool = false
}

nonisolated struct CadenceBulkCancelTaskOptions: Sendable {
    var taskIds: [String]? = nil
    var titlePrefix: String? = nil
}

nonisolated struct CadenceCreateContextOptions: Sendable {
    var name: String
    var colorHex: String? = nil
    var icon: String? = nil
}

/// **`areaId` and `dueDate` are project-only, and that is the model talking, not a policy.**
/// `Area` declares neither an owning area nor a due date — an area is an ongoing responsibility
/// with no end — so an `area` request carrying either is refused rather than quietly ignored. The
/// same argument `CadenceMCPServiceSupport.normalizedSectionName` makes about a mistyped section:
/// a caller who only ever reads the word "success" cannot notice a dropped argument.
nonisolated struct CadenceCreateContainerOptions: Sendable {
    var containerKind: String
    var name: String
    var description: String? = nil
    var contextId: String? = nil
    var areaId: String? = nil
    var colorHex: String? = nil
    var icon: String? = nil
    var dueDate: String? = nil
    var sectionNames: [String]? = nil
}

private struct PendingAuditEntry {
    let tool: String
    let entityType: String
    let entityId: String
    let summary: String

    static func task(tool: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: tool, entityType: "task", entityId: id.uuidString, summary: summary)
    }

    static func coreNote(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "append_core_note", entityType: "core_note", entityId: id.uuidString, summary: summary)
    }

    static func context(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_context", entityType: "context", entityId: id.uuidString, summary: summary)
    }

    /// `entityType` is the container's own kind — `area` or `project` — rather than a flat
    /// "container", so the audit log distinguishes the two the way every other MCP surface does.
    static func container(kind: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_container", entityType: kind, entityId: id.uuidString, summary: summary)
    }
}

@MainActor
final class CadenceWriteService {
    private let context: ModelContext
    private let readService: CadenceReadService
    private let notifiesExternalWrites: Bool
    private let auditLogger: CadenceMCPAuditLogger?

    /// Startup steps executed by *this* instance, plus any its private read service ran. `0` once
    /// the caller has said the container factory already prepared the store (T-309).
    private(set) var executedStartupStepCount = 0

    /// `preparesStore: false` says the caller has already run `CadenceMCPStorePreparation.prepare`
    /// over this store — which `CadenceModelContainerFactory.makeReadWriteContainer()` does, and
    /// which is why `main.swift` passes it (T-309). The private read service never migrates either
    /// way: either this initializer just did, or the caller says it was already done.
    init(
        container: ModelContainer,
        notifiesExternalWrites: Bool = false,
        auditLogger: CadenceMCPAuditLogger? = nil,
        preparesStore: Bool = true
    ) {
        let context = ModelContext(container)
        let steps = preparesStore
            ? CadenceMCPStorePreparation.prepare(in: context, source: "mcp-write-service")
            : 0
        self.context = context
        self.readService = CadenceReadService(context: context, performsMigrations: false)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
        self.executedStartupStepCount = steps + readService.executedStartupStepCount
    }

    init(
        context: ModelContext,
        notifiesExternalWrites: Bool = false,
        auditLogger: CadenceMCPAuditLogger? = nil,
        preparesStore: Bool = true
    ) {
        let steps = preparesStore
            ? CadenceMCPStorePreparation.prepare(in: context, source: "mcp-write-service-context")
            : 0
        self.context = context
        self.readService = CadenceReadService(context: context, performsMigrations: false)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
        self.executedStartupStepCount = steps + readService.executedStartupStepCount
    }

    /// Create a `Context`, the top-level grouping every area and project can be filed under.
    ///
    /// **T-799.** MCP could create a task and append to a core note and nothing else, so the one
    /// argument `create_task` needs in order to put a task anywhere — a `containerId` — could not
    /// be minted from this surface at all. Seeding a kanban board had to be clicked by hand.
    ///
    /// `order` is one past the highest among the rows the new one will sit beside, which is what
    /// `CreateListSheet.nextListOrder` and `iOSContextEditorSheet.nextContextOrder` already do.
    /// Leaving it at the model default is not neutral here: `CadenceMCPOrdering.precedes` breaks an
    /// `order` tie on the *name*, so every seeded context would interleave alphabetically with the
    /// user's own rather than landing at the end of the list where it was created.
    func createContext(options: CadenceCreateContextOptions) throws -> CadenceContextSummary {
        let name = try normalizedRequiredText(options.name, emptyError: CadenceWriteError.emptyName)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)

        let created = Context(name: name)
        if let colorHex { created.colorHex = colorHex }
        if let icon { created.icon = icon }
        created.order = try nextContextOrder()
        context.insert(created)

        try saveNotifyAndAudit(.context(id: created.id, summary: "Created context: \(created.name)"))
        return try readService.contextSummary(contextID: created.id.uuidString)
    }

    /// Create an `Area` or a `Project`, optionally carrying the kanban columns that make it a board.
    ///
    /// **The columns are written straight through `sectionConfigs`, not through
    /// `CadenceSectionConfigMerge`, and that is deliberate.** The merge exists to reconcile two
    /// editors holding stale snapshots of one list's single JSON blob; a container this call
    /// inserted a line earlier has no other holder, no `base` and no `current` to reconcile
    /// against, so the merge would degenerate to "apply the edit" — the case its own documentation
    /// names. It is also not in `CadenceMCPServer`'s explicit Sources phase, and adding a
    /// `Cadence/Shared/` file there to reach a no-op is exactly the coupling
    /// `CadenceMCPServer/AGENTS.md` warns about.
    ///
    /// **A Default column always exists.** `Area.normalizedSectionConfigs` /
    /// `Project.normalizedSectionConfigs` synthesise it when absent and force it to index 0, on
    /// every read and every write, because `AppTask.resolvedSectionName` funnels every task with no
    /// section name into it. So `sectionNames: ["Backlog", "Doing"]` produces three columns, not
    /// two, and the advertised schema says so rather than letting a caller discover it.
    func createContainer(options: CadenceCreateContainerOptions) throws -> CadenceContainerSummary {
        let kind = try normalizedContainerKind(options.containerKind)
        let name = try normalizedRequiredText(options.name, emptyError: CadenceWriteError.emptyName)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)
        let sectionNames = try CadenceMCPServiceSupport.normalizedSectionNames(options.sectionNames)

        // Refused on the *requested* text, before resolution: an `areaId` sent to an area is a
        // misunderstanding of the shape whether or not that id happens to name a real area, and
        // answering "no area found" instead would send the caller looking for the wrong bug.
        let requestsArea = CadenceMCPServiceSupport.normalizedOptionalText(options.areaId) != nil
        let requestsDueDate = CadenceMCPServiceSupport.normalizedOptionalText(options.dueDate) != nil
        if kind == "area" {
            if requestsArea {
                throw CadenceWriteError.invalidCombination("areaId applies to a project; an area cannot be filed inside another area.")
            }
            if requestsDueDate {
                throw CadenceWriteError.invalidCombination("dueDate applies to a project; an area is ongoing and carries no due date.")
            }
        }

        let parentContext = try resolveContext(options.contextId)
        let parentArea = try resolveArea(options.areaId)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let order = try nextListOrder(inContextWithID: parentContext?.id)

        // Colour and icon are only assigned when the caller named one, so an omitted argument
        // leaves the model's own default rather than a copy of it restated here — `Area`,
        // `Project` and `Context` each declare a different pair.
        let id: UUID
        switch kind {
        case "area":
            let area = Area(name: name, context: parentContext)
            if let colorHex { area.colorHex = colorHex }
            if let icon { area.icon = icon }
            if let description = options.description { area.desc = description }
            area.order = order
            context.insert(area)
            if let sectionNames { area.sectionConfigs = sectionNames.map { TaskSectionConfig(name: $0) } }
            id = area.id
        default:
            let project = Project(name: name, context: parentContext, area: parentArea)
            if let colorHex { project.colorHex = colorHex }
            if let icon { project.icon = icon }
            if let description = options.description { project.desc = description }
            if let dueDate { project.dueDate = dueDate }
            project.order = order
            context.insert(project)
            if let sectionNames { project.sectionConfigs = sectionNames.map { TaskSectionConfig(name: $0) } }
            id = project.id
        }

        try saveNotifyAndAudit(.container(kind: kind, id: id, summary: "Created \(kind): \(name)"))
        return try readService.containerSummary(kind: kind, id: id.uuidString)
    }

    func createTask(options: CadenceCreateTaskOptions) throws -> CadenceTaskDetail {
        let title = try normalizedRequiredText(options.title, emptyError: CadenceWriteError.emptyTitle)
        let priority = try options.priority.map(validatePriority) ?? .none
        let dueDate = try validatedOptionalDate(options.dueDate)
        let scheduledDate = try validatedOptionalDate(options.scheduledDate)
        let scheduledStartMin = try validateOptionalScheduledStart(options.scheduledStartMin)
        let estimatedMinutes = try validateEstimatedMinutes(options.estimatedMinutes ?? 30)
        let container = try resolveContainer(kind: options.containerKind, id: options.containerId)
        let sectionName = try normalizedSectionName(options.sectionName, container: container)
        let subtaskTitles = normalizedSubtaskTitles(options.subtaskTitles ?? [])

        if scheduledStartMin != nil && scheduledDate == nil {
            throw CadenceWriteError.invalidCombination("scheduledDate is required when scheduledStartMin is provided.")
        }

        // Resolved before anything is built, so an unreadable tag table fails the call rather than
        // producing an untagged task the caller is told it tagged (T-307).
        let tags = try resolvedTags(named: options.tagNames ?? [])

        let task = AppTask(title: title)
        task.notes = options.notes ?? ""
        task.priority = priority
        task.dueDate = dueDate ?? ""
        task.scheduledDate = scheduledDate ?? ""
        task.scheduledStartMin = scheduledStartMin ?? -1
        task.estimatedMinutes = estimatedMinutes
        task.sectionName = sectionName
        apply(container: container, to: task)
        task.tags = tags

        context.insert(task)
        // NOT `CadenceTaskMutationSupport.insertSubtasks` — that file is not in this target's
        // Sources phase and cannot be, because it reaches `NotificationManager`, which reads
        // `UserDefaults.standard` and so cannot exist in a command-line target. Routing this call
        // through it broke the `CadenceMCPServer` build in aaa0064 while `-scheme Cadence` stayed
        // green, which is the silence `CadenceMCPServer/AGENTS.md` warns about. Both sides of the
        // relationship are still written here by hand; see T-401 for why that is a convention
        // rather than a repair.
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = Subtask(title: subtaskTitle)
            subtask.parentTask = task
            subtask.order = index
            context.insert(subtask)
            task.subtasks = (task.subtasks ?? []) + [subtask]
        }

        try saveNotifyAndAudit(.task(tool: "create_task", id: task.id, summary: "Created task: \(task.title)"))
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func updateTask(options: CadenceUpdateTaskOptions) throws -> CadenceTaskDetail {
        let task = try findTask(options.taskId)

        let title = try options.title.map { try normalizedRequiredText($0, emptyError: CadenceWriteError.emptyTitle) }
        let priority = try options.priority.map(validatePriority)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let estimatedMinutes = try options.estimatedMinutes.map(validateEstimatedMinutes)
        let container = try resolveContainer(kind: options.containerKind, id: options.containerId)

        if options.clearDueDate && dueDate != nil {
            throw CadenceWriteError.invalidCombination("clearDueDate cannot be combined with dueDate.")
        }
        if options.clearContainer && container != nil {
            throw CadenceWriteError.invalidCombination("clearContainer cannot be combined with containerKind/containerId.")
        }

        let finalContainer: CadenceResolvedContainer?
        if options.clearContainer {
            finalContainer = nil
        } else if let container {
            finalContainer = container
        } else {
            finalContainer = currentContainer(for: task)
        }
        let sectionName = try options.sectionName.map { try normalizedSectionName($0, container: finalContainer) }

        guard title != nil || options.notes != nil || priority != nil || dueDate != nil || options.clearDueDate || estimatedMinutes != nil || container != nil || options.clearContainer || sectionName != nil || options.tagNames != nil else {
            throw CadenceWriteError.noChanges
        }

        // Same reason as createTask: the throw has to happen while the task is still untouched.
        let tags = try options.tagNames.map { try resolvedTags(named: $0) }

        if let title { task.title = title }
        if let notes = options.notes { task.notes = notes }
        if let priority { task.priority = priority }
        if options.clearDueDate {
            task.dueDate = ""
        } else if let dueDate {
            task.dueDate = dueDate
        }
        if let estimatedMinutes { task.estimatedMinutes = estimatedMinutes }
        if options.clearContainer {
            apply(container: nil, to: task)
        } else if let container {
            apply(container: container, to: task)
        }
        if let sectionName {
            task.sectionName = sectionName
        } else if options.clearContainer {
            task.sectionName = TaskSectionDefaults.defaultName
        }
        if let tags {
            task.tags = tags
        }

        try saveNotifyAndAudit(.task(tool: "update_task", id: task.id, summary: "Updated task: \(task.title)"))
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func scheduleTask(options: CadenceScheduleTaskOptions) throws -> CadenceTaskDetail {
        let task = try findTask(options.taskId)
        let scheduledDate = try validatedOptionalDate(options.scheduledDate)
        let scheduledStartMin = try validateOptionalScheduledStart(options.scheduledStartMin)
        let estimatedMinutes = try options.estimatedMinutes.map(validateEstimatedMinutes)

        if options.clearScheduledDate && (scheduledDate != nil || scheduledStartMin != nil || estimatedMinutes != nil) {
            throw CadenceWriteError.invalidCombination("clearScheduledDate cannot be combined with scheduledDate, scheduledStartMin, or estimatedMinutes.")
        }
        if scheduledStartMin != nil && scheduledDate == nil {
            throw CadenceWriteError.invalidCombination("scheduledDate is required when scheduledStartMin is provided.")
        }
        guard options.clearScheduledDate || scheduledDate != nil || scheduledStartMin != nil || estimatedMinutes != nil else {
            throw CadenceWriteError.noChanges
        }

        if options.clearScheduledDate {
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        } else {
            if let scheduledDate {
                task.scheduledDate = scheduledDate
            }
            if let scheduledStartMin {
                task.scheduledStartMin = scheduledStartMin
            }
            if let estimatedMinutes {
                task.estimatedMinutes = estimatedMinutes
            }
        }

        try saveNotifyAndAudit(.task(tool: "schedule_task", id: task.id, summary: "Scheduled task: \(task.title)"))
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func completeTask(taskID: String) throws -> CadenceCompleteTaskResult {
        let task = try findTask(taskID)
        guard !task.isCancelled else {
            throw CadenceWriteError.cannotCompleteCancelledTask(taskID)
        }

        var spawnedTaskID: UUID?
        var didChange = false
        if !task.isDone {
            let previouslySpawnedTaskID = task.recurrenceSpawnedTaskID
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
            didChange = true

            if task.recurrenceSpawnedTaskID != previouslySpawnedTaskID {
                spawnedTaskID = task.recurrenceSpawnedTaskID
            }
        }

        if didChange {
            var auditEntries: [PendingAuditEntry] = [
                .task(tool: "complete_task", id: task.id, summary: "Completed task: \(task.title)")
            ]
            if let spawnedTaskID {
                auditEntries.append(.task(tool: "complete_task", id: spawnedTaskID, summary: "Spawned recurring task from: \(task.title)"))
            }
            try saveNotifyAndAudit(auditEntries)
        }
        return CadenceCompleteTaskResult(
            task: try readService.getTask(taskID: task.id.uuidString),
            spawnedRecurringTask: try spawnedTaskID.map { try readService.getTask(taskID: $0.uuidString) }
        )
    }

    func reopenTask(taskID: String) throws -> CadenceTaskDetail {
        let task = try findTask(taskID)
        if task.completedAt != nil || task.status != .todo {
            task.completedAt = nil
            task.status = .todo
            try saveNotifyAndAudit(.task(tool: "reopen_task", id: task.id, summary: "Reopened task: \(task.title)"))
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func cancelTask(taskID: String) throws -> CadenceTaskDetail {
        let task = try findTask(taskID)
        // `status` alone, not `status != .cancelled || completedAt != nil`: since T-202 a cancelled
        // task *carries* a `completedAt`, so the old spelling was true of every already-cancelled
        // task and re-cancelling one would re-stamp its timestamp and write a second audit entry.
        if task.status != .cancelled {
            // Cancelling a single occurrence still advances a recurring series (mirrors completeTask),
            // otherwise cancelling instead of completing one occurrence would silently kill all future ones.
            let previouslySpawnedTaskID = task.recurrenceSpawnedTaskID
            CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)

            var auditEntries: [PendingAuditEntry] = [
                .task(tool: "cancel_task", id: task.id, summary: "Cancelled task: \(task.title)")
            ]
            if let spawnedTaskID = task.recurrenceSpawnedTaskID, spawnedTaskID != previouslySpawnedTaskID {
                auditEntries.append(.task(tool: "cancel_task", id: spawnedTaskID, summary: "Spawned recurring task from: \(task.title)"))
            }
            try saveNotifyAndAudit(auditEntries)
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func bulkCancelTasks(options: CadenceBulkCancelTaskOptions) throws -> CadenceBulkCancelResult {
        let tasks = try fetchTasks()
        let ids = options.taskIds?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let prefix = options.titlePrefix?.trimmingCharacters(in: .whitespacesAndNewlines)

        if !ids.isEmpty && prefix?.isEmpty == false {
            throw CadenceWriteError.invalidCombination("taskIds and titlePrefix cannot be combined.")
        }
        if ids.isEmpty && prefix?.isEmpty != false {
            throw CadenceWriteError.invalidCombination("Provide taskIds or titlePrefix.")
        }

        let selectedTasks: [AppTask]
        if !ids.isEmpty {
            var seen = Set<UUID>()
            let requestedIDs = try ids.map(uuid).filter { seen.insert($0).inserted }
            selectedTasks = try requestedIDs.map { id in
                guard let task = tasks.first(where: { $0.id == id }) else {
                    throw CadenceReadError.taskNotFound(id.uuidString)
                }
                return task
            }
        } else {
            guard let prefix else { throw CadenceWriteError.invalidCombination("Provide taskIds or titlePrefix.") }
            guard prefix.count >= 8 else {
                throw CadenceWriteError.invalidCombination("titlePrefix must be at least 8 characters for bulk cancellation.")
            }
            let normalizedPrefix = prefix.lowercased()
            selectedTasks = tasks.filter {
                !$0.isCancelled && $0.title.lowercased().hasPrefix(normalizedPrefix)
            }
        }

        guard !selectedTasks.isEmpty else {
            throw CadenceWriteError.noChanges
        }

        var changed: [AppTask] = []
        var auditEntries: [PendingAuditEntry] = []
        // `status` alone, for the same reason as `cancelTask` above (T-202): a cancelled task now
        // has a non-nil `completedAt`, so `|| task.completedAt != nil` matched every one of them.
        for task in selectedTasks where task.status != .cancelled {
            // Mirror cancelTask's single-task behavior: route through the shared recurrence
            // workflow instead of setting status/completedAt directly, otherwise bulk-cancelling
            // a recurring task silently kills the rest of its series (it never spawns the next
            // occurrence the way completeTask/cancelTask do).
            let previouslySpawnedTaskID = task.recurrenceSpawnedTaskID
            CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)
            changed.append(task)
            auditEntries.append(.task(tool: "bulk_cancel_tasks", id: task.id, summary: "Bulk cancelled task: \(task.title)"))
            if let spawnedTaskID = task.recurrenceSpawnedTaskID, spawnedTaskID != previouslySpawnedTaskID {
                auditEntries.append(.task(tool: "bulk_cancel_tasks", id: spawnedTaskID, summary: "Spawned recurring task from: \(task.title)"))
            }
        }

        if !changed.isEmpty {
            try saveNotifyAndAudit(auditEntries)
        }

        return CadenceBulkCancelResult(
            cancelledTasks: try selectedTasks.map { try readService.getTask(taskID: $0.id.uuidString).summary }
        )
    }

    func appendCoreNote(kind: String, content: String, dateKey: String? = nil, separator: String? = nil) throws -> CadenceCoreNotesSnapshot {
        let normalizedKind = try normalizeNoteKind(kind)
        let text = try normalizedRequiredText(content, emptyError: CadenceWriteError.emptyContent)
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let separator = separator ?? "\n\n"
        let now = Date()
        let auditEntry: PendingAuditEntry

        switch normalizedKind {
        case "daily":
            let note = try NoteMigrationService.dailyNote(for: resolvedDateKey, in: context)
            var content = note.content
            append(text, separator: separator, to: &content)
            note.content = content
            note.updatedAt = now
            auditEntry = .coreNote(id: note.id, summary: "Appended daily core note: \(resolvedDateKey)")
        case "weekly":
            let resolvedWeekKey = try weekKey(for: resolvedDateKey)
            let note = try NoteMigrationService.weeklyNote(for: resolvedWeekKey, in: context)
            var content = note.content
            append(text, separator: separator, to: &content)
            note.content = content
            note.updatedAt = now
            auditEntry = .coreNote(id: note.id, summary: "Appended weekly core note: \(resolvedWeekKey)")
        case "permanent":
            let note = try NoteMigrationService.permanentNote(in: context)
            var content = note.content
            append(text, separator: separator, to: &content)
            note.content = content
            note.updatedAt = now
            auditEntry = .coreNote(id: note.id, summary: "Appended permanent core note")
        default:
            throw CadenceWriteError.invalidNoteKind(kind)
        }

        try saveNotifyAndAudit(auditEntry)
        return try readService.coreNotes(dateKey: resolvedDateKey)
    }

    private func saveNotifyAndAudit(_ entry: PendingAuditEntry) throws {
        try saveNotifyAndAudit([entry])
    }

    private func saveNotifyAndAudit(_ entries: [PendingAuditEntry]) throws {
        try context.save()
        if notifiesExternalWrites {
            CadenceModelContainerFactory.notifyExternalWrite()
        }
        for entry in entries {
            recordAudit(entry)
        }
    }

    private func recordAudit(_ entry: PendingAuditEntry) {
        guard let auditLogger else { return }
        do {
            try auditLogger.record(
                tool: entry.tool,
                entityType: entry.entityType,
                entityId: entry.entityId,
                summary: entry.summary
            )
        } catch {
            let message = "Cadence MCP audit log failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    private func findTask(_ taskID: String) throws -> AppTask {
        let id = try uuid(from: taskID)
        guard let task = try fetchTasks().first(where: { $0.id == id }) else {
            throw CadenceReadError.taskNotFound(taskID)
        }
        return task
    }

    private func fetchTasks() throws -> [AppTask] {
        try context.fetch(FetchDescriptor<AppTask>())
    }

    private func fetchAreas() throws -> [Area] {
        try context.fetch(FetchDescriptor<Area>())
    }

    private func fetchProjects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>())
    }

    private func fetchContexts() throws -> [Context] {
        try context.fetch(FetchDescriptor<Context>())
    }

    private func nextContextOrder() throws -> Int {
        (try fetchContexts().map(\.order).max() ?? -1) + 1
    }

    /// One past the highest `order` among the lists the new one will sit beside.
    ///
    /// Areas and projects share one sequence per context, and the comparison is
    /// **optional-to-optional** on purpose — `nil == nil` is the unfiled bucket, numbered exactly
    /// like a filed one. `CreateListSheet.nextListOrder` spells the same rule for the same reason:
    /// walking `context.areas` instead would leave every context-less list created at 0.
    private func nextListOrder(inContextWithID id: UUID?) throws -> Int {
        var orders = try fetchAreas().filter { $0.context?.id == id }.map(\.order)
        orders += try fetchProjects().filter { $0.context?.id == id }.map(\.order)
        return (orders.max() ?? -1) + 1
    }

    private func resolveContext(_ id: String?) throws -> Context? {
        guard let requested = CadenceMCPServiceSupport.normalizedOptionalText(id) else { return nil }
        let uuid = try uuid(from: requested)
        guard let match = try fetchContexts().first(where: { $0.id == uuid }) else {
            throw CadenceReadError.contextNotFound(requested)
        }
        return match
    }

    private func resolveArea(_ id: String?) throws -> Area? {
        guard let requested = CadenceMCPServiceSupport.normalizedOptionalText(id) else { return nil }
        let uuid = try uuid(from: requested)
        guard let match = try fetchAreas().first(where: { $0.id == uuid }) else {
            throw CadenceReadError.containerNotFound("area", requested)
        }
        return match
    }

    private func normalizedOptionalColorHex(_ value: String?) throws -> String? {
        try CadenceMCPServiceSupport.normalizedOptionalColorHex(value)
    }

    private func normalizedRequiredText(_ value: String, emptyError: Error) throws -> String {
        try CadenceMCPServiceSupport.normalizedRequiredText(value, emptyError: emptyError)
    }

    private func validatedOptionalDate(_ dateKey: String?) throws -> String? {
        try CadenceMCPServiceSupport.validatedOptionalDate(dateKey)
    }

    private func resolvedDateKey(_ dateKey: String?) throws -> String {
        try CadenceMCPServiceSupport.resolvedDateKey(dateKey)
    }

    private func weekKey(for dateKey: String) throws -> String {
        try CadenceMCPServiceSupport.weekKey(for: dateKey)
    }

    private func parsedDate(_ dateKey: String) throws -> Date {
        try CadenceMCPServiceSupport.parsedDate(dateKey)
    }

    private func uuid(from id: String) throws -> UUID {
        try CadenceMCPServiceSupport.uuid(from: id)
    }

    private func validatePriority(_ value: String) throws -> TaskPriority {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let priority = TaskPriority(rawValue: normalized) else {
            throw CadenceWriteError.invalidPriority(value)
        }
        return priority
    }

    private func validateOptionalScheduledStart(_ value: Int?) throws -> Int? {
        guard let value else { return nil }
        guard (0...1439).contains(value) else {
            throw CadenceWriteError.invalidScheduledStartMin(value)
        }
        return value
    }

    private func validateEstimatedMinutes(_ value: Int) throws -> Int {
        guard (1...1440).contains(value) else {
            throw CadenceWriteError.invalidEstimatedMinutes(value)
        }
        return value
    }

    private func normalizeNoteKind(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["daily", "weekly", "permanent"].contains(normalized) else {
            throw CadenceWriteError.invalidNoteKind(value)
        }
        return normalized
    }

    private func normalizedContainerKind(_ value: String) throws -> String {
        try CadenceMCPServiceSupport.normalizeContainerKind(value)
    }

    private func resolveContainer(kind: String?, id: String?) throws -> CadenceResolvedContainer? {
        let normalizedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (normalizedKind?.isEmpty == false ? normalizedKind : nil, normalizedID?.isEmpty == false ? normalizedID : nil) {
        case (.none, .none):
            return nil
        case (.some(let kind), .some(let id)):
            let uuid = try uuid(from: id)
            switch try normalizedContainerKind(kind) {
            case "area":
                guard let area = try fetchAreas().first(where: { $0.id == uuid }) else {
                    throw CadenceReadError.containerNotFound(kind, id)
                }
                return .area(area)
            case "project":
                guard let project = try fetchProjects().first(where: { $0.id == uuid }) else {
                    throw CadenceReadError.containerNotFound(kind, id)
                }
                return .project(project)
            default:
                throw CadenceReadError.invalidContainerKind(kind)
            }
        default:
            throw CadenceReadError.incompleteContainerFilter
        }
    }

    private func currentContainer(for task: AppTask) -> CadenceResolvedContainer? {
        if let area = task.area { return .area(area) }
        if let project = task.project { return .project(project) }
        return nil
    }

    private func apply(container: CadenceResolvedContainer?, to task: AppTask) {
        switch container {
        case .area(let area):
            task.area = area
            task.project = nil
            task.context = area.context
        case .project(let project):
            task.project = project
            task.area = nil
            task.context = project.resolvedContext
        case nil:
            task.area = nil
            task.project = nil
            task.context = nil
        }
    }

    private func normalizedSectionName(_ value: String?, container: CadenceResolvedContainer?) throws -> String {
        try CadenceMCPServiceSupport.normalizedSectionName(value, container: container)
    }

    private func resolvedTags(named names: [String]) throws -> [Tag] {
        try CadenceMCPServiceSupport.requiredTags(TagSupport.resolveTags(named: names, in: context))
    }

    private func normalizedSubtaskTitles(_ values: [String]) -> [String] {
        CadenceMCPServiceSupport.normalizedSubtaskTitles(values)
    }

    private func append(_ text: String, separator: String, to content: inout String) {
        CadenceMCPServiceSupport.append(text, separator: separator, to: &content)
    }
}
