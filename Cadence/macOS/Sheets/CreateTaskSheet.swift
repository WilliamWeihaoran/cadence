#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

/// **The Mac's Cmd+N / `+` composer is the shared capture card** ([[T-13792]]).
///
/// It was its own form -- priority, title, notes, subtasks and a toolbar of List, Section, Do Date,
/// Due Date and Tags badges -- so a task made here could not be given a repeat, a time of day or an
/// estimate, and could not be an event at all, while iOS's `+` offered every one of them. The form
/// is `CadenceSchedulePanel` + `.capturePresentation`, as `iOSCreateTaskSheet` hosts it, and this
/// view owns only what a Mac adds on top:
///
/// - **The keyboard layer** (`keyboardShortcuts`): Cmd+T / Cmd+D set or clear today as the do and
///   due date, Cmd+Shift+T / Cmd+Shift+D open the card's Do and Due panels, Cmd+P cycles priority,
///   Cmd+Shift+= / Cmd+Shift+- nudge the do date a day, Cmd+Return creates and Escape cancels.
///   Each answers a hardware keyboard, which is the one thing [[T-8201]] lets differ.
/// - **The draft subtask rows**, in the card's host slot, so [[T-10040]]'s Return rule survives:
///   the card's own one-per-line field is switched off here (`offersSubtasks: false`).
/// - **The `~` / `#` suggestion strip** under the title -- the same strip iOS's card draws.
///
/// The **Event arm** comes with the card: keeper `keeper0938` decided it under [[T-13810]], because
/// iOS's `+` offers it and no Mac hardware constraint answers its absence.
struct CreateTaskSheet: View {
    let seed: TaskCreationSeed
    let dismissAction: (() -> Void)?
    let successAction: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Area.order)     private var areas:     [Area]
    @Query(sort: \Project.order)  private var projects:  [Project]
    @Query(sort: \Tag.order)      private var tags:      [Tag]

    @State private var draft: CadenceScheduleDraft
    @State private var selectedTagIDs: Set<String> = []
    /// Why the sheet is still open. `nil` on every path that has not failed. Drawn by the card,
    /// through the panel's `failureNotice:`, above the controls the user is about to press again.
    @State private var actionError: String?
    /// Cmd+Shift+T / Cmd+Shift+D: the card panel to open. See `CadenceScheduleCaptureOptions`.
    @State private var fieldRequest: CadenceCaptureField?
    @FocusState private var focusedSubtask: CreateTaskSubtaskDraft.ID?
    @State private var subtaskDrafts: [CreateTaskSubtaskDraft] = []

    init(
        seed: TaskCreationSeed,
        dismissAction: (() -> Void)? = nil,
        successAction: (() -> Void)? = nil
    ) {
        self.seed = seed
        self.dismissAction = dismissAction
        self.successAction = successAction
        _draft = State(initialValue: CadenceTaskComposerSupport.captureDraft(seed: seed.composerSeed))
        _subtaskDrafts = State(initialValue: CreateTaskSubtaskDraft.drafts(from: seed.subtaskTitles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            keyboardShortcuts
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: CadenceScheduleDraftChoices.listChoices(for: draft, areas: areas, projects: projects),
                sectionChoices: CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: areas, projects: projects),
                calendarChoices: calendarChoices,
                calendarUnavailableNotice: calendarUnavailableNotice,
                failureNotice: actionError,
                canCommit: canCreate,
                // The draft rows below carry the checklist, with [[T-10040]]'s Return rule.
                offersSubtasks: false,
                actions: CadenceSchedulePanelActions(commit: commit, cancel: dismiss)
            ) {
                markerSuggestions
                if draft.kind == .task {
                    subtasksSection
                    addSubtaskButton
                }
            }
            .capturePresentation(CadenceScheduleCaptureOptions(
                tagChoices: TagSupport.uniqueBySlug(tags.filter { !$0.isArchived }).map {
                    CadenceSchedulePanelChoice(id: $0.id.uuidString, name: $0.name, color: Color(hex: $0.colorHex), systemImage: "tag")
                },
                selectedTagIDs: $selectedTagIDs,
                createTag: createTag,
                fieldRequest: $fieldRequest
            ))
        }
        .frame(width: 600)
        .background(Theme.surface)
        .onAppear {
            reconcileContainer()
            normalizeCalendar()
        }
        // **T-317: the lists change too, not just the selection.** A container deleted in another
        // window or removed by sync stayed selected, and creation quietly downgraded it to the
        // Inbox. `@Query` republishes when the store does, so this flips the moment the chosen
        // list stops existing. A list picked in the card re-resolves its section there ([[T-8591]]).
        .onChange(of: containerStillExists) { _, _ in reconcileContainer() }
        .onChange(of: draft.kind) { _, _ in
            actionError = nil
            normalizeCalendar()
        }
        .onChange(of: calendarManager.writableCalendars.map(\.calendarIdentifier)) { _, _ in normalizeCalendar() }
    }

    /// The Mac's keyboard layer over the shared card ([[T-13792]]). Hidden buttons, so each chord
    /// is a key equivalent of this window -- the card's popovers are their own windows and keep
    /// their keys, Escape included.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { CreateTaskKeyboardCommands.toggleDoToday(&draft) }
                .keyboardShortcut("t", modifiers: .command)
            Button("") { fieldRequest = .doDate }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("") { CreateTaskKeyboardCommands.toggleDueToday(&draft) }
                .keyboardShortcut("d", modifiers: .command)
            Button("") { fieldRequest = .dueDate }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("") { CreateTaskKeyboardCommands.cyclePriority(&draft) }
                .keyboardShortcut("p", modifiers: .command)
            // Was `TaskTitleEntryField`'s, which the card's title field is not.
            Button("") { CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: 1) }
                .keyboardShortcut("=", modifiers: [.command, .shift])
            Button("") { CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: -1) }
                .keyboardShortcut("-", modifiers: [.command, .shift])
            Button("") { actionError = commit() }
                .keyboardShortcut(.return, modifiers: [.command])
            // [[T-8103]] (a): Escape closes the sheet the way the card's ✕ does. The in-window host
            // (`TaskCreationLayerView`) had no Escape at all, so the key fell through to the main
            // window's `cancelOperation` and did nothing. The quick-capture panel's
            // `dismissAction` is the `closeDiscardingDraft` its `NSPanel.cancelOperation` runs, so
            // the key means the same there. The card's field popovers, and the `~` / `#` strip's,
            // are their own windows, so this key equivalent does not take Escape from them.
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var markerSuggestions: some View {
        if draft.kind == .task, let shortcut = TaskTitleSupport.containerShortcut(in: draft.title) {
            iOSTaskComposerMarkerSuggestions(
                kind: .list, shortcut: shortcut, areas: areas, projects: projects, allTags: tags,
                onPickContainer: { selection in
                    draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    draft.listToken = CadenceTaskComposerSupport.token(for: selection)
                    normalizeSection()
                }, onPickTag: { _ in }, onCreateTag: { _ in }
            )
        } else if draft.kind == .task, let shortcut = TaskTitleSupport.tagShortcut(in: draft.title) {
            iOSTaskComposerMarkerSuggestions(
                kind: .tag, shortcut: shortcut, areas: areas, projects: projects, allTags: tags,
                onPickContainer: { _ in },
                onPickTag: { tag in
                    draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    selectedTagIDs.insert(tag.id.uuidString)
                },
                onCreateTag: { name in
                    // Keep the shortcut on refusal, so no typed input is lost.
                    if createTag(name) == nil {
                        draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    }
                },
                onAddDefaultTags: addDefaultTags
            )
        }
    }

    @ViewBuilder
    private var subtasksSection: some View {
        if !subtaskDrafts.isEmpty {
            VStack(spacing: 0) {
                // T-6452: keyed by each draft's own id, not its index. An index-keyed row bound to
                // `$titles[index]` outlived a removal — the row SwiftUI retired was the last index,
                // whose binding still subscripted the shrunk array as it tore down.
                ForEach($subtaskDrafts) { $draft in
                    subtaskRow($draft)
                }
            }
        }
    }

    private func subtaskRow(_ draft: Binding<CreateTaskSubtaskDraft>) -> some View {
        let draftID = draft.wrappedValue.id
        return HStack(spacing: 8) {
            Circle()
                .strokeBorder(Theme.dim.opacity(0.3), lineWidth: 1)
                .frame(width: 12, height: 12)
            TextField("Subtask", text: draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($focusedSubtask, equals: draftID)
                .onSubmit { addSubtaskDraft(after: draftID) }
            Button {
                subtaskDrafts = CreateTaskSubtaskDraft.removing(draftID, from: subtaskDrafts)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.dim.opacity(0.5))
                    // [[T-9501]]: the bare 9pt glyph was the whole hit area and hover wash.
                    .frame(minWidth: 18, minHeight: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            // T-673: the glyph says "remove"; VoiceOver still needs to know remove *what* — a
            // draft subtask has no model yet, so the row hands down its own text, normalised the
            // same way an unnamed one would render.
            .cadenceControlLabel("Remove")
            .accessibilityValue(TaskTitleSupport.displayTitle(
                draft.wrappedValue.title,
                fallback: TaskTitleSupport.defaultCompactDisplayTitle
            ))
        }
        .padding(.vertical, 4)
    }

    private var addSubtaskButton: some View {
        Button { addSubtaskDraft(after: nil) } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add Subtask")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.dim.opacity(0.65))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
    }

    /// Return in a draft row (`after:` that row) or the Add Subtask button (`after: nil`).
    /// What it does is `CreateTaskSubtaskDraft.addingDraft(after:in:)`'s to decide ([[T-10040]]).
    private func addSubtaskDraft(after draftID: CreateTaskSubtaskDraft.ID?) {
        let next = CreateTaskSubtaskDraft.addingDraft(after: draftID, in: subtaskDrafts)
        subtaskDrafts = next.drafts
        focusedSubtask = next.focus
    }

    // MARK: - Logic

    private var selection: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
    }

    private var containerResolver: TaskContainerResolver {
        TaskContainerResolver(areas: areas, projects: projects)
    }

    /// `false` once the chosen list has stopped existing. Watched rather than read — see the
    /// `onChange` in `body`.
    private var containerStillExists: Bool {
        !CadenceTaskComposerSupport.namesMissingContainer(selection, areas: areas, projects: projects)
    }

    private var canCreate: Bool {
        switch draft.kind {
        case .task: return CadenceTaskComposerSupport.canCreate(title: draft.title)
        case .event:
            return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCalendar != nil
        }
    }

    private func normalizeSection() {
        draft.sectionName = containerResolver.normalizedSectionName(draft.sectionName, for: selection)
    }

    /// Puts the selection back where it can be honoured, and says so when it had to.
    ///
    /// **T-317.** `TaskContainerResolver.applyContainer` attaches nothing for an id it cannot find
    /// and `insertTask` inserts the task regardless, so a stale selection produced an Inbox task
    /// under a card whose chip still named a list. The chip is reset where the user can see it
    /// and this Add is refused; the composer still holds everything they typed, so confirming costs
    /// one keystroke and nothing is lost by asking.
    ///
    /// Returns whether the selection was already good.
    @discardableResult
    private func reconcileContainer() -> Bool {
        guard CadenceTaskComposerSupport.namesMissingContainer(
            selection,
            areas: areas,
            projects: projects
        ) else { return true }

        draft.listToken = CadenceTaskComposerSupport.token(for: .inbox)
        normalizeSection()
        actionError = CadenceTaskComposerSupport.missingContainerNotice
        return false
    }

    /// The card's Add, its title's Return, and Cmd+Return. `nil` when the draft left the sheet,
    /// the sentence to draw when it did not.
    private func commit() -> String? {
        guard canCreate else { return nil }
        switch draft.kind {
        case .task:
            createTask()
        case .event:
            createEvent()
        }
        return actionError
    }

    private func createTask() {
        guard CadenceTaskComposerSupport.canCreate(title: draft.title) else { return }
        guard reconcileContainer() else { return }
        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft,
            container: selection,
            tags: tags.filter { selectedTagIDs.contains($0.id.uuidString) },
            subtaskTitles: CreateTaskSubtaskDraft.titles(of: subtaskDrafts)
        )
        // T-364: the commit is part of the creation, and it can fail. Everything below this line
        // is the success experience — a reconcile pass, a success toast, a closed sheet — and none
        // of it may run over a task the store did not take. On a throw `createTask` has already
        // removed the task and its subtasks again, so the sheet is back to exactly what the user
        // typed, with the reason on the card. `iOSCreateTaskSheet.create()` is the same shape; the
        // two composers do not get to differ about this.
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: creation, into: modelContext)
        } catch {
            actionError = TaskCreationService.saveFailureNotice
            return
        }
        guard created != nil else { return }

        actionError = nil
        // Fast-path reconcile so a newly-created scheduled/due task's notification is picked up
        // immediately, instead of waiting for the next scenePhase checkpoint.
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)

        if let successAction {
            successAction()
        } else {
            dismiss()
            taskCreationManager.presentSuccessToast()
        }
    }

    /// The card's Event arm, through the write the drag-create popover uses. A refusal stays on the
    /// card with the draft (T-658); `report` clears the window-wide alert so it is said once.
    private func createEvent() {
        let failure = calendarManager.createStandaloneEvent(
            QuickCreateEventDraft(scheduleDraft: draft),
            hostDay: Date()
        )
        calendarManager.report(
            CadenceCalendarEventEditingSupport.saveOutcome(for: failure),
            into: $actionError
        ) {
            if let successAction { successAction() } else { dismiss() }
        }
    }

    private func dismiss() {
        if let dismissAction { dismissAction() } else { taskCreationManager.dismiss() }
    }

    // MARK: - Calendars

    private var selectedCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
    }

    private var calendarChoices: [CadenceSchedulePanelChoice] {
        let _ = calendarManager.storeVersion
        return calendarManager.writableCalendars.map {
            CadenceSchedulePanelChoice(
                id: $0.calendarIdentifier,
                name: $0.title,
                // `cgColor` is implicitly unwrapped and nil on a calendar EventKit has not coloured
                // yet; read as the dim row rather than trapping (T-2047's shape).
                color: $0.cgColor.map { Color(cgColor: $0) } ?? Theme.dim,
                systemImage: "calendar"
            )
        }
    }

    /// Said instead of the picker when there is nothing to pick. Never a permission request: the
    /// composer names what is missing and leaves the request to Settings, as the drag-create
    /// popover does.
    private var calendarUnavailableNotice: String? {
        guard draft.kind == .event else { return nil }
        if !calendarManager.isAuthorized {
            return "Calendar access is needed to create events. Turn it on in Settings, then try again."
        }
        if calendarManager.writableCalendars.isEmpty {
            return "No writable calendars are available."
        }
        return nil
    }

    private func normalizeCalendar() {
        guard draft.kind == .event, selectedCalendar == nil else { return }
        draft.calendarID = calendarManager.defaultWritableCalendar?.calendarIdentifier
            ?? calendarManager.writableCalendars.first?.calendarIdentifier
            ?? ""
    }

    // MARK: - Tags

    /// [[T-9231]]: the strip's Add Default Tags chip, the same committing seed the tag popover
    /// runs. A refusal rolls the whole seed back and says so.
    private func addDefaultTags() {
        do {
            try TagSupport.seedDefaultTagsCommitting(in: modelContext)
            actionError = nil
        } catch {
            actionError = CadencePendingChangePersistence.editFailureNotice
        }
    }

    /// **T-631, half 3 of the `try? save()` rule.** A tag typed here is committed on the spot, so
    /// one abandoned with Cancel is not left *pending* for whatever unrelated screen saves next.
    /// `nil` when the tag exists and is selected; the sentence the card draws when it does not.
    private func createTag(_ name: String) -> String? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {
            actionError = CadencePendingChangePersistence.editFailureNotice
            return actionError
        }
        selectedTagIDs.insert(tag.id.uuidString)
        actionError = nil
        return nil
    }
}

extension TaskCreationSeed {
    /// The fields the shared capture card opens on ([[T-13792]]). The draft subtasks are the
    /// Mac sheet's own rows and travel separately.
    var composerSeed: CadenceTaskComposerSeed {
        CadenceTaskComposerSeed(
            title: title,
            notes: notes,
            doDateKey: doDateKey,
            dueDateKey: dueDateKey,
            priority: priority,
            container: container,
            sectionName: sectionName,
            scheduledStartMin: scheduledStartMin,
            estimatedMinutes: estimatedMinutes
        )
    }
}

/// The Mac composer's keyboard layer, as draft edits ([[T-13792]]). Static so each chord is
/// checked against a draft rather than inferred from a view.
///
/// The date chords are the **task's**: an event's start is a range with an end to keep after it,
/// which the card's Starts row moves; a chord that cleared it would leave an event with no day.
enum CreateTaskKeyboardCommands {
    /// Cmd+T: today as the do date, or no do date when it is already today.
    static func toggleDoToday(_ draft: inout CadenceScheduleDraft, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        if draft.startDateKey == today {
            draft.clearDoDate()
        } else {
            setDoDate(&draft, to: today)
        }
    }

    /// Cmd+D: today as the due date, or none when it is already today.
    static func toggleDueToday(_ draft: inout CadenceScheduleDraft, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        draft.dueDateKey = draft.dueDateKey == today ? "" : today
    }

    /// Cmd+Shift+= / Cmd+Shift+-: the do date a day later or earlier, starting from today when
    /// there is none.
    static func nudgeDoDate(_ draft: inout CadenceScheduleDraft, by days: Int, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        let base = draft.startDateKey.isEmpty ? today : draft.startDateKey
        guard let day = DateFormatters.date(from: base),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        setDoDate(&draft, to: DateFormatters.dateKey(from: moved))
    }

    /// Cmd+P: the next priority, wrapping.
    static func cyclePriority(_ draft: inout CadenceScheduleDraft) {
        guard draft.kind == .task else { return }
        let all = TaskPriority.allCases
        let index = all.firstIndex(of: draft.priority) ?? 0
        draft.priority = all[(index + 1) % all.count]
    }

    /// A task's one day: start and end together, as the card's own Do grid writes it. A task with
    /// no do date stays untimed (`clearDoDate` left it all-day); one with a time keeps it.
    private static func setDoDate(_ draft: inout CadenceScheduleDraft, to key: String) {
        draft.startDateKey = key
        draft.endDateKey = key
    }
}

/// One draft subtask in the New Task sheet, with an identity of its own (T-6452).
///
/// The sheet used to hold `[String]` and key its rows by index, so removing a draft retired the
/// row for the *last* index while its `$titles[index]` binding still read the shrunk array. A
/// draft keyed by its own id removes exactly itself, and the row bound to it goes with it.
struct CreateTaskSubtaskDraft: Identifiable, Equatable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    static func drafts(from titles: [String]) -> [CreateTaskSubtaskDraft] {
        titles.map { CreateTaskSubtaskDraft(title: $0) }
    }

    /// What the save path hands `TaskCreationDraft.subtaskTitles` — the titles in row order,
    /// unchanged, exactly as the `[String]` state was handed over before.
    static func titles(of drafts: [CreateTaskSubtaskDraft]) -> [String] {
        drafts.map(\.title)
    }

    /// The drafts and the focused row after Return in the row `after`, or the Add Subtask button
    /// when `after` is `nil` ([[T-10040]]).
    ///
    /// Return used to append a fresh empty row every time, wherever it was pressed: a second
    /// Return on the row it had just made stacked a second blank "Subtask" row, then a third, and
    /// Return in the middle of the list put the new row at the bottom. The inspector's own
    /// "Add subtask" field never did either -- a blank Return there adds nothing. So:
    ///
    /// - Return on a blank row adds nothing and leaves the caret where it is.
    /// - Return on a filled row moves to the blank row straight after it if there is one, and
    ///   otherwise opens a new one directly below it, not at the end.
    /// - The button reuses a blank last row rather than stacking another under it.
    static func addingDraft(
        after id: CreateTaskSubtaskDraft.ID?,
        in drafts: [CreateTaskSubtaskDraft]
    ) -> (drafts: [CreateTaskSubtaskDraft], focus: CreateTaskSubtaskDraft.ID?) {
        let isBlank: (CreateTaskSubtaskDraft) -> Bool = { CadenceTitleNormalization.isBlank($0.title) }
        let insertionIndex: Int
        if let id, let index = drafts.firstIndex(where: { $0.id == id }) {
            if isBlank(drafts[index]) { return (drafts, id) }
            insertionIndex = index + 1
            if insertionIndex < drafts.count, isBlank(drafts[insertionIndex]) {
                return (drafts, drafts[insertionIndex].id)
            }
        } else {
            if let last = drafts.last, isBlank(last) { return (drafts, last.id) }
            insertionIndex = drafts.count
        }
        let draft = CreateTaskSubtaskDraft(title: "")
        var next = drafts
        next.insert(draft, at: insertionIndex)
        return (next, draft.id)
    }

    /// The drafts without the one whose x was clicked; every other draft keeps its id and text.
    static func removing(_ id: CreateTaskSubtaskDraft.ID, from drafts: [CreateTaskSubtaskDraft]) -> [CreateTaskSubtaskDraft] {
        drafts.filter { $0.id != id }
    }
}

#endif
