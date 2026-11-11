#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Edit Area Sheet

struct EditAreaSheet: View {
    @Bindable var area: Area
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Context.order) private var contexts: [Context]

    @State private var selectedContextID: UUID?
    @State private var name: String
    /// `Area.desc`. Loaded and saved raw, the way iOS's list editor does it — see `applyEdits()`.
    @State private var details: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var selectedCalendarID: String
    @State private var hideDueDateIfEmpty: Bool
    @State private var hideSectionDueDateIfEmpty: Bool
    @State private var showDeleteConfirmation = false
    /// Set when the delete failed. The sheet stays open holding it — see `deleteArea()`.
    @State private var deleteFailureNotice: String?
    /// Set when the *save* failed, which is a different event with the same rule: the sheet stays
    /// open, and nothing was changed. See `saveEdits()`.
    @State private var saveFailureNotice: String?

    init(area: Area) {
        self.area = area
        _selectedContextID = State(initialValue: area.context?.id)
        _name = State(initialValue: area.name)
        _details = State(initialValue: area.desc)
        _selectedColor = State(initialValue: area.colorHex)
        _selectedIcon = State(initialValue: area.icon)
        _selectedCalendarID = State(initialValue: area.linkedCalendarID)
        _hideDueDateIfEmpty = State(initialValue: area.hideDueDateIfEmpty)
        _hideSectionDueDateIfEmpty = State(initialValue: area.hideSectionDueDateIfEmpty)
    }

    private var statusLabel: String {
        CadenceListEditorFieldSet.statusLabel(area.status)
    }

    /// [[T-8562]]: the shared field list both platforms' editors draw. `.columns` is in it and not
    /// drawn here yet -- see the SHIP-NOTE on T-8562; the board's column popover edits them.
    private var fields: [CadenceListEditorField] {
        CadenceListEditorFieldSet.fields(
            kind: .area,
            isEditing: true,
            isCalendarAccessGranted: calendarManager.isAuthorized
        )
    }

    var body: some View {
        ListEditorSheetShell(
            title: "Edit Area",
            confirmTitle: "Save",
            isConfirmDisabled: !CadenceListEditorFieldSet.acceptsName(name),
            onConfirm: saveEdits
        ) {
            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: CadenceListVocabularyCopy.areaNamePlaceholder,
                details: $details
            )

            TaskInspectorRecessedGroup {
                ListEditorContextRow(contexts: contexts, selectedID: $selectedContextID)
                TaskInspectorFieldDivider()

                if fields.contains(.appleCalendar) {
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        allCalendars: calendarManager.allCalendars,
                        selectedID: $selectedCalendarID
                    )
                    TaskInspectorFieldDivider()
                }

                ListEditorCheckRow(
                    label: CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle,
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle,
                    isOn: $hideSectionDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorStatusRow(
                    noun: "Area",
                    statusLabel: statusLabel,
                    currentChoice: ListEditorLifecycleChoice(area.status),
                    // [[T-11871]]: the row writes the name as Save does, so it is refused on the same test.
                    isDisabled: !CadenceListEditorFieldSet.acceptsName(name),
                    onSelect: apply
                )
            }

            if let deleteFailureNotice {
                CadenceInlineFailureNotice(text: deleteFailureNotice)
            }

            if let saveFailureNotice {
                CadenceInlineFailureNotice(text: saveFailureNotice)
            }
        } footerLeading: {
            ListEditorArchiveButton(
                isArchived: area.isArchived,
                noun: "Area",
                isDisabled: !CadenceListEditorFieldSet.acceptsName(name)
            ) {
                apply(area.isArchived ? .active : .archived)
            }
            ListEditorDeleteButton(title: "Delete") { showDeleteConfirmation = true }
        }
        .accessibilityIdentifier("edit.area.sheet")
        .confirmationDialog(
            "Delete Area?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Area", role: .destructive) { deleteArea() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CadenceListDeletionKind.area.cascadeSentence)
        }
    }

    /// `details` is assigned raw. iOS writes `area.desc = details` with no trim at all, so the two
    /// platforms round-trip a description byte for byte; T-332's `.whitespaces` /
    /// `.whitespacesAndNewlines` split is about the *name* fields and is left alone here.
    private func applyEdits() {
        // **T-559.** Moving the list has to move its tasks. `AppTask.context` is a denormalized
        // copy of the list's, and SwiftData does not re-point copies, so an area that changes
        // owner without this leaves every task in it *in* the list and *out* of the context. That
        // is T-293, which iOS's editor already had to fix; giving this sheet a context control
        // without the re-point would have shipped the same bug a second time.
        //
        // Guarded on an actual change because the reassignment writes every task the area owns —
        // including, by `inheritedContextTargets`, those of child projects with no context of
        // their own — and an ordinary rename has no business dirtying them.
        let contextChanged = area.context?.id != selectedContextID
        // [[T-16401]]: a moved area goes to the end of its new section, numbered there.
        CadenceSidebarLists.refile(area, into: selectedContext)
        if contextChanged {
            CadenceTaskMutationSupport.reassignInheritedContext(area: area)
        }
        area.name = CadenceTitleNormalization.normalized(name)
        area.desc = details
        area.colorHex = selectedColor
        area.icon = selectedIcon
        // **T-624.** Before the assignment, because the comparison is the point: a *changed*
        // selection came from a menu of live calendars, so this Mac has just seen that identifier,
        // and recording it is what lets `CadenceCalendarLinkHealth` later vouch the calendar is
        // gone rather than merely unknown here. An unchanged one may be another device's, and
        // recording it would hand this Mac evidence it does not have. Settings has its own refresh;
        // a list linked only from this sheet would otherwise never reach it.
        CadenceCalendarLinkObservations.recordPick(selectedCalendarID, replacing: area.linkedCalendarID)
        area.linkedCalendarID = selectedCalendarID
        area.hideDueDateIfEmpty = hideDueDateIfEmpty
        area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
    }

    /// The Save button (T-321).
    ///
    /// It used to write the fields and dismiss with no commit at all, so the sheet closed without
    /// anyone — the sheet included — knowing whether the edit had reached the store. The
    /// dismissal *is* the report of success here, exactly as it is for `deleteArea()` below, so it
    /// has to sit under a commit that can fail.
    ///
    /// The undo is a field snapshot, never `modelContext.rollback()` — `CadenceListEditSnapshot`
    /// holds the measurement that rules the rollback out. The only tasks it carries are the ones a
    /// *changed* context re-points (T-559); on every other save `contextChangeTargets` is empty,
    /// because `applyEdits()` then writes the area's own fields and nothing else.
    private func saveEdits() {
        guard CadenceListEditorFieldSet.acceptsName(name) else { return }
        let undo = CadenceListEditSnapshot(area, tasks: contextChangeTargets)
        applyEdits()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    /// A lifecycle change still closes the sheet, so the pending field edits are written first
    /// rather than thrown away by the dismissal.
    private func apply(_ choice: ListEditorLifecycleChoice) {
        // [[T-11871]]: behind the disabled row and button, as `saveEdits()` is behind Save.
        guard CadenceListEditorFieldSet.acceptsName(name) else { return }
        // The settle below writes every task still open in the area, so the snapshot is handed the
        // same set the service is about to walk rather than guessing at it.
        let undo = CadenceListEditSnapshot(
            area,
            tasks: TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
                + contextChangeTargets
        )
        applyEdits()
        switch choice {
        case .active: CadenceSidebarLists.reopen(area)
        case .completed: area.status = .done
        case .archived: area.status = .archived
        }
        // One call, and which way it settles is `choice.windDownOutcome` — a tested value, not a
        // branch spelled out here. See that property for what the two hand-written branches cost.
        if let outcome = choice.windDownOutcome {
            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                outcome: outcome,
                in: modelContext
            )
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    private var selectedContext: Context? {
        guard let selectedContextID else { return nil }
        return contexts.first { $0.id == selectedContextID }
    }

    /// The tasks `applyEdits()` is about to re-point, or none when the context has not moved.
    ///
    /// Empty on an ordinary save, deliberately: snapshotting every task in a list costs a
    /// `CadenceTaskFieldSnapshot` each, and a save that does not touch them has nothing to put
    /// back. `apply(_:)` concatenates this with the set it settles and the two overlap; that is
    /// fine, and `CadenceListEditSnapshot` says why.
    private var contextChangeTargets: [AppTask] {
        guard area.context?.id != selectedContextID else { return [] }
        return CadenceTaskMutationSupport.inheritedContextTargets(area: area)
    }

    /// T-291: the cascade's `false` and a refused save were both being saved over and dismissed
    /// through, so a delete that did not happen closed the sheet and reported nothing. Now the
    /// dismissal *is* the report of success, and a failure keeps the sheet on screen holding the
    /// same sentence iOS's confirmation shows.
    private func deleteArea() {
        do {
            try CadencePendingChangePersistence.commitCascade(in: modelContext) {
                modelContext.deleteArea(area)
            }
        } catch {
            deleteFailureNotice = CadenceListDeletionKind.area.deleteFailureNotice
            return
        }
        deleteFailureNotice = nil
        dismiss()
    }
}

// MARK: - Edit Project Sheet

struct EditProjectSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]

    @State private var selectedContextID: UUID?
    /// [[T-10180]]: the parent area, which iOS's editor could set and this sheet could not.
    @State private var selectedAreaID: UUID?
    @State private var name: String
    /// `Project.desc`. Loaded and saved raw — same rule as `EditAreaSheet`.
    @State private var details: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    /// [[T-9804]]: the due date as `applyEdits()` stores it, "" for none -- whether the project is
    /// dated is this alone. `dueDate` is only where the picker opens. See `ListEditorDueDateRow`.
    @State private var dueDateKey: String
    @State private var dueDate: Date
    @State private var selectedCalendarID: String
    @State private var hideDueDateIfEmpty: Bool
    @State private var hideSectionDueDateIfEmpty: Bool
    @State private var showDeleteConfirmation = false
    /// Same contract as `EditAreaSheet`'s — see `deleteProject()`.
    @State private var deleteFailureNotice: String?
    /// Same contract as `EditAreaSheet`'s — see `saveEdits()`.
    @State private var saveFailureNotice: String?

    init(project: Project) {
        self.project = project
        _selectedContextID = State(initialValue: project.context?.id)
        _selectedAreaID = State(initialValue: project.area?.id)
        _name = State(initialValue: project.name)
        _details = State(initialValue: project.desc)
        _selectedColor = State(initialValue: project.colorHex)
        _selectedIcon = State(initialValue: project.icon)
        _selectedCalendarID = State(initialValue: project.linkedCalendarID)
        _hideDueDateIfEmpty = State(initialValue: project.hideDueDateIfEmpty)
        _hideSectionDueDateIfEmpty = State(initialValue: project.hideSectionDueDateIfEmpty)
        if !project.dueDate.isEmpty, let d = DateFormatters.date(from: project.dueDate) {
            _dueDateKey = State(initialValue: DateFormatters.dateKey(from: d))
            _dueDate = State(initialValue: d)
        } else {
            _dueDateKey = State(initialValue: "")
            _dueDate = State(initialValue: Date())
        }
    }

    /// Projects can also be paused or cancelled, so the row reports the stored status instead of
    /// assuming it is one of the three the picker offers.
    private var statusLabel: String {
        CadenceListEditorFieldSet.statusLabel(project.status)
    }

    /// [[T-8562]]: same shared field list as `EditAreaSheet.fields`.
    private var fields: [CadenceListEditorField] {
        CadenceListEditorFieldSet.fields(
            kind: .project,
            isEditing: true,
            isCalendarAccessGranted: calendarManager.isAuthorized
        )
    }

    var body: some View {
        ListEditorSheetShell(
            title: "Edit Project",
            confirmTitle: "Save",
            isConfirmDisabled: !CadenceListEditorFieldSet.acceptsName(name),
            onConfirm: saveEdits
        ) {
            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: CadenceListVocabularyCopy.projectNamePlaceholder,
                details: $details
            )

            TaskInspectorRecessedGroup {
                ListEditorContextRow(contexts: contexts, selectedID: $selectedContextID)
                TaskInspectorFieldDivider()

                ListEditorAreaRow(areas: areas, selectedID: $selectedAreaID)
                TaskInspectorFieldDivider()

                ListEditorDueDateRow(dueDateKey: $dueDateKey, seed: $dueDate)

                if fields.contains(.appleCalendar) {
                    TaskInspectorFieldDivider()
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        allCalendars: calendarManager.allCalendars,
                        selectedID: $selectedCalendarID
                    )
                }

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle,
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle,
                    isOn: $hideSectionDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorStatusRow(
                    noun: "Project",
                    statusLabel: statusLabel,
                    currentChoice: ListEditorLifecycleChoice(project.status),
                    // [[T-11871]]: the row writes the name as Save does, so it is refused on the same test.
                    isDisabled: !CadenceListEditorFieldSet.acceptsName(name),
                    onSelect: apply
                )
            }

            if let deleteFailureNotice {
                CadenceInlineFailureNotice(text: deleteFailureNotice)
            }

            if let saveFailureNotice {
                CadenceInlineFailureNotice(text: saveFailureNotice)
            }
        } footerLeading: {
            ListEditorArchiveButton(
                isArchived: project.isArchived,
                noun: "Project",
                isDisabled: !CadenceListEditorFieldSet.acceptsName(name)
            ) {
                apply(project.isArchived ? .active : .archived)
            }
            ListEditorDeleteButton(title: "Delete") { showDeleteConfirmation = true }
        }
        .accessibilityIdentifier("edit.project.sheet")
        .confirmationDialog(
            "Delete Project?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) { deleteProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CadenceListDeletionKind.project.cascadeSentence)
        }
    }

    /// Same rule as `EditAreaSheet.applyEdits()`, same reason (T-559/T-293). A project reads its
    /// context through `resolvedContext` — its own if set, otherwise its area's — so clearing this
    /// row does not orphan its tasks, it hands them back to the area's context. There is no cascade
    /// on this branch: nothing inherits from a project.
    ///
    /// [[T-10180]]: the area is written beside the context, by `applyOwnership`, because a project
    /// with no context of its own reads its area's — so a moved area re-points its tasks exactly as
    /// a moved context does.
    private func applyEdits() {
        Self.applyOwnership(to: project, context: selectedContext, area: selectedArea)
        project.name = CadenceTitleNormalization.normalized(name)
        project.desc = details
        project.colorHex = selectedColor
        project.icon = selectedIcon
        project.dueDate = dueDateKey
        // **T-624**, as in `EditAreaSheet.applyEdits()` above — before the assignment, so the
        // comparison still has the stored value to compare against.
        CadenceCalendarLinkObservations.recordPick(selectedCalendarID, replacing: project.linkedCalendarID)
        project.linkedCalendarID = selectedCalendarID
        project.hideDueDateIfEmpty = hideDueDateIfEmpty
        project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
    }


    /// Same as `EditAreaSheet.saveEdits()`, same reason. The project's due date is one of the
    /// fields `applyEdits()` writes, and the snapshot holds it for the same reason it holds the
    /// rest.
    private func saveEdits() {
        guard CadenceListEditorFieldSet.acceptsName(name) else { return }
        let undo = CadenceListEditSnapshot(project, tasks: contextChangeTargets)
        applyEdits()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    private func apply(_ choice: ListEditorLifecycleChoice) {
        // [[T-11871]]: behind the disabled row and button, as `saveEdits()` is behind Save.
        guard CadenceListEditorFieldSet.acceptsName(name) else { return }
        // Same set the settle walks, for the same reason as `EditAreaSheet.apply(_:)`.
        let undo = CadenceListEditSnapshot(
            project,
            tasks: TaskContainerLifecycleService.remainingActiveTasks(in: project) + contextChangeTargets
        )
        applyEdits()
        switch choice {
        case .active: CadenceSidebarLists.reopen(project)
        case .completed: project.status = .done
        case .archived: project.status = .archived
        }
        // Same one call as `EditAreaSheet`, same reason.
        if let outcome = choice.windDownOutcome {
            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: project,
                outcome: outcome,
                in: modelContext
            )
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    private var selectedContext: Context? {
        guard let selectedContextID else { return nil }
        return contexts.first { $0.id == selectedContextID }
    }

    private var selectedArea: Area? {
        guard let selectedAreaID else { return nil }
        return areas.first { $0.id == selectedAreaID }
    }

    /// Same contract as `EditAreaSheet.contextChangeTargets`, widened to a moved area
    /// ([[T-10180]]) — the tasks `applyOwnership` re-points when either one moves.
    private var contextChangeTargets: [AppTask] {
        guard Self.ownershipChanged(project, contextID: selectedContextID, areaID: selectedAreaID) else {
            return []
        }
        return CadenceTaskMutationSupport.inheritedContextTargets(project: project)
    }

    /// Same as `EditAreaSheet.deleteArea()`, same reason.
    private func deleteProject() {
        do {
            try CadencePendingChangePersistence.commitCascade(in: modelContext) {
                modelContext.deleteProject(project)
            }
        } catch {
            deleteFailureNotice = CadenceListDeletionKind.project.deleteFailureNotice
            return
        }
        deleteFailureNotice = nil
        dismiss()
    }
}

// MARK: - Project ownership (T-10180)

extension EditProjectSheet {
    /// Whether the sheet's context or area differs from the project's — the condition under which
    /// its tasks' denormalized `context` has to be re-derived.
    static func ownershipChanged(_ project: Project, contextID: UUID?, areaID: UUID?) -> Bool {
        project.context?.id != contextID || project.area?.id != areaID
    }

    /// Writes the project's context and parent area, as iOS's editor writes them
    /// (`project.context = selectedContext; project.area = selectedArea`), and re-points its
    /// tasks when either moved. `CadenceListEditSnapshot` already holds `project.area`, so a
    /// refused commit puts the area back with everything else.
    static func applyOwnership(to project: Project, context: Context?, area: Area?) {
        let changed = ownershipChanged(project, contextID: context?.id, areaID: area?.id)
        // [[T-16401]]: a project moved to another context goes to the end of its new section.
        CadenceSidebarLists.refile(project, into: context)
        project.area = area
        if changed {
            CadenceTaskMutationSupport.reassignInheritedContext(project: project)
        }
    }
}

#endif
