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
        isUntouchedClone(task, matching: spawnCopiedFields(of: survivor))
    }

    /// The same test against the copied fields a row is *expected* to carry, rather than a
    /// sibling's: the fork collapse compares two forks, and [[T-14824]]'s reopen compares a
    /// successor with what its predecessor's spawn would have written. One gate, two references.
    private static func isUntouchedClone(_ task: AppTask, matching expected: SpawnCopiedFields) -> Bool {
        spawnDefaultsAreUntouched(task) && spawnCopiedFields(of: task) == expected
    }

    // MARK: - Reopening a settled occurrence ([[T-14824]])

    /// The successor `task`'s settle spawned, when reopening `task` may take it back: it is still
    /// exactly the copy the spawn made, so nobody has done anything to it.
    ///
    /// **Why reopening takes it back at all (keeper call, 2026-11-09).** Unticking is almost
    /// always correcting an accidental or premature tick, and leaving the successor gave the series
    /// two open occurrences — today's, reopened, beside tomorrow's copy. Dropping the successor and
    /// clearing `recurrenceSpawnedTaskID` puts the series back as it was before the tick, so the
    /// next tick spawns it afresh.
    ///
    /// **Strict in the same direction as the fork collapse**, through the same gate
    /// (`isUntouchedClone`): open, never settled, no time, no focus session, no event, no bundle,
    /// no successor of its own, no ticked subtask, and every field the spawn copies equal to what
    /// the spawn would have copied. A successor the user has edited, ticked or worked on answers
    /// `nil`, and the caller leaves both rows and the link alone — a visible second occurrence is
    /// the side the user can fix; a deleted edit is not.
    ///
    /// **The expected dates are recomputed at the spawn's own `now`.** `markDone` and
    /// `markCancelled` stamp `completedAt` with the very `now` they hand
    /// `spawnNextOccurrenceIfNeeded`, so planning again from `completedAt` reproduces the dates the
    /// spawn wrote, including a late completion's catch-up. A `completedAt` that has since been
    /// changed, or a successor someone rescheduled, fails the comparison and is kept.
    ///
    /// Also `nil` unless exactly one row carries the successor's id: `deleteTasks(withIDs:)`
    /// removes every row with an id, and two rows sharing one (T-6451) are not both this copy.
    static func untouchedSpawnedSuccessor(of task: AppTask, in context: ModelContext) -> AppTask? {
        guard task.isRecurring,
              let successorID = task.recurrenceSpawnedTaskID,
              let spawnedAt = task.completedAt
        else { return nil }
        let descriptor = FetchDescriptor<AppTask>(predicate: #Predicate<AppTask> { $0.id == successorID })
        guard let matches = try? context.fetch(descriptor), matches.count == 1, let successor = matches.first
        else { return nil }
        let dates = plannedNextDates(for: task, in: context, now: spawnedAt)
        guard isUntouchedClone(successor, matching: spawnedSuccessorFields(of: task, dates: dates))
        else { return nil }
        return successor
    }

    /// The copied fields `makeNextRecurringTask` writes on a successor of `task` carrying `dates`.
    ///
    /// Derived from `spawnCopiedFields(of: task)` so every field the spawn copies verbatim is
    /// verbatim here by construction; only the ones the spawn *transforms* are re-spelled, each
    /// beside the line it mirrors. A change to one of those lines in `makeNextRecurringTask` that is
    /// not made here turns every successor into a "touched" one and the reopen keeps it — the safe
    /// failure — and `CadenceRecurringReopenSuccessorTests` reds on it.
    private static func spawnedSuccessorFields(of task: AppTask, dates: PlannedRecurrenceDates) -> SpawnCopiedFields {
        var fields = spawnCopiedFields(of: task)
        fields.estimatedMinutes = task.estimatedMinutes > 0 ? task.timelineDurationMinutes : 0
        fields.recurrenceSeriesIDRaw = task.recurrenceSeriesID.uuidString
        fields.recurrenceSourceTaskIDRaw = task.id.uuidString
        fields.recurrenceOccurrenceIndex = task.recurrenceOccurrenceIndex + 1
        fields.dueDate = dates.dueDate
        fields.scheduledDate = dates.scheduledDate
        // The same one rule `makeNextRecurringTask` writes through, including
        // `AppTask.scheduledStartMin`'s "-1 = not scheduled" default when the spawn set no date of
        // its own to hang a time on.
        fields.scheduledStartMin = dates.scheduledStartMin(inheritedFrom: task)
        return fields
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
        var title: String
        var notes: String
        var priorityRaw: String
        var recurrenceRaw: String
        var recurrenceEndModeRaw: String
        var recurrenceEndDate: String
        var recurrenceEndCount: Int
        var estimatedMinutes: Int
        var sectionName: String
        var areaID: UUID?
        var projectID: UUID?
        var contextID: UUID?
        var goalID: UUID?
        var tagIDs: [UUID]
        var recurrenceSeriesIDRaw: String
        var recurrenceSourceTaskIDRaw: String
        var recurrenceOccurrenceIndex: Int
        var dueDate: String
        var scheduledDate: String
        var scheduledStartMin: Int
        var subtasks: [CopiedSubtask]
    }

    static func ensureRecurrenceSeriesMetadata(for task: AppTask) {
        if task.recurrenceSeriesIDRaw.isEmpty {
            task.recurrenceSeriesIDRaw = task.id.uuidString
        }
    }

    /// **[[T-14731]]: turning repeat off also drops the series' end.** An end condition on a task
    /// that no longer repeats is meaningless, and left behind it re-arms the moment a rule is
    /// picked again: the task editor's save already cleared it (`CadenceTaskEditDraftCommit.apply`),
    /// but every row door -- the Mac row's Repeat menu and chip popover, the note embed card, the
    /// iOS row menu -- writes only through here, so Never-then-Weekly from a row silently restored
    /// an old "After 5" or a passed "Until" date, and a series whose bound was already reached
    /// spawned nothing on its next completion while its row still wore the repeat glyph. Cleared
    /// here, on the same targets the rule reaches, so every door agrees with the editor.
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
                target.recurrenceEndMode = .never
                target.recurrenceEndDate = ""
                target.recurrenceEndCount = 0
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

    // MARK: - [[T-6191]] repairing an After count stored below its occurrence

    /// The After count a task's stored figure should read as: the stored count, raised to the
    /// task's own occurrence number when an `.afterCount` series was stored below it.
    ///
    /// Before [[T-6114]]'s floor an editor could store a count under the occurrence already
    /// reached, and such a series read "15 of 10". `recurrenceHasEnded` is already true for it, so
    /// raising the count to the occurrence keeps the series exactly as ended while making the
    /// figure true: "15 of 15". Anything else — a coherent count, another end mode, a count that
    /// `effectiveRecurrenceEndMode` already degrades to `.never` — comes back unchanged.
    static func coherentEndCount(
        stored: Int,
        effectiveMode: TaskRecurrenceEndMode,
        occurrenceNumber: Int
    ) -> Int {
        guard effectiveMode == .afterCount, stored < occurrenceNumber else { return stored }
        return occurrenceNumber
    }

    /// **The owner's 2026-10-26 ruling on [[T-6191]]: repair the stored count when the task is
    /// OPENED, never in a sweep.** Raises an incoherent After count to the task's occurrence
    /// number and commits that one field; a task whose count is already coherent is not written
    /// at all, so calling this on every open is idempotent and costs nothing.
    ///
    /// Only the opened task is repaired — not the rest of its series, which each get the same
    /// repair when they are opened themselves. A refused commit puts the stored count back, so the
    /// task is exactly as it was and the next open tries again.
    ///
    /// - Returns: `true` when a repair was committed, `false` when nothing needed it or the store
    ///   refused.
    @discardableResult
    static func repairEndCountOnOpen(
        _ task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let stored = task.recurrenceEndCount
        let coherent = coherentEndCount(
            stored: stored,
            effectiveMode: task.effectiveRecurrenceEndMode,
            occurrenceNumber: task.recurrenceOccurrenceNumber
        )
        guard coherent != stored else { return false }
        task.recurrenceEndCount = coherent
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                task.recurrenceEndCount = stored
            }
            return true
        } catch {
            return false
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

    /// The dates the next occurrence would carry. A date the predecessor had advances; a series
    /// with **neither** date is given a do date by [[T-14823]] (see `plannedNextDates`).
    struct PlannedRecurrenceDates {
        var dueDate: String = ""
        var scheduledDate: String = ""
        /// True when `scheduledDate` was **seeded** by [[T-14823]] — the predecessor had neither
        /// date, so this day is new information rather than the predecessor's own do date moved
        /// forward. It decides one thing, `scheduledStartMin(inheritedFrom:)`, and is read from
        /// there by both the spawn and the reopen's reconstruction of it.
        var scheduledDateIsSeeded: Bool = false

        /// The start minute a successor carrying these dates takes from `task`.
        ///
        /// `-1` is `AppTask.scheduledStartMin`'s "not scheduled" default, and it is the answer in
        /// both the cases where the successor's do date is not the predecessor's: there is no do
        /// date at all, or [[T-14823]] seeded one. **A seeded do date carries no time**: a task
        /// with no do date has no meaningful start minute — a positive one on such a row is a
        /// leftover, not a plan — so inheriting it would conjure a timed block on a day the user
        /// never scheduled. An inherited do date keeps the time the occurrence was planned at,
        /// exactly as it always has.
        ///
        /// It lives on the value rather than at either call site because
        /// `makeNextRecurringTask` and `spawnedSuccessorFields` must agree field for field: a
        /// successor the reopen cannot recognise as the spawn's copy is one it refuses to take
        /// back ([[T-14824]]).
        func scheduledStartMin(inheritedFrom task: AppTask) -> Int {
            guard !scheduledDate.isEmpty, !scheduledDateIsSeeded else { return -1 }
            return task.scheduledStartMin
        }

        /// The single date key that represents this occurrence for end-date purposes. Do date
        /// (`scheduledDate`) wins over due date because that's the same precedence
        /// `recurrenceSortDateKey` already uses to decide "when is this occurrence".
        ///
        /// The `now` fallback is what a dateless occurrence used to be anchored to — the day it
        /// would appear, because it carried no date of its own. Since [[T-14823]] a dateless
        /// *recurring* series' successor carries a do date, so for the spawn path the first branch
        /// answers and the end condition is asked about the day the successor really lands on.
        /// The fallback is kept as the honest answer for a value that still has no date at all.
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
        // **[[T-14823]]: a series with NEITHER date gets its successor a do date, one period after
        // the completion day** (owner call, [[T-15000]]). Both branches above advance a date the
        // predecessor already had, so an undated repeating task minted an equally undated
        // successor: completing a daily Inbox task put an identical open copy straight back into
        // the same list, tickable again at once, and the series never read as done for the day.
        // A do date one period on sends the successor to Scheduled and brings it back on its day.
        //
        // It is the same arithmetic the dated path uses for a late completion — `shiftedDateKey`
        // off the completion day — which is why this is one period from `todayKey` rather than a
        // seeded date of today: the predecessor is being settled *now*, so "now" is the occurrence
        // that is finishing and the next one is a period away.
        //
        // **Only a series with neither date reaches here.** A task with a due date or a do date
        // took a branch above and is untouched by this.
        if task.dueDate.isEmpty, task.scheduledDate.isEmpty,
           let seeded = shiftedDateKey(todayKey, recurrence: task.recurrenceRule, anchorDay: nil) {
            planned.scheduledDate = seeded
            planned.scheduledDateIsSeeded = true
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
        // `timelineDurationMinutes` keeps 10 at 10 and keeps a dirty sub-5 positive at the 5-minute
        // floor every write path already enforces.
        //
        // **[[T-14231]]: None stays None.** `0` is the Estimate row's None since [[T-6581]] — a
        // value the user chooses, which every composer stores as itself and every inspector reads
        // back as "No estimate". Copying `timelineDurationMinutes` resolved it to its 30-minute
        // *drawing* default, so a repeating task created with no estimate came back from its first
        // completion estimated at 30m, and stayed so for the rest of the series. The successor
        // still DRAWS 30 minutes tall, because `timelineDurationMinutes` reads its `0` that way.
        nextTask.estimatedMinutes = task.estimatedMinutes > 0 ? task.timelineDurationMinutes : 0
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
            // One rule, stated on the value, so the reopen's `spawnedSuccessorFields` cannot drift
            // from it: an inherited do date keeps the occurrence's time, a do date [[T-14823]]
            // seeded onto a dateless series carries none.
            nextTask.scheduledStartMin = dates.scheduledStartMin(inheritedFrom: task)
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

    /// The next occurrence's date: one period after the occurrence's own date, or — when that date
    /// has already gone by — the first date **on the series' own schedule** that is after today.
    /// A daily/weekly/etc. task completed long after it was last due (e.g. a week-stale daily task)
    /// must not produce another still-overdue occurrence (`dd93a5d2`), and that rule is kept.
    ///
    /// **[[T-14821]]: a late completion no longer moves the series.** The catch-up used to restart
    /// the cadence from TODAY: a weekly task due Monday and ticked on Wednesday came back the next
    /// Wednesday, and every Wednesday after; rent due on the 1st and paid on the 3rd came back due
    /// on the 3rd. Now the periods are stepped forward from the occurrence's own date, on its own
    /// weekday and its own anchored day of the month (T-3103's `anchorDay`, clamped per hop), until
    /// one lands after today. For `.daily` that is tomorrow, exactly what the old rule gave.
    private static func nextRecurrenceDateKey(
        from key: String,
        todayKey: String,
        recurrence: TaskRecurrenceRule,
        anchorDay: () -> Int?
    ) -> String? {
        guard recurrence != .none else { return nil }
        let anchor = anchorDay()
        guard key < todayKey else { return shiftedDateKey(key, recurrence: recurrence, anchorDay: anchor) }
        return firstScheduledDateKey(after: todayKey, from: key, recurrence: recurrence, anchorDay: anchor)
    }

    /// The first date a whole number of periods (at least one) after `key` that is later than
    /// `todayKey`. The starting estimate is the number of periods between the two days, so the loop
    /// runs at most a couple of hops however stale the occurrence is; the cap only guards a date the
    /// shift cannot advance.
    private static func firstScheduledDateKey(
        after todayKey: String,
        from key: String,
        recurrence: TaskRecurrenceRule,
        anchorDay: Int?
    ) -> String? {
        guard let start = DateFormatters.date(from: key), let today = DateFormatters.date(from: todayKey) else {
            return shiftedDateKey(todayKey, recurrence: recurrence, anchorDay: nil)
        }
        let calendar = DateFormatters.storageCalendar(inheritingTimeZoneFrom: Calendar.current)
        let elapsed: Int
        switch recurrence {
        case .none: return nil
        case .daily: elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        case .weekly: elapsed = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) / 7
        case .monthly: elapsed = calendar.dateComponents([.month], from: start, to: today).month ?? 0
        case .yearly: elapsed = calendar.dateComponents([.year], from: start, to: today).year ?? 0
        }
        var periods = max(1, elapsed)
        for _ in 0..<4 {
            guard let candidate = shiftedDateKey(key, recurrence: recurrence, anchorDay: anchorDay, periods: periods)
            else { return nil }
            if candidate > todayKey { return candidate }
            periods += 1
        }
        return shiftedDateKey(todayKey, recurrence: recurrence, anchorDay: nil)
    }

    /// One period forward. `.monthly` and `.yearly` land on `anchorDay` (or the key's own day when
    /// it is nil), **clamped** to the target month's length — the same rule the habit engine uses
    /// for `frequencyDays = [31]` (`HabitStreakTests`, "Pay rent"). Clamping per hop, rather than
    /// letting `Calendar.date(byAdding: .month, ...)` clamp and then carrying the clamped day
    /// forward, is what lets Jan 31 -> Feb 28 come back to Mar 31 instead of sticking on the 28th
    /// for ever (T-3103).
    ///
    /// `periods` is how many whole periods to move (1 for an ordinary hop); the late-completion
    /// path in `firstScheduledDateKey` moves several at once, still landing on the anchor day.
    private static func shiftedDateKey(
        _ key: String,
        recurrence: TaskRecurrenceRule,
        anchorDay: Int? = nil,
        periods: Int = 1
    ) -> String? {
        guard recurrence != .none, let date = DateFormatters.date(from: key) else { return nil }

        switch recurrence {
        case .none:
            return key
        case .daily, .weekly:
            let calendar = Calendar.current
            let component: Calendar.Component = recurrence == .daily ? .day : .weekOfYear
            guard let next = calendar.date(byAdding: component, value: periods, to: date) else { return nil }
            return DateFormatters.dateKey(from: next)
        case .monthly, .yearly:
            let calendar = DateFormatters.storageCalendar(inheritingTimeZoneFrom: Calendar.current)
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            let monthsAhead = (recurrence == .monthly ? 1 : 12) * periods
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
