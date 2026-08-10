import Foundation
import SwiftData

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

/// Segments of a one-line task detail: a context/scheduling `lead` and an independently styleable
/// `due` marker. Kept apart so a row can render "Scheduled today / Overdue Aug 2" with only the
/// overdue half in red.
struct CadenceTaskDetailLine: Hashable {
    let lead: String?
    let due: String?
    let isOverdue: Bool

    var text: String {
        [lead, due].compactMap { $0 }.joined(separator: " / ")
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

    static func isOverdue(dueDateKey: String, todayKey: String) -> Bool {
        !dueDateKey.isEmpty && dueDateKey < todayKey
    }

    /// Compact due-date label for focus and bundle rows. `nil` only when there is no due date at
    /// all, so an absent label reliably means "no deadline". Overdue is spelled out rather than
    /// left for the reader to infer from a bare past date, and the real day is always kept.
    ///
    /// Forwards to `CadenceWidgetDateSupport.dueLabel(for:todayKey:)`, which owns the single
    /// implementation of this vocabulary. It lives there, not here, because it has to be
    /// `nonisolated` for widget timeline providers while this file's `DateFormatters` statics are
    /// main-actor isolated. Keeping a second copy here is what let the widget drift to a bare
    /// "Overdue" with no date on it.
    static func dueLabel(forDueDateKey key: String, todayKey: String) -> String? {
        CadenceWidgetDateSupport.dueLabel(for: key, todayKey: todayKey)
    }

    /// Detail line for focus rows, split into segments so surfaces can tint the due segment red
    /// without staining the scheduling segment beside it.
    ///
    /// A due date always contributes when the task has one: falling through to the container name
    /// swaps a deadline signal for a neutral list name, which reads as "no deadline". The container
    /// name is a last resort for tasks that genuinely have no date to show.
    static func sidebarDetailParts(
        for task: AppTask,
        todayKey: String,
        fallback: String = "Ready"
    ) -> CadenceTaskDetailLine {
        let due = dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)
        let overdue = isOverdue(dueDateKey: task.dueDate, todayKey: todayKey)

        if task.scheduledDate == todayKey {
            return CadenceTaskDetailLine(lead: "Scheduled today", due: due, isOverdue: overdue)
        }
        if due != nil {
            return CadenceTaskDetailLine(lead: nil, due: due, isOverdue: overdue)
        }
        return CadenceTaskDetailLine(
            lead: task.containerName.isEmpty ? fallback : task.containerName,
            due: nil,
            isOverdue: false
        )
    }

    static func sidebarDetail(for task: AppTask, todayKey: String, fallback: String = "Ready") -> String {
        sidebarDetailParts(for: task, todayKey: todayKey, fallback: fallback).text
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

    /// Completion must route through `CadenceTaskRecurrenceWorkflowSupport` rather than setting
    /// `status`/`completedAt` inline: a recurring task finished here would otherwise go done with no
    /// successor, silently ending the series on whichever platform happened to use this helper.
    static func complete(_ task: AppTask, elapsedSeconds: Int, modelContext: ModelContext) {
        logElapsedSeconds(elapsedSeconds, to: task)
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
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

/// Rollup for a top-level goal and everything hanging off it — its milestones (`subGoals`)
/// and habits. Formerly `CadencePursuitSummary`, back when that grouping was its own model.
struct CadenceGoalGroupSummary {
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

enum CadenceGoalGroupSupport {
    /// Milestones nested directly under this goal.
    static func milestones(for goal: Goal) -> [Goal] {
        (goal.subGoals ?? []).sorted { $0.order < $1.order }
    }

    static func habits(for goal: Goal) -> [Habit] {
        (goal.habits ?? []).sorted { $0.order < $1.order }
    }

    static func summary(for goal: Goal) -> CadenceGoalGroupSummary {
        CadenceGoalGroupSummary(goals: milestones(for: goal), habits: habits(for: goal))
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
