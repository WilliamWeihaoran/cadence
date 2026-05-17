import Foundation
import SwiftData

enum CadenceTaskSortMode: String, CaseIterable, Hashable {
    case listOrder
    case priority
    case dueDate
    case newest
}

enum CadenceTodayTaskGroupKind: String, CaseIterable, Hashable {
    case overdue
    case dueToday
    case plannedToday

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueToday: return "Due Today"
        case .plannedToday: return "Planned Today"
        }
    }
}

struct CadenceTodayTaskGroup: Identifiable {
    let kind: CadenceTodayTaskGroupKind
    let tasks: [AppTask]

    var id: CadenceTodayTaskGroupKind { kind }
    var title: String { kind.title }
}

enum CadenceTaskQuerySupport {
    static func activeTodayTasks(
        from tasks: [AppTask],
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                return task.scheduledDate == todayKey ||
                    task.dueDate == todayKey ||
                    (!task.dueDate.isEmpty && task.dueDate < todayKey)
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

    static func todayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTodayTaskGroup] {
        [
            CadenceTodayTaskGroup(
                kind: .overdue,
                tasks: tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
            ),
            CadenceTodayTaskGroup(
                kind: .dueToday,
                tasks: tasks.filter { $0.dueDate == todayKey }
            ),
            CadenceTodayTaskGroup(
                kind: .plannedToday,
                tasks: tasks.filter { $0.dueDate != todayKey && !(!$0.dueDate.isEmpty && $0.dueDate < todayKey) }
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

    static func activeTasks(from tasks: [AppTask], sortMode: CadenceTaskSortMode) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { sortTasks($0, $1, sortMode: sortMode) }
    }

    static func completedTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks
            .filter { $0.isDone && !$0.isCancelled }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    static func sortedTasks(_ tasks: [AppTask], sortMode: CadenceTaskSortMode) -> [AppTask] {
        tasks.sorted { sortTasks($0, $1, sortMode: sortMode) }
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let task = AppTask(title: trimmed)
        task.estimatedMinutes = estimatedMinutes
        task.order = nextTaskOrder(in: allTasks)
        if let scheduledDate {
            task.scheduledDate = scheduledDate
        }
        return task
    }

    static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }

    private static func todayRank(_ task: AppTask, todayKey: String) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 1 }
        if task.scheduledDate == todayKey { return 2 }
        return 3
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
        sortMode: CadenceTaskSortMode
    ) -> Bool {
        switch sortMode {
        case .listOrder:
            return lhs.order < rhs.order
        case .priority:
            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
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
}

enum CadenceScheduleSupport {
    static func tasks(on dateKey: String, from tasks: [AppTask], includeCompleted: Bool = true) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isCancelled else { return false }
                guard includeCompleted || !task.isDone else { return false }
                return task.scheduledDate == dateKey || task.dueDate == dateKey
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func scheduledTasks(
        on dateKey: String,
        from tasks: [AppTask],
        includeCompleted: Bool = false,
        excludeBundled: Bool = false
    ) -> [AppTask] {
        tasks
            .filter {
                !$0.isCancelled &&
                (includeCompleted || !$0.isDone) &&
                (!excludeBundled || $0.bundle == nil) &&
                $0.scheduledDate == dateKey &&
                $0.scheduledStartMin >= 0
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func bundles(on dateKey: String, from bundles: [TaskBundle], includeCompleted: Bool = true) -> [TaskBundle] {
        bundles
            .filter { $0.dateKey == dateKey && (includeCompleted || !$0.isCompleted) }
            .sorted { $0.startMin < $1.startMin }
    }

    static func tasks(in hour: Int, from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.scheduledStartMin / 60 == hour }
    }

    static func bundles(in hour: Int, from bundles: [TaskBundle]) -> [TaskBundle] {
        bundles.filter { $0.startMin / 60 == hour }
    }

    static func itemCount(on dateKey: String, tasks: [AppTask], bundles: [TaskBundle]) -> Int {
        let taskCount = tasks.filter { !$0.isCancelled && ($0.scheduledDate == dateKey || $0.dueDate == dateKey) }.count
        let bundleCount = bundles.filter { $0.dateKey == dateKey }.count
        return taskCount + bundleCount
    }
}

struct CadenceFocusTimerState: Hashable {
    var isRunning = false
    var startedAt: Date?
    var accumulatedSeconds = 0

    func elapsedSeconds(now: Date = Date()) -> Int {
        accumulatedSeconds + (isRunning ? Int(now.timeIntervalSince(startedAt ?? now)) : 0)
    }

    mutating func toggle(now: Date = Date()) {
        if isRunning {
            accumulatedSeconds = elapsedSeconds(now: now)
            startedAt = nil
            isRunning = false
        } else {
            startedAt = now
            isRunning = true
        }
    }

    mutating func reset() {
        isRunning = false
        startedAt = nil
        accumulatedSeconds = 0
    }
}

enum CadenceFocusSupport {
    static func readyTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { lhs, rhs in
                let lhsScore = focusScore(for: lhs, todayKey: todayKey)
                let rhsScore = focusScore(for: rhs, todayKey: todayKey)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func sidebarDetail(for task: AppTask, todayKey: String, fallback: String = "Ready") -> String {
        if task.scheduledDate == todayKey { return "Scheduled today" }
        if task.dueDate == todayKey { return "Due today" }
        if !task.containerName.isEmpty { return task.containerName }
        return fallback
    }

    static func clockDisplay(elapsedSeconds: Int) -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func logElapsedSeconds(_ seconds: Int, to task: AppTask) {
        let minutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        guard minutes > 0 else { return }

        task.actualMinutes += minutes
        if let project = task.project {
            project.loggedMinutes += minutes
        } else if let area = task.area {
            area.loggedMinutes += minutes
        }
    }

    static func complete(_ task: AppTask, elapsedSeconds: Int, modelContext: ModelContext) {
        logElapsedSeconds(elapsedSeconds, to: task)
        task.status = .done
        task.completedAt = Date()
        try? modelContext.save()
    }

    private static func focusScore(for task: AppTask, todayKey: String) -> Int {
        var score = 0
        if task.scheduledDate == todayKey { score += 4 }
        if task.dueDate == todayKey { score += 3 }
        if !task.dueDate.isEmpty && task.dueDate < todayKey { score += 5 }
        score += CadenceTaskQuerySupport.priorityRank(task.priority)
        if task.actualMinutes == 0 { score += 1 }
        return score
    }
}

struct CadencePursuitSummary {
    let goals: [Goal]
    let habits: [Habit]

    var activeGoalCount: Int {
        goals.filter { $0.status == .active }.count
    }

    var activeHabitCount: Int {
        habits.count
    }

    var nextActionTitle: String? {
        goals.compactMap { GoalContributionResolver.summary(for: $0).nextActionTitle }.first
    }

    var dueHabitCount: Int {
        habits.filter(\.isDueToday).count
    }

    var doneHabitCount: Int {
        let todayKey = DateFormatters.todayKey()
        return habits.filter { $0.isDone(on: todayKey) }.count
    }
}

enum CadencePursuitSupport {
    static func goals(for pursuit: Pursuit) -> [Goal] {
        (pursuit.goals ?? []).sorted { $0.order < $1.order }
    }

    static func habits(for pursuit: Pursuit) -> [Habit] {
        (pursuit.habits ?? []).sorted { $0.order < $1.order }
    }

    static func summary(for pursuit: Pursuit) -> CadencePursuitSummary {
        CadencePursuitSummary(goals: goals(for: pursuit), habits: habits(for: pursuit))
    }
}

enum CadenceHabitSupport {
    static func toggle(_ habit: Habit, on dateKey: String, modelContext: ModelContext) {
        let existing = (habit.completions ?? []).filter { $0.date == dateKey }
        if existing.isEmpty {
            let completion = HabitCompletion(date: dateKey, habit: habit)
            modelContext.insert(completion)
            habit.completions = (habit.completions ?? []) + [completion]
        } else {
            for completion in existing {
                habit.completions = (habit.completions ?? []).filter { $0.id != completion.id }
                modelContext.delete(completion)
            }
        }
        try? modelContext.save()
    }
}
