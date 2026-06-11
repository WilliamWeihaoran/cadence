#if os(macOS)
import SwiftData
import Foundation

enum TaskRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisTask
    case thisAndFuture

    var label: String {
        switch self {
        case .thisTask: return "Only This Task"
        case .thisAndFuture: return "This And Future Tasks"
        }
    }
}

enum TaskWorkflowService {
    static func markDone(_ task: AppTask, in context: ModelContext) {
        task.completedAt = Date()
        task.status = .done

        guard task.isRecurring, task.recurrenceSpawnedTaskID == nil else { return }
        ensureRecurrenceSeriesMetadata(for: task)
        let nextTask = makeNextRecurringTask(from: task)
        context.insert(nextTask)
        task.recurrenceSpawnedTaskID = nextTask.id
    }

    static func markTodo(_ task: AppTask) {
        task.completedAt = nil
        task.status = .todo
    }

    static func ensureRecurrenceSeriesMetadata(for task: AppTask) {
        if task.recurrenceSeriesIDRaw.isEmpty {
            task.recurrenceSeriesIDRaw = task.id.uuidString
        }
    }

    static func applyRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        to task: AppTask,
        allTasks: [AppTask],
        scope: TaskRecurrenceEditScope
    ) {
        ensureRecurrenceSeriesMetadata(for: task)
        let targetTasks = recurrenceTargets(from: task, allTasks: allTasks, scope: scope)
        for target in targetTasks {
            ensureRecurrenceSeriesMetadata(for: target)
            target.recurrenceRule = rule
            if rule == .none {
                target.recurrenceSpawnedTaskID = nil
            }
        }
    }

    static func recurrenceTargets(
        from task: AppTask,
        allTasks: [AppTask],
        scope: TaskRecurrenceEditScope
    ) -> [AppTask] {
        guard scope == .thisAndFuture else { return [task] }

        var targets = [task]
        var seen = Set([task.id])
        var current = task

        while let nextID = current.recurrenceSpawnedTaskID,
              let next = allTasks.first(where: { $0.id == nextID }),
              seen.insert(next.id).inserted {
            targets.append(next)
            current = next
        }

        let currentDate = recurrenceSortDateKey(for: task)
        let seriesID = task.recurrenceSeriesID
        for candidate in allTasks where !seen.contains(candidate.id) {
            guard candidate.recurrenceSeriesID == seriesID else { continue }
            if let currentDate,
               let candidateDate = recurrenceSortDateKey(for: candidate),
               candidateDate < currentDate {
                continue
            }
            targets.append(candidate)
            seen.insert(candidate.id)
        }

        return targets.sorted { lhs, rhs in
            recurrenceSortKey(for: lhs) < recurrenceSortKey(for: rhs)
        }
    }

    private static func makeNextRecurringTask(from task: AppTask) -> AppTask {
        let nextTask = AppTask(title: task.title)
        nextTask.notes = task.notes
        nextTask.priority = task.priority
        nextTask.recurrenceRule = task.recurrenceRule
        nextTask.estimatedMinutes = max(task.estimatedMinutes, 30)
        nextTask.sectionName = task.sectionName
        nextTask.area = task.area
        nextTask.project = task.project
        nextTask.context = task.context
        nextTask.recurrenceSeriesIDRaw = task.recurrenceSeriesID.uuidString
        nextTask.recurrenceSourceTaskID = task.id
        nextTask.recurrenceOccurrenceIndex = task.recurrenceOccurrenceIndex + 1

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

    private static func recurrenceSortDateKey(for task: AppTask) -> String? {
        if !task.scheduledDate.isEmpty { return task.scheduledDate }
        if !task.dueDate.isEmpty { return task.dueDate }
        return nil
    }

    private static func recurrenceSortKey(for task: AppTask) -> String {
        [
            recurrenceSortDateKey(for: task) ?? "9999-12-31",
            String(format: "%04d", max(0, task.scheduledStartMin)),
            String(format: "%08d", task.recurrenceOccurrenceIndex),
            task.createdAt.ISO8601Format(),
            task.id.uuidString
        ].joined(separator: "|")
    }

    private static func shiftedDateKey(_ key: String, recurrence: TaskRecurrenceRule) -> String? {
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

enum TaskContainerLifecycleService {
    static func completeRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: area, includingChildProjects: includingChildProjects), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: area, includingChildProjects: includingChildProjects), as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in project: Project, in context: ModelContext) {
        finishRemainingActiveTasks(project.tasks ?? [], as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in project: Project, in context: ModelContext) {
        finishRemainingActiveTasks(project.tasks ?? [], as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: section, area: area, project: project), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: section, area: area, project: project), as: .cancelled, in: context)
    }

    private static func finishRemainingActiveTasks(_ tasks: [AppTask], as status: TaskStatus, in context: ModelContext) {
        for task in unique(tasks) where !task.isDone && !task.isCancelled {
            switch status {
            case .done:
                task.completedAt = Date()
                task.status = .done
            case .cancelled:
                task.completedAt = nil
                task.status = .cancelled
            case .todo, .inProgress:
                task.completedAt = nil
                task.status = status
            }
        }
    }

    private static func tasks(in area: Area, includingChildProjects: Bool) -> [AppTask] {
        var result = area.tasks ?? []
        if includingChildProjects {
            for project in area.projects ?? [] {
                result.append(contentsOf: project.tasks ?? [])
            }
        }
        return result
    }

    private static func tasks(in section: TaskSectionConfig, area: Area?, project: Project?) -> [AppTask] {
        let sourceTasks = area?.tasks ?? project?.tasks ?? []
        return sourceTasks.filter {
            $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
    }

    private static func unique(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}
#endif
