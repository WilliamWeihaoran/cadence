#if os(macOS)
import SwiftUI
import SwiftData

/// **The Mac task row's right-click menu ([[T-1479]]), built from iOS's long-press menu.**
///
/// `MacTaskRow`'s right-click used to run the identical closure as its tap — it opened the
/// inspector — so the gesture macOS reserves for a menu was spent on a duplicate. The owner kept
/// single click on the inspector and gave right-click this menu, so nothing anyone already does
/// changes.
///
/// **Same actions, same words, same order as `iOSTaskRowContextMenu`** (Edit, Focus, Priority,
/// Repeat, Do Date, Due Date, Move Section, Move to List, Duplicate, Delete Task), and every
/// mutation goes through the shared helper the iOS menu calls — `CadenceTaskMutationSupport`,
/// `CadenceTaskDateEditing`, `CadenceTaskRecurrenceWorkflowSupport`, `CadenceTaskComposerSupport`'s
/// pickable lists. A divergence in vocabulary here would be a new parity finding in the place
/// PA-05 just closed, and `MacTaskRowContextMenuParityTests` holds the two label sets equal.
///
/// Three items act through the Mac's own existing path rather than iOS's, because the platforms
/// already answer them differently and this menu is a new door onto the Mac answer, not a second
/// one: **Edit** opens the row's inspector popover; **Focus** is the row's hover ▶
/// (`FocusManager.startFocus`) rather than `CadenceFocusHandoffCenter`, which is iOS's tab-switch
/// handoff; **Delete Task** is `DeleteConfirmationManager`'s refusable overlay rather than an
/// alert.
///
/// The `@Query`s live here, not on the row, for the reason `iOSTaskRowContextMenu` gives: this view
/// is the menu's content, and the row exists once per visible task.
struct MacTaskRowContextMenu: View {
    let task: AppTask
    let openDetail: () -> Void
    let startFocus: () -> Void
    let requestDelete: () -> Void
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    /// A menu closes itself on the click and has nowhere to say a write was refused, so a refusal
    /// is handed back to the row, which raises `MacTaskRowMenuOutcomeModifier`'s alert.
    @Binding var failure: MacTaskRowMenuFailure?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private var offerableAreas: [Area] {
        CadenceTaskComposerSupport.pickableAreas(areas, selectedID: task.area?.id)
    }

    private var offerableProjects: [Project] {
        CadenceTaskComposerSupport.pickableProjects(projects, selectedID: task.project?.id)
    }

    private var availableSectionNames: [String] {
        let rawNames = task.area?.sectionNames ?? task.project?.sectionNames ?? []
        let names = rawNames.isEmpty ? [TaskSectionDefaults.defaultName] : rawNames
        if names.contains(where: { $0.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame }) {
            return names
        }
        return names + [task.resolvedSectionName]
    }

    var body: some View {
        Button(action: openDetail) {
            Label("Edit", systemImage: "square.and.pencil")
        }

        focusMenuItem

        priorityMenu
        recurrenceMenu
        doDateMenu
        dueDateMenu
        sectionMenu
        moveToListMenu

        Button {
            settle(Self.duplicate(task, allTasks: allTasks, modelContext: modelContext))
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(role: .destructive, action: requestDelete) {
            Label("Delete Task", systemImage: "trash")
        }
        .cadenceDestructiveMenuRow()
    }

    /// Absent on a settled task, not disabled — the predicate the row's ▶ and iOS's entry share
    /// (T-276).
    @ViewBuilder
    private var focusMenuItem: some View {
        if CadenceFocusSupport.canFocus(task) {
            Button(action: startFocus) {
                Label("Focus", systemImage: CadenceFeatureDestination.focus.systemImage)
            }
        }
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    settle(Self.setPriority(priority, for: task, modelContext: modelContext))
                } label: {
                    Label(priority.label, systemImage: priority == task.priority ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label("Priority: \(task.priority.label)", systemImage: "flag.fill")
        }
    }

    private var recurrenceMenu: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { recurrence in
                Button {
                    settle(Self.selectRecurrenceRule(recurrence, for: task, allTasks: allTasks, modelContext: modelContext))
                } label: {
                    Label(
                        recurrence.label,
                        systemImage: recurrence == task.recurrenceRule ? "checkmark.circle.fill" : recurrence.systemImage
                    )
                }
            }
        } label: {
            Label(task.recurrenceRule == .none ? "Repeat" : "Repeat: \(task.recurrenceRule.label)", systemImage: "repeat")
        }
    }

    private var doDateMenu: some View {
        Menu {
            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.scheduleToday(task, in: modelContext)))
            } label: {
                Label("Today", systemImage: CadenceTaskDateMenuLabel.glyph(.today, dateKey: task.scheduledDate, otherwise: "sun.max.fill"))
            }

            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.scheduleTomorrow(task, in: modelContext)))
            } label: {
                Label("Tomorrow", systemImage: CadenceTaskDateMenuLabel.glyph(.tomorrow, dateKey: task.scheduledDate, otherwise: "calendar"))
            }

            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.scheduleNextWeek(task, in: modelContext)))
            } label: {
                Label("Next Week", systemImage: CadenceTaskDateMenuLabel.glyph(.nextWeek, dateKey: task.scheduledDate, otherwise: "calendar.badge.clock"))
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    settle(Self.dateOutcome(CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)))
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label(CadenceTaskDateMenuLabel.title("Do Date", dateKey: task.scheduledDate), systemImage: "sun.max.fill")
        }
    }

    private var dueDateMenu: some View {
        Menu {
            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.dueToday(task, in: modelContext)))
            } label: {
                Label("Today", systemImage: CadenceTaskDateMenuLabel.glyph(.today, dateKey: task.dueDate, otherwise: "flag.fill"))
            }

            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.dueTomorrow(task, in: modelContext)))
            } label: {
                Label("Tomorrow", systemImage: CadenceTaskDateMenuLabel.glyph(.tomorrow, dateKey: task.dueDate, otherwise: "calendar"))
            }

            Button {
                settle(Self.dateOutcome(CadenceTaskDateEditing.dueNextWeek(task, in: modelContext)))
            } label: {
                Label("Next Week", systemImage: CadenceTaskDateMenuLabel.glyph(.nextWeek, dateKey: task.dueDate, otherwise: "calendar.badge.clock"))
            }

            if !task.dueDate.isEmpty {
                Button {
                    settle(Self.dateOutcome(CadenceTaskDateEditing.clearDueDate(task, in: modelContext)))
                } label: {
                    Label("Clear Due Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label(CadenceTaskDateMenuLabel.title("Due Date", dateKey: task.dueDate), systemImage: "flag.fill")
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        let names = availableSectionNames
        if names.count > 1 {
            Menu {
                ForEach(names, id: \.self) { section in
                    Button {
                        settle(Self.moveSection(section, task: task, modelContext: modelContext))
                    } label: {
                        Label(section, systemImage: section.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame ? "checkmark.circle.fill" : "rectangle.split.3x1")
                    }
                }
            } label: {
                Label("Move Section", systemImage: "rectangle.split.3x1.fill")
            }
        }
    }

    /// Rows read `CadenceListKindIcon`, never the list's own `icon` ([[T-10102]]).
    ///
    /// [[T-8553]]'s unification reached six chooser paths and not this one, so until now an area
    /// whose user-chosen glyph was an iPhone drew an iPhone here and a folder in every other
    /// chooser. The owner refused exactly that. The per-list COLOUR is a separate vocabulary and
    /// still shows through; only the glyph is canonical. The selected row keeps its checkmark.
    private var moveToListMenu: some View {
        Menu {
            Button {
                settle(Self.moveToList(task, area: nil, project: nil, allTasks: allTasks, modelContext: modelContext))
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : CadenceListKindIcon.inbox)
            }

            if !offerableAreas.isEmpty {
                Divider()

                ForEach(offerableAreas) { area in
                    Button {
                        settle(Self.moveToList(task, area: area, project: nil, allTasks: allTasks, modelContext: modelContext))
                    } label: {
                        Label(CadenceAreaPickerSupport.title(for: area), systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : CadenceListKindIcon.area)
                    }
                }
            }

            if !offerableProjects.isEmpty {
                Divider()

                ForEach(offerableProjects) { project in
                    Button {
                        settle(Self.moveToList(task, area: nil, project: project, allTasks: allTasks, modelContext: modelContext))
                    } label: {
                        Label(CadenceProjectPickerSupport.title(for: project), systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : CadenceListKindIcon.project)
                    }
                }
            }
        } label: {
            Label("Move to List", systemImage: "folder.fill")
        }
    }

    /// What one of the four testable actions left for the row to do. The menu has closed by the
    /// time an action returns, so anything it cannot say itself goes back through the two bindings.
    enum ActionOutcome: Equatable {
        /// Written, or nothing to write (the rule already chosen).
        case settled
        /// A series member must answer "this one" or "this and future" first.
        case needsRecurrenceScope(TaskRecurrenceRule)
        case refused(MacTaskRowMenuFailure)
    }

    private func settle(_ outcome: ActionOutcome) {
        switch outcome {
        case .settled: break
        case .needsRecurrenceScope(let rule): pendingRecurrenceRule = rule
        case .refused(let refusal): failure = refusal
        }
    }

    // [[T-3210]] The four actions below are `static` so a test can invoke each one against an
    // in-memory store and read the model back -- the menu itself is SwiftUI and cannot be
    // presented from a unit test. They stay inside this struct so the parity reader in
    // `MacTaskRowContextMenuParityTests` still sees every shared call in the menu's body.
    // `MacTaskRowContextMenuEffectTests` holds them by effect. `commit:` is threaded wherever the
    // shared helper takes one -- `duplicate` too since [[T-13843]] gave the helper one. [[T-11614]]
    // added `setPriority` and gave `moveSection` a `commit:`; the date submenus answer through
    // `dateOutcome`.

    /// A refused duplicate would otherwise look exactly like a menu that did nothing, so the
    /// refusal is named, as every other write in this menu that can refuse is. iOS names it too
    /// since [[T-13843]] (`iOSTaskRowContextMenu.duplicate`).
    static func duplicate(
        _ task: AppTask,
        allTasks: [AppTask],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        do {
            _ = try CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext, commit: commit)
        } catch {
            return .refused(.duplicate)
        }
        return .settled
    }

    /// The same three-way answer `iOSTaskRecurrenceSelection.select` gives: unchanged, parked for
    /// the scope dialog (a series member must say "this one" or "this and future" first), or
    /// committed — and a refused commit is reported, not dropped (T-761(c)).
    static func selectRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        for task: AppTask,
        allTasks: [AppTask],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        guard task.recurrenceRule != rule else { return .settled }
        guard !task.isRecurrenceSeriesMember else { return .needsRecurrenceScope(rule) }
        let landed = CadenceTaskFieldEditCommit.commit(task, in: modelContext, commit: commit) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
        }
        return landed ? .settled : .refused(.recurrence(CadenceTaskFieldEditCommit.saveFailureNotice))
    }

    /// The second half of `selectRecurrenceRule`: a series member's rule, once the scope dialog has
    /// been answered. `iOSTaskRowRecurrenceScopeDialogModifier.applyPendingRecurrenceRule`'s unit,
    /// on the Mac: the series is fetched only for "this and future", a failed fetch is not quietly
    /// downgraded to a one-occurrence edit, and the commit's undo reaches every occurrence the edit
    /// wrote. `static` and shared for the reason `selectRecurrenceRule` is: the row's dialog and
    /// the note embed card's dialog are two places to answer the scope question, and [[T-9122]]
    /// found them answering it through two writers.
    static func applyRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        scope: CadenceTaskRecurrenceEditScope,
        for task: AppTask,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        var allTasks: [AppTask] = []
        if scope == .thisAndFuture {
            do {
                allTasks = try modelContext.fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
            } catch {
                return .refused(.recurrence(CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice))
            }
        }

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
        let landed = CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext, commit: commit) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        return landed ? .settled : .refused(.recurrence(CadencePendingChangePersistence.editFailureNotice))
    }

    /// **[[T-11614]] (G4).** This used to say there was "nothing here to refuse", because the
    /// shared helper swallowed its save. It does not any more: the row moves under another heading
    /// and the menu has closed, so a refused move is undone by the helper and named here, as
    /// Move to List names one.
    static func moveSection(
        _ section: String,
        task: AppTask,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext, commit: commit)
            ? .settled : .refused(.move)
    }

    /// **[[T-11614]] (G4).** The Priority submenu, the next item down from Repeat, which already
    /// reported. A refusal puts the old priority back; the checkmarks read the task, so they agree.
    static func setPriority(
        _ priority: TaskPriority,
        for task: AppTask,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext, commit: commit)
            ? .settled : .refused(.priority)
    }

    /// **[[T-11614]] (G2).** The Do Date and Due Date submenus' answer. Each item calls
    /// `CadenceTaskDateEditing` directly, so the parity reader still sees the same shared calls as
    /// iOS's menu; this only turns the `Bool` into the row's alert.
    static func dateOutcome(_ landed: Bool) -> ActionOutcome {
        landed ? .settled : .refused(.date)
    }

    /// T-702's shape: the checkmarks read the task, so they self-correct on the restore; what the
    /// closed menu cannot do is say so, which is the row's alert.
    static func moveToList(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        allTasks: [AppTask],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext,
            commit: commit
        ) else {
            return .refused(.move)
        }
        return .settled
    }
}

/// Not a menu action, so outside the menu's struct: `MacTaskRowContextMenuParityTests` compares
/// what the menu itself calls with iOS's menu, and these entry points belong to the pickers.
extension MacTaskRowContextMenu {
    /// **T-5353.** The same move, asked by a picker that speaks `TaskContainerSelection` — the
    /// row's list chip. It wrote `area`/`project`/`context`/`sectionName` inline, never touched
    /// `order` and left the commit to autosave, so a task landed wherever its old list's order
    /// number fell in the new one. Routed here it moves the way the context menu does: end of the
    /// new list, one commit, a refusal put back and reported. A selection naming a list that is
    /// gone, or the list the task is already in, moves nothing. (The inspector is not a caller: since
    /// T-4108 it moves a task through the shared panel's draft commit, `CadenceTaskEditDraftCommit`,
    /// which reaches the same `CadenceTaskMutationSupport.assignContainer`.)
    static func moveToList(
        _ task: AppTask,
        selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActionOutcome {
        let area: Area?
        let project: Project?
        switch selection {
        case .inbox:
            (area, project) = (nil, nil)
        case .area(let id):
            guard let target = areas.first(where: { $0.id == id }) else { return .settled }
            (area, project) = (target, nil)
        case .project(let id):
            guard let target = projects.first(where: { $0.id == id }) else { return .settled }
            (area, project) = (nil, target)
        }
        guard !CadenceTaskMutationSupport.isAlreadyInContainer(task, area: area, project: project) else {
            return .settled
        }
        let allTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        return moveToList(task, area: area, project: project, allTasks: allTasks, modelContext: modelContext, commit: commit)
    }
}

/// What a closed menu could not report itself. Titles are the shared ones iOS's row alerts carry,
/// so a refusal reads the same on both platforms.
enum MacTaskRowMenuFailure: Equatable {
    case move
    case recurrence(String)
    case duplicate
    /// [[T-11614]]: a Do Date / Due Date submenu item. Titled as iOS titles it.
    case date
    /// [[T-11614]]: the Priority submenu. Titled as iOS titles it.
    case priority

    var title: String {
        switch self {
        case .move: CadenceTaskMutationSupport.moveFailureAlertTitle
        case .recurrence: CadenceTaskMutationSupport.recurrenceFailureAlertTitle
        case .duplicate: CadenceTaskMutationSupport.duplicateFailureAlertTitle
        case .date: CadenceTaskMutationSupport.dateFailureAlertTitle
        case .priority: CadenceTaskMutationSupport.priorityFailureAlertTitle
        }
    }

    var message: String {
        switch self {
        case .move, .duplicate, .date, .priority: CadenceTaskFieldEditCommit.saveFailureNotice
        case .recurrence(let notice): notice
        }
    }
}

/// The row-side half of the menu: the recurrence scope dialog a series member's repeat change
/// waits on, and the alert a refused menu write raises. Applied to the row rather than inside the
/// menu because the menu is gone by the time either has to show.
struct MacTaskRowMenuOutcomeModifier: ViewModifier {
    let task: AppTask
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Binding var failure: MacTaskRowMenuFailure?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.taskScopeTitle,
                isPresented: Binding(
                    get: { pendingRecurrenceRule != nil },
                    set: { if !$0 { pendingRecurrenceRule = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                    applyPendingRecurrenceRule(scope: .thisTask)
                }
                Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                    applyPendingRecurrenceRule(scope: .thisAndFuture)
                }
                Button("Cancel", role: .cancel) {
                    pendingRecurrenceRule = nil
                }
            } message: {
                Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
            }
            .alert(
                failure?.title ?? "",
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { failure = nil } }
                ),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { failure in
                Text(failure.message)
            }
    }

    /// The scope dialog's answer, written by `MacTaskRowContextMenu.applyRecurrenceRule` -- the
    /// one Mac series writer, shared with the note embed card's Repeat field ([[T-9122]]).
    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let rule = pendingRecurrenceRule else { return }
        pendingRecurrenceRule = nil
        if case .refused(let refusal) = MacTaskRowContextMenu.applyRecurrenceRule(
            rule,
            scope: scope,
            for: task,
            modelContext: modelContext
        ) {
            failure = refusal
        }
    }
}

/// **[[T-10205]] — the task menu for a task surface that is not a row or a board card.**
///
/// [[T-1479]]'s owner ruling is that right-clicking a task on macOS opens this menu, not the
/// inspector, and [[T-8062]] carried it to the board card. The Calendar's Month and all-day task
/// chips and the timeline's task block still answered a right-click with an AppKit
/// `RightClickActionTrigger` that ran the click's own path, so the same task offered its actions on
/// the Tasks page and only its inspector on the calendar. Those surfaces hold none of the menu's
/// after-the-click state, so this modifier holds it for them: the menu's Edit is the host's click
/// path, Focus and Delete Task are `MacTaskRow`'s (`FocusManager.startFocus`, the refusable delete
/// overlay), and the scope dialog and refusal alert are `MacTaskRowMenuOutcomeModifier`.
/// `willDelete` is the host's own teardown, run just before a confirmed delete.
struct MacTaskContextMenuHost: ViewModifier {
    let task: AppTask
    let openDetail: () -> Void
    var willDelete: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(FocusManager.self) private var focusManager
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?
    @State private var menuFailure: MacTaskRowMenuFailure?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                MacTaskRowContextMenu(
                    task: task,
                    openDetail: openDetail,
                    startFocus: startFocus,
                    requestDelete: presentDelete,
                    pendingRecurrenceRule: $pendingRecurrenceRule,
                    failure: $menuFailure
                )
            }
            .modifier(MacTaskRowMenuOutcomeModifier(
                task: task,
                pendingRecurrenceRule: $pendingRecurrenceRule,
                failure: $menuFailure
            ))
    }

    private func startFocus() {
        do {
            try focusManager.startFocus(task: task, in: modelContext)
        } catch {
            TaskCompletionAnimationManager.shared.recordSettleFailure()
        }
    }

    private func presentDelete() {
        deleteConfirmationManager.presentTaskDelete(task, in: modelContext, willDelete: willDelete)
    }
}
#endif
