#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskDetailSheet: View {
    @Bindable var task: AppTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var newSubtaskTitle = ""
    /// Set when a subtask insert or delete was refused by the store. See `addSubtask()`.
    @State private var subtaskFailureNotice: String?
    @State private var newTagName = ""
    @State private var scheduledDate = Date()
    @State private var dueDate = Date()
    @State private var hasScheduledDate = false
    @State private var hasDueDate = false
    @State private var containerSelection = "inbox"
    /// Set while `applyContainerSelection` puts the token back after a refused move, so the
    /// `onChange` that restore fires does not re-commit the move the store just refused (T-702).
    @State private var isRestoringContainerSelection = false
    @State private var showDeleteConfirmation = false
    /// Set when the delete's commit was refused and rolled back. Same flag, same sentence and the
    /// same second alert `iOSTaskRow` carries — see `deleteTask()`.
    @State private var deleteFailed = false
    @State private var isNotesFocused = false
    /// Set when Done could not flush the sheet's edits. See `finishEditingAndDismiss()`.
    @State private var saveFailureNotice: String?
    @State private var pendingRecurrenceChange: PendingRecurrenceChange?
    /// Set when a recurrence edit did not reach the store. See `apply(_:scope:)`.
    @State private var recurrenceUpdateFailure: String?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var sortedSubtasks: [Subtask] {
        (task.subtasks ?? []).sorted { $0.order < $1.order }
    }

    private var availableGoals: [Goal] {
        let openGoals = goals.filter { $0.status != .done }
        guard let currentGoal = task.goal,
              !openGoals.contains(where: { $0.id == currentGoal.id })
        else { return openGoals }
        return openGoals + [currentGoal]
    }

    private var availableSectionNames: [String] {
        CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject)
    }

    /// The token this sheet holds, read through the one mapping that owns the prefix arithmetic.
    /// `selection(fromToken:)` answers `.inbox` for anything it cannot parse — including a
    /// well-formed prefix over a malformed id — which is what these two used to spell themselves.
    private var containerChoice: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: containerSelection)
    }

    private var selectedAreaID: UUID? {
        CadenceTaskComposerSupport.selectedAreaID(containerChoice)
    }

    private var selectedProjectID: UUID? {
        CadenceTaskComposerSupport.selectedProjectID(containerChoice)
    }

    private var selectedArea: Area? {
        guard let selectedAreaID else { return nil }
        return areas.first { $0.id == selectedAreaID }
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    /// The **only** thing this sheet reads the size class for: the margin between its card and the
    /// edge of the host. Everything else it draws is `iOSTaskInspectorMetrics`, which takes no
    /// width — see that file for why a sheet's measurements are its own.
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// **Split from `editorSurface` (T-407).** The sheet observes eleven fields and presents a
    /// dialog and two alerts, and the moment the second alert joined the chain the whole of `body`
    /// stopped type-checking: `error: the compiler is unable to type-check this expression in
    /// reasonable time`, on the iOS-simulator build and nowhere else. Two expressions rather than
    /// one is the whole fix — nothing here is conditional and no modifier changed.
    var body: some View {
        editorSurface
            .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteTask)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
            // Shared with `iOSTaskRow`; see `iOSTaskDeleteFailureAlert`.
            .iOSTaskDeleteFailureAlert(isPresented: $deleteFailed)
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.taskScopeTitle,
                isPresented: recurrenceScopeDialogPresentation,
                titleVisibility: .visible
            ) {
                Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                    applyPendingRecurrenceChange(scope: .thisTask)
                }
                Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                    applyPendingRecurrenceChange(scope: .thisAndFuture)
                }
                Button("Cancel", role: .cancel) {
                    pendingRecurrenceChange = nil
                }
            } message: {
                Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
            }
            // The same alert `iOSTaskRowRecurrenceScopeDialogModifier` raises, from the same copy:
            // this sheet asks the same scope question about the same series (T-633).
            .alert(
                CadenceRecurrenceScopeCopy.taskScopeFailureTitle,
                isPresented: Binding(
                    get: { recurrenceUpdateFailure != nil },
                    set: { if !$0 { recurrenceUpdateFailure = nil } }
                ),
                presenting: recurrenceUpdateFailure
            ) { _ in
                Button("OK", role: .cancel) { recurrenceUpdateFailure = nil }
            } message: { notice in
                Text(notice)
            }
            .iOSMarkdownReferenceSheets(
                selectedNote: $selectedReferenceNote,
                selectedTask: $selectedReferenceTask,
                referenceNotes: allNotes,
                referenceTasks: allTasks
            )
    }

    /// The scroll view and everything that watches a field on it. Unchanged from what `body`
    /// carried inline; see `body` for why it is a separate expression.
    private var editorSurface: some View {
        NavigationStack {
            editorScrollView
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: initializeTaskSheet)
        .onChange(of: containerSelection) { _, _ in
            applyContainerSelection()
        }
        // No "seed today when switched on" fallback any more: nothing turns these on except a day
        // being picked, so seeding here would overwrite the day the user just chose.
        .onChange(of: hasScheduledDate) { _, _ in applyDates() }
        .onChange(of: hasDueDate) { _, _ in applyDates() }
        .onChange(of: scheduledDate) { _, _ in applyDates() }
        .onChange(of: dueDate) { _, _ in applyDates() }
        .onChange(of: task.title) { _, _ in saveTask() }
        .onChange(of: task.priorityRaw) { _, _ in saveTask() }
        .onChange(of: task.statusRaw) { _, _ in saveTask() }
        .onChange(of: task.recurrenceRaw) { _, _ in saveTask() }
        .onChange(of: task.estimatedMinutes) { _, _ in saveTask() }
        .onChange(of: task.actualMinutes) { _, _ in saveTask() }
        .onChange(of: task.sectionName) { _, _ in saveTask() }
    }

    private var editorScrollView: some View {
        ScrollView {
            taskForm
                .padding(iOSTaskInspectorMetrics.cardPadding)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                .frame(maxWidth: iOSTaskInspectorMetrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: isRegularWidth))
        }
        .background(Theme.bg)
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { taskToolbar }
        .tint(Theme.blue)
    }

    /// Same order as macOS's inspector, for the same reasons: what the task *is* (title, tags,
    /// where it lives), then when it happens, then the work inside it, then its notes, then the
    /// actions that change its state.
    private var taskForm: some View {
        VStack(alignment: .leading, spacing: iOSTaskInspectorMetrics.sectionSpacing) {
            saveFailureNoticeRow
            headerBlock
            propertiesSection
            scheduleSection
            subtasksSection
            notesSection
            statusActionsSection
            focusSection
        }
    }

    /// At the top of the card, because Done is in the navigation bar directly above it — the
    /// refusal reads where the user just tapped rather than at the far end of a scroll.
    @ViewBuilder
    private var saveFailureNoticeRow: some View {
        if let saveFailureNotice {
            CadenceInlineFailureNotice(text: saveFailureNotice)
        }
    }

    /// Title row, then the task's tags and its `List › Section` line indented to the title column —
    /// the same identity block `TaskDetailHeaderSection` draws on macOS.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            iOSTaskEditorTitleCard(task: task, onToggleCompletion: toggleCompletion)

            VStack(alignment: .leading, spacing: 8) {
                iOSTaskTagStrip(task: task, allTags: tags, newTagName: $newTagName)

                iOSTaskPlacementBreadcrumb(
                    task: task,
                    containerSelection: $containerSelection,
                    areas: areas,
                    projects: projects,
                    availableSectionNames: availableSectionNames
                )
            }
            // Completion-circle width plus the title row's spacing, so everything under the title
            // lines up with the title text rather than with the circle. Derived in
            // `iOSTaskInspectorMetrics` from the circle itself, rather than restated here where it
            // could — and did — go on ramping after the circle stopped.
            .padding(.leading, iOSTaskInspectorMetrics.titleColumnInset)
        }
    }

    @ToolbarContentBuilder
    private var taskToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                finishEditingAndDismiss()
            }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private var propertiesSection: some View {
        iOSTaskPropertiesSection(task: task, availableGoals: availableGoals)
    }

    private var scheduleSection: some View {
        iOSTaskScheduleSection(
            task: task,
            recurrenceSelection: recurrenceSelection,
            applyRecurrenceEnd: selectRecurrenceEnd,
            hasScheduledDate: $hasScheduledDate,
            scheduledDate: $scheduledDate,
            hasDueDate: $hasDueDate,
            dueDate: $dueDate,
            scheduledStartSelection: scheduledStartSelection,
            scheduledTimeLabel: scheduledTimeLabel
        )
    }

    private var statusActionsSection: some View {
        iOSTaskStatusActionsSection(task: task) { status in
            CadenceTaskStatusEditing.setStatus(status, for: task, in: modelContext)
        }
    }

    /// T-273: the task half of "start a session from somewhere other than the Focus screen",
    /// finishing what [[T-266]] left. The row long-press menu already carried one — but
    /// `iOSTaskRowContextMenu` is attached to `iOSTaskRow` and to nothing else, so a task met on
    /// the Calendar Board or on a day timeline had no route to a session at all.
    ///
    /// It goes **here** rather than onto `iOSBoardTaskCard` and `iOSTimelineTaskBlock` for the same
    /// reason `iOSCalendarBundleDetailSheet.focusSection` is on the block sheet rather than on the
    /// two cards that open it: both of those surfaces open *this* sheet (pinned by
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
    /// One reachable rough edge, left rather than papered over: `iOSCalendarBundleDetailSheet`
    /// presents this sheet for a block's member tasks, and `dismiss()` there closes only this one,
    /// so the block sheet is still standing over the routed Focus screen and needs its own Close.
    /// Fixing it would mean a third observer of `CadenceFocusHandoffCenter`, and "the shell routes,
    /// the Focus screen adopts" is the division T-266 is built on.
    ///
    /// **T-276: absent on a settled task, not disabled.** The panel sits directly under
    /// `statusActionsSection`, so the button offering to spend time on a task and the control that
    /// just declared it finished were one scroll apart — and the minutes were really banked, since
    /// `iOSFocusView.pickItem(for:)` resolves a handed-over target out of the whole store rather
    /// than out of the ready list. Same predicate the Focus picker filters by and the same one
    /// macOS's hover ▶ has always read.
    @ViewBuilder
    private var focusSection: some View {
        if CadenceFocusSupport.canFocus(task) {
            iOSEditorSection(title: nil, style: .ruled, contentSpacing: 10) {
                iOSActionButton(
                    title: "Focus This Task",
                    systemImage: CadenceFeatureDestination.focus.systemImage,
                    tint: CadenceFeatureDestination.focus.tint,
                    fullWidth: true
                ) {
                    CadenceFocusHandoffCenter.shared.request(.task(task.id))
                    dismiss()
                }
            }
        }
    }

    private var notesSection: some View {
        iOSTaskNotesSection(
            notesText: Binding(
                get: { task.notes },
                set: {
                    task.notes = $0
                    try? modelContext.save()
                }
            ),
            isFocused: $isNotesFocused,
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
            onAdd: addSubtask,
            onDelete: deleteSubtask
        )
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recurrenceSelection: Binding<TaskRecurrenceRule> {
        Binding(
            get: { task.recurrenceRule },
            set: { selectRecurrenceRule($0) }
        )
    }

    private var recurrenceScopeDialogPresentation: Binding<Bool> {
        Binding(
            get: { pendingRecurrenceChange != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRecurrenceChange = nil
                }
            }
        )
    }

    /// The time picker's own "No time" row is what clears the time, so this binding is the single
    /// control for the field — there is no separate switch beside it to fall out of step.
    private var scheduledStartSelection: Binding<Int> {
        Binding(
            get: { task.scheduledStartMin },
            set: { minutes in
                guard minutes >= 0 else {
                    CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext)
                    return
                }
                // A time needs a day under it, so an untimed task adopts today first. `applyDates`
                // reconciles the new day; the wrapper below reconciles the minute (T-362) — before
                // this ticket only the first half did.
                if !hasScheduledDate {
                    scheduledDate = Date()
                    hasScheduledDate = true
                    applyDates()
                }
                CadenceTaskDateEditing.setScheduledTime(minutes, for: task, in: modelContext)
            }
        )
    }

    /// **T-497.** This ended `try? modelContext.save(); dismiss()`, and the dismissal is what told
    /// the user the sheet's last edit had landed. Every field on this sheet is an in-place write to
    /// a task the store already holds, so there is nothing to un-insert and nothing worth undoing
    /// under a caret the user still has in the notes field: the sheet stays open, keeps what they
    /// typed, and names the refusal. See `CadenceInPlaceEditFlush` for the decision.
    private func finishEditingAndDismiss() {
        isNotesFocused = false
        // `applyDates()` answers now rather than swallowing (T-497), so both halves of "the sheet's
        // last edit landed" are one condition: the dates it writes, and whatever else the eleven
        // field observers left pending.
        guard applyDates(), CadenceInPlaceEditFlush.flush(in: modelContext) else {
            saveFailureNotice = CadenceInPlaceEditFlush.failureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    private var scheduledTimeLabel: String {
        task.scheduledStartMin >= 0 ? TimeFormatters.timeString(from: task.scheduledStartMin) : "No time"
    }

    private func initializeTaskSheet() {
        loadDates()
        loadContainerSelection()
    }

    private func loadContainerSelection() {
        containerSelection = containerToken
        normalizeSectionForCurrentContainer()
    }

    /// The token for the list the task is **actually** in. Read twice: once to seed the picker on
    /// open, and once to put it back when a move is refused.
    private var containerToken: String {
        if let area = task.area {
            return "area:\(area.id.uuidString)"
        }
        if let project = task.project {
            return "project:\(project.id.uuidString)"
        }
        return "inbox"
    }

    private func loadDates() {
        if let date = DateFormatters.date(from: task.scheduledDate) {
            scheduledDate = date
            hasScheduledDate = true
        } else {
            scheduledDate = Date()
            hasScheduledDate = false
        }

        if let date = DateFormatters.date(from: task.dueDate) {
            dueDate = date
            hasDueDate = true
        } else {
            dueDate = Date()
            hasDueDate = false
        }
    }

    /// Already reconciled before T-362 — this is the shape the rest of the app was missing. It
    /// now says so through the shared wrapper rather than pairing the two calls by hand.
    ///
    /// **Answers since T-497.** `false` means the store refused the two date fields. The eleven
    /// field observers above discard it — an `onChange` has nothing to report and nothing to close —
    /// and `finishEditingAndDismiss` does not, because closing is a claim.
    @discardableResult
    private func applyDates() -> Bool {
        CadenceTaskDateEditing.setPlanningDates(
            scheduledDate: hasScheduledDate ? DateFormatters.dateKey(from: scheduledDate) : nil,
            dueDate: hasDueDate ? DateFormatters.dateKey(from: dueDate) : nil,
            for: task,
            in: modelContext
        )
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

    /// **T-702.** This discarded what `moveToContainer` answered, and `containerSelection` is a
    /// token the user has just changed: on a refusal the task went back to the list it started in
    /// while the picker — and the breadcrumb reading off it — went on naming the one it never
    /// reached. That is a report in the family the `try? save()` rule already names, because here
    /// the token *is* the claim, and it is more visible than the pending move it replaced.
    ///
    /// The sheet stays open, so it answers inline rather than with the row's alert, and it uses
    /// the slot every other refusal on this sheet uses — one notice per surface, as T-646 decided,
    /// rather than a second flag the two could disagree through.
    private func applyContainerSelection() {
        // The restore below re-enters here through `onChange`. Without this the second pass would
        // re-commit the refused move and clear the notice the first pass just set.
        guard !isRestoringContainerSelection else {
            isRestoringContainerSelection = false
            return
        }

        // **T-726.** `onAppear` seeds this token from the task's own container, and `onChange`
        // cannot tell that seed from a pick — so opening the sheet on any task filed in a list ran
        // the move. `assignContainer` guards the *order* against a re-assert, so nothing moved, but
        // the commit still happened; since T-702 a refusal on it names itself, which put
        // "Couldn't save this change." on a sheet the user had only just opened for an edit they
        // never made. The same question `assignContainer` asks internally, asked one frame up so
        // the commit is not reached at all.
        //
        // The open path loses no write by returning here: `loadContainerSelection()` has already
        // run `normalizeSectionForCurrentContainer()`, and Done flushes through
        // `CadenceInPlaceEditFlush`.
        guard !CadenceTaskMutationSupport.isAlreadyInContainer(
            task,
            area: selectedArea,
            project: selectedProject
        ) else { return }

        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: selectedArea,
            project: selectedProject,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        ) else {
            saveFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            restoreContainerSelection()
            return
        }
        saveFailureNotice = nil
    }

    /// Puts the picker back on the list the refused move left the task in.
    ///
    /// Written only when it actually differs: an unconditional write would leave
    /// `isRestoringContainerSelection` set with no `onChange` coming to consume it, and the flag
    /// would then swallow the user's next pick instead of the restore it was raised for.
    private func restoreContainerSelection() {
        let restored = containerToken
        guard restored != containerSelection else { return }
        isRestoringContainerSelection = true
        containerSelection = restored
    }

    private func normalizeSectionForCurrentContainer() {
        task.sectionName = CadenceTaskMutationSupport.normalizedSectionName(
            task.resolvedSectionName,
            area: selectedArea,
            project: selectedProject
        )
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
    private func addSubtask() {
        let restored = task.subtasks ?? []
        guard let inserted = CadenceTaskMutationSupport.insertSubtask(
            titled: newSubtaskTitle,
            into: task,
            modelContext: modelContext
        ) else { return }
        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            task.subtasks = restored
            subtaskFailureNotice = CadenceTaskInspectorSupport.subtaskAddFailureNotice
            return
        }
        subtaskFailureNotice = nil
        newSubtaskTitle = ""
    }

    /// The delete half of T-634. `commitDelete`'s `rollback()` un-deletes the row but does not put
    /// it back on `task.subtasks`, which `deleteSubtask` edited — so without the restore a refused
    /// delete takes the subtask off the screen and leaves it in the store. Pinned by
    /// `arefusedSubtaskDeleteLeavesTheRowMissingFromTheParentUntilTheCallerPutsItBack`.
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
    private func deleteTask() {
        guard CadenceTaskMutationSupport.delete(task, modelContext: modelContext) else {
            deleteFailed = true
            return
        }
        dismiss()
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        stage(.rule(rule))
    }

    /// The Ends rows' one write path. Same shape as the rule edit above, and deliberately the same
    /// scope question: an end condition belongs to the series, so "only this one" against "this and
    /// future" is exactly as meaningful here as it is for the frequency, and it would be strange
    /// for one of the two edits in the same well to ask and the other to decide silently.
    private func selectRecurrenceEnd(mode: TaskRecurrenceEndMode, dateKey: String, count: Int) {
        let normalizedDate = mode == .onDate ? dateKey : ""
        let normalizedCount = mode == .afterCount
            ? CadenceTaskRecurrenceEndPresentation.normalizedEndCount(count)
            : 0
        guard mode != task.recurrenceEndMode
                || normalizedDate != task.recurrenceEndDate
                || normalizedCount != task.recurrenceEndCount else { return }
        stage(.end(mode: mode, dateKey: normalizedDate, count: normalizedCount))
    }

    /// A task with no siblings has nothing to propagate to, so there is no scope to ask about and
    /// the edit lands immediately. One staging function for both edits, so a future change to how
    /// the scope is asked — the inline "APPLY TO" row macOS uses instead of this dialog — has one
    /// place to land rather than two.
    private func stage(_ change: PendingRecurrenceChange) {
        guard task.isRecurrenceSeriesMember else {
            apply(change, scope: .thisTask)
            return
        }
        pendingRecurrenceChange = change
    }

    private func applyPendingRecurrenceChange(scope: CadenceTaskRecurrenceEditScope) {
        guard let pendingRecurrenceChange else { return }
        // Closed either way: the dialog dismisses itself on the button tap, and the alert below
        // cannot present from behind it.
        self.pendingRecurrenceChange = nil
        apply(pendingRecurrenceChange, scope: scope)
    }

    /// **Commits, and says so when it could not (T-633).**
    ///
    /// This used to end `try? modelContext.save()` with `applyPendingRecurrenceChange` clearing the
    /// pending change — the thing that closes the scope dialog — immediately before it. So a
    /// refused write closed the dialog exactly as an accepted one does, having already rewritten
    /// the rule on every later occurrence of the series in memory.
    ///
    /// `alsoRestoring:` carries those later occurrences, because that is how far the edit reaches:
    /// `recurrenceTargets` is the same list `applyRecurrenceRule`/`applyRecurrenceEnd` walk, asked
    /// for once rather than derived a second way. The row chip's copy of this dialog
    /// (`iOSTaskRowRecurrenceScopeDialogModifier`) is the same shape, through the same unit.
    private func apply(_ change: PendingRecurrenceChange, scope: CadenceTaskRecurrenceEditScope) {
        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
        let landed = CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext) {
            switch change {
            case .rule(let rule):
                CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                    rule,
                    to: task,
                    allTasks: allTasks,
                    scope: scope
                )
                if rule == .none {
                    // An end condition on a task that no longer repeats is meaningless, and leaving
                    // it behind would re-arm the moment repeating is switched back on.
                    CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                        mode: .never,
                        to: task,
                        allTasks: allTasks,
                        scope: scope
                    )
                }
            case .end(let mode, let dateKey, let count):
                CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                    mode: mode,
                    endDateKey: dateKey,
                    endCount: count,
                    to: task,
                    allTasks: allTasks,
                    scope: scope
                )
            }
        }
        recurrenceUpdateFailure = landed ? nil : CadencePendingChangePersistence.editFailureNotice
    }
}

/// One recurrence edit awaiting its scope. Rule and end changes share a single case list — the
/// same shape macOS's inspector uses — so neither can grow a path that forgets the scope.
private enum PendingRecurrenceChange {
    case rule(TaskRecurrenceRule)
    case end(mode: TaskRecurrenceEndMode, dateKey: String, count: Int)
}

#endif
