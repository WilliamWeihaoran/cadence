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
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: {
                applyEdits()
                dismiss()
            }
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
        area.name = name
        area.desc = details
        area.colorHex = selectedColor
        area.icon = selectedIcon
        area.linkedCalendarID = selectedCalendarID
        area.hideDueDateIfEmpty = hideDueDateIfEmpty
        area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
    }

    /// A lifecycle change still closes the sheet, so the pending field edits are written first
    /// rather than thrown away by the dismissal.
    private func apply(_ choice: ListEditorLifecycleChoice) {
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
        try? modelContext.save()
        dismiss()
    }

    private func deleteArea() {
        modelContext.deleteArea(area)
        try? modelContext.save()
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
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: {
                applyEdits()
                dismiss()
            }
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
        project.name = name
        project.desc = details
        project.colorHex = selectedColor
        project.icon = selectedIcon
        project.dueDate = hasDueDate ? DateFormatters.dateKey(from: dueDate) : ""
        project.linkedCalendarID = selectedCalendarID
        project.hideDueDateIfEmpty = hideDueDateIfEmpty
        project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
    }

    private func apply(_ choice: ListEditorLifecycleChoice) {
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
        try? modelContext.save()
        dismiss()
    }

    private func deleteProject() {
        modelContext.deleteProject(project)
        try? modelContext.save()
        dismiss()
    }
}

#endif
