#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Shared scheduling mutations

enum SchedulingActions {
    private static let dayStartMin = TimelineDayRange.startMin
    private static let dayEndMin = TimelineDayRange.endMin
    private static let minimumBundleDuration = TimelineDayRange.minimumDuration

    /// Creates a scheduled task in a list or section from a drag on a calendar day column, and
    /// **commits it** ([[T-655]]).
    ///
    /// T-759 deleted the un-committing `createTask(title:…containerSelection:…)` sibling this
    /// replaced: it had zero production callers left (every real drag-into-a-list path already
    /// called this committing one instead), and its only caller was a test exercising a path the
    /// app no longer has.
    ///
    /// The undo is `TaskCreationService.createTask`'s, which is the whole insertion — the task and
    /// the subtasks the quick-create popover typed alongside it. `AppTask.subtasks` declares no
    /// cascade, so un-inserting only the task would leave those rows in the context attached to
    /// nothing.
    ///
    /// **T-1436.** `priority` defaults to `.none` because this is also the plain drag-out entry
    /// point — a drag that never named a priority has none to state — but it is a parameter now
    /// rather than a literal. The literal was what made the Calendar page's quick-create tab the
    /// one macOS Task composer with no priority row: the tab could have drawn one, and
    /// `QuickCreateTaskDraft` has carried `priority` since [[T-1433]], but this write path had
    /// nowhere to put it, so the call site dropped the field under a comment saying so.
    ///
    /// Whatever is passed here still loses to a `!`/`!!` shortcut typed into the title, because
    /// `TaskCreationDraft.resolvedPriority` is what applies it — the picker is the slower spelling
    /// of the same field, not a second one.
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
        priority: TaskPriority = .none,
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
            priority: priority,
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

    // `addTask(_:to:)` was declared here -- the Mac's "drop a task onto an existing block".
    // [[T-3170]] deleted the canvas arm that could express that drop, so it has no caller.

    // [[T-3170]] removed createBundle(from:adding:in:) and insertBundle(from:adding:in:commit:)
    // with the Mac timeline's drag-a-task-onto-a-task gesture, their only caller. The shared
    // constructor they forwarded to went too, once iOS's Calendar Board stopped forming blocks.

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

    // completeBundle(_:in:commit:) was declared here -- "Complete Block" on the Mac. Its last
    // caller went with the Block UI ([[T-3170]]); only `TaskBundleTests` still reached it. The
    // shared detach-and-delete it forwarded to is `CadenceTaskMutationSupport.deleteBundle`.

    // `updateBundleTime(_:startMin:endMin:)` was declared here -- the block's resize handle.
    // Its only caller was `TimelineBundleBlock`, deleted by [[T-3170]]'s trio pass.

    // unbundle(_:in:commit:) was declared here, with deleteBundle(_:in:commit:), which only
    // forwarded to it. [[T-3170]] removed both once no production path called either.

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
