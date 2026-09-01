#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Edit Area Sheet

struct EditAreaSheet: View {
    @Bindable var area: Area
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

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
        _name = State(initialValue: area.name)
        _details = State(initialValue: area.desc)
        _selectedColor = State(initialValue: area.colorHex)
        _selectedIcon = State(initialValue: area.icon)
        _selectedCalendarID = State(initialValue: area.linkedCalendarID)
        _hideDueDateIfEmpty = State(initialValue: area.hideDueDateIfEmpty)
        _hideSectionDueDateIfEmpty = State(initialValue: area.hideSectionDueDateIfEmpty)
    }

    private var statusLabel: String {
        if area.isDone { return "Completed" }
        if area.isArchived { return "Archived" }
        return "Active"
    }

    var body: some View {
        ListEditorSheetShell(
            title: "Edit Area",
            confirmTitle: "Save",
            isConfirmDisabled: CadenceTitleNormalization.isBlank(name),
            onConfirm: saveEdits
        ) {
            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: "Area name…",
                details: $details
            )

            TaskInspectorRecessedGroup {
                if calendarManager.isAuthorized {
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        allCalendars: calendarManager.allCalendars,
                        selectedID: $selectedCalendarID
                    )
                    TaskInspectorFieldDivider()
                }

                ListEditorCheckRow(
                    label: "Hide empty task due date",
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: "Hide empty column due date",
                    isOn: $hideSectionDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorStatusRow(
                    noun: "Area",
                    statusLabel: statusLabel,
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
            ListEditorArchiveButton(isArchived: area.isArchived, noun: "Area") {
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
    /// holds the measurement that rules the rollback out. No tasks are passed: `applyEdits()`
    /// writes the area's own fields and nothing else.
    private func saveEdits() {
        let undo = CadenceListEditSnapshot(area)
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
        // The settle below writes every task still open in the area, so the snapshot is handed the
        // same set the service is about to walk rather than guessing at it.
        let undo = CadenceListEditSnapshot(
            area,
            tasks: TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
        )
        applyEdits()
        switch choice {
        case .active: area.status = .active
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

    @State private var name: String
    /// `Project.desc`. Loaded and saved raw — same rule as `EditAreaSheet`.
    @State private var details: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
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
        _name = State(initialValue: project.name)
        _details = State(initialValue: project.desc)
        _selectedColor = State(initialValue: project.colorHex)
        _selectedIcon = State(initialValue: project.icon)
        _selectedCalendarID = State(initialValue: project.linkedCalendarID)
        _hideDueDateIfEmpty = State(initialValue: project.hideDueDateIfEmpty)
        _hideSectionDueDateIfEmpty = State(initialValue: project.hideSectionDueDateIfEmpty)
        if !project.dueDate.isEmpty, let d = DateFormatters.date(from: project.dueDate) {
            _hasDueDate = State(initialValue: true)
            _dueDate = State(initialValue: d)
        } else {
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
        }
    }

    /// Projects can also be paused or cancelled, so the row reports the stored status instead of
    /// assuming it is one of the three the picker offers.
    private var statusLabel: String {
        switch project.status {
        case .active:    return "Active"
        case .done:      return "Completed"
        case .archived:  return "Archived"
        case .paused:    return "Paused"
        case .cancelled: return "Cancelled"
        }
    }

    var body: some View {
        ListEditorSheetShell(
            title: "Edit Project",
            confirmTitle: "Save",
            isConfirmDisabled: CadenceTitleNormalization.isBlank(name),
            onConfirm: saveEdits
        ) {
            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: "Project name…",
                details: $details
            )

            TaskInspectorRecessedGroup {
                TaskInspectorDateControl(
                    label: "Due",
                    reservesIconSlot: false,
                    isOn: $hasDueDate,
                    date: $dueDate
                )

                if calendarManager.isAuthorized {
                    TaskInspectorFieldDivider()
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        allCalendars: calendarManager.allCalendars,
                        selectedID: $selectedCalendarID
                    )
                }

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: "Hide empty task due date",
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: "Hide empty column due date",
                    isOn: $hideSectionDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorStatusRow(
                    noun: "Project",
                    statusLabel: statusLabel,
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
            ListEditorArchiveButton(isArchived: project.isArchived, noun: "Project") {
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

    private func applyEdits() {
        project.name = CadenceTitleNormalization.normalized(name)
        project.desc = details
        project.colorHex = selectedColor
        project.icon = selectedIcon
        project.dueDate = hasDueDate ? DateFormatters.dateKey(from: dueDate) : ""
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
        let undo = CadenceListEditSnapshot(project)
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
        // Same set the settle walks, for the same reason as `EditAreaSheet.apply(_:)`.
        let undo = CadenceListEditSnapshot(
            project,
            tasks: TaskContainerLifecycleService.remainingActiveTasks(in: project)
        )
        applyEdits()
        switch choice {
        case .active: project.status = .active
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

#endif
