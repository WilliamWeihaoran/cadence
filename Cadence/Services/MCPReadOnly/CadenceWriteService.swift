import Foundation
import SwiftData

enum CadenceWriteError: Error, LocalizedError, Sendable {
    case emptyTitle
    case emptyContent
    case invalidPriority(String)
    case invalidNoteKind(String)
    case invalidScheduledStartMin(Int)
    case invalidEstimatedMinutes(Int)
    case invalidCombination(String)
    case noChanges
    case dependencyNotFound(String)
    case selfDependency
    case cannotCompleteCancelledTask(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Task title must not be empty."
        case .emptyContent:
            return "Note content must not be empty."
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
        case .dependencyNotFound(let id):
            return "No dependency task found with id \(id)."
        case .selfDependency:
            return "A task cannot depend on itself."
        case .cannotCompleteCancelledTask(let id):
            return "Cancelled task \(id) cannot be completed."
        }
    }
}

struct CadenceCreateTaskOptions: Sendable {
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
    var dependencyTaskIds: [String]? = nil
    var subtaskTitles: [String]? = nil
}

struct CadenceUpdateTaskOptions: Sendable {
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
    var dependencyTaskIds: [String]? = nil
}

struct CadenceScheduleTaskOptions: Sendable {
    var taskId: String
    var scheduledDate: String? = nil
    var scheduledStartMin: Int? = nil
    var estimatedMinutes: Int? = nil
    var clearScheduledDate: Bool = false
}

struct CadenceBulkCancelTaskOptions: Sendable {
    var taskIds: [String]? = nil
    var titlePrefix: String? = nil
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
}

@MainActor
final class CadenceWriteService {
    private let context: ModelContext
    private let readService: CadenceReadService
    private let notifiesExternalWrites: Bool
    private let auditLogger: CadenceMCPAuditLogger?

    init(container: ModelContainer, notifiesExternalWrites: Bool = false, auditLogger: CadenceMCPAuditLogger? = nil) {
        let context = ModelContext(container)
        self.context = context
        self.readService = CadenceReadService(context: context)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
    }

    init(context: ModelContext, notifiesExternalWrites: Bool = false, auditLogger: CadenceMCPAuditLogger? = nil) {
        self.context = context
        self.readService = CadenceReadService(context: context)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
    }

    func createTask(options: CadenceCreateTaskOptions) throws -> CadenceTaskDetail {
        let title = try normalizedRequiredText(options.title, emptyError: CadenceWriteError.emptyTitle)
        let priority = try options.priority.map(validatePriority) ?? .none
        let dueDate = try validatedOptionalDate(options.dueDate)
        let scheduledDate = try validatedOptionalDate(options.scheduledDate)
        let scheduledStartMin = try validateOptionalScheduledStart(options.scheduledStartMin)
        let estimatedMinutes = try validateEstimatedMinutes(options.estimatedMinutes ?? 30)
        let allTasks = try fetchTasks()
        let dependencyIDs = try validateDependencyIDs(options.dependencyTaskIds ?? [], allTasks: allTasks, taskID: nil)
        let container = try resolveContainer(kind: options.containerKind, id: options.containerId)
        let sectionName = normalizedSectionName(options.sectionName, container: container)
        let subtaskTitles = normalizedSubtaskTitles(options.subtaskTitles ?? [])

        if scheduledStartMin != nil && scheduledDate == nil {
            throw CadenceWriteError.invalidCombination("scheduledDate is required when scheduledStartMin is provided.")
        }

        let task = AppTask(title: title)
        task.notes = options.notes ?? ""
        task.priority = priority
        task.dueDate = dueDate ?? ""
        task.scheduledDate = scheduledDate ?? ""
        task.scheduledStartMin = scheduledStartMin ?? -1
        task.estimatedMinutes = estimatedMinutes
        task.dependencyTaskIDs = dependencyIDs
        task.sectionName = sectionName
        apply(container: container, to: task)

        context.insert(task)
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = Subtask(title: subtaskTitle)
            subtask.parentTask = task
            subtask.order = index
            context.insert(subtask)
        }

        try saveNotifyAndAudit(.task(tool: "create_task", id: task.id, summary: "Created task: \(task.title)"))
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func updateTask(options: CadenceUpdateTaskOptions) throws -> CadenceTaskDetail {
        let task = try findTask(options.taskId)
        let allTasks = try fetchTasks()

        let title = try options.title.map { try normalizedRequiredText($0, emptyError: CadenceWriteError.emptyTitle) }
        let priority = try options.priority.map(validatePriority)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let estimatedMinutes = try options.estimatedMinutes.map(validateEstimatedMinutes)
        let dependencyIDs = try options.dependencyTaskIds.map { try validateDependencyIDs($0, allTasks: allTasks, taskID: task.id) }
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
        let sectionName = options.sectionName.map { normalizedSectionName($0, container: finalContainer) }

        guard title != nil || options.notes != nil || priority != nil || dueDate != nil || options.clearDueDate || estimatedMinutes != nil || container != nil || options.clearContainer || sectionName != nil || dependencyIDs != nil else {
            throw CadenceWriteError.noChanges
        }

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
        if let dependencyIDs { task.dependencyTaskIDs = dependencyIDs }

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
            task.completedAt = Date()
            task.status = .done
            didChange = true

            if task.isRecurring, task.recurrenceSpawnedTaskID == nil {
                let nextTask = makeNextRecurringTask(from: task)
                context.insert(nextTask)
                task.recurrenceSpawnedTaskID = nextTask.id
                spawnedTaskID = nextTask.id
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
        if task.completedAt != nil || task.status != .cancelled {
            task.completedAt = nil
            task.status = .cancelled
            try saveNotifyAndAudit(.task(tool: "cancel_task", id: task.id, summary: "Cancelled task: \(task.title)"))
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
        for task in selectedTasks where task.status != .cancelled || task.completedAt != nil {
            task.completedAt = nil
            task.status = .cancelled
            changed.append(task)
        }

        if !changed.isEmpty {
            try saveNotifyAndAudit(changed.map {
                .task(tool: "bulk_cancel_tasks", id: $0.id, summary: "Bulk cancelled task: \($0.title)")
            })
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
            let note: DailyNote
            if let existing = try fetchDailyNotes().first(where: { $0.date == resolvedDateKey }) {
                note = existing
            } else {
                note = DailyNote(date: resolvedDateKey)
                context.insert(note)
            }
            append(text, separator: separator, to: &note.content)
            note.updatedAt = now
            auditEntry = .coreNote(id: note.id, summary: "Appended daily core note: \(resolvedDateKey)")
        case "weekly":
            let resolvedWeekKey = try weekKey(for: resolvedDateKey)
            let note: WeeklyNote
            if let existing = try fetchWeeklyNotes().first(where: { $0.weekKey == resolvedWeekKey }) {
                note = existing
            } else {
                note = WeeklyNote(weekKey: resolvedWeekKey)
                context.insert(note)
            }
            append(text, separator: separator, to: &note.content)
            note.updatedAt = now
            auditEntry = .coreNote(id: note.id, summary: "Appended weekly core note: \(resolvedWeekKey)")
        case "permanent":
            let note: PermNote
            if let existing = try fetchPermNotes().first {
                note = existing
            } else {
                note = PermNote()
                context.insert(note)
            }
            append(text, separator: separator, to: &note.content)
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

    private func fetchDailyNotes() throws -> [DailyNote] {
        try context.fetch(FetchDescriptor<DailyNote>())
    }

    private func fetchWeeklyNotes() throws -> [WeeklyNote] {
        try context.fetch(FetchDescriptor<WeeklyNote>())
    }

    private func fetchPermNotes() throws -> [PermNote] {
        try context.fetch(FetchDescriptor<PermNote>())
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

    private func validateDependencyIDs(_ values: [String], allTasks: [AppTask], taskID: UUID?) throws -> [UUID] {
        var result: [UUID] = []
        var seen = Set<UUID>()
        for value in values {
            let id = try uuid(from: value)
            if id == taskID { throw CadenceWriteError.selfDependency }
            guard allTasks.contains(where: { $0.id == id }) else {
                throw CadenceWriteError.dependencyNotFound(value)
            }
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
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
            task.context = project.context
        case nil:
            task.area = nil
            task.project = nil
            task.context = nil
        }
    }

    private func normalizedSectionName(_ value: String?, container: CadenceResolvedContainer?) -> String {
        CadenceMCPServiceSupport.normalizedSectionName(value, container: container)
    }

    private func normalizedSubtaskTitles(_ values: [String]) -> [String] {
        CadenceMCPServiceSupport.normalizedSubtaskTitles(values)
    }

    private func append(_ text: String, separator: String, to content: inout String) {
        CadenceMCPServiceSupport.append(text, separator: separator, to: &content)
    }

    private func makeNextRecurringTask(from task: AppTask) -> AppTask {
        let nextTask = AppTask(title: task.title)
        nextTask.notes = task.notes
        nextTask.priority = task.priority
        nextTask.recurrenceRule = task.recurrenceRule
        nextTask.dependencyTaskIDs = task.dependencyTaskIDs
        nextTask.estimatedMinutes = max(task.estimatedMinutes, 30)
        nextTask.sectionName = task.sectionName
        nextTask.area = task.area
        nextTask.project = task.project
        nextTask.goal = task.goal
        nextTask.context = task.context

        if !task.dueDate.isEmpty {
            nextTask.dueDate = shiftedDateKey(task.dueDate, recurrence: task.recurrenceRule) ?? task.dueDate
        }
        if !task.scheduledDate.isEmpty {
            nextTask.scheduledDate = shiftedDateKey(task.scheduledDate, recurrence: task.recurrenceRule) ?? task.scheduledDate
            nextTask.scheduledStartMin = task.scheduledStartMin
        }

        if let subtasks = task.subtasks {
            nextTask.subtasks = subtasks
                .sorted { $0.order < $1.order }
                .map { source in
                    let copy = Subtask(title: source.title)
                    copy.order = source.order
                    return copy
                }
        }

        return nextTask
    }

    private func shiftedDateKey(_ key: String, recurrence: TaskRecurrenceRule) -> String? {
        guard recurrence != .none, let date = DateFormatters.date(from: key) else { return nil }
        let calendar = Calendar.current
        let component: Calendar.Component
        let value: Int

        switch recurrence {
        case .none:
            return key
        case .daily:
            component = .day
            value = 1
        case .weekly:
            component = .weekOfYear
            value = 1
        case .monthly:
            component = .month
            value = 1
        case .yearly:
            component = .year
            value = 1
        }

        guard let next = calendar.date(byAdding: component, value: value, to: date) else { return nil }
        return DateFormatters.dateKey(from: next)
    }
}
