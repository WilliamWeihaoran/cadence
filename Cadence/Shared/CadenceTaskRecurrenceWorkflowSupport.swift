import Foundation
import SwiftData

// This file intentionally depends only on Foundation + SwiftData (no SwiftUI) so it can be
// compiled directly into the headless CadenceMCPServer tool target alongside the macOS/iOS
// app target, letting both share the exact same recurring-task completion/cancellation logic
// instead of maintaining separate copies that can silently drift apart.

nonisolated enum CadenceTaskRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisTask
    case thisAndFuture

    var label: String {
        switch self {
        case .thisTask: return "Only This Task"
        case .thisAndFuture: return "This And Future Tasks"
        }
    }
}

nonisolated enum CadenceTaskRecurrenceWorkflowSupport {
    static func markDone(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = now
        task.status = .done
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    /// Cancelling a single occurrence skips it, but the recurring series must keep going —
    /// otherwise the whole future series silently dies the first time anyone cancels instead of completes.
    ///
    /// `completedAt` is "when this task stopped being open", not "when it was accomplished", so a
    /// cancellation records it exactly as `markDone` does (T-202). It used to be cleared, and
    /// clearing it was what kept a cancelled task out of Today's Completed section: that section's
    /// only ground for a task whose do and due dates are empty or in the past is `completedAt`
    /// falling inside today, and macOS's `TasksPanelDerivedState` asks about `completedAt` and
    /// nothing else. So abandoning an overdue task reached All Tasks → Completed and no Today
    /// section at all.
    ///
    /// This changes the **semantics of existing rows**, not the column — there is no
    /// `SchemaMigrationPlan`, and none is wanted. Tasks cancelled by an earlier build keep a nil
    /// timestamp and stay out of Today's Completed; nothing backfills them, because the only
    /// honest value for "when was this abandoned" is one we never recorded.
    ///
    /// Callers that treated a nil `completedAt` as part of the cancelled state must not read it
    /// that way any more: `status == .cancelled` is the whole test. `CadenceWriteService`'s
    /// `cancelTask` / `bulkCancelTasks` idempotency guards were the two that did.
    static func markCancelled(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = now
        task.status = .cancelled
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    static func markTodo(_ task: AppTask) {
        task.completedAt = nil
        task.status = .todo
    }

    /// Settles a task **without** advancing its series — the bulk counterpart to `markDone` and
    /// `markCancelled`, for a container being wound down rather than a task being finished.
    ///
    /// Those two are *transitions* about one occurrence: they stamp `completedAt` and then call
    /// `spawnNextOccurrenceIfNeeded`. That is right when a person finishes or skips a single task,
    /// and wrong for every bulk path, because the successor inherits `area`, `project` and
    /// `sectionName` — so completing or archiving a list would mint fresh open work inside the list
    /// that was just closed, and archiving a kanban column would refill the column. `docs/TODO.md`
    /// T-213 and T-214 both record that hazard; this is the shape a bulk caller is supposed to use
    /// instead of reaching for `markDone` / `markCancelled` / `applyStatusCompletion`.
    ///
    /// What it does *not* skip is the timestamp. `completedAt` is "when this stopped being open",
    /// not "when it was accomplished" (T-202), so a bulk cancellation records it exactly as a
    /// single one does — a bulk cancel that left it nil produced settled work that reached no
    /// Today Completed section on either platform (T-212). The invariant is the same one
    /// `normalizeCompletionState` states: a settled status carries a timestamp, an open status
    /// carries none. Pass one `now` for a whole batch so a single user action does not scatter
    /// timestamps across it.
    static func settleWithoutAdvancingSeries(_ task: AppTask, as status: TaskStatus, now: Date = Date()) {
        switch status {
        case .done, .cancelled:
            task.completedAt = now
            task.status = status
        case .todo, .inProgress:
            task.completedAt = nil
            task.status = status
        }
    }

    /// If a predecessor's recorded `recurrenceSpawnedTaskID` points at a task being deleted, that
    /// predecessor would otherwise believe the series already has a live next occurrence forever —
    /// even though that occurrence no longer exists. That silently kills the series: the predecessor
    /// can never spawn a replacement, including if it's later reopened and completed again.
    ///
    /// Walk forward through the chain of *also-deleted* successors (covers deleting several
    /// consecutive occurrences in one batch, e.g. a multi-select delete) to find the first surviving
    /// occurrence and re-point the predecessor directly at it, or clear the pointer to nil if nothing
    /// in the chain survives. Callers on every platform must run this before actually deleting the
    /// tasks — sharing one implementation here (rather than each delete path reimplementing it) is
    /// what keeps that guarantee true everywhere.
    static func repairDanglingRecurrenceLinks(forDeleted deletedTasks: [AppTask], allTasks: [AppTask]) {
        let deletedByID = Dictionary(uniqueKeysWithValues: deletedTasks.map { ($0.id, $0) })
        guard !deletedByID.isEmpty else { return }

        func survivingSuccessor(startingFrom taskID: UUID) -> UUID? {
            var seen = Set<UUID>()
            var currentID: UUID? = taskID
            while let id = currentID, seen.insert(id).inserted {
                guard let deletedTask = deletedByID[id] else { return id }
                currentID = deletedTask.recurrenceSpawnedTaskID
            }
            return nil
        }

        for task in allTasks where deletedByID[task.id] == nil {
            guard let spawnedID = task.recurrenceSpawnedTaskID, deletedByID[spawnedID] != nil else { continue }
            task.recurrenceSpawnedTaskID = survivingSuccessor(startingFrom: spawnedID)
        }
    }

    /// Spawns the successor unless the series' end condition (see `TaskRecurrenceEndMode`) says the
    /// series stops here. The end check has to happen *before* the successor is built: assigning
    /// relationships (area/project/goal/context/tags) onto a freshly-made `AppTask` can pull it into
    /// the context through the inverse side, so a "build it then throw it away" shape would risk
    /// leaking a phantom occurrence. We therefore compute the successor's dates first, ask the end
    /// condition about them, and only then materialize the task.
    ///
    /// When the series does end, the current task still completes/cancels normally (its status was
    /// already set by the caller) and its `recurrenceSpawnedTaskID` stays nil — no dangling pointer.
    private static func spawnNextOccurrenceIfNeeded(from task: AppTask, in context: ModelContext, now: Date) {
        guard task.isRecurring, task.recurrenceSpawnedTaskID == nil else { return }
        ensureRecurrenceSeriesMetadata(for: task)

        guard !task.recurrenceHasEnded else { return }
        let plannedDates = plannedNextDates(for: task, now: now)
        guard task.shouldSpawnNextOccurrence(nextDateKey: plannedDates.anchorKey(now: now)) else { return }

        let nextTask = makeNextRecurringTask(from: task, dates: plannedDates)
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

    /// Sets the series end condition. Values that don't belong to the chosen mode are normalized
    /// away so a stale end date can't resurface if the user flips back to `.onDate` later with a
    /// half-configured value, and so `.never` never leaves a stray limit behind.
    static func applyRecurrenceEnd(
        mode: TaskRecurrenceEndMode,
        endDateKey: String = "",
        endCount: Int = 0,
        to task: AppTask,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) {
        ensureRecurrenceSeriesMetadata(for: task)
        let normalizedDate = mode == .onDate ? endDateKey : ""
        let normalizedCount = mode == .afterCount ? max(1, endCount) : 0

        for target in recurrenceTargets(from: task, allTasks: allTasks, scope: scope) {
            ensureRecurrenceSeriesMetadata(for: target)
            target.recurrenceEndMode = mode
            target.recurrenceEndDate = normalizedDate
            target.recurrenceEndCount = normalizedCount
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

    /// The dates the next occurrence would carry. Each date only advances if the predecessor
    /// actually had one, matching the historical behavior.
    struct PlannedRecurrenceDates {
        var dueDate: String = ""
        var scheduledDate: String = ""

        /// The single date key that represents this occurrence for end-date purposes. Do date
        /// (`scheduledDate`) wins over due date because that's the same precedence
        /// `recurrenceSortDateKey` already uses to decide "when is this occurrence". A dateless
        /// occurrence is anchored to `now` — that's the day it would actually appear.
        func anchorKey(now: Date) -> String {
            if !scheduledDate.isEmpty { return scheduledDate }
            if !dueDate.isEmpty { return dueDate }
            return DateFormatters.dateKey(from: now)
        }
    }

    private static func plannedNextDates(for task: AppTask, now: Date) -> PlannedRecurrenceDates {
        var planned = PlannedRecurrenceDates()
        let todayKey = DateFormatters.dateKey(from: now)
        if !task.dueDate.isEmpty {
            planned.dueDate = nextRecurrenceDateKey(from: task.dueDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.dueDate
        }
        if !task.scheduledDate.isEmpty {
            planned.scheduledDate = nextRecurrenceDateKey(from: task.scheduledDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.scheduledDate
        }
        return planned
    }

    private static func makeNextRecurringTask(from task: AppTask, dates: PlannedRecurrenceDates) -> AppTask {
        let nextTask = AppTask(title: task.title)
        nextTask.notes = task.notes
        nextTask.priority = task.priority
        nextTask.recurrenceRule = task.recurrenceRule
        // The successor must inherit the end condition, or the series forgets its own limit after
        // one hop and starts repeating forever again.
        nextTask.recurrenceEndModeRaw = task.recurrenceEndModeRaw
        nextTask.recurrenceEndDate = task.recurrenceEndDate
        nextTask.recurrenceEndCount = task.recurrenceEndCount
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

        nextTask.dueDate = dates.dueDate
        if !dates.scheduledDate.isEmpty {
            nextTask.scheduledDate = dates.scheduledDate
            nextTask.scheduledStartMin = task.scheduledStartMin
        }

        if let subtasks = task.subtasks {
            let copies = subtasks
                .sorted { $0.order < $1.order }
                .map { source -> Subtask in
                    let copy = Subtask(title: source.title)
                    copy.order = source.order
                    return copy
                }
            nextTask.subtasks = copies
            // Both sides, explicitly. Assigning only `nextTask.subtasks` leaves each copy's
            // `parentTask` to SwiftData's inverse back-population, and the delete and export paths
            // read `Subtask.parentTask` *directly* — `CadenceTaskMutationSupport.deleteTasks`
            // selects a task's subtasks by that field, and `CadenceDataExportService` writes
            // `parentTaskID` from it. A copy whose inverse has not been populated by the time one
            // of those runs is an orphan the delete sweep cannot see. This is the same distrust
            // that makes the shared delete path nil the inverse before deleting.
            for copy in copies {
                copy.parentTask = nextTask
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
