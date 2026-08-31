import Foundation
import SwiftData

enum CadenceTaskMutationSupport {
    /// **T-344, decided: the completion circle toggles *settled*, not *done*.** Tapping it on a
    /// cancelled task restores it to todo, exactly as tapping it on a done task does. It does not
    /// convert an abandoned task into an accomplished one.
    ///
    /// The circle is already *painted* by that rule — `CadenceTaskCompletionGlyph` gives `.done`
    /// and `.cancelled` a filled glyph, and `CadenceTaskCompletionState.isSettled` covers both, so
    /// the row's strikethrough and dimming already treat the two alike. Deciding the *action* on
    /// `isDone` while deciding the *appearance* on settled is one rule spelled two ways, which is
    /// the exact shape of T-147, T-203 and T-342. `isFinishedTask` is the name this codebase
    /// already gave that rule; reading it here makes the glyph and the gesture agree: a filled
    /// circle un-settles, an empty circle settles as done.
    ///
    /// Two consequences worth stating rather than discovering:
    ///
    /// - **Cancelled → done is two taps now** (restore, then complete), which is also how you would
    ///   say it out loud. That is the right direction for the asymmetry: `markDone` stamps
    ///   `completedAt` and spawns the next occurrence of a recurring series, so a mis-tap under the
    ///   old rule minted live work, and a mis-tap under this one costs a tap.
    /// - **Restore is reachable from a list again.** The iOS row's trailing swipe offers exactly
    ///   toggle-completion and delete; under the old rule a cancelled row's only un-cancel was the
    ///   Status row inside the detail sheet, while a done row un-did itself in one swipe.
    ///
    /// The labels that describe this gesture read the same predicate — see `iOSTaskRowActions`,
    /// `iOSTaskRow`, `iOSTaskEditorTitleCard` and `iOSBoardTaskCard` — and
    /// `CadenceTaskStatusLifecycleSurfaceTests` pins that they do.
    static func toggleCompletion(_ task: AppTask, modelContext: ModelContext) {
        if CadenceTaskQuerySupport.isFinishedTask(task) {
            CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
        } else {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        }
        try? modelContext.save()
    }

    static func setStatus(_ status: TaskStatus, for task: AppTask, modelContext: ModelContext) {
        applyStatusCompletion(status, to: task, modelContext: modelContext)
        try? modelContext.save()
    }

    static func applyStatusCompletion(_ status: TaskStatus, to task: AppTask, modelContext: ModelContext) {
        switch status {
        case .done:
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        case .cancelled:
            CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: modelContext)
        case .todo, .inProgress:
            task.status = status
            task.completedAt = nil
        }
    }

    /// Reconciles `completedAt` with `status` when the iOS task sheet saves. It is a *normalizer*,
    /// so it may clear a timestamp that contradicts the status and must not invent one that the
    /// status merely permits.
    ///
    /// The `else` this used to be cleared `completedAt` for every status that is not `.done`, and
    /// `.cancelled` is one of them — so on iOS it undid the cancellation timestamp the moment the
    /// sheet saved, which is every route out of that sheet. That made T-202 invisible on the one
    /// surface the ticket was reported from: the task landed in Inbox → Completed (no date test) and
    /// not in Today's Completed (a `completedAt` test), exactly the split the fix was meant to close.
    ///
    /// `.cancelled` therefore does nothing here. Not clearing is the fix; *stamping* would be a
    /// backfill of pre-T-202 rows with a value we never recorded, performed silently by opening a
    /// sheet.
    ///
    /// **`.done` does nothing here either, for the same reason (T-213).** It used to call
    /// `markDone`, which is a *transition* and does two things a normalizer must not: it sets
    /// `completedAt = now` unconditionally, and it spawns the next recurrence occurrence. The sheet
    /// re-saves on every change to title, priority, status, recurrence, estimate, actual minutes and
    /// section, so editing the title of a task finished last week rewrote its timestamp to today and
    /// pulled it into Today's Completed — the same class of bug as the `.cancelled` branch above,
    /// pointing the other way. Nothing is lost by not stamping: every real done transition on this
    /// surface goes through `toggleCompletion` or `setStatus` → `applyStatusCompletion` → `markDone`,
    /// which has already recorded the timestamp before this normalizer ever runs.
    ///
    /// So the rule is symmetric and the switch says it directly: a **settled** status keeps whatever
    /// timestamp it was given, and only the two **open** statuses clear one. Do not re-add a
    /// transition call to either settled case.
    static func normalizeCompletionState(for task: AppTask, modelContext: ModelContext) {
        switch task.status {
        case .done, .cancelled:
            break
        case .todo, .inProgress:
            task.completedAt = nil
        }
        try? modelContext.save()
    }

    static func setPriority(_ priority: TaskPriority, for task: AppTask, modelContext: ModelContext) {
        task.priority = priority
        try? modelContext.save()
    }

    static func scheduleToday(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func scheduleTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func scheduleNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func setScheduledDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = dateKey
        try? modelContext.save()
    }

    static func moveTaskToDate(_ task: AppTask, dateKey: String, modelContext: ModelContext) {
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = dateKey
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = 30
        }
        try? modelContext.save()
    }

    static func setScheduledTime(_ startMin: Int, for task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = min(max(0, startMin), 1425)
        try? modelContext.save()
    }

    static func clearScheduledDate(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func clearScheduledTime(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func setDueDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.dueDate = dateKey
        try? modelContext.save()
    }

    /// Clamped to the same 0…24h range every other duration field in the app accepts, so a chip
    /// that edits an estimate in place cannot write a value the pickers could not have produced.
    static func setEstimatedMinutes(_ minutes: Int, for task: AppTask, modelContext: ModelContext) {
        task.estimatedMinutes = min(max(0, minutes), 24 * 60)
        try? modelContext.save()
    }

    static func dueToday(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func dueTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func dueNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func clearDueDate(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = ""
        try? modelContext.save()
    }

    static func setPlanningDates(
        scheduledDate: String?,
        dueDate: String?,
        for task: AppTask,
        modelContext: ModelContext
    ) {
        let scheduleKey = scheduledDate ?? ""
        task.scheduledDate = scheduleKey
        if scheduleKey.isEmpty {
            task.scheduledStartMin = -1
        }
        task.dueDate = dueDate ?? ""
        try? modelContext.save()
    }

    static func moveToSection(_ sectionName: String, task: AppTask, modelContext: ModelContext) {
        task.sectionName = sectionName
        try? modelContext.save()
    }

    static func sectionNames(forArea area: Area?, project: Project?) -> [String] {
        if let area {
            return area.sectionNames
        }
        if let project {
            return project.sectionNames
        }
        return [TaskSectionDefaults.defaultName]
    }

    static func normalizedSectionName(_ sectionName: String, area: Area?, project: Project?) -> String {
        let names = sectionNames(forArea: area, project: project)
        if let matched = names.first(where: { $0.caseInsensitiveCompare(sectionName) == .orderedSame }) {
            return matched
        }
        return names.first ?? TaskSectionDefaults.defaultName
    }

    /// True when `area`/`project` already name the container the task sits in — so assigning them
    /// would move it nowhere.
    ///
    /// Used to decide whether `assignContainer` re-places the task at the end of its container.
    /// Both nil means Inbox, which is a real container here and not "unset".
    static func isAlreadyInContainer(_ task: AppTask, area: Area?, project: Project?) -> Bool {
        if let area {
            return task.area?.id == area.id && task.project == nil
        }
        if let project {
            return task.project?.id == project.id && task.area == nil
        }
        return task.area == nil && task.project == nil
    }

    /// Re-ordering is what a *move* needs: the task arrives among siblings it has never been
    /// ordered against, so it goes to the end. Re-assigning the container it is already in is not
    /// a move, and `nextContainerOrder` would send it to the bottom of a list it never left.
    ///
    /// That is not hypothetical. Every caller that re-asserts the current container hit it: the
    /// iOS task detail sheet seeds `containerSelection` in `onAppear` and its `onChange` cannot
    /// tell that seeding from an edit, so merely *opening* a task's sheet sent it to the bottom of
    /// its list — and reopening it bumped it again. The two "Move to List" menus have the same
    /// shape: they mark the current list with a checkmark, so tapping the row you are already in
    /// looks like a no-op and silently re-ordered the task.
    ///
    /// Genuine moves are untouched: a different container still re-places the task.
    static func assignContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        updateOrder: Bool = true
    ) {
        let normalizedSectionName = normalizedSectionName(sectionName, area: area, project: project)
        // Read before the relationships below are rewritten.
        let isContainerChange = !isAlreadyInContainer(task, area: area, project: project)

        if let area {
            task.area = area
            task.project = nil
        } else if let project {
            task.project = project
            task.area = nil
        } else {
            task.area = nil
            task.project = nil
        }
        task.context = inheritedContext(area: area, project: project)

        task.sectionName = normalizedSectionName
        if updateOrder && isContainerChange {
            task.order = nextContainerOrder(excluding: task, in: allTasks, area: area, project: project)
        }
    }

    /// The context a task takes from the list it is filed in.
    ///
    /// `AppTask.context` is a denormalized copy of the list's context, so this is the only value a
    /// task filed into `area`/`project` may be given. The project branch reads
    /// `Project.resolvedContext`, which is where the "own context, else the area's" rule is
    /// spelled; nothing here re-types it.
    static func inheritedContext(area: Area?, project: Project?) -> Context? {
        if let area { return area.context }
        if let project { return project.resolvedContext }
        return nil
    }

    /// Re-points the denormalized `AppTask.context` of every task already in a list, after the
    /// list itself changed owner.
    ///
    /// Editing a project's context - or the area it sits under - changes what context its tasks
    /// belong to, but `task.context` is a copy and SwiftData does not re-point copies. The tasks
    /// stayed in the list and vanished from the context they now belong to (T-293). This is the
    /// same rule `assignContainer` applies to one arriving task, applied to every task already
    /// there.
    ///
    /// **An area owns two levels of tasks, not one** (T-340). `area.tasks` is only the tasks filed
    /// directly in the area; a project under it whose own `context` is `nil` reads its context
    /// through the area too, so changing the area's context changes `Project.resolvedContext` for
    /// every such project and invalidates the copy on all of *their* tasks as well. Every caller
    /// passes `area.tasks ?? []` and none of them walked the projects, which is the same defect one
    /// level down. The cascade lives here rather than at the call sites so both list editors get it
    /// from the one rule.
    ///
    /// Projects that name their own context are skipped: `resolvedContext` prefers it, so the
    /// area's change does not reach them. Each cascaded task is re-derived from
    /// `child.resolvedContext` rather than from the `context` computed above, so the fallback stays
    /// spelled in exactly one place.
    static func reassignInheritedContext(in tasks: [AppTask], area: Area? = nil, project: Project? = nil) {
        let context = inheritedContext(area: area, project: project)
        for task in tasks {
            task.context = context
        }

        guard let area else { return }
        for child in area.projects ?? [] where child.context == nil {
            for task in child.tasks ?? [] {
                task.context = child.resolvedContext
            }
        }
    }

    static func moveToContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        modelContext: ModelContext
    ) {
        assignContainer(
            task,
            area: area,
            project: project,
            sectionName: sectionName,
            allTasks: allTasks
        )
        try? modelContext.save()
    }

    static func duplicate(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) throws -> AppTask {
        let duplicate = AppTask(title: task.title)
        duplicate.notes = task.notes
        duplicate.priority = task.priority
        duplicate.status = .todo
        duplicate.recurrenceRule = task.recurrenceRule
        // A duplicate starts its own series at occurrence 1, but it should carry the same end
        // condition the user configured rather than silently becoming an endless series.
        duplicate.recurrenceEndModeRaw = task.recurrenceEndModeRaw
        duplicate.recurrenceEndDate = task.recurrenceEndDate
        duplicate.recurrenceEndCount = task.recurrenceEndCount
        duplicate.dueDate = task.dueDate
        duplicate.scheduledDate = task.scheduledDate
        duplicate.scheduledStartMin = task.scheduledStartMin
        duplicate.estimatedMinutes = task.estimatedMinutes
        duplicate.actualMinutes = 0
        duplicate.sectionName = task.resolvedSectionName
        duplicate.order = nextOrderForSibling(of: task, in: allTasks)
        duplicate.area = task.area
        duplicate.project = task.project
        duplicate.goal = task.goal
        duplicate.context = task.context
        duplicate.tags = task.tags

        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            return duplicate
        } catch {
            modelContext.delete(duplicate)
            throw error
        }
    }

    /// Shown when an ordinary task delete could not be committed (T-365).
    ///
    /// The second sentence is the one `CadencePendingChangePersistence.commitDelete`'s rollback
    /// earns, and it is deliberately the **same** promise `CadenceListDeletionKind` and
    /// `CadenceNoteDeletionSummary` already make: the row is back where the user can see it, so
    /// nothing has been lost while they decide whether to try again. Before T-365 this path could
    /// not have said it — `try? modelContext.save()` left the task marked deleted in the context
    /// and undeleted in the store, which is the state the sentence denies.
    ///
    /// Like the other three, it names its own object rather than saying "item": four screens, four
    /// nouns, one shape.
    static let deleteFailureNotice = "Couldn't delete this task. Nothing was removed."

    /// The alert title that carries `deleteFailureNotice` on iOS (T-440).
    ///
    /// Beside the sentence rather than in the view, because two iOS surfaces raise this alert —
    /// `iOSTaskRow` and `iOSTaskDetailSheet` — and both used to type the title out. The modifier
    /// they now share, `iOSTaskDeleteFailureAlert`, reads it from here, so the title and the body
    /// travel together and there is no arrangement in which one of them is updated alone.
    ///
    /// Title-case because it is an alert title; `deleteFailureNotice` is the sentence under it.
    /// macOS does not use this: there the refusal lands inside the still-open confirmation overlay
    /// (`DeleteConfirmationManager.failureNotice`), which has a title already.
    static let deleteFailureAlertTitle = "Couldn't Delete Task"

    /// Shown when a block the user asked for could not be committed (T-471).
    ///
    /// "Block" rather than "task": a `TaskBundle` is a *block* everywhere the user meets one — the
    /// quick-create sheet's own segmented control, `iOSCalendarBundleDetailSheet`'s "Delete this
    /// block?" — so `TaskCreationService.saveFailureNotice` would name an object the sheet was not
    /// making. It is held here, beside the `insertBundle(title:…)` that throws, for the same reason
    /// the other notices sit beside their mutations: the next surface that creates a block reads
    /// this sentence instead of inventing a third spelling of "that didn't work".
    ///
    /// No "Nothing was created." clause, even though `insertBundle` earns one — it deletes the
    /// pending bundle before it rethrows. The *create* family does not carry that clause
    /// (`TaskCreationService.saveFailureNotice`, `CadenceSavedLinkPersistence.saveFailureNotice`):
    /// a refused creation has nothing the user could fear losing, which is exactly what the delete
    /// family's second sentence exists to deny.
    static let bundleSaveFailureNotice = "Couldn't save this block."

    /// Shown when a block the user asked to delete could not be committed (T-322).
    ///
    /// It carries the delete family's second sentence — `deleteFailureNotice`,
    /// `CadenceListDeletionKind.deleteFailureNotice` and `CadenceNoteDeletionSummary` all promise
    /// the same thing — because `deleteBundle` now rolls back, so the block really is back where
    /// the user can see it. `bundleSaveFailureNotice` above deliberately has no such clause; a
    /// refused *creation* has nothing to fear losing, and a refused deletion does.
    static let bundleDeleteFailureNotice = "Couldn't delete this block. Nothing was removed."

    /// The alert title that carries `bundleDeleteFailureNotice` on iOS.
    ///
    /// Beside the sentence for the reason `deleteFailureAlertTitle` gives: the title and the body
    /// travel together, so there is no arrangement in which one is updated alone.
    static let bundleDeleteFailureAlertTitle = "Couldn't Delete Block"

    /// The alert title that carries a refused block **edit** on iOS (T-566).
    ///
    /// Beside its sibling above for the same reason, and it deliberately does not reuse
    /// `bundleSaveFailureNotice`: that sentence is the *create* family's, with no clause about
    /// what became of the work, because a refused creation has nothing to lose. A refused edit
    /// does, and `updateBundle` now undoes it — so the sheet reports
    /// `CadencePendingChangePersistence.editFailureNotice`, whose "Nothing was changed." is a
    /// promise that undo is what earns.
    static let bundleEditFailureAlertTitle = "Couldn't Save Block"

    /// - Parameter commit: See `deleteTasks(withIDs:modelContext:commitsImmediately:commit:…)`.
    @discardableResult
    static func delete(
        _ task: AppTask,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        deleteTasks(withIDs: [task.id], modelContext: modelContext, commit: commit)
    }

    /// The one task-deletion core. Every surface on both platforms funnels through here — macOS's
    /// `ModelContext.deleteTasks(withIDs:)` is a thin wrapper that supplies its AppKit-only
    /// hooks — because the two used to be independent implementations and the iOS one quietly
    /// lacked bundle disposal, notification cancellation, and relationship detachment.
    ///
    /// Returns `false` — having changed nothing — when the store could not be read, and (T-365)
    /// when an immediate commit was refused, in which case the delete has been rolled back and the
    /// rows are visible again. `deleteFailureNotice` is the sentence for the second case.
    ///
    /// Both fetches below are `guard let try? …` rather than `(try? fetch(…)) ?? []`, which would
    /// make a failed read indistinguishable from an empty store, and every consequence of that
    /// confusion is destructive rather than merely inert:
    ///
    /// - An empty `allTasks` matches no IDs, so the `tasks.isEmpty` guard aborts the delete — but
    ///   `willDelete` has already torn down focus/hover/subtask-entry state, and the cascade
    ///   callers go on to delete the list regardless. `Area.tasks` and `Project.tasks` nullify
    ///   rather than cascade, so the list's tasks do not die with it: they reappear in Inbox with
    ///   no container.
    /// - An empty `Subtask` fetch skips the unlink-and-delete loop while the parent tasks are
    ///   deleted anyway, leaving `Subtask` rows with `parentTask == nil` — invisible, unreachable,
    ///   and syncing to CloudKit forever.
    /// - An empty `allTasks` also gives `repairDanglingRecurrenceLinks` nothing to re-point, so the
    ///   predecessor keeps believing its successor is alive and the series silently stalls.
    ///
    /// Returning a failure and touching nothing is the only safe reading of "I could not read the
    /// store"; the cascade callers abort on it.
    ///
    /// - Parameter commitsImmediately: Whether this delete commits itself. `true` for every
    ///   ordinary surface — a task swiped away has no enclosing unit of work to ride, and a delete
    ///   left waiting on autosave is lost by a quit.
    ///
    ///   The list cascades pass `false` (T-291). Deleting a list is *one* delete of many rows, and
    ///   it can still fail after this point — a nested project whose store read fails, or the
    ///   caller's own commit being refused. Committing here would put the tasks in the store as
    ///   deleted while the list they belonged to came back, which is the exact half-applied state
    ///   the cascade's `false` return exists to prevent. With this `false`, everything the cascade
    ///   touches is one pending change, so `ModelContext.rollback()` undoes all of it and the
    ///   confirmation can honestly say nothing was removed.
    ///
    ///   `processPendingChanges()` runs either way: it settles the inverse relationships this
    ///   function severed by hand, and it does not write to the store.
    ///
    ///   **That commit goes through `CadencePendingChangePersistence.commitDelete` and its failure
    ///   is returned (T-365).** It used to be `try? modelContext.save()`, which is the one
    ///   spelling that leaves the two halves of a delete disagreeing: the rows marked deleted in
    ///   the context the list reads from, and present in the store the next launch reads from.
    ///   Neither macOS nor iOS could tell that from a delete that landed. Committing through the
    ///   shared spine means a refused save rolls the whole pending delete back — the task, its
    ///   subtasks, the emptied bundle and the repaired recurrence links, which are one pending
    ///   change by this point — and this function says so with `false`.
    ///
    ///   The notification cancellation below is *not* gated on `commitsImmediately`, deliberately.
    ///   It is not a store write, it was already unconditional before the flag existed, and a
    ///   reminder cancelled for a task that comes back is re-scheduled by the next reconcile —
    ///   whereas a reminder left armed for a task that really is gone fires at the user. A
    ///   **refused** commit is the one case that skips it, because it returns first: the task is
    ///   demonstrably still there, so cancelling its reminder would be a change made by a delete
    ///   that promises it made none.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter for
    ///   the reason `CadencePendingChangePersistence` gives — a `save()` that throws cannot be
    ///   provoked out of an in-memory container, and a rollback no test can reach is a rollback no
    ///   test can prove.
    @discardableResult
    static func deleteTasks(
        withIDs taskIDs: Set<UUID>,
        modelContext: ModelContext,
        commitsImmediately: Bool = true,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        willDelete: (Set<UUID>) -> Void = { _ in },
        didDeleteBundles: (Set<UUID>) -> Void = { _ in }
    ) -> Bool {
        guard !taskIDs.isEmpty else { return true }

        guard let allTasks = try? modelContext.fetch(FetchDescriptor<AppTask>()),
              let allSubtasks = try? modelContext.fetch(FetchDescriptor<Subtask>())
        else { return false }

        let tasks = allTasks.filter { taskIDs.contains($0.id) }
        guard !tasks.isEmpty else { return true }

        // Only now that the reads have succeeded and there is real work to do.
        willDelete(taskIDs)

        let subtasks = allSubtasks.filter { subtask in
            guard let parentTask = subtask.parentTask else { return false }
            return taskIDs.contains(parentTask.id)
        }
        for subtask in subtasks {
            subtask.parentTask = nil
            modelContext.delete(subtask)
        }

        let touchedBundles = uniqueBundles(from: tasks.compactMap(\.bundle))

        // Otherwise, if a deleted task is a mid-series recurring occurrence, whichever task
        // recorded it as its `recurrenceSpawnedTaskID` would keep believing the series has a live
        // next occurrence forever, silently stalling it — see
        // CadenceTaskRecurrenceWorkflowSupport for the full story.
        CadenceTaskRecurrenceWorkflowSupport.repairDanglingRecurrenceLinks(forDeleted: tasks, allTasks: allTasks)

        for task in tasks {
            detachRelationships(for: task)
            modelContext.delete(task)
        }

        let deletedBundleIDs = deleteEmptyBundles(touchedBundles, modelContext: modelContext)
        didDeleteBundles(deletedBundleIDs)

        modelContext.processPendingChanges()
        if commitsImmediately {
            do {
                try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)
            } catch {
                return false
            }
        }

        // Cheaper than a full reconcile since we already know exactly which tasks were removed.
        // Without it a scheduled-start reminder fires for a task that no longer exists, because
        // reconciliation only converges at the next `scenePhase` transition.
        Task { await NotificationManager.shared.cancel(taskIDs: Array(taskIDs)) }
        return true
    }

    /// The one place a subtask is attached to a parent task.
    ///
    /// The create-side counterpart to `deleteSubtask` below, and it exists for the same reason:
    /// this codebase does not trust SwiftData to have back-populated an inverse by the moment the
    /// next resolver reads it, so both sides are written explicitly. Five surfaces used to
    /// open-code the insert and only two of them agreed with the rule in `Cadence/Models/AGENTS.md`
    /// — the macOS task detail popover, `TaskCreationService` and the MCP write service set
    /// `subtask.parentTask` and never appended to `parent.subtasks` (T-338, T-387).
    ///
    /// **Those three were not broken, and the tests below cannot make them look broken.** T-387
    /// guessed at a window before the save where a SwiftUI list re-renders off a `task.subtasks`
    /// the write never reached. Measured 2026-08-28, that window does not exist on the create
    /// side: setting `subtask.parentTask = task` leaves `task.subtasks` correct *immediately*, with
    /// no save and no `processPendingChanges`, because SwiftData back-populates the inverse inside
    /// the owning context synchronously. The behavioural tests in
    /// `CadenceSubtaskInverseParityTests` were written against the unfixed call sites first and
    /// passed there.
    ///
    /// So this helper is a convention, not a repair — the same standing as the explicit
    /// `copy.parentTask = nextTask` in the recurrence spawn, which T-294 also found unobservable
    /// and kept anyway. What justifies it is the *delete* side, where the window is real and was
    /// measured (T-296): between `modelContext.delete` and the next flush the parent's array still
    /// holds the deleted row. One subtask path trusting back-population and its neighbour refusing
    /// to is how the two answers drift apart, and drift is what produced three spellings of this
    /// insert. The source scan in that suite is what actually holds the rule; this doc comment and
    /// the two writes below are what make the rule worth holding.
    ///
    /// Blank titles are dropped rather than stored, so a caller can hand over raw user input.
    /// `order` defaults to one past the highest the parent already holds; pass it only to place a
    /// row somewhere other than the end.
    ///
    /// Saving is deliberately the caller's, same as `deleteSubtask`: the surfaces differ on whether
    /// a subtask edit commits immediately or rides an enclosing save.
    @discardableResult
    static func insertSubtask(
        titled title: String,
        into parent: AppTask,
        order: Int? = nil,
        modelContext: ModelContext
    ) -> Subtask? {
        let trimmed = CadenceTitleNormalization.normalized(title)
        guard !trimmed.isEmpty else { return nil }

        let existing = parent.subtasks ?? []
        let subtask = Subtask(title: trimmed)
        subtask.order = order ?? ((existing.map(\.order).max() ?? -1) + 1)
        subtask.parentTask = parent
        modelContext.insert(subtask)
        parent.subtasks = existing + [subtask]
        return subtask
    }

    /// The batch spelling of `insertSubtask(titled:into:order:modelContext:)`, for the creation
    /// paths that take a list of titles typed into a composer or handed over by an MCP client.
    /// Rows land in the given order, appended after whatever the parent already holds; blanks are
    /// skipped without consuming an `order` slot.
    @discardableResult
    static func insertSubtasks(
        titled titles: [String],
        into parent: AppTask,
        modelContext: ModelContext
    ) -> [Subtask] {
        titles.compactMap { insertSubtask(titled: $0, into: parent, modelContext: modelContext) }
    }

    /// The one place a single subtask is deleted from.
    ///
    /// It exists for the same reason the loop in `deleteTasks` above writes `subtask.parentTask = nil`
    /// before deleting: this codebase does not trust SwiftData to have back-populated — or torn
    /// down — an inverse by the moment the next resolver reads it, so both sides are severed
    /// explicitly. Two surfaces used to open-code `modelContext.delete(subtask)` instead, and they
    /// disagreed with that rule and with each other: the iOS task sheet dropped the subtask from
    /// `parent.subtasks` but left `parentTask` pointing at a deleted row, and the macOS task detail
    /// popover left both sides alone.
    ///
    /// `parent` is accepted explicitly because a nil `subtask.parentTask` is exactly the
    /// unpropagated-inverse case this helper exists to survive; callers that already hold the owner
    /// should pass it rather than trusting the back-reference to answer.
    ///
    /// Saving is deliberately the caller's: the two surfaces differ on whether a subtask edit
    /// commits immediately or rides the enclosing sheet's save.
    static func deleteSubtask(_ subtask: Subtask, parent: AppTask? = nil, modelContext: ModelContext) {
        let subtaskID = subtask.id
        if let owner = parent ?? subtask.parentTask {
            owner.subtasks = (owner.subtasks ?? []).filter { $0.id != subtaskID }
        }
        subtask.parentTask = nil
        modelContext.delete(subtask)
    }

    static func detachRelationships(for task: AppTask) {
        let taskID = task.id

        // Legacy rows written by an earlier build can still carry a calendar event identifier.
        // Clearing it is what `SchedulingActions.removeFromCalendar` does; it is spelled out here
        // because that helper is macOS-only and this path is shared.
        if !task.calendarEventID.isEmpty {
            task.calendarEventID = ""
        }

        if let area = task.area {
            area.tasks = (area.tasks ?? []).filter { $0.id != taskID }
        }
        if let project = task.project {
            project.tasks = (project.tasks ?? []).filter { $0.id != taskID }
        }
        if let context = task.context {
            context.tasks = (context.tasks ?? []).filter { $0.id != taskID }
        }
        if let goal = task.goal {
            goal.tasks = (goal.tasks ?? []).filter { $0.id != taskID }
        }
        if let bundle = task.bundle {
            bundle.tasks = (bundle.tasks ?? []).filter { $0.id != taskID }
        }
        for tag in task.tags ?? [] {
            tag.tasks = (tag.tasks ?? []).filter { $0.id != taskID }
        }

        task.area = nil
        task.project = nil
        task.context = nil
        task.goal = nil
        task.bundle = nil
        task.bundleOrder = 0
        task.tags = []
        task.subtasks = []
    }

    /// Disposes of any bundle the delete just emptied. Without this an empty `TaskBundle` survives
    /// and `CadenceCalendarPlanningSupport.bundlesByDate` — which does not filter empty bundles —
    /// keeps rendering a block for it on the timeline indefinitely.
    @discardableResult
    static func deleteEmptyBundles(_ bundles: [TaskBundle], modelContext: ModelContext) -> Set<UUID> {
        var deletedIDs = Set<UUID>()
        for bundle in bundles where (bundle.tasks ?? []).isEmpty {
            deletedIDs.insert(bundle.id)
            modelContext.delete(bundle)
        }
        return deletedIDs
    }

    private static func uniqueBundles(from bundles: [TaskBundle]) -> [TaskBundle] {
        var seen = Set<UUID>()
        return bundles.filter { seen.insert($0.id).inserted }
    }

    static func insertTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String? = nil,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate
        ) else { return nil }

        configure(task)
        modelContext.insert(task)
        do {
            try modelContext.save()
            return task
        } catch {
            modelContext.delete(task)
            throw error
        }
    }

    static func insertScheduledTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String,
        scheduledStartMin: Int,
        estimatedMinutes: Int,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate,
            estimatedMinutes: max(5, estimatedMinutes)
        ) else { return nil }

        task.scheduledStartMin = scheduledStartMin
        configure(task)
        modelContext.insert(task)
        do {
            try modelContext.save()
            return task
        } catch {
            modelContext.delete(task)
            throw error
        }
    }

    /// The day a bundle has to fit inside, and the shortest slot it may occupy.
    ///
    /// macOS spells the same two numbers as `TimelineDayRange` in `macOS/Views/TimelineMetrics.swift`,
    /// which this file cannot see — `Shared/` does not compile the timeline. They are deliberately
    /// identical, and `bundleClampsMatchTheTimelineDayRange` in `TaskBundleTests` fails if one side
    /// moves. Do not re-spell either literal at a call site; that is how the timeline clamp came to
    /// exist four times with three different bounds.
    static let bundleDayEndMin = 24 * 60
    static let bundleMinimumDuration = 5

    /// Clamps a start minute so a minimum-length block still ends inside the day.
    static func clampedBundleStart(_ startMin: Int) -> Int {
        min(max(0, startMin), bundleDayEndMin - bundleMinimumDuration)
    }

    /// Minutes a bundle starting at `startMin` needs in order to hold `tasks`, clamped inside the day.
    ///
    /// Every member contributes at least `bundleMinimumDuration`, so two estimate-less tasks still
    /// get a block tall enough to see and hit rather than a zero-height sliver.
    static func bundleDuration(startingAt startMin: Int, tasks: [AppTask]) -> Int {
        let total = tasks.reduce(0) { partial, task in
            partial + max(task.estimatedMinutes, bundleMinimumDuration)
        }
        return max(bundleMinimumDuration, min(total, bundleDayEndMin - clampedBundleStart(startMin)))
    }

    /// Forms a new bundle out of a scheduled task plus a task dropped onto it.
    ///
    /// **This is the one implementation of the drop-a-task-on-a-task gesture.** It was
    /// `SchedulingActions.createBundle(from:adding:)` inside `#if os(macOS)`, in a file that imports
    /// no AppKit, which is why the gesture existed only on the Mac timeline (T-190).
    /// `SchedulingActions.createBundle(from:adding:)` now delegates here, so macOS's timeline and
    /// iOS's Calendar Board mint a block the same way.
    ///
    /// Returns `nil` when the drop cannot form a block: the same task twice, or a target with no day
    /// or no time-of-day slot. A bundle *is* a timeline block — `dateKey` plus `startMin` — so a
    /// target that is merely do-dated has nothing for the block to sit on, and inventing a start
    /// minute for it would be this platform guessing where the other one refuses to.
    @discardableResult
    static func insertBundle(
        from targetTask: AppTask,
        adding draggedTask: AppTask,
        modelContext: ModelContext
    ) -> TaskBundle? {
        guard targetTask.id != draggedTask.id,
              !targetTask.scheduledDate.isEmpty,
              targetTask.scheduledStartMin >= 0 else { return nil }

        let bundle = TaskBundle(
            title: TaskBundle.defaultDisplayTitle,
            dateKey: targetTask.scheduledDate,
            startMin: clampedBundleStart(targetTask.scheduledStartMin),
            durationMinutes: bundleDuration(
                startingAt: targetTask.scheduledStartMin,
                tasks: [targetTask, draggedTask]
            )
        )
        modelContext.insert(bundle)
        addTask(targetTask, to: bundle, modelContext: modelContext)
        addTask(draggedTask, to: bundle, modelContext: modelContext)
        return bundle
    }

    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) throws -> TaskBundle {
        let clampedStart = clampedBundleStart(startMin)
        let duration = min(max(bundleMinimumDuration, durationMinutes), bundleDayEndMin - clampedStart)
        let bundle = TaskBundle(
            title: TaskBundle.storedTitle(title),
            dateKey: dateKey,
            startMin: clampedStart,
            durationMinutes: duration
        )

        modelContext.insert(bundle)
        do {
            try modelContext.save()
            return bundle
        } catch {
            modelContext.delete(bundle)
            throw error
        }
    }

    /// **Throws when the commit is refused (T-566).** It used to end `try? modelContext.save()`,
    /// and `iOSCalendarBundleDetailSheet`'s "Save" dismissed straight afterwards, so a refused
    /// save closed the sheet exactly as a successful one does — the block's own *delete* button
    /// ten lines above already caught and reported (T-322), and so did the sibling create sheet
    /// (T-471). This is the third way that sheet ends, and it was the one still swallowing.
    ///
    /// The undo is the caller-supplied kind `commitEdit(in:commit:undo:)` asks for, and it has to
    /// reach further than the four fields on the block: moving a block moves its members' own
    /// `scheduledDate`/`scheduledStartMin` too, so an undo that restored only the header would
    /// leave the tasks on the day the store refused to put them on. `rollback()` is not the
    /// answer here for the reasons `commitEdit` records — it would discard unrelated pending work
    /// from the app's single context, and an edit it un-did would not be visible until something
    /// re-fetched.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func updateBundle(
        _ bundle: TaskBundle,
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedStart = min(max(0, startMin), (24 * 60) - 5)
        let duration = min(max(5, durationMinutes), (24 * 60) - clampedStart)

        let previousTitle = bundle.title
        let previousDateKey = bundle.dateKey
        let previousStartMin = bundle.startMin
        let previousDuration = bundle.durationMinutes
        let members = bundle.tasks ?? []
        let previousSchedules = members.map { ($0.scheduledDate, $0.scheduledStartMin) }

        bundle.title = trimmed
        bundle.dateKey = dateKey
        bundle.startMin = clampedStart
        bundle.durationMinutes = duration

        for task in members {
            task.scheduledDate = dateKey
            task.scheduledStartMin = -1
        }

        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            bundle.title = previousTitle
            bundle.dateKey = previousDateKey
            bundle.startMin = previousStartMin
            bundle.durationMinutes = previousDuration
            for (task, schedule) in zip(members, previousSchedules) {
                task.scheduledDate = schedule.0
                task.scheduledStartMin = schedule.1
            }
        }
    }

    /// - Parameter commit: See `updateBundle(_:title:dateKey:startMin:durationMinutes:modelContext:commit:)`.
    static func moveBundle(
        _ bundle: TaskBundle,
        to dateKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try updateBundle(
            bundle,
            title: bundle.title,
            dateKey: dateKey,
            startMin: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            modelContext: modelContext,
            commit: commit
        )
    }

    static func addTask(_ task: AppTask, to bundle: TaskBundle, modelContext: ModelContext) {
        let nextOrder = ((bundle.tasks ?? []).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        // The task's own slot is gone — the bundle owns the block now — so any stale calendar link
        // it still carries has to go with it. `SchedulingActions.addTask` has always cleared this;
        // this copy did not, which was the one field on which the two platforms' add-to-bundle
        // paths disagreed. See "Calendar / Events" in `docs/CLAUDE_REFERENCE.md`: nothing writes
        // this field a non-empty value any more, and every write site clears it.
        task.calendarEventID = ""
        if !(bundle.tasks ?? []).contains(where: { $0.id == task.id }) {
            bundle.tasks = (bundle.tasks ?? []) + [task]
        }
        try? modelContext.save()
    }

    static func removeTaskFromBundle(_ task: AppTask, modelContext: ModelContext) {
        let bundleDateKey = task.bundle?.dateKey ?? task.scheduledDate
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = bundleDateKey
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    /// Moves an unfinished task from a day that has gone by onto today, clearing the slot it used
    /// to hold — the timeline start minute, the block it sat in, and any legacy calendar link.
    ///
    /// **Lifted out of `SchedulingActions.rollOverTaskToToday`** (T-195), which sat in
    /// `macOS/Services/` while importing nothing platform-specific, and was therefore why Today's
    /// rollover banner could not exist on iOS. The Mac spelling delegates to this and must not grow
    /// a second body — same rule as `insertBundle(from:adding:)` (T-190).
    ///
    /// It does **not** save; the batch caller (`CadenceTodayRolloverSupport.rollOver`) saves once
    /// for the whole roll.
    ///
    /// Order matters. The block is left first, so the write below lands on a task that no longer
    /// belongs to yesterday's block rather than dragging the block's members with it; and a block
    /// whose remaining members are all settled is deleted rather than left behind as an empty
    /// timeline row on a past day.
    static func rollOverTaskToToday(_ task: AppTask, todayKey: String, modelContext: ModelContext) {
        if let bundle = task.bundle {
            bundle.tasks = (bundle.tasks ?? []).filter { $0.id != task.id }
            task.bundle = nil
            task.bundleOrder = 0
            normalizeBundleOrder(bundle)
            deleteBundleIfFullySettled(bundle, modelContext: modelContext)
        }
        task.scheduledDate = todayKey
        task.scheduledStartMin = -1
        // Unconditional, not `if scheduledStartMin >= 0`. Nothing writes this field a non-empty
        // value any more (see "Calendar / Events" in `docs/CLAUDE_REFERENCE.md`) and every write
        // site clears it, so a stale identifier from an earlier build must not survive onto the
        // new day.
        task.calendarEventID = ""
    }

    /// The bundle's real members: `bundle.tasks` can still list a task whose own `bundle` has
    /// already been reassigned, and the inverse is what decides membership.
    private static func bundleMembers(in bundle: TaskBundle) -> [AppTask] {
        (bundle.tasks ?? []).filter { $0.bundle?.id == bundle.id }
    }

    private static func normalizeBundleOrder(_ bundle: TaskBundle) {
        let ordered = bundleMembers(in: bundle).sorted {
            if $0.bundleOrder != $1.bundleOrder { return $0.bundleOrder < $1.bundleOrder }
            return $0.createdAt < $1.createdAt
        }
        for (offset, member) in ordered.enumerated() {
            member.bundleOrder = offset
        }
        bundle.tasks = ordered
    }

    private static func deleteBundleIfFullySettled(_ bundle: TaskBundle, modelContext: ModelContext) {
        let members = bundleMembers(in: bundle)
        guard members.allSatisfy({ $0.isDone || $0.isCancelled }) else { return }
        for member in members {
            member.bundle = nil
            member.bundleOrder = 0
            member.scheduledDate = bundle.dateKey
            member.scheduledStartMin = -1
            member.calendarEventID = ""
        }
        bundle.tasks = []
        modelContext.delete(bundle)
    }

    /// Unbundles every member and deletes the block.
    ///
    /// The member loop is deliberately the same one `deleteBundleIfFullySettled` runs twelve lines
    /// above, `calendarEventID` included (T-295). Nothing in the app writes that field a non-empty
    /// value — every assignment is `""` (see "Persisted Fields With No Readers" in
    /// `Cadence/Models/AGENTS.md`) — so this is not a live bug being fixed. It is the two loops
    /// agreeing: a value left on disk by an older build, or arriving from CloudKit, must not
    /// survive one of the two ways a bundle can end and not the other.
    ///
    /// **Throws when the commit is refused (T-322).** It used to end `try? modelContext.save()`,
    /// and its one production caller — `iOSCalendarBundleDetailSheet`'s "Delete Block" — dismissed
    /// straight afterwards, so a refused delete closed the sheet exactly as a successful one does.
    /// That is the shape `delete(_:modelContext:commit:)` two hundred lines above was already fixed
    /// into (T-365), and this is the sibling that was missed: the *other* way a block can end.
    ///
    /// `commitDelete` rolls back, so `bundleDeleteFailureNotice` can say nothing was removed and be
    /// telling the truth — the block and its members are visible again, unbundling and all.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitDelete(in:commit:)`.
    static func deleteBundle(
        _ bundle: TaskBundle,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        for task in bundle.tasks ?? [] {
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }

        bundle.tasks = []
        modelContext.delete(bundle)
        try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)
    }

    private static func nextContainerOrder(
        excluding task: AppTask,
        in allTasks: [AppTask],
        area: Area?,
        project: Project?
    ) -> Int {
        let siblings = allTasks.filter { candidate in
            guard candidate.id != task.id else { return false }
            if let area {
                return candidate.area?.id == area.id
            }
            if let project {
                return candidate.project?.id == project.id
            }
            return candidate.area == nil && candidate.project == nil
        }
        return CadenceTaskQuerySupport.nextTaskOrder(in: siblings)
    }

    private static func nextOrderForSibling(of task: AppTask, in allTasks: [AppTask]) -> Int {
        nextContainerOrder(excluding: task, in: allTasks, area: task.area, project: task.project)
    }
}

// CadenceTaskRecurrenceEditScope and CadenceTaskRecurrenceWorkflowSupport now live in
// CadenceTaskRecurrenceWorkflowSupport.swift (Foundation + SwiftData only) so the same
// recurrence logic can also compile into the headless CadenceMCPServer tool target.
