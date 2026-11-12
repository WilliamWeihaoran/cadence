import Foundation
import SwiftData

/// **Editing a task through the one schedule panel** ([[T-3171]], the task editor's slice).
///
/// `CadenceScheduleDraft` holds no `AppTask`, so the two halves that need one live here: reading a
/// saved task into a draft, and writing a draft back. Both are platform-neutral, which is what lets
/// the macOS inspector adopt the same pair, and both run in the macOS-built `CadenceTests`.
///
/// ## Read exactly, write once
///
/// The draft opens with the task's **own** figures, unsnapped and unfloored: a task at 10:05 with a
/// 20-minute estimate, or with no estimate at all, opens as exactly that, so saving a rename writes
/// back what was there. The inspector this replaces wrote every field the moment it changed; the
/// panel writes them all on Save, as **one** commit through `CadenceTaskFieldEditCommit`, so a
/// refusal restores every field it touched rather than leaving half an edit pending in the one
/// app-wide `ModelContext`.
extension CadenceScheduleDraft {

    /// What an untimed task's clock reads when its time is switched on. The record carries no time
    /// to restore, so this is a starting point, not a reading — the same hour an all-day event
    /// falls back to.
    static let untimedTaskFallbackStartMinute = allDayEventFallbackStartMinute

    /// The latest start a saved task's time can name: 23:59, the last minute that is still on the
    /// day. One figure for the read in `init(editing:)` and the write in
    /// `CadenceTaskEditDraftCommit.apply` ([[T-14233]]), so a time the draft opened with is the
    /// time Save writes back.
    static let lastTaskStartMinute = 24 * 60 - 1

    /// A draft over a task that **already exists**.
    ///
    /// The section is read through the container's own section list, the normalization the
    /// inspector used to perform in place on open — here it is a value in the draft, so opening a
    /// task writes nothing at all.
    init(editing task: AppTask) {
        self.init(dateKey: task.scheduledDate, startMin: Self.untimedTaskFallbackStartMinute, kind: .task)
        subject = .editingTask(task.id)
        title = task.title
        notes = task.notes
        repeatRule = task.recurrenceRule
        priority = task.priority
        dueDateKey = task.dueDate
        listToken = Self.containerToken(of: task)
        sectionName = CadenceTaskMutationSupport.normalizedSectionName(
            task.resolvedSectionName,
            area: task.filedArea,
            project: task.project
        )
        estimateMinutes = max(0, task.estimatedMinutes)
        seriesEndMode = task.recurrenceEndMode
        seriesEndDateKey = task.recurrenceEndDate
        // [[T-6191]]: the count the host's repair-on-open commits, so an old "15 of 10" series
        // opens reading "15 of 15" here too. A pure read; the write is the host's.
        seriesEndCount = CadenceTaskRecurrenceWorkflowSupport.coherentEndCount(
            stored: task.recurrenceEndCount,
            effectiveMode: task.effectiveRecurrenceEndMode,
            occurrenceNumber: task.recurrenceOccurrenceNumber
        )
        seriesOccurrenceNumber = task.recurrenceOccurrenceNumber
        isSettled = CadenceTaskQuerySupport.isFinishedTask(task)

        let hasTime = task.scheduledStartMin >= 0 && !task.scheduledDate.isEmpty
        isAllDay = !hasTime
        startMin = hasTime ? min(task.scheduledStartMin, Self.lastTaskStartMinute) : Self.untimedTaskFallbackStartMinute
        endMin = min(24 * 60, startMin + max(Self.minimumDurationMinutes, estimateMinutes))
    }

    /// `CadenceTaskComposerSupport`'s token for the list the task is **actually** in -- the
    /// picker's own `container(of:)`, so a dual-filed task opens on its project ([[T-15561]]) and
    /// Save cannot re-file it under the area the rest of the app does not show it in.
    static func containerToken(of task: AppTask) -> String {
        CadenceTaskComposerSupport.token(for: CadenceTaskComposerSupport.container(of: task))
    }

    /// Whether the series' rule or its end condition moved — the one edit that reaches beyond this
    /// task, and so the one that asks "only this task, or this and future ones?" before it lands.
    func changesRecurrence(from opened: CadenceScheduleDraft) -> Bool {
        repeatRule != opened.repeatRule || changesRecurrenceEnd(from: opened)
    }

    fileprivate func changesRecurrenceEnd(from opened: CadenceScheduleDraft) -> Bool {
        let mode = effectiveSeriesEndMode
        let openedMode = opened.effectiveSeriesEndMode
        guard mode == openedMode else { return true }
        switch mode {
        case .never: return false
        case .onDate: return seriesEndDateKey != opened.seriesEndDateKey
        case .afterCount: return seriesEndCount != opened.seriesEndCount
        }
    }
}

/// Writes an edited task draft back, as one commit.
@MainActor
enum CadenceTaskEditDraftCommit {

    /// Applies the draft to the task and commits it, restoring every field on a refusal.
    ///
    /// `false` means the store refused and the task — and every later occurrence a series edit
    /// reached — is back exactly as it was: the caller keeps the panel open over the draft, which
    /// still holds what the user chose.
    ///
    /// - Parameters:
    ///   - opened: the draft as the panel opened it. Only the series edit is gated on it: the
    ///     rule and the end condition are applied only when they moved, because applying either
    ///     stamps series metadata and walks the series.
    ///   - area, project: the list `draft.listToken` names, resolved by the host against the store.
    ///   - scope: how far a series edit reaches. Ignored when the series did not move.
    ///   - commit: see `CadenceTaskFieldEditCommit.commit`.
    @discardableResult
    static func save(
        _ draft: CadenceScheduleDraft,
        opened: CadenceScheduleDraft,
        to task: AppTask,
        area: Area?,
        project: Project?,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope,
        in modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let movesSeries = draft.changesRecurrence(from: opened)
        let targets = movesSeries
            ? CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(from: task, allTasks: allTasks, scope: scope)
            : []
        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            alsoRestoring: targets,
            in: modelContext,
            reconciler: reconciler,
            commit: commit
        ) {
            apply(draft, opened: opened, to: task, area: area, project: project, allTasks: allTasks, scope: scope)
        }
        guard landed else { return false }
        // A do date or a time moved, so the wind-down reminders are re-read — the reconcile
        // `CadenceTaskDateEditing` runs after every date write.
        (reconciler ?? .default).run(in: modelContext)
        return true
    }

    /// The writes, and nothing else — no commit. Separate so the commit above is the only place a
    /// refusal is decided.
    static func apply(
        _ draft: CadenceScheduleDraft,
        opened: CadenceScheduleDraft,
        to task: AppTask,
        area: Area?,
        project: Project?,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) {
        // `normalizeCompletionState`'s repair, which the inspector's field observers ran on every
        // edit — spelled here rather than called, because that helper commits behind a `try?` and
        // a commit inside this closure would land half the edit before the undo could cover it.
        // An open task carries no completion stamp; a settled one keeps the one it was given.
        switch task.status {
        case .todo, .inProgress: task.completedAt = nil
        case .done, .cancelled: break
        }
        task.title = draft.title
        task.notes = draft.notes
        task.priority = draft.priority
        task.estimatedMinutes = draft.estimateMinutes
        task.dueDate = draft.dueDateKey
        task.scheduledDate = draft.startDateKey
        // [[T-14233]]: capped where the draft's own read caps it, not at `setScheduledTime`'s
        // 1425. That was the last QUARTER-hour, and the panel's Start roller steps in five minutes
        // ([[T-3171]]), so a picked 11:50 or 11:55 PM saved as 11:45 PM -- and a task already at
        // 23:50 (a five-minute block dragged to the end of the timeline) moved to 23:45 on any
        // unrelated Save, a rename included, against "read exactly, write once" above.
        let minute = draft.scheduledStartMin
        task.scheduledStartMin = minute < 0 ? -1 : min(minute, CadenceScheduleDraft.lastTaskStartMinute)

        let sectionName = CadenceTaskMutationSupport.normalizedSectionName(draft.sectionName, area: area, project: project)
        if CadenceTaskMutationSupport.isAlreadyInContainer(task, area: area, project: project) {
            // **Not `assignContainer`** (T-726's ground, one frame lower): re-asserting the list a
            // task is already in would re-derive its context from the list and overwrite one the
            // user set by hand. Staying put changes only the section.
            task.sectionName = sectionName
        } else {
            CadenceTaskMutationSupport.assignContainer(
                task,
                area: area,
                project: project,
                sectionName: sectionName,
                allTasks: allTasks
            )
        }

        if draft.repeatRule != opened.repeatRule {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                draft.repeatRule,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        if draft.repeatRule == .none {
            // An end condition on a task that no longer repeats is meaningless, and leaving it
            // behind would re-arm the moment repeating is switched back on.
            if opened.repeatRule != .none {
                CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                    mode: .never,
                    to: task,
                    allTasks: allTasks,
                    scope: scope
                )
            }
        } else if draft.changesRecurrenceEnd(from: opened) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                mode: draft.effectiveSeriesEndMode,
                endDateKey: draft.seriesEndDateKey,
                endCount: draft.seriesEndCount,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
    }
}

/// **[[T-16625]]: a task inspector's notes are written as typed, on both platforms.**
///
/// The Mac inspector's notes box always wrote through (`TaskDetailNotesSection`), and the iOS
/// sheet drafted its notes and wrote them only on Save — so Cancel kept typed notes on the Mac and
/// threw them away on iOS, with no hardware reason for the difference ([[T-8201]]). Write-through
/// wins, for reasons the code holds rather than taste:
///
/// - **The notes well mints real tasks.** Turning a line into an embedded task inserts an
///   `AppTask` the moment it is asked for (both platforms' markdown surfaces), so a drafted note
///   discarded by Cancel left that task orphaned with nothing pointing at it.
/// - **Every other notes editor writes through**: the Mac's pop-out Task Notes panel and Focus
///   panel over these same notes, and the event editor's Notes field on both platforms
///   ([[T-8572]]: committed notes are not an unsaved edit).
/// - **A drafted copy overwrote other writers.** Save wrote the copy the sheet opened with back
///   over a sync, MCP or second-editor change made while it was open.
///
/// So notes are an action on the record, like a subtask or a tag: Cancel does not take them back,
/// and Save commits the panel's fields with the notes the task holds **now**.
@MainActor
enum CadenceTaskInspectorNotes {

    /// The inspector's write of typed notes: lands them and commits at once, through the one
    /// typed-content commit every notes editor uses. Text equal to the stored notes writes nothing,
    /// so a well loading or normalising its binding is not an edit. `false` means the store
    /// refused; the text stays pending in the context, as it does on every other typed surface.
    @discardableResult
    static func writeTyped(
        _ content: String,
        to task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard task.notes != content else { return true }
        task.notes = content
        return CadencePendingChangePersistence.commitTypedContent(in: modelContext, commit: commit)
    }

    /// The draft an inspector's Save commits: the panel's fields, with the task's current notes in
    /// place of the copy the draft opened with — so Save never writes notes back at all.
    static func savePayload(_ draft: CadenceScheduleDraft, for task: AppTask) -> CadenceScheduleDraft {
        var payload = draft
        payload.notes = task.notes
        return payload
    }
}
