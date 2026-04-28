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

    var body: some View {
        sheetBody(title: "Edit Area") {
            area.name = name
            area.colorHex = selectedColor
            area.icon = selectedIcon
            area.linkedCalendarID = selectedCalendarID
            area.hideDueDateIfEmpty = hideDueDateIfEmpty
            area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            dismiss()
        }
    }

    @ViewBuilder
    private func sheetBody(title: String, onSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Name")
                    TextField("List name…", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Task Due Date Display")
                    Toggle("Hide due date if empty", isOn: $hideDueDateIfEmpty)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)

                    fieldLabel("Column Due Date Display")
                    Toggle("Hide column due date if empty", isOn: $hideSectionDueDateIfEmpty)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)

                    if calendarManager.isAuthorized {
                        fieldLabel("Apple Calendar")
                        CadenceCalendarPickerButton(
                            calendars: calendarManager.availableCalendars,
                            selectedID: $selectedCalendarID
                        )
                    }

                    fieldLabel("Lifecycle")
                    lifecycleCard(
                        isDone: area.isDone,
                        isArchived: area.isArchived,
                        onToggleDone: toggleDone,
                        onToggleArchived: toggleArchived,
                        onDelete: { showDeleteConfirmation = true }
                    )
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Save",
                    role: .primary,
                    size: .compact,
                    isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    onSave()
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 600)
        .background(Theme.surface)
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    @ViewBuilder
    private func lifecycleCard(
        isDone: Bool,
        isArchived: Bool,
        onToggleDone: @escaping () -> Void,
        onToggleArchived: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LifecycleButton(
                title: isDone ? "Reopen Area" : "Complete Area",
                subtitle: isDone ? "Bring this area back into the active sidebar." : "Hide it from the active sidebar but keep it restorable.",
                tint: Theme.green,
                action: onToggleDone
            )
            LifecycleButton(
                title: isArchived ? "Unarchive Area" : "Archive Area",
                subtitle: isArchived ? "Return this area to the active sidebar." : "Store it away without deleting its tasks and documents.",
                tint: Theme.amber,
                action: onToggleArchived
            )
            LifecycleButton(
                title: "Delete Area",
                subtitle: "Permanently remove the area and everything inside it.",
                tint: Theme.red,
                action: onDelete
            )
        }
    }

    private func toggleDone() {
        area.status = area.isDone ? .active : .done
        dismiss()
    }

    private func toggleArchived() {
        area.status = area.isArchived ? .active : .archived
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Project")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Name")
                    TextField("Project name…", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Due Date")
                    HStack(spacing: 8) {
                        Toggle("", isOn: $hasDueDate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .scaleEffect(0.75)
                        if hasDueDate {
                            CadenceDatePicker(selection: $dueDate)
                        } else {
                            Text("None")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                        }
                    }

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Task Due Date Display")
                    Toggle("Hide due date if empty", isOn: $hideDueDateIfEmpty)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)

                    fieldLabel("Column Due Date Display")
                    Toggle("Hide column due date if empty", isOn: $hideSectionDueDateIfEmpty)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)

                    if calendarManager.isAuthorized {
                        fieldLabel("Apple Calendar")
                        CadenceCalendarPickerButton(
                            calendars: calendarManager.availableCalendars,
                            selectedID: $selectedCalendarID
                        )
                    }

                    fieldLabel("Lifecycle")
                    lifecycleCard
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Save",
                    role: .primary,
                    size: .compact,
                    isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    save()
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 640)
        .background(Theme.surface)
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

    private func save() {
        project.name = name
        project.colorHex = selectedColor
        project.icon = selectedIcon
        project.dueDate = hasDueDate ? DateFormatters.dateKey(from: dueDate) : ""
        project.linkedCalendarID = selectedCalendarID
        project.hideDueDateIfEmpty = hideDueDateIfEmpty
        project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
        dismiss()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private var lifecycleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LifecycleButton(
                title: project.isDone ? "Reopen Project" : "Complete Project",
                subtitle: project.isDone ? "Bring this project back into the active sidebar." : "Hide it from the active sidebar but keep it restorable.",
                tint: Theme.green,
                action: toggleDone
            )
            LifecycleButton(
                title: project.isArchived ? "Unarchive Project" : "Archive Project",
                subtitle: project.isArchived ? "Return this project to the active sidebar." : "Store it away without deleting its tasks and documents.",
                tint: Theme.amber,
                action: toggleArchived
            )
            LifecycleButton(
                title: "Delete Project",
                subtitle: "Permanently remove the project and everything inside it.",
                tint: Theme.red,
                action: { showDeleteConfirmation = true }
            )
        }
    }

    private func toggleDone() {
        project.status = project.isDone ? .active : .done
        dismiss()
    }

    private func toggleArchived() {
        project.status = project.isArchived ? .active : .archived
        dismiss()
    }

    private func deleteProject() {
        modelContext.deleteProject(project)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Shared lifecycle button

private struct LifecycleButton: View {
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

#endif
