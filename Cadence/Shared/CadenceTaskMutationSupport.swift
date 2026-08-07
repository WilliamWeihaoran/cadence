import Foundation
import SwiftData

enum CadenceTaskMutationSupport {
    static func toggleCompletion(_ task: AppTask, modelContext: ModelContext) {
        if task.isDone {
            CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
        } else {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        }
        try? modelContext.save()
    }

    static func setStatus(_ status: TaskStatus, for task: AppTask, modelContext: ModelContext) {
        applyStatusCompletion(status, to: task, modelContext: modelContext)
        try? modelContext.save()
    }

    static func applyStatusCompletion(_ status: TaskStatus, to task: AppTask, modelContext: ModelContext) {
        switch status {
        case .done:
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        case .cancelled:
            CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: modelContext)
        case .todo, .inProgress:
            task.status = status
            task.completedAt = nil
        }
    }

    static func normalizeCompletionState(for task: AppTask, modelContext: ModelContext) {
        if task.status == .done {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        } else {
            task.completedAt = nil
        }
        try? modelContext.save()
    }

    static func setPriority(_ priority: TaskPriority, for task: AppTask, modelContext: ModelContext) {
        task.priority = priority
        try? modelContext.save()
    }

    static func setGoal(_ goal: Goal?, for task: AppTask, modelContext: ModelContext) {
        task.goal = goal
        try? modelContext.save()
    }

    static func scheduleToday(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func scheduleTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func scheduleNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func setScheduledDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = dateKey
        try? modelContext.save()
    }

    static func moveTaskToDate(_ task: AppTask, dateKey: String, modelContext: ModelContext) {
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = dateKey
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = 30
        }
        try? modelContext.save()
    }

    static func setScheduledTime(_ startMin: Int, for task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = min(max(0, startMin), 1425)
        try? modelContext.save()
    }

    static func clearScheduledDate(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func clearScheduledTime(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func dueToday(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func dueTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func dueNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func setDueDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.dueDate = dateKey
        try? modelContext.save()
    }

    static func clearDueDate(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = ""
        try? modelContext.save()
    }

    static func setPlanningDates(
        scheduledDate: String?,
        dueDate: String?,
        for task: AppTask,
        modelContext: ModelContext
    ) {
        let scheduleKey = scheduledDate ?? ""
        task.scheduledDate = scheduleKey
        if scheduleKey.isEmpty {
            task.scheduledStartMin = -1
        }
        task.dueDate = dueDate ?? ""
        try? modelContext.save()
    }

    static func moveToSection(_ sectionName: String, task: AppTask, modelContext: ModelContext) {
        task.sectionName = sectionName
        try? modelContext.save()
    }

    static func sectionNames(forArea area: Area?, project: Project?) -> [String] {
        if let area {
            return area.sectionNames
        }
        if let project {
            return project.sectionNames
        }
        return [TaskSectionDefaults.defaultName]
    }

    static func normalizedSectionName(_ sectionName: String, area: Area?, project: Project?) -> String {
        let names = sectionNames(forArea: area, project: project)
        if let matched = names.first(where: { $0.caseInsensitiveCompare(sectionName) == .orderedSame }) {
            return matched
        }
        return names.first ?? TaskSectionDefaults.defaultName
    }

    static func assignContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        updateOrder: Bool = true
    ) {
        let normalizedSectionName = normalizedSectionName(sectionName, area: area, project: project)

        if let area {
            task.area = area
            task.project = nil
            task.context = area.context
        } else if let project {
            task.project = project
            task.area = nil
            task.context = project.context ?? project.area?.context
        } else {
            task.area = nil
            task.project = nil
            task.context = nil
        }

        task.sectionName = normalizedSectionName
        if updateOrder {
            task.order = nextContainerOrder(excluding: task, in: allTasks, area: area, project: project)
        }
    }

    static func moveToContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        modelContext: ModelContext
    ) {
        assignContainer(
            task,
            area: area,
            project: project,
            sectionName: sectionName,
            allTasks: allTasks
        )
        try? modelContext.save()
    }

    static func moveToInbox(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) {
        assignContainer(
            task,
            area: nil,
            project: nil,
            sectionName: TaskSectionDefaults.defaultName,
            allTasks: allTasks
        )
        try? modelContext.save()
    }

    static func duplicate(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) throws -> AppTask {
        let duplicate = AppTask(title: task.title)
        duplicate.notes = task.notes
        duplicate.priority = task.priority
        duplicate.status = .todo
        duplicate.recurrenceRule = task.recurrenceRule
        duplicate.dueDate = task.dueDate
        duplicate.scheduledDate = task.scheduledDate
        duplicate.scheduledStartMin = task.scheduledStartMin
        duplicate.estimatedMinutes = task.estimatedMinutes
        duplicate.actualMinutes = 0
        duplicate.sectionName = task.resolvedSectionName
        duplicate.order = nextOrderForSibling(of: task, in: allTasks)
        duplicate.area = task.area
        duplicate.project = task.project
        duplicate.goal = task.goal
        duplicate.context = task.context
        duplicate.tags = task.tags

        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            return duplicate
        } catch {
            modelContext.delete(duplicate)
            throw error
        }
    }

    static func delete(_ task: AppTask, modelContext: ModelContext) {
        let subtasks = task.subtasks ?? []
        task.subtasks = []
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }

        // Otherwise, if `task` is a mid-series recurring occurrence, whichever task recorded it as
        // its `recurrenceSpawnedTaskID` would keep believing the series has a live next occurrence
        // forever, silently stalling it — see CadenceTaskRecurrenceWorkflowSupport for the full story.
        let allTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        CadenceTaskRecurrenceWorkflowSupport.repairDanglingRecurrenceLinks(forDeleted: [task], allTasks: allTasks)

        for subtask in subtasks {
            modelContext.delete(subtask)
        }

        modelContext.delete(task)
        try? modelContext.save()
    }

    static func insertTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String? = nil,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate
        ) else { return nil }

        configure(task)
        modelContext.insert(task)
        do {
            try modelContext.save()
            return task
        } catch {
            modelContext.delete(task)
            throw error
        }
    }

    static func insertScheduledTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String,
        scheduledStartMin: Int,
        estimatedMinutes: Int,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate,
            estimatedMinutes: max(5, estimatedMinutes)
        ) else { return nil }

        task.scheduledStartMin = scheduledStartMin
        configure(task)
        modelContext.insert(task)
        do {
            try modelContext.save()
            return task
        } catch {
            modelContext.delete(task)
            throw error
        }
    }

    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) throws -> TaskBundle {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedStart = min(max(0, startMin), (24 * 60) - 5)
        let duration = min(max(5, durationMinutes), (24 * 60) - clampedStart)
        let bundle = TaskBundle(
            title: trimmed.isEmpty ? "Task Bundle" : trimmed,
            dateKey: dateKey,
            startMin: clampedStart,
            durationMinutes: duration
        )

        modelContext.insert(bundle)
        do {
            try modelContext.save()
            return bundle
        } catch {
            modelContext.delete(bundle)
            throw error
        }
    }

    static func updateBundle(
        _ bundle: TaskBundle,
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedStart = min(max(0, startMin), (24 * 60) - 5)
        let duration = min(max(5, durationMinutes), (24 * 60) - clampedStart)

        bundle.title = trimmed
        bundle.dateKey = dateKey
        bundle.startMin = clampedStart
        bundle.durationMinutes = duration

        for task in bundle.tasks ?? [] {
            task.scheduledDate = dateKey
            task.scheduledStartMin = -1
        }

        try? modelContext.save()
    }

    static func moveBundle(_ bundle: TaskBundle, to dateKey: String, modelContext: ModelContext) {
        updateBundle(
            bundle,
            title: bundle.title,
            dateKey: dateKey,
            startMin: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            modelContext: modelContext
        )
    }

    static func addTask(_ task: AppTask, to bundle: TaskBundle, modelContext: ModelContext) {
        let nextOrder = ((bundle.tasks ?? []).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        if !(bundle.tasks ?? []).contains(where: { $0.id == task.id }) {
            bundle.tasks = (bundle.tasks ?? []) + [task]
        }
        try? modelContext.save()
    }

    static func removeTaskFromBundle(_ task: AppTask, modelContext: ModelContext) {
        let bundleDateKey = task.bundle?.dateKey ?? task.scheduledDate
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = bundleDateKey
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func deleteBundle(_ bundle: TaskBundle, modelContext: ModelContext) {
        for task in bundle.tasks ?? [] {
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
        }

        bundle.tasks = []
        modelContext.delete(bundle)
        try? modelContext.save()
    }

    private static func nextContainerOrder(
        excluding task: AppTask,
        in allTasks: [AppTask],
        area: Area?,
        project: Project?
    ) -> Int {
        let siblings = allTasks.filter { candidate in
            guard candidate.id != task.id else { return false }
            if let area {
                return candidate.area?.id == area.id
            }
            if let project {
                return candidate.project?.id == project.id
            }
            return candidate.area == nil && candidate.project == nil
        }
        return CadenceTaskQuerySupport.nextTaskOrder(in: siblings)
    }

    private static func nextOrderForSibling(of task: AppTask, in allTasks: [AppTask]) -> Int {
        nextContainerOrder(excluding: task, in: allTasks, area: task.area, project: task.project)
    }
}

// CadenceTaskRecurrenceEditScope and CadenceTaskRecurrenceWorkflowSupport now live in
// CadenceTaskRecurrenceWorkflowSupport.swift (Foundation + SwiftData only) so the same
// recurrence logic can also compile into the headless CadenceMCPServer tool target.
