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

    /// Whether a task can be the **subject** of a focus session at all.
    ///
    /// This predicate is not new — it is the first line of `readyTasks` below, which both Focus
    /// pickers have always filtered through, and the condition macOS's `MacTaskRow.focusButtonSlot`
    /// spells to decide whether to draw its hover ▶ at all. What is new is that it has a name, so
    /// the *entry points* can ask the same question the picker asks. Every iOS entry added by T-266
    /// and T-273 asked nothing: `iOSFocusView.pickItem(for:)` deliberately falls back to the whole
    /// store when the picker does not list a handed-over target, so "Focus" on a settled task really
    /// started a session and really banked its minutes into `actualMinutes` — and from there into
    /// `area.loggedMinutes` / `project.loggedMinutes`, which an hours-based `Goal` reads. Logging
    /// work against something you cancelled is not a cosmetic divergence (T-276).
    ///
    /// Stated positively as "can focus" rather than negatively as "is settled": the surfaces reading
    /// it are deciding whether to *offer* something, and `CadenceTaskQuerySupport.isFinishedTask`
    /// already owns the other phrasing for the surfaces that are deciding where to file a row.
    static func canFocus(_ task: AppTask) -> Bool {
        !task.isDone && !task.isCancelled
    }

    static func readyTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { canFocus($0) }
            .sorted { lhs, rhs in
                let lhsScore = focusScore(for: lhs, todayKey: todayKey)
                let rhsScore = focusScore(for: rhs, todayKey: todayKey)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                // Newest first among equal scores, then the repo's total tie-break. This list is
                // read head-first — Focus offers the top of it — so a comparator that stopped at
                // `createdAt` changed *which* task was offered, not merely the order behind it:
                // tasks created in one batch (a rollover, a migration, a paste) share a timestamp.
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return TaskOrdering.fallbackPrecedes(lhs, rhs)
            }
    }

    /// Deadline-only overdue test, for callers holding a date key rather than a task. Forwards to
    /// `AppTask.isDueDateOverdue`, which owns the comparison; use `task.isOverdue(todayKey:)`
    /// whenever a task is in hand, because that one also answers the `isDone` half.
    static func isOverdue(dueDateKey: String, todayKey: String) -> Bool {
        AppTask.isDueDateOverdue(dueDateKey, todayKey: todayKey)
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

    /// The stopwatch state after the play/pause control on a pick row is tapped.
    ///
    /// The rows in the focus picker each carry a play affordance. It used to be decorative — part
    /// of the row's own label, so tapping it only re-selected the task and left the timer at
    /// 00:00. This is the behaviour that makes it honest.
    ///
    /// Tapping the control on the task already loaded toggles it, so one row is start and pause.
    /// Tapping a *different* task's control starts that task from zero rather than inheriting the
    /// elapsed count: the seconds on the clock were measured against the task they were started
    /// on, and carrying them over would log one task's minutes onto another when the session is
    /// finished.
    /// Forwards to the target-shaped rule in `CadenceFocusBundleSupport.swift`. Two bodies here
    /// would be two answers to "does tapping play on another row inherit the clock", and a bundle
    /// row is exactly another row.
    static func timerState(
        afterPlayTapOn tappedTaskID: UUID,
        selectedTaskID: UUID?,
        state: CadenceFocusTimerState,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        timerState(
            afterPlayTapOn: .task(tappedTaskID),
            selectedTarget: selectedTaskID.map { .task($0) },
            state: state,
            now: now
        )
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

    /// Elapsed stopwatch seconds as whole logged minutes.
    ///
    /// Nearest-minute, not rounded up. macOS's timer used to ceil, so ten 61-second sessions
    /// reported twenty minutes of work for ten minutes done, and the same stopwatch reading
    /// logged a different number on each platform. Logged time is a record; systematic
    /// over-reporting is worse than losing a partial minute.
    static func minutes(fromElapsedSeconds seconds: Int) -> Int {
        max(0, Int((Double(seconds) / 60.0).rounded()))
    }

    static func logElapsedSeconds(_ seconds: Int, to task: AppTask) {
        let minutes = minutes(fromElapsedSeconds: seconds)
        guard minutes > 0 else { return }

        task.actualMinutes += minutes
        if let project = task.project {
            project.loggedMinutes += minutes
        } else if let area = task.area {
            area.loggedMinutes += minutes
        }
    }

    /// Leave one task for another the way macOS's `FocusManager` does: bank the seconds the
    /// outgoing task earned, then hand the incoming task a clock at zero. Returns the state the
    /// stopwatch carries into `nextTaskID`.
    ///
    /// iOS reset the clock on a switch instead of committing it, on **both** of its switch paths —
    /// the picker row's select and the row's own play control — so every minute measured before a
    /// switch was dropped. The visible consequence was that a goal with
    /// `progressType == "hours"` could only be advanced from a Mac, because `loggedMinutes` on the
    /// list behind it only ever moved through this helper.
    ///
    /// Re-selecting the task already focused returns the state untouched: that is not leaving a
    /// session, and zeroing the clock there was the other half of the same discard. Under a whole
    /// minute nothing is written — `logElapsedSeconds` rounds to the nearest minute, and a zero is
    /// not worth a `save()`.
    ///
    /// Forwards to the subject-shaped version in `CadenceFocusBundleSupport.swift`, which is the
    /// same rule with a `TaskBundle` allowed as the thing being left.
    static func commitElapsed(
        leaving outgoingTask: AppTask?,
        switchingTo nextTaskID: UUID,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        commitElapsed(
            leaving: outgoingTask.map { .task($0) },
            switchingTo: .task(nextTaskID),
            state: state,
            modelContext: modelContext,
            now: now
        )
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

    /// Habits attached to this goal **or to any of its milestones**.
    ///
    /// This read `goal.habits` flat while `GoalContributionResolver` recursed sub-goals for tasks,
    /// so iOS rendered a milestone-attached habit's task contribution in the percentage and "0
    /// habits" beside it — and once the momentum resolver started recursing, the iPhone's goal
    /// list ("3 milestones / 0 habits") disagreed with the Milestone widget on the same phone
    /// ("0/2 habits today"). One traversal, shared, so the two cannot drift again.
    static func habits(for goal: Goal) -> [Habit] {
        GoalHabitMomentumResolver.linkedHabits(for: goal).sorted { $0.order < $1.order }
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
