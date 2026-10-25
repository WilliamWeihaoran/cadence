#if os(iOS)
import SwiftData
import SwiftUI

/// Edits an existing task through **the one shared schedule panel** ([[T-3171]]).
///
/// The form is `CadenceSchedulePanel` in edit mode — the same view the iPad timeline creates a task
/// with and the event editor edits an event with — so creating a task and editing one differ by
/// `CadenceScheduleDraft.subject` and by the Delete control, and by nothing else the panel draws.
/// The panel owns the title and priority, Do (with its time and Clear), Due, the list and section,
/// and the estimate; it writes **nothing** until Save, which commits every one of those fields at
/// once through `CadenceTaskEditDraftCommit` and restores them all on a refusal.
///
/// This file is what the panel cannot hold, carried in its host slot: the tags, the task's series
/// (Repeat, its end condition and the logged time, in `iOSTaskFieldListSection`), the subtasks, the
/// markdown well, the status transitions and completion, and Focus. Those are **actions on the
/// record**, not fields of the draft — a subtask added, a tag removed or a task completed lands the
/// moment it is asked for, exactly as before, and Cancel does not take it back.
struct iOSTaskDetailSheet: View {
    @Bindable var task: AppTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var cardHeight: CGFloat = 520
    @State private var draft: CadenceScheduleDraft
    @State private var newSubtaskTitle = ""
    /// Set when a subtask insert or delete was refused by the store. See `addSubtask()`.
    @State private var subtaskFailureNotice: String?
    @State private var newTagName = ""
    @State private var showDeleteConfirmation = false
    /// Set when the delete's commit was refused and rolled back. Same flag, same sentence and the
    /// same second alert `iOSTaskRow` carries — see `deleteTask()`.
    @State private var deleteFailed = false
    @State private var isNotesFocused = false
    /// The Notes well's held-back typing, flushed before Save reads `draft` ([[T-5170]]).
    @State private var notesFlush = iOSMarkdownEditorFlush()
    /// The one slot this sheet reports a refused save through (T-497, T-646): the panel draws it
    /// beside its footer, whether the save was asked directly or after the series-scope question.
    @State private var saveFailureNotice: String?
    /// Raised by Save when the draft moved the series of a task that has one.
    @State private var isAskingRecurrenceScope = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    /// The draft as the sheet opened it. Save compares against it to decide whether the series
    /// moved — the one edit that asks how far it reaches — and an unsaved difference from it is
    /// what keeps a swipe from discarding the edit.
    private let openedDraft: CadenceScheduleDraft

    init(task: AppTask) {
        _task = Bindable(wrappedValue: task)
        var opened = CadenceScheduleDraft(editing: task)
        opened.estimateIsExplicit = task.estimatedMinutes > 0
        openedDraft = opened
        _draft = State(initialValue: opened)
    }

    /// What closing the sheet now would discard: the swipe guard, Focus This Task and Save all read
    /// this one answer. See `CadenceTaskSheetUnsavedWork`.
    private var hasUnsavedWork: Bool {
        CadenceTaskSheetUnsavedWork.hasUnsavedWork(
            draft: draft,
            opened: openedDraft,
            notesHavePendingEdit: notesFlush.hasPendingEdit,
            pendingSubtaskTitle: newSubtaskTitle
        )
    }

    private var sortedSubtasks: [Subtask] {
        (task.subtasks ?? []).sorted { $0.order < $1.order }
    }

    /// The token the draft holds, read through the one mapping that owns the prefix arithmetic.
    /// `selection(fromToken:)` answers `.inbox` for anything it cannot parse — including a
    /// well-formed prefix over a malformed id.
    private var containerChoice: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
    }

    /// Resolved against the **unfiltered** queries (T-514): a task in an archived list saves and
    /// sections against the list it is in, not against the active ones.
    private var selectedArea: Area? {
        guard let id = CadenceTaskComposerSupport.selectedAreaID(containerChoice) else { return nil }
        return areas.first { $0.id == id }
    }

    private var selectedProject: Project? {
        guard let id = CadenceTaskComposerSupport.selectedProjectID(containerChoice) else { return nil }
        return projects.first { $0.id == id }
    }

    /// The lists a task can be moved to — the active ones — **plus the one it is in**, archived or
    /// not, so the List row names where the task actually lives (T-514). One rule, shared with the
    /// Mac's inline schedule panel (T-3204).
    private var listChoices: [CadenceSchedulePanelChoice] {
        CadenceSchedulePanelChoice.editableTaskListChoices(
            areas: areas,
            projects: projects,
            selection: containerChoice
        )
    }

    private var sectionChoices: [String] {
        CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject)
    }

    /// The state the old title card drew beside the words: an eyebrow for the one status a
    /// checkbox cannot express, and a struck-through title once the task is settled. Read live
    /// off the task, because completing it from this sheet lands at once.
    ///
    /// It read `status == .inProgress || task.isCancelled` until [[T-5015]] (b) retired In
    /// Progress; `isCancelled` is the whole test now.
    private var titleStatus: CadenceSchedulePanelTitleStatus {
        let status = task.status
        let showsEyebrow = task.isCancelled
        return CadenceSchedulePanelTitleStatus(
            eyebrow: showsEyebrow ? status.label : nil,
            eyebrowTint: CadenceTaskPresentationSupport.statusColor(status),
            isSettled: CadenceTaskCompletionState.resolve(task: task).isSettled
        )
    }

    /// **Split from `editorSurface` (T-407).** The sheet presents a dialog and two alerts, and the
    /// moment the second alert joined the chain the whole of `body` stopped type-checking on the
    /// iOS-simulator build. Two expressions rather than one is the whole fix.
    var body: some View {
        editorSurface
            // Shared with `iOSTaskRow`, scope question and all; see
            // `iOSTaskDeleteConfirmationModifier` (T-6115).
            .iOSTaskDeleteConfirmation(task: task, isPresented: $showDeleteConfirmation) { scope in
                deleteTask(scope: scope)
            }
            // Shared with `iOSTaskRow`; see `iOSTaskDeleteFailureAlert`.
            .iOSTaskDeleteFailureAlert(isPresented: $deleteFailed)
            // The same question `iOSTaskRowRecurrenceScopeDialogModifier` asks, from the same copy
            // (T-633) — asked once, at Save, for the series edit the draft carries.
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.taskScopeTitle,
                isPresented: $isAskingRecurrenceScope,
                titleVisibility: .visible
            ) {
                Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                    applySave(scope: .thisTask)
                }
                Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                    applySave(scope: .thisAndFuture)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
            }
            .iOSMarkdownReferenceSheets(
                selectedNote: $selectedReferenceNote,
                selectedTask: $selectedReferenceTask,
                referenceNotes: allNotes,
                referenceTasks: allTasks
            )
    }

    private var editorSurface: some View {
        editorScrollView
            .presentationBackground(.clear)
            .presentationDragIndicator(.hidden)
            .presentationDetents([.height(cardHeight)])
        // **The other half of T-1364's one converted workflow.** Creating a task and then opening
        // it are the same errand, so the sheet that reads it back scales exactly where the sheet
        // that wrote it does. Everything below here is inside the scope.
        .cadenceScaledTypography()
        .preferredColorScheme(.dark)
        // The panel writes on Save, so an unsaved draft is the user's work and nowhere else. A
        // swipe that dropped it would be the silent loss the old write-through sheet never had.
        // `hasPendingEdit`: notes typed in the well's last 2.5 s are not in `draft` yet ([[T-5170]]).
        // Completion is not an edit ([[T-5359]]); an unsent subtask is ([[T-5175]]).
        .interactiveDismissDisabled(hasUnsavedWork)
        // The two fields this sheet does not draft: status, which its own actions write at once,
        // and logged time, which the focus timer writes. `normalizeCompletionState` is the repair
        // the old field observers fired; Save runs it for every drafted field.
        .onChange(of: task.statusRaw) { _, _ in
            draft.isDone = task.isDone
            saveTask()
        }
        .onChange(of: task.actualMinutes) { _, _ in saveTask() }
    }

    private var editorScrollView: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: listChoices,
                sectionChoices: sectionChoices,
                failureNotice: saveFailureNotice,
                titleStatus: titleStatus,
                // The series is drawn below, with its end condition and its scope question.
                offersTaskRepeat: false,
                actions: panelActions
            ) {
                recordSections
            }
            .capturePresentation(CadenceScheduleCaptureOptions())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
            .frame(maxWidth: 540)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.never)
        .scrollIndicators(.hidden)
        .tint(Theme.blue)
    }

    /// Save, Cancel and Delete. Delete stops at its confirmation; Save may stop at the series-scope
    /// question, so every outcome is reported through `saveFailureNotice` rather than returned.
    private var panelActions: CadenceSchedulePanelActions {
        CadenceSchedulePanelActions(
            commit: save,
            cancel: { dismiss() },
            delete: {
                showDeleteConfirmation = true
                return nil
            }
        )
    }

    /// What the panel cannot hold, in the order the inspector always drew it: what the task is
    /// tagged with, its series, the work inside it, its notes, then the actions that change its
    /// state.
    private var recordSections: some View {
        VStack(alignment: .leading, spacing: iOSTaskInspectorMetrics.sectionSpacing) {
            iOSTaskTagStrip(task: task, allTags: tags, newTagName: $newTagName)
            iOSTaskFieldListSection(draft: $draft, loggedMinutes: task.actualMinutes)
            subtasksSection
            notesSection
            statusActionsSection
            focusSection
        }
    }

    private var statusActionsSection: some View {
        iOSTaskStatusActionsSection(task: task, onToggleCompletion: toggleCompletion) { status in
            CadenceTaskStatusEditing.setStatus(status, for: task, in: modelContext)
        }
    }

    /// T-273: the task half of "start a session from somewhere other than the Focus screen",
    /// finishing what [[T-266]] left. The row long-press menu already carried one — but
    /// `iOSTaskRowContextMenu` is attached to `iOSTaskRow` and to nothing else, so a task met on
    /// the Calendar Board or on a day timeline had no route to a session at all.
    ///
    /// It goes **here** rather than onto `iOSBoardTaskCard` and `iOSTimelineTaskBlock`, for the
    /// reason the Block sheet put its own focus section on the sheet rather than on the two cards
    /// that opened it: both of those surfaces open *this* sheet (pinned by
    /// `CadenceTaskInspectorHostTests.noRowOrCardStillPresentsTheInspector`), so one entry is
    /// reachable from both, and neither a permanently visible play glyph on every board card nor a
    /// long-press on an 11pt timeline block is an affordance those surfaces can afford — the
    /// timeline carries a `simultaneousGesture` pinch that a long-press competes with (T-243).
    ///
    /// The request is made **before** `dismiss()`, not after: it is a value dropped in an inbox, so
    /// the shell routes underneath while this sheet is still on screen, and there is no dismissal
    /// callback to hang a second half on. Sequence matters only in that order — reversing it would
    /// post the request from a view being torn down.
    ///
    /// **The one reachable rough edge this used to carry is gone with its surface.** The Block
    /// panel presented this sheet for a block's member tasks, and `dismiss()` there closed only
    /// this one — so the block sheet was left standing over the routed Focus screen and needed its
    /// own Close. [[T-3170]] deleted the Block panel; the surfaces that present this sheet from
    /// inside another sheet are the two markdown ones, and neither offers this section's handoff.
    ///
    /// **T-276: absent on a settled task, not disabled.** The panel sits directly under
    /// `statusActionsSection`, so the button offering to spend time on a task and the control that
    /// just declared it finished were one scroll apart — and the minutes were really banked, since
    /// `iOSFocusView.pickItem(for:)` resolves a handed-over target out of the whole store rather
    /// than out of the ready list. Same predicate the Focus picker filters by and the same one
    /// macOS's hover ▶ has always read.
    ///
    /// **[[T-5173]]: disabled while the sheet holds unsaved work.** The handoff closes the sheet, and
    /// closing it discards the draft, so it used to drop a retitled task or a moved date past the
    /// very swipe guard that protects them, and Focus opened on the old title. Saving first is not
    /// done here: Save can stop at the series-scope question or be refused, and neither has a path
    /// that then also hands off. The caption says what to do instead.
    @ViewBuilder
    private var focusSection: some View {
        if CadenceFocusSupport.canFocus(task) {
            let blocked = hasUnsavedWork
            iOSEditorSection(title: nil, style: .ruled, contentSpacing: 10) {
                iOSActionButton(
                    title: "Focus This Task",
                    systemImage: CadenceFeatureDestination.focus.systemImage,
                    tint: CadenceFeatureDestination.focus.tint,
                    fullWidth: true,
                    isDisabled: blocked
                ) {
                    guard !hasUnsavedWork else { return }
                    CadenceFocusHandoffCenter.shared.request(.task(task.id))
                    dismiss()
                }
                if blocked {
                    Text(CadenceTaskSheetUnsavedWork.focusBlockedCaption)
                        .cadenceFont(.metadata)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The markdown well, writing the **draft's** note: it is saved with everything else the panel
    /// holds, in the one commit, rather than on each keystroke behind a swallowed `try?`.
    private var notesSection: some View {
        iOSTaskNotesSection(
            notesText: $draft.notes,
            isFocused: $isNotesFocused,
            flush: notesFlush,
            referenceNotes: allNotes,
            referenceTasks: allTasks,
            onOpenReference: openMarkdownReference
        )
    }

    private var subtasksSection: some View {
        iOSTaskSubtasksSection(
            subtasks: sortedSubtasks,
            newSubtaskTitle: $newSubtaskTitle,
            canAddSubtask: canAddSubtask,
            failureNotice: subtaskFailureNotice,
            onAdd: { addSubtask() },
            onDelete: deleteSubtask
        )
    }

    private var canAddSubtask: Bool {
        CadenceTaskSheetUnsavedWork.hasPendingComposerEntry(newSubtaskTitle)
    }

    /// The panel's commit. `nil` always: a series edit stops at the scope question, and every
    /// outcome is reported through `saveFailureNotice`, which the panel draws.
    ///
    /// A task with no series has nothing to propagate to, so there is no scope to ask about and the
    /// save lands at once — the rule the per-field series edit this replaces followed.
    private func save() -> String? {
        // [[T-5170]]: first, so `draft.notes` holds the words typed just before the tap. Dropping
        // focus alone writes them a frame later, after the sheet has committed and closed.
        notesFlush.flush()
        isNotesFocused = false
        if draft.changesRecurrence(from: openedDraft) && task.isRecurrenceSeriesMember {
            isAskingRecurrenceScope = true
            return nil
        }
        applySave(scope: .thisTask)
        return nil
    }

    /// **T-497's rule, one commit wide.** The sheet this replaces flushed each field as it changed
    /// and closed on Done only once the flush landed. Here every drafted field is one commit: a
    /// refusal puts the task — and any later occurrence a series edit reached — back as it was,
    /// which is what makes `editFailureNotice`'s "Nothing was changed" true of the record, while
    /// the draft still holds what the user chose and the sheet stays open over it. Retrying is
    /// pressing Save again.
    ///
    /// **[[T-5175]]: a subtask typed and not yet sent is added first**, as Reminders does, through
    /// the composer's own path. It is an action on the record like any added subtask, so it lands
    /// before the draft's commit and stays if that commit is refused; if the subtask itself is
    /// refused, the sheet stays open over the composer's notice and the draft is not committed.
    private func applySave(scope: CadenceTaskRecurrenceEditScope) {
        if canAddSubtask {
            guard addSubtask() else { return }
        }
        guard CadenceTaskEditDraftCommit.save(
            draft,
            opened: openedDraft,
            to: task,
            area: selectedArea,
            project: selectedProject,
            allTasks: allTasks,
            scope: scope,
            in: modelContext
        ) else {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    /// **Deliberately not routed through `CadenceTaskStatusEditing` (T-407).**
    ///
    /// `normalizeCompletionState` is not a user's status change: it is the repair every one of the
    /// field observers above fires through, including the ones that run when the sheet merely
    /// opens and loads its dates. Routing it would reconcile notifications on every appearance and
    /// every keystroke in the title, which is a store-wide fetch per edit for a status that in the
    /// overwhelming majority of calls did not move. The two real transitions this sheet offers —
    /// `statusActionsSection` and `toggleCompletion()` — are routed, and each of them lands its
    /// write *before* this observer sees it.
    private func saveTask() {
        CadenceTaskMutationSupport.normalizeCompletionState(for: task, modelContext: modelContext)
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    /// **T-634.** This cleared the field *first* and swallowed the save after it, so an emptied
    /// composer reported a subtask the store may never have taken. `insertSubtask` is handed a
    /// `ModelContext` and commits nothing of its own, which is what put the insert one frame below
    /// the `try?`.
    ///
    /// `restored` is the same one-field snapshot macOS's `TaskDetailPopover.addSubtask` takes, and
    /// for the same measured reason: `commitInsert` deletes the row it inserted, but the row is
    /// also in `task.subtasks` and the delete does not reach that array before the sheet
    /// re-renders. See `arefusedSubtaskInsertLeavesAPhantomOnTheParentUntilTheCallerDropsIt`.
    ///
    /// Answers whether the subtask landed, for Save ([[T-5175]]); the composer ignores it.
    @discardableResult
    private func addSubtask() -> Bool {
        let restored = task.subtasks ?? []
        guard let inserted = CadenceTaskMutationSupport.insertSubtask(
            titled: newSubtaskTitle,
            into: task,
            modelContext: modelContext
        ) else { return false }
        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            task.subtasks = restored
            subtaskFailureNotice = CadenceTaskInspectorSupport.subtaskAddFailureNotice
            return false
        }
        subtaskFailureNotice = nil
        newSubtaskTitle = ""
        return true
    }

    /// The delete half of T-634, and the twin of `TaskDetailPopover.deleteSubtask` on macOS, whose
    /// doc comment carries the full reasoning.
    ///
    /// **This used to say the rollback "does not put it back on `task.subtasks`", and that expired
    /// on 2026-09-18.** Through Xcode 26 it was true (T-402) and `restored` was the repair: a
    /// refused delete took the subtask off the screen and left it in the store. **Xcode 27 restores
    /// the relationship immediately** (T-1279), which T-1279's own sweep of this claim missed here.
    ///
    /// `restored` stays, and [[T-1280]] is the survey that decided so rather than a guess: on
    /// Xcode 26 it is still the repair, and on either toolchain re-applying this parent's own array
    /// is how *this* caller repairs *its* object without depending on what else `commitDelete`'s
    /// rollback of the one app-wide `ModelContext` swept up. That it is a no-op on 27 — neither a
    /// duplicate nor a second insertion — is pinned by
    /// `arefusedSubtaskDeleteIsRepairedByTheCapturedArrayOnEveryToolchain`.
    private func deleteSubtask(_ subtask: Subtask) {
        let restored = task.subtasks ?? []
        CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)
        do {
            try CadencePendingChangePersistence.commitDelete(in: modelContext)
        } catch {
            task.subtasks = restored
            subtaskFailureNotice = CadenceTaskInspectorSupport.subtaskDeleteFailureNotice
            return
        }
        subtaskFailureNotice = nil
    }

    /// The completion half of the old title card's circle — it settles the task the moment it is
    /// tapped. T-344's rule is `toggleCompletion`'s: on a cancelled task it restores to todo.
    private func toggleCompletion() {
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
    }

    /// Attempt, then decide — the shape `iOSTaskRow.deleteTask()` and
    /// `iOSNoteDeleteConfirmationSheet.confirm()` use.
    ///
    /// **T-407.** This sheet dismissed on the button tap regardless of what the delete returned.
    /// Since T-365 `delete` answers `false` when its commit was refused, having rolled the whole
    /// pending delete back — so the sheet closed announcing a removal the store never took, and
    /// the task was still in the list behind it with nothing to say why.
    ///
    /// The `dismiss()` is inside the success branch rather than after the call, because a sheet
    /// that stays open is the *point*: the user is looking at the task that did not go away. The
    /// notice is `CadenceTaskMutationSupport.deleteFailureNotice`, the shared sentence, on a second
    /// alert — [[T-376]]'s answer for a confirmation that dismisses itself on the tap, rather than
    /// a third pattern.
    private func deleteTask(scope: CadenceTaskRecurrenceDeleteScope) {
        guard CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: scope
        ) else {
            deleteFailed = true
            return
        }
        dismiss()
    }
}

#endif
