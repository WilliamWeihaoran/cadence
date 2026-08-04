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
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
    }

    static func markCancelled(_ task: AppTask, in context: ModelContext) {
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)
    }

    static func markTodo(_ task: AppTask) {
        CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
    }

    static func ensureRecurrenceSeriesMetadata(for task: AppTask) {
        CadenceTaskRecurrenceWorkflowSupport.ensureRecurrenceSeriesMetadata(for: task)
    }

    static func applyRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        to task: AppTask,
        allTasks: [AppTask],
        scope: TaskRecurrenceEditScope
    ) {
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
            rule,
            to: task,
            allTasks: allTasks,
            scope: scope.sharedScope
        )
    }

    static func recurrenceTargets(
        from task: AppTask,
        allTasks: [AppTask],
        scope: TaskRecurrenceEditScope
    ) -> [AppTask] {
        CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope.sharedScope
        )
    }
}

private extension TaskRecurrenceEditScope {
    var sharedScope: CadenceTaskRecurrenceEditScope {
        switch self {
        case .thisTask: return .thisTask
        case .thisAndFuture: return .thisAndFuture
        }
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
