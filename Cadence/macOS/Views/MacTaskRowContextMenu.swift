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
                    CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext)
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
                CadenceTaskDateEditing.scheduleToday(task, in: modelContext)
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }

            Button {
                CadenceTaskDateEditing.scheduleTomorrow(task, in: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskDateEditing.scheduleNextWeek(task, in: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Do Date", systemImage: "sun.max.fill")
        }
    }

    private var dueDateMenu: some View {
        Menu {
            Button {
                CadenceTaskDateEditing.dueToday(task, in: modelContext)
            } label: {
                Label("Today", systemImage: "flag.fill")
            }

            Button {
                CadenceTaskDateEditing.dueTomorrow(task, in: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskDateEditing.dueNextWeek(task, in: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.dueDate.isEmpty {
                Button {
                    CadenceTaskDateEditing.clearDueDate(task, in: modelContext)
                } label: {
                    Label("Clear Due Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Due Date", systemImage: "flag.fill")
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

    private var moveToListMenu: some View {
        Menu {
            Button {
                settle(Self.moveToList(task, area: nil, project: nil, allTasks: allTasks, modelContext: modelContext))
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : "tray.fill")
            }

            if !offerableAreas.isEmpty {
                Divider()

                ForEach(offerableAreas) { area in
                    Button {
                        settle(Self.moveToList(task, area: area, project: nil, allTasks: allTasks, modelContext: modelContext))
                    } label: {
                        Label(CadenceAreaPickerSupport.title(for: area), systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : area.icon)
                    }
                }
            }

            if !offerableProjects.isEmpty {
                Divider()

                ForEach(offerableProjects) { project in
                    Button {
                        settle(Self.moveToList(task, area: nil, project: project, allTasks: allTasks, modelContext: modelContext))
                    } label: {
                        Label(CadenceProjectPickerSupport.title(for: project), systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : project.icon)
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
    // shared helper takes one; `duplicate` and `moveToSection` take none.

    /// iOS swallows this one (`_ = try?`), which the save rule permits because `duplicate` commits
    /// through `commitInsert`; but a refused duplicate then looks exactly like a menu that did
    /// nothing. Here the refusal is named, as every other write in this menu that can refuse is.
    static func duplicate(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) -> ActionOutcome {
        do {
            _ = try CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext)
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

    /// The shared helper's own `try? save()` is an in-place field edit the save rule permits, and
    /// it reports nothing, so there is nothing here to refuse.
    static func moveSection(_ section: String, task: AppTask, modelContext: ModelContext) -> ActionOutcome {
        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext)
        return .settled
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
/// so a refusal reads the same on both platforms; `duplicate` has no iOS title because iOS does
/// not report it.
enum MacTaskRowMenuFailure: Equatable {
    case move
    case recurrence(String)
    case duplicate

    var title: String {
        switch self {
        case .move: CadenceTaskMutationSupport.moveFailureAlertTitle
        case .recurrence: CadenceTaskMutationSupport.recurrenceFailureAlertTitle
        case .duplicate: "Couldn't Duplicate Task"
        }
    }

    var message: String {
        switch self {
        case .move, .duplicate: CadenceTaskFieldEditCommit.saveFailureNotice
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

    /// `iOSTaskRowRecurrenceScopeDialogModifier.applyPendingRecurrenceRule`'s unit, on the Mac: the
    /// series is fetched only for "this and future", a failed fetch is not quietly downgraded to a
    /// one-occurrence edit, and the commit's undo reaches every occurrence the edit wrote.
    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let rule = pendingRecurrenceRule else { return }
        pendingRecurrenceRule = nil

        var allTasks: [AppTask] = []
        if scope == .thisAndFuture {
            do {
                allTasks = try modelContext.fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
            } catch {
                failure = .recurrence(CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice)
                return
            }
        }

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
        let landed = CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        if !landed {
            failure = .recurrence(CadencePendingChangePersistence.editFailureNotice)
        }
    }
}
#endif
