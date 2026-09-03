#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Shared scheduling mutations

enum SchedulingActions {
    private static let dayStartMin = TimelineDayRange.startMin
    private static let dayEndMin = TimelineDayRange.endMin
    private static let minimumBundleDuration = TimelineDayRange.minimumDuration

    /// Create and insert a new task scheduled to a specific date/time slot.
    static func createTask(title: String, dateKey: String, startMin: Int, endMin: Int, in context: ModelContext) {
        var priority: TaskPriority = .none
        let cleanedTitle = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        guard !cleanedTitle.isEmpty else { return }

        let task = AppTask(title: cleanedTitle)
        task.priority = priority
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        task.estimatedMinutes = max(5, endMin - startMin)
        context.insert(task)
        // No calendar sync here — task has no area/project container yet when created from timeline drag
    }

    /// Create and insert a new scheduled task bundle.
    @discardableResult
    static func createBundle(title: String, dateKey: String, startMin: Int, endMin: Int, in context: ModelContext) -> TaskBundle {
        let range = clampedRange(startMin: startMin, endMin: endMin)
        let bundle = TaskBundle(
            title: TaskBundle.storedTitle(title),
            dateKey: dateKey,
            startMin: range.start,
            durationMinutes: range.duration
        )
        context.insert(bundle)
        return bundle
    }

    /// Creates a scheduled block from a timeline drag, adds the tasks the user ticked to it, and
    /// **commits the pair as one unit** ([[T-636]](e)).
    ///
    /// `createBundle(title:…)` above is right to commit nothing: it is handed a `ModelContext`, and
    /// that signature is this repo's statement that the caller owns the unit of work. What was
    /// missing is the caller doing so. Every timeline that offers "create block" ran
    /// `createBundle` and then `addTask` per selection and then closed its draft popover, so a
    /// refused store left a pending `TaskBundle` — and the membership edits that go with it — in
    /// the app's one `ModelContext`, for the next unrelated `save()` to take or the next unrelated
    /// `rollback()` to discard.
    ///
    /// **Both halves are one unit deliberately.** Committing the block and then adding its members
    /// would put an empty block in the store and leave the memberships pending, which is the same
    /// defect with a smaller blast radius. The undo is therefore two-sided as well:
    /// `commitInsert` un-inserts the block, and `BundleMembership` puts back the five fields
    /// `addTask` writes on each task it moved.
    ///
    /// It does **not** promise "nothing was changed" — the sentence for a refused creation is
    /// `CadenceTaskMutationSupport.bundleSaveFailureNotice`, which deliberately has no such clause.
    /// A task that was already in another block has that block's own member ordering renormalised
    /// on the way out, and this restores the task rather than re-deriving its former siblings.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        endMin: Int,
        adding tasks: [AppTask],
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> TaskBundle {
        // An explicit loop, not `tasks.map(BundleMembership.init)`: this module builds with
        // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so passing the initializer as a function
        // value into `map`'s nonisolated closure is a warning, and the baseline here is zero.
        var members: [BundleMembership] = []
        for task in tasks {
            members.append(BundleMembership(task))
        }
        let bundle = createBundle(
            title: title,
            dateKey: dateKey,
            startMin: startMin,
            endMin: endMin,
            in: context
        )
        for task in tasks {
            addTask(task, to: bundle)
        }
        do {
            try CadencePendingChangePersistence.commitInsert(of: bundle, in: context, commit: commit)
        } catch {
            for member in members {
                member.restore()
            }
            throw error
        }
        return bundle
    }

    /// The fields `addTask(_:to:)` writes on the task it moves, captured before the write.
    ///
    /// The block itself is un-inserted by `commitInsert`, but that does not put the task back: it
    /// was detached from whatever block it was in, given a `bundleOrder`, moved onto the block's
    /// day, stripped of its time slot and of any calendar-event link. A refused creation that
    /// restored only the block would leave the tasks scheduled somewhere the store never agreed to.
    private struct BundleMembership {
        private let task: AppTask
        private let bundle: TaskBundle?
        private let bundleOrder: Int
        private let scheduledDate: String
        private let scheduledStartMin: Int
        private let calendarEventID: String

        init(_ task: AppTask) {
            self.task = task
            bundle = task.bundle
            bundleOrder = task.bundleOrder
            scheduledDate = task.scheduledDate
            scheduledStartMin = task.scheduledStartMin
            calendarEventID = task.calendarEventID
        }

        func restore() {
            task.bundle = bundle
            task.bundleOrder = bundleOrder
            task.scheduledDate = scheduledDate
            task.scheduledStartMin = scheduledStartMin
            task.calendarEventID = calendarEventID
        }
    }

    /// Create and insert a new scheduled task in a specific list/section.
    static func createTask(
        title: String,
        dateKey: String,
        startMin: Int,
        endMin: Int,
        containerSelection: TaskContainerSelection,
        sectionName: String,
        notes: String = "",
        subtaskTitles: [String] = [],
        areas: [Area],
        projects: [Project],
        in context: ModelContext
    ) {
        let draft = TaskCreationDraft(
            title: title,
            notes: notes,
            priority: .none,
            container: containerSelection,
            sectionName: sectionName,
            dueDateKey: "",
            scheduledDateKey: dateKey,
            subtaskTitles: subtaskTitles,
            tags: [],
            scheduledStartMin: startMin,
            estimatedMinutes: max(5, endMin - startMin)
        )
        TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: context)
    }

    /// Creates a scheduled task in a list or section from a drag on a calendar day column, and
    /// **commits it** ([[T-655]]).
    ///
    /// A differently-named sibling of `createTask(title:…containerSelection:…)` above rather than a
    /// commit added to it, for the reason [[T-636]](e) gave when it added `insertBundle` beside
    /// `createBundle`: the commit index resolves a call by *name*, so it vouches for a name only
    /// once **every** overload of it on that type commits. `SchedulingActions` declares two
    /// `createTask`, so committing in one of them would have silenced nothing.
    ///
    /// The undo is `TaskCreationService.createTask`'s, which is the whole insertion — the task and
    /// the subtasks the quick-create popover typed alongside it. `AppTask.subtasks` declares no
    /// cascade, so un-inserting only the task would leave those rows in the context attached to
    /// nothing.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func insertTask(
        title: String,
        dateKey: String,
        startMin: Int,
        endMin: Int,
        containerSelection: TaskContainerSelection,
        sectionName: String,
        notes: String = "",
        subtaskTitles: [String] = [],
        areas: [Area],
        projects: [Project],
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> AppTask? {
        let draft = TaskCreationDraft(
            title: title,
            notes: notes,
            priority: .none,
            container: containerSelection,
            sectionName: sectionName,
            dueDateKey: "",
            scheduledDateKey: dateKey,
            subtaskTitles: subtaskTitles,
            tags: [],
            scheduledStartMin: startMin,
            estimatedMinutes: max(5, endMin - startMin)
        )
        return try TaskCreationService(areas: areas, projects: projects).createTask(
            from: draft,
            into: context,
            commit: commit
        )
    }

    /// Move an existing task to a new date/time. Materialises the default estimate if the task has
    /// none, so the block it lands in is the length `AppTask.timelineDurationMinutes` already draws.
    static func dropTask(_ task: AppTask, to dateKey: String, startMin: Int) {
        removeTaskFromBundle(task, keepOnBundleDate: false)
        task.scheduledDate = dateKey
        task.scheduledStartMin = clampedStartMin(startMin)
        if task.estimatedMinutes <= 0 { task.estimatedMinutes = AppTask.defaultTimelineDurationMinutes }
    }

    static func dropBundle(_ bundle: TaskBundle, to dateKey: String, startMin: Int) {
        let duration = max(bundle.durationMinutes, minimumBundleDuration)
        let clampedStart = TimelineDayRange.clampStart(startMin, duration: duration)
        bundle.dateKey = dateKey
        bundle.startMin = clampedStart
        bundle.durationMinutes = min(duration, dayEndMin - clampedStart)
        for task in memberTasks(in: bundle) {
            task.scheduledDate = dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }
    }

    static func addTask(_ task: AppTask, to bundle: TaskBundle) {
        if task.bundle?.id == bundle.id {
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
            ensureTask(task, isLinkedIn: bundle)
            normalizeBundleOrder(bundle)
            return
        }

        removeTaskFromBundle(task, keepOnBundleDate: false)
        let nextOrder = (memberTasks(in: bundle).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        task.calendarEventID = ""
        ensureTask(task, isLinkedIn: bundle)
        normalizeBundleOrder(bundle)
    }

    /// Forms a bundle out of a scheduled task plus a task dropped onto it.
    ///
    /// The mutation itself is `CadenceTaskMutationSupport.insertBundle(from:adding:)` — shared, and
    /// therefore reachable from iOS's Calendar Board too (T-190). This spelling stays because the
    /// timeline calls it and reads better in `SchedulingActions`' vocabulary; it must not grow a
    /// second body.
    @discardableResult
    static func createBundle(from targetTask: AppTask, adding draggedTask: AppTask, in context: ModelContext) -> TaskBundle? {
        CadenceTaskMutationSupport.insertBundle(
            from: targetTask,
            adding: draggedTask,
            modelContext: context
        )
    }

    /// Forms a block out of a scheduled task plus a task dropped onto it, and **commits the block
    /// and both memberships as one unit** ([[T-655]]).
    ///
    /// The committing sibling of `createBundle(from:adding:in:)` above, added rather than folded
    /// into it for the reason `insertTask` records — `createBundle` has two overloads on this type
    /// and the index needs unanimity before it will vouch for the name.
    ///
    /// **Both tasks are restored on a refusal, not just the block.** `commitInsert` un-inserts the
    /// `TaskBundle`, and that on its own would leave two tasks detached from whatever block they
    /// were in, moved onto a day the store never agreed to and stripped of their time slot and any
    /// calendar link — the same five fields `insertBundle(title:…adding:in:)` restores through
    /// `BundleMembership`, and the same reason.
    ///
    /// **It cannot promise the store holds no block, and that is a finding rather than a caveat.**
    /// `CadenceTaskMutationSupport.addTask` — the shared mutation moves each task with — ends
    /// `try? modelContext.save()`, so the pair is already committed before this frame's `commit` is
    /// asked. In the app the two are the same `save()` and refuse together, so a real refusal
    /// leaves nothing behind; an injected one cannot model that. What this frame does own either
    /// way is that neither task is left where the store never agreed to put it, and that the
    /// canvas is told. `SchedulingActions.addTask`, which `insertBundle(title:…adding:in:)` uses,
    /// has no save of its own. [[T-760]].
    ///
    /// Answers `nil` for a pair the shared mutation refuses — the same task twice, or a target
    /// with no day and time — which is "nothing to make" rather than a failure, so there is
    /// nothing to commit and nothing to report.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func insertBundle(
        from targetTask: AppTask,
        adding draggedTask: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> TaskBundle? {
        let members = [BundleMembership(targetTask), BundleMembership(draggedTask)]
        guard let bundle = createBundle(from: targetTask, adding: draggedTask, in: context) else {
            return nil
        }
        do {
            try CadencePendingChangePersistence.commitInsert(of: bundle, in: context, commit: commit)
        } catch {
            for member in members {
                member.restore()
            }
            throw error
        }
        return bundle
    }

    static func removeTaskFromBundle(_ task: AppTask, keepOnBundleDate: Bool = true) {
        guard let bundle = task.bundle else { return }
        if keepOnBundleDate {
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
        }
        bundle.tasks = (bundle.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        normalizeBundleOrder(bundle)
    }

    static func moveTaskInBundle(_ task: AppTask, direction: Int) {
        guard let bundle = task.bundle, direction != 0 else { return }
        var tasks = bundle.sortedTasks
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let nextIndex = min(max(index + direction, 0), tasks.count - 1)
        guard nextIndex != index else { return }
        tasks.swapAt(index, nextIndex)
        let hiddenMembers = orderedMemberTasks(in: bundle).filter { $0.isCancelled }
        let ordered = tasks + hiddenMembers.filter { hidden in !tasks.contains(where: { $0.id == hidden.id }) }
        for (offset, member) in ordered.enumerated() {
            member.bundleOrder = offset
        }
        bundle.tasks = ordered
    }

    /// Today's rollover, in `SchedulingActions`' vocabulary.
    ///
    /// The body is `CadenceTaskMutationSupport.rollOverTaskToToday` — shared, and therefore
    /// reachable from iOS's Today too (T-195). This spelling stays because the Mac's Today panel
    /// and `TaskBundleTests` read better in it; it must not grow a second body.
    static func rollOverTaskToToday(_ task: AppTask, todayKey: String, in context: ModelContext) {
        CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: todayKey, modelContext: context)
    }

    /// Completes every open member and ends the block.
    ///
    /// **Throws when the commit is refused (T-628).** It used to end `context.delete(bundle)` with
    /// no save at all — and the members it had just marked done spawn recurrence successors, so a
    /// single tap on Complete left an insert *and* a delete pending in the app's one
    /// `ModelContext`, to be taken by the next unrelated `save()` or discarded by the next
    /// unrelated `rollback()`. The hosts then closed their popover over it.
    ///
    /// The detach-and-delete half is `CadenceTaskMutationSupport.deleteBundle` rather than a
    /// fourth copy of the member loop: that is T-322's fix, iOS already routes "Delete Block"
    /// through it, and its `commitDelete` rolls back — which is what lets the popover say nothing
    /// was changed and be telling the truth about the successors too.
    /// - Parameter commit: See `CadencePendingChangePersistence.commitDelete(in:commit:)`. It is a
    ///   parameter for the reason that helper's own doc gives: a `save()` that throws cannot be
    ///   provoked out of an in-memory container, and an undo path no test can reach is an undo path
    ///   no test can prove.
    static func completeBundle(
        _ bundle: TaskBundle,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        for task in memberTasks(in: bundle) where !task.isDone && !task.isCancelled {
            TaskWorkflowService.markDone(task, in: context)
        }
        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context, commit: commit)
    }

    static func updateBundleTime(_ bundle: TaskBundle, startMin: Int, endMin: Int) {
        let range = clampedRange(startMin: startMin, endMin: endMin)
        bundle.startMin = range.start
        bundle.durationMinutes = range.duration
    }

    /// Detaches every member and ends the block, leaving the tasks on the block's day.
    ///
    /// The body was a private `detachBundleMembers` and a bare `context.delete` — the same five
    /// field writes `CadenceTaskMutationSupport.deleteBundle` already ran, and the same missing
    /// commit `completeBundle` had (T-628). Two loops agreeing by inspection is what T-295 was
    /// about; one loop cannot disagree.
    ///
    /// - Parameter commit: See `completeBundle(_:in:commit:)`.
    static func unbundle(
        _ bundle: TaskBundle,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context, commit: commit)
    }

    private static func ensureTask(_ task: AppTask, isLinkedIn bundle: TaskBundle) {
        let existing = bundle.tasks ?? []
        if !existing.contains(where: { $0.id == task.id }) {
            bundle.tasks = existing + [task]
        }
    }

    static func normalizeBundleOrder(_ bundle: TaskBundle) {
        let ordered = orderedMemberTasks(in: bundle)
        for (offset, task) in ordered.enumerated() {
            task.bundleOrder = offset
        }
        bundle.tasks = ordered
    }

    static func deleteBundle(
        _ bundle: TaskBundle,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try unbundle(bundle, in: context, commit: commit)
    }

    /// Detach any legacy calendar-event reference from a task without deleting the calendar event.
    static func removeFromCalendar(_ task: AppTask) {
        task.calendarEventID = ""
    }

    private static func clampedStartMin(_ startMin: Int) -> Int {
        TimelineDayRange.clampStart(startMin)
    }

    private static func memberTasks(in bundle: TaskBundle) -> [AppTask] {
        (bundle.tasks ?? []).filter { $0.bundle?.id == bundle.id }
    }

    private static func orderedMemberTasks(in bundle: TaskBundle) -> [AppTask] {
        memberTasks(in: bundle).sorted {
            if $0.bundleOrder != $1.bundleOrder {
                return $0.bundleOrder < $1.bundleOrder
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private static func clampedRange(startMin: Int, endMin: Int) -> (start: Int, duration: Int) {
        let orderedStart = min(startMin, endMin)
        let orderedEnd = max(startMin, endMin)
        let start = clampedStartMin(orderedStart)
        let end = min(max(start + minimumBundleDuration, orderedEnd), dayEndMin)
        return (start, max(minimumBundleDuration, end - start))
    }
}

// MARK: - Shared zoom control view

struct TimelineZoomControl: View {
    @Binding var zoomLevel: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Button { if zoomLevel > range.lowerBound { zoomLevel -= 1 } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel > range.lowerBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.cadencePlain)
            .cadenceControlLabel("Zoom out")
            Text("\(zoomLevel)×")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 22)
            Button { if zoomLevel < range.upperBound { zoomLevel += 1 } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel < range.upperBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.cadencePlain)
            .cadenceControlLabel("Zoom in")
        }
    }
}
#endif
