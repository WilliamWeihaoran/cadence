import Foundation
import SwiftUI

enum CadenceTaskQuerySupport {
    // `isInActiveContainer` is a property on `AppTask` (in `Models/`, which every target compiles,
    // unlike `Shared/`). There is deliberately no free-function wrapper here: passing a
    // main-actor-isolated static method *reference* to `filter` strips its isolation and warns,
    // which is exactly what the wrapper caused at three call sites. Use `filter(\.isInActiveContainer)`.

    static func activeTodayTasks(
        from tasks: [AppTask],
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                // The four buckets macOS's `TasksPanelDerivedState` shows on Today, in the same
                // order: due today, past due, do today, and — the one this used to omit — *past
                // do*. A task planned for yesterday and never finished is still today's work; it
                // was appearing nowhere on iPad while macOS listed it under "Past Do" and offered
                // the rollover banner for it.
                return task.dueDate == todayKey ||
                    !task.dueDate.isEmpty && task.dueDate < todayKey ||
                    task.scheduledDate == todayKey ||
                    !task.scheduledDate.isEmpty && task.scheduledDate < todayKey
            }
            .sorted { sortTodayTasks($0, $1, todayKey: todayKey, sortMode: sortMode) }
    }

    static func completedTodayTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { task in
                guard task.isDone && !task.isCancelled else { return false }
                if task.scheduledDate == todayKey || task.dueDate == todayKey { return true }
                if let completedAt = task.completedAt {
                    return DateFormatters.dateKey(from: completedAt) == todayKey
                }
                return false
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    /// The same four sections macOS's `todayDateSections` draws, in the same order. A due date
    /// outranks a do date, so a task is only ever considered for `pastDo` once both due buckets
    /// have passed on it.
    static func todayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTodayTaskGroup] {
        let overdue = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let dueToday = tasks.filter { $0.dueDate == todayKey }
        let claimedIDs = Set(overdue.map(\.id)).union(dueToday.map(\.id))
        let remaining = tasks.filter { !claimedIDs.contains($0.id) }

        return [
            CadenceTodayTaskGroup(kind: .overdue, tasks: overdue),
            CadenceTodayTaskGroup(
                kind: .pastDo,
                tasks: remaining.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate < todayKey }
            ),
            CadenceTodayTaskGroup(kind: .dueToday, tasks: dueToday),
            CadenceTodayTaskGroup(
                kind: .plannedToday,
                tasks: remaining.filter { $0.scheduledDate.isEmpty || $0.scheduledDate >= todayKey }
            )
        ]
        .filter { !$0.tasks.isEmpty }
    }

    static func activeInboxTasks(from tasks: [AppTask], sortMode: CadenceTaskSortMode) -> [AppTask] {
        tasks
            .filter { $0.area == nil && $0.project == nil && !$0.isDone && !$0.isCancelled }
            .sorted { sortTasks($0, $1, sortMode: sortMode) }
    }

    static func completedInboxTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks
            .filter { $0.area == nil && $0.project == nil && $0.isDone && !$0.isCancelled }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    static func activeTasks(
        from tasks: [AppTask],
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { sortTasks($0, $1, sortMode: sortMode, sectionNames: sectionNames) }
    }

    static func completedTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks
            .filter { $0.isDone && !$0.isCancelled }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    static func sortedTasks(
        _ tasks: [AppTask],
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> [AppTask] {
        tasks.sorted { sortTasks($0, $1, sortMode: sortMode, sectionNames: sectionNames) }
    }

    static func sectionGroups(from tasks: [AppTask], sectionNames: [String]) -> [CadenceTaskDisplayGroup] {
        sectionNames.compactMap { sectionName in
            let sectionTasks = tasks.filter {
                $0.resolvedSectionName.caseInsensitiveCompare(sectionName) == .orderedSame
            }
            guard !sectionTasks.isEmpty else { return nil }
            return CadenceTaskDisplayGroup(
                id: "section-\(sectionName.lowercased())",
                title: sectionName,
                accent: Theme.blue,
                tasks: sectionTasks
            )
        }
    }

    static func dateDisplayGroups(
        from tasks: [AppTask],
        todayKey: String,
        includeDueToday: Bool = true
    ) -> [CadenceTaskDisplayGroup] {
        let buckets = dateBuckets(for: tasks, todayKey: todayKey)
        let overdue = tasks.filter { buckets.overdueIDs.contains($0.id) }
        let dueToday = tasks.filter { buckets.dueTodayIDs.contains($0.id) }
        let doToday = tasks.filter { buckets.doTodayIDs.contains($0.id) }
        let scheduled = tasks.filter {
            !$0.scheduledDate.isEmpty &&
            $0.scheduledDate != todayKey &&
            !buckets.contains($0)
        }
        let unscheduled = tasks.filter {
            $0.scheduledDate.isEmpty &&
            !buckets.contains($0)
        }

        var groups = [
            CadenceTaskDisplayGroup(id: "overdue", title: "Overdue", accent: Theme.red, tasks: overdue)
        ]
        if includeDueToday {
            groups.append(CadenceTaskDisplayGroup(id: "due-today", title: "Due Today", accent: Theme.red.opacity(0.8), tasks: dueToday))
        }
        groups.append(contentsOf: [
            CadenceTaskDisplayGroup(id: "do-today", title: "Do Today", accent: Theme.blue, tasks: doToday),
            CadenceTaskDisplayGroup(id: "scheduled", title: "Scheduled", accent: Theme.dim, tasks: scheduled),
            CadenceTaskDisplayGroup(id: "unscheduled", title: "Unscheduled", accent: Theme.amber, tasks: unscheduled)
        ])

        return groups.filter { !$0.tasks.isEmpty }
    }

    static func planningDisplayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTaskDisplayGroup] {
        let overdue = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let dueToday = tasks.filter { $0.dueDate == todayKey }
        let scheduledToday = tasks.filter { $0.scheduledDate == todayKey && $0.dueDate != todayKey }
        let upcoming = tasks
            .filter { task in
                let dueFuture = !task.dueDate.isEmpty && task.dueDate > todayKey
                let scheduledFuture = !task.scheduledDate.isEmpty && task.scheduledDate > todayKey
                return dueFuture || scheduledFuture
            }
            .sorted { planningKey(for: $0) < planningKey(for: $1) }
        let unscheduled = tasks.filter { $0.dueDate.isEmpty && $0.scheduledDate.isEmpty }

        return [
            CadenceTaskDisplayGroup(id: "overdue", title: "Overdue", accent: Theme.red, tasks: overdue),
            CadenceTaskDisplayGroup(id: "due-today", title: "Due Today", accent: Theme.amber, tasks: dueToday),
            CadenceTaskDisplayGroup(id: "scheduled-today", title: "Scheduled Today", accent: Theme.blue, tasks: scheduledToday),
            CadenceTaskDisplayGroup(id: "upcoming", title: "Upcoming", accent: Theme.purple, tasks: upcoming),
            CadenceTaskDisplayGroup(id: "unscheduled", title: "Unscheduled", accent: Theme.dim, tasks: unscheduled)
        ]
        .filter { !$0.tasks.isEmpty }
    }

    static func priorityDisplayGroups(from tasks: [AppTask]) -> [CadenceTaskDisplayGroup] {
        TaskPriority.allCases.reversed().compactMap { priority in
            let priorityTasks = tasks.filter { $0.priority == priority }
            guard !priorityTasks.isEmpty else { return nil }
            return CadenceTaskDisplayGroup(
                id: "priority-\(priority.rawValue)",
                title: priority.label,
                accent: Theme.priorityColor(priority),
                tasks: priorityTasks,
                dropKey: "priority:\(priority.rawValue)"
            )
        }
    }

    static func nextTaskOrder(in tasks: [AppTask]) -> Int {
        (tasks.map(\.order).max() ?? -1) + 1
    }

    static func makeTask(
        title: String,
        allTasks: [AppTask],
        scheduledDate: String? = nil,
        estimatedMinutes: Int = 30
    ) -> AppTask? {
        var priority: TaskPriority = .none
        let trimmed = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        guard !trimmed.isEmpty else { return nil }

        let task = AppTask(title: trimmed)
        task.priority = priority
        task.estimatedMinutes = estimatedMinutes
        task.order = nextTaskOrder(in: allTasks)
        if let scheduledDate {
            task.scheduledDate = scheduledDate
        }
        return task
    }

    /// Free-function spelling of `TaskPriority.rank`, kept because several sort comparators here
    /// read better with it. The definition lives on the enum.
    static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }

    /// Mirrors the section order in `todayGroups` so a flat, un-grouped Today list still reads
    /// past due → past do → due today → do today.
    private static func todayRank(_ task: AppTask, todayKey: String) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 2 }
        if !task.scheduledDate.isEmpty && task.scheduledDate < todayKey { return 1 }
        if task.scheduledDate == todayKey { return 3 }
        return 4
    }

    private static func sortTodayTasks(
        _ lhs: AppTask,
        _ rhs: AppTask,
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> Bool {
        let leftRank = todayRank(lhs, todayKey: todayKey)
        let rightRank = todayRank(rhs, todayKey: todayKey)
        if leftRank != rightRank { return leftRank < rightRank }
        return sortTasks(lhs, rhs, sortMode: sortMode)
    }

    private static func sortTasks(
        _ lhs: AppTask,
        _ rhs: AppTask,
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> Bool {
        switch sortMode {
        case .listOrder:
            if let sectionNames, lhs.resolvedSectionName != rhs.resolvedSectionName {
                return sectionRank(lhs.resolvedSectionName, in: sectionNames) < sectionRank(rhs.resolvedSectionName, in: sectionNames)
            }
            return lhs.order < rhs.order
        case .priority:
            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }
            return lhs.order < rhs.order
        case .doDate:
            let leftDate = sortDateKey(lhs.scheduledDate)
            let rightDate = sortDateKey(rhs.scheduledDate)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            let leftTimed = lhs.scheduledStartMin >= 0
            let rightTimed = rhs.scheduledStartMin >= 0
            if leftTimed != rightTimed {
                return leftTimed
            }
            if leftTimed && lhs.scheduledStartMin != rhs.scheduledStartMin {
                return lhs.scheduledStartMin < rhs.scheduledStartMin
            }
            return lhs.order < rhs.order
        case .dueDate:
            if lhs.dueDate != rhs.dueDate {
                if lhs.dueDate.isEmpty { return false }
                if rhs.dueDate.isEmpty { return true }
                return lhs.dueDate < rhs.dueDate
            }
            return lhs.order < rhs.order
        case .newest:
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// The one date-bucketing rule: due-before-today wins, then due-today, and only tasks in
    /// neither due bucket can be "do today". Internal rather than `private` so tests reach the
    /// copy production runs — a `private` spelling here is what kept a dead twin alive in
    /// `TaskSortHelpers`.
    static func dateBuckets(for tasks: [AppTask], todayKey: String) -> CadenceTaskDateBuckets {
        var overdueIDs = Set<UUID>()
        var dueTodayIDs = Set<UUID>()
        var doTodayIDs = Set<UUID>()

        for task in tasks {
            if !task.dueDate.isEmpty && task.dueDate < todayKey {
                overdueIDs.insert(task.id)
            } else if task.dueDate == todayKey {
                dueTodayIDs.insert(task.id)
            }
        }

        for task in tasks where !overdueIDs.contains(task.id) && !dueTodayIDs.contains(task.id) {
            if task.scheduledDate == todayKey {
                doTodayIDs.insert(task.id)
            }
        }

        return CadenceTaskDateBuckets(
            overdueIDs: overdueIDs,
            dueTodayIDs: dueTodayIDs,
            doTodayIDs: doTodayIDs
        )
    }

    private static func planningKey(for task: AppTask) -> String {
        [task.dueDate, task.scheduledDate]
            .filter { !$0.isEmpty }
            .min() ?? "9999-99-99"
    }

    private static func sectionRank(_ name: String, in sectionNames: [String]) -> Int {
        sectionNames.firstIndex {
            $0.caseInsensitiveCompare(name) == .orderedSame
        } ?? Int.max
    }

    private static func sortDateKey(_ dateKey: String) -> String {
        dateKey.isEmpty ? "9999-99-99" : dateKey
    }
}
