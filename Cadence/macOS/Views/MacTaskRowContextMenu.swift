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

        Button(action: duplicate) {
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
                    selectRecurrenceRule(recurrence)
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
                        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext)
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
                moveToContainer(area: nil, project: nil)
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : "tray.fill")
            }

            if !offerableAreas.isEmpty {
                Divider()

                ForEach(offerableAreas) { area in
                    Button {
                        moveToContainer(area: area, project: nil)
                    } label: {
                        Label(CadenceAreaPickerSupport.title(for: area), systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : area.icon)
                    }
                }
            }

            if !offerableProjects.isEmpty {
                Divider()

                ForEach(offerableProjects) { project in
                    Button {
                        moveToContainer(area: nil, project: project)
                    } label: {
                        Label(CadenceProjectPickerSupport.title(for: project), systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : project.icon)
                    }
                }
            }
        } label: {
            Label("Move to List", systemImage: "folder.fill")
        }
    }

    /// iOS swallows this one (`_ = try?`), which the save rule permits because `duplicate` commits
    /// through `commitInsert`; but a refused duplicate then looks exactly like a menu that did
    /// nothing. Here the refusal is named, as every other write in this menu that can refuse is.
    private func duplicate() {
        do {
            _ = try CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext)
        } catch {
            failure = .duplicate
        }
    }

    /// The same three-way answer `iOSTaskRecurrenceSelection.select` gives: unchanged, parked for
    /// the scope dialog (a series member must say "this one" or "this and future" first), or
    /// committed — and a refused commit is reported, not dropped (T-761(c)).
    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        guard !task.isRecurrenceSeriesMember else {
            pendingRecurrenceRule = rule
            return
        }
        let landed = CadenceTaskFieldEditCommit.commit(task, in: modelContext) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
        }
        if !landed {
            failure = .recurrence(CadenceTaskFieldEditCommit.saveFailureNotice)
        }
    }

    /// T-702's shape: the checkmarks read the task, so they self-correct on the restore; what the
    /// closed menu cannot do is say so, which is the row's alert.
    private func moveToContainer(area: Area?, project: Project?) {
        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        ) else {
            failure = .move
            return
        }
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
