import Foundation
import SwiftData

// This file intentionally depends only on Foundation + SwiftData (no SwiftUI) so it can be
// compiled directly into the headless CadenceMCPServer tool target alongside the macOS/iOS
// app target, letting both share the exact same recurring-task completion/cancellation logic
// instead of maintaining separate copies that can silently drift apart.

enum CadenceTaskRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisTask
    case thisAndFuture

    var label: String {
        switch self {
        case .thisTask: return "Only This Task"
        case .thisAndFuture: return "This And Future Tasks"
        }
    }
}

enum CadenceTaskRecurrenceWorkflowSupport {
    static func markDone(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = now
        task.status = .done
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    /// Cancelling a single occurrence skips it, but the recurring series must keep going —
    /// otherwise the whole future series silently dies the first time anyone cancels instead of completes.
    static func markCancelled(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = nil
        task.status = .cancelled
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    static func markTodo(_ task: AppTask) {
        task.completedAt = nil
        task.status = .todo
    }

    private static func spawnNextOccurrenceIfNeeded(from task: AppTask, in context: ModelContext, now: Date) {
        guard task.isRecurring, task.recurrenceSpawnedTaskID == nil else { return }
        ensureRecurrenceSeriesMetadata(for: task)
        let nextTask = makeNextRecurringTask(from: task, now: now)
        context.insert(nextTask)
        task.recurrenceSpawnedTaskID = nextTask.id
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
        scope: CadenceTaskRecurrenceEditScope
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
        scope: CadenceTaskRecurrenceEditScope
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

    private static func makeNextRecurringTask(from task: AppTask, now: Date) -> AppTask {
        let nextTask = AppTask(title: task.title)
        nextTask.notes = task.notes
        nextTask.priority = task.priority
        nextTask.recurrenceRule = task.recurrenceRule
        nextTask.estimatedMinutes = max(task.estimatedMinutes, 30)
        nextTask.sectionName = task.sectionName
        nextTask.area = task.area
        nextTask.project = task.project
        nextTask.context = task.context
        nextTask.goal = task.goal
        nextTask.tags = task.sortedTags
        nextTask.recurrenceSeriesIDRaw = task.recurrenceSeriesID.uuidString
        nextTask.recurrenceSourceTaskID = task.id
        nextTask.recurrenceOccurrenceIndex = task.recurrenceOccurrenceIndex + 1

        let todayKey = DateFormatters.dateKey(from: now)
        if !task.dueDate.isEmpty {
            nextTask.dueDate = nextRecurrenceDateKey(from: task.dueDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.dueDate
        }
        if !task.scheduledDate.isEmpty {
            nextTask.scheduledDate = nextRecurrenceDateKey(from: task.scheduledDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.scheduledDate
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

    /// Shifts one recurrence period forward from whichever is later: the occurrence's own date or today.
    /// A daily/weekly/etc. task completed long after it was last due (e.g. a week-stale daily task)
    /// should catch up to today rather than advancing by one period from its stale date, which would
    /// just produce another still-overdue occurrence.
    private static func nextRecurrenceDateKey(from key: String, todayKey: String, recurrence: TaskRecurrenceRule) -> String? {
        guard recurrence != .none else { return nil }
        let anchorKey = max(key, todayKey)
        return shiftedDateKey(anchorKey, recurrence: recurrence)
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
