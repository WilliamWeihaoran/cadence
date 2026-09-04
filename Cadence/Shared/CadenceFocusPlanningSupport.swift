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

    /// The pending, non-committing write `complete(_:elapsedSeconds:modelContext:commit:)` below
    /// needs — banking and settling have to land as one commit, so this cannot save on its own.
    ///
    /// **Renamed from `logElapsedSeconds(_:to:in:)` (T-654).** The bundle-shaped door in
    /// `CadenceFocusBundleSupport.swift` used to share that name while *also* being
    /// `logElapsedSeconds`, just committing — and `CadenceSaveCommitDisciplineTests`' commit index
    /// "resolves a call by name and type and cannot see an argument list, so a name is only allowed
    /// to vouch for itself when every overload of it agrees" (see `CadenceTaskMutationSupport`'s
    /// `createBundle`/`insertBundle` split for the same reasoning). One overload committing and one
    /// deliberately not is exactly the disagreement that rule exists to catch, and it made
    /// `iOSFocusView.logBundleSession`'s real commit invisible to the scan. `bank` is this file's
    /// own vocabulary for the write (`CadenceFocusLedger.bank`), so the rename costs nothing a
    /// reader did not already know.
    static func bankElapsedSeconds(_ seconds: Int, to task: AppTask, in modelContext: ModelContext) {
        let minutes = minutes(fromElapsedSeconds: seconds)
        guard minutes > 0 else { return }

        CadenceFocusLedger.bank(minutes, forTaskAndItsList: task, in: modelContext)
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
    ///
    /// **Throws now (T-654).** The subject-shaped version banks through `endSession`, which commits
    /// and can refuse; this forwarder has nothing of its own to add to that answer, so it passes the
    /// throw straight up rather than swallowing it into a state the caller cannot tell from success.
    static func commitElapsed(
        leaving outgoingTask: AppTask?,
        switchingTo nextTaskID: UUID,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> CadenceFocusTimerState {
        try commitElapsed(
            leaving: outgoingTask.map { .task($0) },
            switchingTo: .task(nextTaskID),
            state: state,
            modelContext: modelContext,
            now: now,
            commit: commit
        )
    }

    /// Completion must route through `CadenceTaskRecurrenceWorkflowSupport` rather than setting
    /// `status`/`completedAt` inline: a recurring task finished here would otherwise go done with no
    /// successor, silently ending the series on whichever platform happened to use this helper.
    ///
    /// **It throws and takes `commit:` now (T-636(c)).** It used to end `try? modelContext.save()`,
    /// and `markDone` reaches `spawnNextOccurrenceIfNeeded` → `context.insert(nextTask)` — so
    /// finishing a repeating task from the focus timer minted its successor as a *pending* row in
    /// the app's one `ModelContext`, for the next unrelated `save()` to take or the next unrelated
    /// `rollback()` to discard. That is [[T-636]](a)'s defect reached through the other door: the
    /// completion spine's `toggleCompletion` was fixed there, and this helper is the second way a
    /// task is settled.
    ///
    /// **The minutes are undone too, and that half is not decoration.** `logElapsedSeconds` writes
    /// with `+=`, so the rule's standing justification for swallowing a commit — *"the next fetch
    /// corrects it"* — does not hold: a fetch re-reads whatever the accumulator now holds, and an
    /// accumulator that lost a write stays wrong for ever. `commitSettle` restores the status, the
    /// timestamp and the successor; `BankedMinutes` restores the three counters it cannot see.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func complete(
        _ task: AppTask,
        elapsedSeconds: Int,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let banked = BankedMinutes(task)
        bankElapsedSeconds(elapsedSeconds, to: task, in: modelContext)
        do {
            try CadenceTaskMutationSupport.commitSettle(task, in: modelContext, commit: commit) {
                CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
            }
        } catch {
            banked.restore(in: modelContext)
            throw error
        }
    }

    /// The three accumulators `bankElapsedSeconds(_:to:)` adds to, captured before the write.
    ///
    /// A snapshot rather than a subtraction, for the reason `CadenceTaskFieldSnapshot` gives:
    /// putting the old value back is an exact no-op when the commit lands and an exact undo when
    /// it does not, whereas `-= minutes` would have to agree for ever with a rounding rule that
    /// lives somewhere else.
    ///
    /// The container is captured as well as its count, because `restore()` must write back to the
    /// object the write reached — not to whatever `task.project` answers afterwards.
    ///
    /// **It undoes the ledger rows as well as the counters, and it has to.** Since T-621 the same
    /// write also inserts a `FocusSessionLog` per counter. Putting the counter back and leaving the
    /// row would be worse than not restoring at all: the row is a *pending insert* in the app's one
    /// `ModelContext`, so the next unrelated `save()` takes it, and the next
    /// `CadenceFocusLedger.reconcile(in:)` then raises the counter back to include a session the
    /// user was told was not recorded. Rows are identified by what was present beforehand rather
    /// than by asking `bank` what it wrote, so a future second row on the same write is undone too.
    ///
    /// **Not `private` (T-654).** `CadenceFocusBundleSupport.swift`'s `distributeMinutes` needs the
    /// identical snapshot-and-restore shape for the tasks a block session credits, and a second copy
    /// of this struct would be the near-duplicate `CadenceBundleTaskRowSupport`'s own doc warns
    /// against. Both files extend the same `CadenceFocusSupport`, so this is reached as
    /// `CadenceFocusSupport.BankedMinutes` from either.
    struct BankedMinutes {
        private let task: AppTask
        private let taskMinutes: Int
        private let project: Project?
        private let projectMinutes: Int
        private let area: Area?
        private let areaMinutes: Int
        private let existingRowIDs: Set<ObjectIdentifier>

        init(_ task: AppTask) {
            self.task = task
            taskMinutes = task.actualMinutes
            project = task.project
            projectMinutes = task.project?.loggedMinutes ?? 0
            area = task.area
            areaMinutes = task.area?.loggedMinutes ?? 0
            existingRowIDs = Set(
                Self.rows(task: task, project: task.project, area: task.area).map(ObjectIdentifier.init)
            )
        }

        func restore(in modelContext: ModelContext) {
            task.actualMinutes = taskMinutes
            project?.loggedMinutes = projectMinutes
            area?.loggedMinutes = areaMinutes

            for row in Self.rows(task: task, project: project, area: area)
            where !existingRowIDs.contains(ObjectIdentifier(row)) {
                row.task = nil
                row.project = nil
                row.area = nil
                modelContext.delete(row)
            }
        }

        private static func rows(task: AppTask, project: Project?, area: Area?) -> [FocusSessionLog] {
            (task.focusSessions ?? []) + (project?.focusSessions ?? []) + (area?.focusSessions ?? [])
        }
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

// `CadenceHabitSupport.toggle` lived here and was one of four open-coded copies of the habit
// check-in toggle (T-359). It moved to `Services/CadenceHabitCompletionStore.swift`, which the
// widget extension's target also compiles — this file's target does not include it, so a shared
// toggle here could never have been the *one* toggle while `ToggleHabitCompletionIntent` existed.
