#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Edit Area Sheet

struct EditAreaSheet: View {
    @Bindable var area: Area
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedColor: String
    @State private var selectedIcon: String

    init(area: Area) {
        self.area = area
        _name = State(initialValue: area.name)
        _selectedColor = State(initialValue: area.colorHex)
        _selectedIcon = State(initialValue: area.icon)
    }

    var body: some View {
        sheetBody(title: "Edit Area") {
            area.name = name
            area.colorHex = selectedColor
            area.icon = selectedIcon
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
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Button("Save") { onSave() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 420, height: 600)
        .background(Theme.surface)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}

// MARK: - Edit Project Sheet

struct EditProjectSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _selectedColor = State(initialValue: project.colorHex)
        _selectedIcon = State(initialValue: project.icon)
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
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 420, height: 640)
        .background(Theme.surface)
    }

    private func save() {
        project.name = name
        project.colorHex = selectedColor
        project.icon = selectedIcon
        project.dueDate = hasDueDate ? DateFormatters.dateKey(from: dueDate) : ""
        dismiss()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}
#endif
