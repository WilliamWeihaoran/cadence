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

/// Which occurrences a **delete** on a repeating task means.
///
/// The sibling of `CadenceTaskRecurrenceEditScope`, for the other question a repeating task can be
/// asked. They are deliberately **two** enums rather than one shared pair of cases: an edit's two
/// scopes are "only this task" and "this and future tasks", both of which rewrite rows that go on
/// existing, while a delete's are "remove this row and advance the series" and "remove this row and
/// let the series stop". Collapsing them would put a case on each enum that its own call sites must
/// never pass, which is the shape a reader resolves wrongly.
///
/// `wholeSeries` is the behaviour every delete had before [[T-6115]], and it stays the default
/// everywhere, so a bulk path or a list cascade keeps minting nothing.
nonisolated enum CadenceTaskRecurrenceDeleteScope: String, CaseIterable, Hashable {
    /// Remove this occurrence and advance the series past it, so the next one still appears.
    case thisOccurrence
    /// Remove this occurrence and leave the series with nothing to advance from.
    case wholeSeries

    var label: String {
        switch self {
        case .thisOccurrence: return "Delete This Occurrence"
        case .wholeSeries: return "Delete Series"
        }
    }
}

nonisolated enum CadenceTaskRecurrenceWorkflowSupport {
    /// Returns the successor it spawned, or `nil` — see `spawnNextOccurrenceIfNeeded` (T-628).
    @discardableResult
    static func markDone(_ task: AppTask, in context: ModelContext, now: Date = Date()) -> AppTask? {
        task.completedAt = now
        task.status = .done
        return spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
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
    /// Returns the successor it spawned, or `nil` — see `spawnNextOccurrenceIfNeeded` (T-628).
    @discardableResult
    static func markCancelled(_ task: AppTask, in context: ModelContext, now: Date = Date()) -> AppTask? {
        task.completedAt = now
        task.status = .cancelled
        return spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
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

    /// Advances the series past an occurrence that is about to be **deleted** rather than settled
    /// ([[T-6115]]).
    ///
    /// Until this existed, `markDone` and `markCancelled` were the only two ways a successor was
    /// ever minted, so deleting the live occurrence of a repeating task ended the repeat and
    /// neither platform's confirmation said so. `markCancelled`'s own doc already states the rule
    /// this restores: settling one occurrence must not kill the series. A delete scoped to one
    /// occurrence is the same event with the row removed instead of struck through.
    ///
    /// **It is a thin door onto `spawnNextOccurrenceIfNeeded`, on purpose.** Every condition that
    /// decides whether a series may advance — `recurrenceHasEnded`, `shouldSpawnNextOccurrence`,
    /// the series metadata, and the field copy `makeNextRecurringTask` performs — has to give the
    /// delete path the same answer it gives the settle path, and a second implementation beside
    /// `CadenceTaskMutationSupport.deleteTasks` is exactly the drift this file's header exists to
    /// prevent. What belongs to the caller is only *when* to ask: see `deleteTasks`, which calls
    /// this above `repairDanglingRecurrenceLinks` so the repair walks the fresh successor.
    ///
    /// Answers `nil` — having inserted nothing — when the series' end condition is already met, so
    /// deleting the **last** occurrence a finite recurrence would produce behaves exactly like
    /// deleting the series. That is the honest outcome: there is no next occurrence to keep.
    @discardableResult
    static func spawnSuccessorBeforeDeletingOccurrence(
        _ task: AppTask,
        in context: ModelContext,
        now: Date = Date()
    ) -> AppTask? {
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    /// Whether deleting `task` has a live series to ask the user about ([[T-6115]]).
    ///
    /// The one answer both platforms' delete confirmations ask before growing a second button, so
    /// a non-repeating task cannot gain one and the two surfaces cannot disagree about which tasks
    /// are repeating.
    ///
    /// Three conditions, and the second is the interesting one:
    ///
    /// - `isRecurring` — a plain task has no series, and its confirmation is untouched.
    /// - `recurrenceSpawnedTaskID == nil` — **this is what settles the past-occurrence question.**
    ///   A settled occurrence that already minted its successor cannot end the series by being
    ///   deleted: `repairDanglingRecurrenceLinks` re-points its predecessor at the survivor, and
    ///   the live occurrence is some other row. Offering a choice there would offer two buttons
    ///   that do the same thing, so it is not offered. The occurrences that *do* get the question
    ///   are the ones the series actually hangs from — which is the live one, and a settled one
    ///   whose spawn was refused and which is therefore the tail of the chain.
    /// - `!recurrenceHasEnded` — a count-limited series that has already produced its last
    ///   occurrence has no successor to keep, so again the two buttons would coincide.
    ///
    /// The date-limited sibling of that last case cannot be decided without a `ModelContext` to
    /// compute the successor's planned dates from, so a series whose end **date** has passed still
    /// offers the choice and "this occurrence" then spawns nothing. The cost of that is one
    /// superfluous question on a series that is over; the cost of taking a context parameter is a
    /// fetch inside a view body, on every row, to answer a question about a button's label.
    static func deleteOffersSeriesChoice(for task: AppTask) -> Bool {
        task.isRecurring && task.recurrenceSpawnedTaskID == nil && !task.recurrenceHasEnded
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
        // First wins on a shared id (T-6451), the rule `CadenceIdentityMap.firstWins` states. Spelt
        // out here because this file is also compiled into the widget and MCP targets, which do not
        // carry `CadenceIdentityMap`; `uniqueKeysWithValues:` trapped on two rows sharing an id.
        let deletedByID = Dictionary(deletedTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
    /// **Returns the successor, so the caller can undo the insert (T-628).** The row it inserts is
    /// the whole reason a completion needs a commit boundary rather than an autosave: a status
    /// field that did not land still reads right and is corrected by the next fetch, and a task
    /// that does or does not exist has no such halfway reading. The only party that can un-insert
    /// it is one holding the object, so the object comes back up the chain —
    /// `TaskWorkflowService.commitSettle` hands it to
    /// `CadencePendingChangePersistence.commitInsert`. Every other caller ignores it.
    private static func spawnNextOccurrenceIfNeeded(
        from task: AppTask,
        in context: ModelContext,
        now: Date
    ) -> AppTask? {
        guard task.isRecurring, task.recurrenceSpawnedTaskID == nil else { return nil }
        ensureRecurrenceSeriesMetadata(for: task)

        guard !task.recurrenceHasEnded else { return nil }
        let plannedDates = plannedNextDates(for: task, in: context, now: now)
        guard task.shouldSpawnNextOccurrence(nextDateKey: plannedDates.anchorKey(now: now)) else { return nil }

        let nextTask = makeNextRecurringTask(from: task, dates: plannedDates)
        context.insert(nextTask)
        task.recurrenceSpawnedTaskID = nextTask.id
        return nextTask
    }

    // MARK: - Forked successor chains (T-622)

    /// One spawned occurrence's identity: which series, and where in it.
    ///
    /// Both halves are already written on every successor by `makeNextRecurringTask`, which is why
    /// [[T-622]] needs no stored property: a fork is *identifiable* today, it was simply never
    /// collapsed.
    nonisolated struct OccurrenceKey: Hashable, Sendable {
        let seriesID: UUID
        let occurrenceIndex: Int
    }

    /// The occurrences two devices minted for the same slot in one series.
    ///
    /// **How the fork happens.** `spawnNextOccurrenceIfNeeded` guards on
    /// `recurrenceSpawnedTaskID == nil` against the **local replica** and then inserts. Two devices
    /// completing the same occurrence before their records meet each insert a successor and each
    /// write their own id into a single `String` pointer, so CloudKit keeps both tasks and can name
    /// only one of them as the successor. The outcome is proliferation: a second occurrence with
    /// its own reminders, in the same list, on the same day.
    ///
    /// **Only spawned rows are grouped.** A non-empty `recurrenceSeriesIDRaw` is required because
    /// the computed `recurrenceSeriesID` falls back to the task's own `id` — grouping on the
    /// computed value would put every non-recurring task in a series of its own and invite a future
    /// reader to widen this by accident. `recurrenceOccurrenceIndex > 0` excludes the series
    /// origin, whose series id *is* its own id and therefore cannot collide with another row.
    static func duplicateOccurrenceGroups(among tasks: [AppTask]) -> [[AppTask]] {
        var groups: [OccurrenceKey: [AppTask]] = [:]
        for task in tasks where !task.recurrenceSeriesIDRaw.isEmpty && task.recurrenceOccurrenceIndex > 0 {
            let key = OccurrenceKey(
                seriesID: task.recurrenceSeriesID,
                occurrenceIndex: task.recurrenceOccurrenceIndex
            )
            groups[key, default: []].append(task)
        }
        return groups.values.filter { $0.count > 1 }
    }

    /// Which row of a forked group survives, and which of the others may be removed.
    ///
    /// **The survivor is the lowest `id.uuidString`, and nothing else, because the rule has to give
    /// the same answer on every device.** A rule that reads local state — "keep the one that was
    /// completed", "keep the newest", "keep the first the fetch returned" — is not a tie-break, it
    /// is a second fork: device A keeps X and deletes Y while device B keeps Y and deletes X, and
    /// the occurrence disappears entirely. Turning a duplicate into a *deletion* is strictly worse
    /// than the duplicate. `id` is immutable, synced with the record, and totally ordered, so every
    /// device that can see the group computes the same survivor with no coordination.
    ///
    /// **Only untouched clones are removed.** The survivor is chosen without reference to work, so
    /// the protection for work lives here instead: a row is removable only if it still looks like
    /// the copy the spawn made — open, never settled, no time logged, no focus session, no calendar
    /// event, not in a bundle, no successor of its own, no ticked subtask, and every field the
    /// spawn copies identical to the survivor's: title, notes, priority, both dates and the start
    /// minute, estimate, section, area/project/context/goal, tags, and subtask text. Anything else
    /// is a task the user has acted on, and it stays. That is the answer to "what about a duplicate
    /// that has already been completed or has reminders scheduled": a **completed** one is never
    /// collected, and a removable one's reminders go with it, because the delete runs through
    /// `CadenceTaskMutationSupport.deleteTasks`, which cancels a deleted task's notifications.
    ///
    /// The cost of that conservatism, stated: if the *lowest-id* row is the pristine one and
    /// another in the group has been worked on, nothing is removed and the user still sees two
    /// occurrences. Leaving a visible duplicate is the right side of this trade — it is the side
    /// the user can fix.
    ///
    /// Residual, also stated: a device holding a *stale* replica of a row that was completed
    /// elsewhere sees a pristine clone and removes it. What is lost is that occurrence's completion
    /// stamp, not its content — a spawned successor's fields are a copy of its predecessor's — and
    /// the survivor is still there to complete. Closing that needs a sync-state gate the app does
    /// not have ([[T-623]]).
    static func collapsibleDuplicateOccurrences(
        among group: [AppTask]
    ) -> (survivor: AppTask, removable: [AppTask])? {
        guard group.count > 1,
              let survivor = group.min(by: { $0.id.uuidString < $1.id.uuidString })
        else { return nil }
        let removable = group.filter { $0 !== survivor && isUntouchedClone($0, of: survivor) }
        guard !removable.isEmpty else { return nil }
        return (survivor, removable)
    }

    /// Whether this row still looks exactly like the copy `makeNextRecurringTask` produced.
    ///
    /// Split the way the spawn itself is (T-3100). `spawnDefaultsAreUntouched` covers the fields
    /// the copy never writes — the spawn left each at the model's default, so anything else is the
    /// user — and `spawnCopiedFields` covers the fields the copy writes *from the predecessor*.
    /// Two forks of one occurrence were minted by the same spawn from the same predecessor, so
    /// every copied field must still be equal between them; a difference is an edit, whichever of
    /// the two rows is carrying it.
    ///
    /// **This used to enumerate ten fields and assert that the enumeration was complete.** It was
    /// not: the copy also sets `area`, `project`, `context`, `goal`, `tags`, `sectionName`,
    /// `estimatedMinutes`, `scheduledStartMin` and the subtask *titles*, and the gate read none of
    /// them. A forked occurrence the user had dragged into another project, re-timed, retagged, or
    /// whose subtask text they had rewritten therefore still answered `true` here and was deleted
    /// at the next launch of either device, unconfirmed and with no undo.
    ///
    /// Strict in one direction only, and that is the whole design: a wrong `false` leaves a visible
    /// duplicate the user can delete, a wrong `true` destroys work they cannot get back.
    ///
    /// **Three fields are left out on purpose, and none of them is work this can protect.**
    /// `createdAt` is minted per device, so two genuine forks legitimately differ on it. `order` is
    /// copied by the spawn since T-6112, and still left out here, because it is
    /// renumbered *wholesale* across a list by one drag-reorder (`CadenceWriteService`'s placement
    /// write), so requiring it to be pristine would make the collapse inert for anyone who has ever
    /// reordered that list — and a row's position is re-draggable, unlike a project assignment or a
    /// rewritten subtask. `bundleOrder` is only meaningful inside a bundle, and `bundle == nil` is
    /// already required below.
    private static func isUntouchedClone(_ task: AppTask, of survivor: AppTask) -> Bool {
        spawnDefaultsAreUntouched(task)
            && spawnCopiedFields(of: task) == spawnCopiedFields(of: survivor)
    }

    /// The fields `makeNextRecurringTask` never writes, so the spawn left each at `AppTask`'s own
    /// default: a non-default value is something that happened to this row afterwards.
    private static func spawnDefaultsAreUntouched(_ task: AppTask) -> Bool {
        task.status == .todo
            && task.completedAt == nil
            && task.actualMinutes == 0
            && task.calendarEventID.isEmpty
            && task.bundle == nil
            && task.recurrenceSpawnedTaskID == nil
            && (task.focusSessions ?? []).isEmpty
            && (task.subtasks ?? []).allSatisfy { !$0.isDone }
    }

    /// Everything `makeNextRecurringTask` copies off its predecessor, as one value, so the list
    /// lives in exactly one place instead of being re-spelled at a comparison site. Relationships
    /// are compared by `id`, not by identity: two replicas of one row are two objects. Subtasks
    /// carry their **titles**, because the copy copies the text and an edit to it is the part of a
    /// collected duplicate that nothing else in the store still holds.
    private static func spawnCopiedFields(of task: AppTask) -> SpawnCopiedFields {
        SpawnCopiedFields(
            title: task.title,
            notes: task.notes,
            priorityRaw: task.priorityRaw,
            recurrenceRaw: task.recurrenceRaw,
            recurrenceEndModeRaw: task.recurrenceEndModeRaw,
            recurrenceEndDate: task.recurrenceEndDate,
            recurrenceEndCount: task.recurrenceEndCount,
            estimatedMinutes: task.estimatedMinutes,
            sectionName: task.sectionName,
            areaID: task.area?.id,
            projectID: task.project?.id,
            contextID: task.context?.id,
            goalID: task.goal?.id,
            tagIDs: task.sortedTags.map(\.id),
            recurrenceSeriesIDRaw: task.recurrenceSeriesIDRaw,
            recurrenceSourceTaskIDRaw: task.recurrenceSourceTaskIDRaw,
            recurrenceOccurrenceIndex: task.recurrenceOccurrenceIndex,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            scheduledStartMin: task.scheduledStartMin,
            subtasks: (task.subtasks ?? [])
                .sorted { $0.order < $1.order }
                .map { CopiedSubtask(order: $0.order, title: $0.title) }
        )
    }

    private struct CopiedSubtask: Equatable {
        let order: Int
        let title: String
    }

    private struct SpawnCopiedFields: Equatable {
        let title: String
        let notes: String
        let priorityRaw: String
        let recurrenceRaw: String
        let recurrenceEndModeRaw: String
        let recurrenceEndDate: String
        let recurrenceEndCount: Int
        let estimatedMinutes: Int
        let sectionName: String
        let areaID: UUID?
        let projectID: UUID?
        let contextID: UUID?
        let goalID: UUID?
        let tagIDs: [UUID]
        let recurrenceSeriesIDRaw: String
        let recurrenceSourceTaskIDRaw: String
        let recurrenceOccurrenceIndex: Int
        let dueDate: String
        let scheduledDate: String
        let scheduledStartMin: Int
        let subtasks: [CopiedSubtask]
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

    private static func plannedNextDates(for task: AppTask, in context: ModelContext, now: Date) -> PlannedRecurrenceDates {
        var planned = PlannedRecurrenceDates()
        let todayKey = DateFormatters.dateKey(from: now)
        if !task.dueDate.isEmpty {
            planned.dueDate = nextRecurrenceDateKey(
                from: task.dueDate,
                todayKey: todayKey,
                recurrence: task.recurrenceRule,
                anchorDay: { recurrenceAnchorDay(of: task, field: \.dueDate, in: context) }
            ) ?? task.dueDate
        }
        if !task.scheduledDate.isEmpty {
            planned.scheduledDate = nextRecurrenceDateKey(
                from: task.scheduledDate,
                todayKey: todayKey,
                recurrence: task.recurrenceRule,
                anchorDay: { recurrenceAnchorDay(of: task, field: \.scheduledDate, in: context) }
            ) ?? task.scheduledDate
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
        // The successor's duration is the predecessor's, resolved by the model's single rule.
        // `max(estimatedMinutes, 30)` is the spelling `AppTask.timelineDurationMinutes` documents
        // as rejected: it cannot tell "no estimate" from "a deliberate short estimate", so it grew
        // a real 10-minute occurrence into a half-hour block, label and overlap footprint.
        // `timelineDurationMinutes` keeps 10 at 10, keeps unset (0) at the 30-minute default, and
        // keeps a dirty sub-5 positive at the 5-minute floor every write path already enforces.
        nextTask.estimatedMinutes = task.timelineDurationMinutes
        nextTask.sectionName = task.sectionName
        // The successor takes the predecessor's slot in a hand-ordered list (T-6112). Left at the
        // model's default `0`, it sorted among a list's first rows on every completion, so a daily
        // task kept third in the Inbox came back first. The predecessor is settled, so the shared
        // value only ever meets it where completed rows are shown, and there `fallbackPrecedes`
        // breaks the tie on `createdAt` and puts the successor directly after it. `order` is
        // deliberately NOT in `SpawnCopiedFields`: see `isUntouchedClone`.
        nextTask.order = task.order
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
            recurrenceSortDateKey(for: task) ?? TaskOrdering.noDateSortKey,
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
    ///
    /// `anchorDay` is only consulted when the occurrence's own date wins (T-3103): a catch-up from
    /// today deliberately restarts the cadence on today's day, so the series' old day-of-month no
    /// longer applies.
    private static func nextRecurrenceDateKey(
        from key: String,
        todayKey: String,
        recurrence: TaskRecurrenceRule,
        anchorDay: () -> Int?
    ) -> String? {
        guard recurrence != .none else { return nil }
        guard key >= todayKey else { return shiftedDateKey(todayKey, recurrence: recurrence, anchorDay: nil) }
        return shiftedDateKey(key, recurrence: recurrence, anchorDay: anchorDay())
    }

    /// One period forward. `.monthly` and `.yearly` land on `anchorDay` (or the key's own day when
    /// it is nil), **clamped** to the target month's length — the same rule the habit engine uses
    /// for `frequencyDays = [31]` (`HabitStreakTests`, "Pay rent"). Clamping per hop, rather than
    /// letting `Calendar.date(byAdding: .month, ...)` clamp and then carrying the clamped day
    /// forward, is what lets Jan 31 -> Feb 28 come back to Mar 31 instead of sticking on the 28th
    /// for ever (T-3103).
    private static func shiftedDateKey(_ key: String, recurrence: TaskRecurrenceRule, anchorDay: Int? = nil) -> String? {
        guard recurrence != .none, let date = DateFormatters.date(from: key) else { return nil }

        switch recurrence {
        case .none:
            return key
        case .daily, .weekly:
            let calendar = Calendar.current
            let component: Calendar.Component = recurrence == .daily ? .day : .weekOfYear
            guard let next = calendar.date(byAdding: component, value: 1, to: date) else { return nil }
            return DateFormatters.dateKey(from: next)
        case .monthly, .yearly:
            let calendar = DateFormatters.storageCalendar(inheritingTimeZoneFrom: Calendar.current)
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            let monthsAhead = recurrence == .monthly ? 1 : 12
            let zeroBasedMonth = month - 1 + monthsAhead
            let targetYear = year + zeroBasedMonth / 12
            let targetMonth = zeroBasedMonth % 12 + 1
            guard let firstOfTarget = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: firstOfTarget)?.count
            else { return nil }
            let targetDay = min(anchorDay ?? day, length)
            guard let next = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: targetDay))
            else { return nil }
            return DateFormatters.dateKey(from: next, calendar: calendar)
        }
    }

    /// The day of the month a monthly/yearly series is really anchored on, recovered from the
    /// occurrence chain because a task stores no anchor of its own (T-3103).
    ///
    /// A date can only be a *clamp* if it is the last day of a month shorter than 31 days — Feb 28,
    /// Apr 30, Feb 29 in a leap year. Only then is the predecessor worth reading: if it sits exactly
    /// one period earlier on a day at least as late, the series was anchored there and this date is
    /// that day clamped. The walk repeats while the recovered day could itself still be a clamp,
    /// which matters for `.yearly` from Feb 29 (Feb 28 three years running, then Feb 29 again).
    ///
    /// It stops at anything that breaks the shape — no predecessor (deleted, or the series origin),
    /// an empty field, a gap other than one period (a catch-up restarted the cadence), or an earlier
    /// day (the user moved the occurrence) — and returns the day it has. So a series that was
    /// *started* on Feb 28 or Apr 30 keeps that day, and a lost history degrades to the clamped day,
    /// which is what every series did before this.
    private static func recurrenceAnchorDay(
        of task: AppTask,
        field: KeyPath<AppTask, String>,
        in context: ModelContext
    ) -> Int? {
        let recurrence = task.recurrenceRule
        guard recurrence == .monthly || recurrence == .yearly,
              var current = storageDayParts(task[keyPath: field])
        else { return nil }

        var anchor = current.day
        var cursor = task
        var seen: Set<UUID> = [task.id]
        for _ in 0..<maxAnchorWalkHops {
            guard anchor < 31, anchor == current.monthLength,
                  let predecessor = recurrencePredecessor(of: cursor, in: context),
                  seen.insert(predecessor.id).inserted,
                  let previous = storageDayParts(predecessor[keyPath: field]),
                  previous.monthIndex + (recurrence == .monthly ? 1 : 12) == current.monthIndex,
                  previous.day >= anchor
            else { break }
            anchor = previous.day
            current = previous
            cursor = predecessor
        }
        return anchor
    }

    /// Feb 29 -> Feb 28 (x3) -> Feb 29 is the longest legitimate walk; the cap only guards a
    /// corrupted chain.
    private static let maxAnchorWalkHops = 8

    private struct StorageDayParts {
        let monthIndex: Int  // year * 12 + (month - 1), so "one month earlier" is subtraction
        let day: Int
        let monthLength: Int
    }

    private static func storageDayParts(_ key: String) -> StorageDayParts? {
        guard !key.isEmpty, let date = DateFormatters.date(from: key) else { return nil }
        let calendar = DateFormatters.storageCalendar(inheritingTimeZoneFrom: Calendar.current)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let length = calendar.range(of: .day, in: .month, for: date)?.count
        else { return nil }
        return StorageDayParts(monthIndex: year * 12 + (month - 1), day: day, monthLength: length)
    }

    private static func recurrencePredecessor(of task: AppTask, in context: ModelContext) -> AppTask? {
        guard let sourceID = task.recurrenceSourceTaskID else { return nil }
        var descriptor = FetchDescriptor<AppTask>(predicate: #Predicate<AppTask> { $0.id == sourceID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
