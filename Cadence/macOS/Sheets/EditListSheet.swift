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
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var selectedCalendarID: String
    @State private var hideDueDateIfEmpty: Bool
    @State private var hideSectionDueDateIfEmpty: Bool
    @State private var showDeleteConfirmation = false

    init(area: Area) {
        self.area = area
        _name = State(initialValue: area.name)
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
            ListEditorNameField(name: $name)

            TaskInspectorRecessedGroup {
                ListEditorAppearanceRows(colorHex: $selectedColor, icon: $selectedIcon)

                if calendarManager.isAuthorized {
                    TaskInspectorFieldDivider()
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        selectedID: $selectedCalendarID
                    )
                }

                TaskInspectorFieldDivider()
                ListEditorToggleRow(
                    label: "Hide empty task due date",
                    icon: "calendar.badge.exclamationmark",
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorToggleRow(
                    label: "Hide empty column due date",
                    icon: "rectangle.split.3x1",
                    isOn: $hideSectionDueDateIfEmpty
                )
            }

            TaskInspectorRecessedSection(title: "Lifecycle") {
                ListEditorStatusRow(
                    noun: "Area",
                    statusLabel: statusLabel,
                    isActive: area.isActive,
                    onSelect: apply
                )
                TaskInspectorFieldDivider()
                ListEditorDeleteRow(title: "Delete Area") { showDeleteConfirmation = true }
            }
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
            Text("This permanently deletes the area and its tasks, projects, documents, and links.")
        }
    }

    private func applyEdits() {
        area.name = name
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
        case .active:
            area.status = .active
        case .completed:
            area.status = .done
            TaskContainerLifecycleService.completeRemainingActiveTasks(in: area, includingChildProjects: true, in: modelContext)
        case .archived:
            area.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: area, includingChildProjects: true, in: modelContext)
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
            ListEditorNameField(name: $name, placeholder: "Project name…")

            TaskInspectorRecessedGroup {
                TaskInspectorDateControl(
                    label: "Due",
                    icon: "flag.fill",
                    activeColor: Theme.red,
                    isOn: $hasDueDate,
                    date: $dueDate
                )

                TaskInspectorFieldDivider()
                ListEditorAppearanceRows(colorHex: $selectedColor, icon: $selectedIcon)

                if calendarManager.isAuthorized {
                    TaskInspectorFieldDivider()
                    ListEditorCalendarRow(
                        calendars: calendarManager.availableCalendars,
                        selectedID: $selectedCalendarID
                    )
                }

                TaskInspectorFieldDivider()
                ListEditorToggleRow(
                    label: "Hide empty task due date",
                    icon: "calendar.badge.exclamationmark",
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorToggleRow(
                    label: "Hide empty column due date",
                    icon: "rectangle.split.3x1",
                    isOn: $hideSectionDueDateIfEmpty
                )
            }

            TaskInspectorRecessedSection(title: "Lifecycle") {
                ListEditorStatusRow(
                    noun: "Project",
                    statusLabel: statusLabel,
                    isActive: project.isActive,
                    onSelect: apply
                )
                TaskInspectorFieldDivider()
                ListEditorDeleteRow(title: "Delete Project") { showDeleteConfirmation = true }
            }
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
            Text("This permanently deletes the project and its tasks, documents, and links.")
        }
    }

    private func applyEdits() {
        project.name = name
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
        case .active:
            project.status = .active
        case .completed:
            project.status = .done
            TaskContainerLifecycleService.completeRemainingActiveTasks(in: project, in: modelContext)
        case .archived:
            project.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: project, in: modelContext)
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
