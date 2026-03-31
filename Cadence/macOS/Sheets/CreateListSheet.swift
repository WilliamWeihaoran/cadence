#if os(macOS)
import SwiftUI
import SwiftData

struct CreateListSheet: View {
    let context: Context

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var listType: ListType = .area
    @State private var selectedColor = "#4a9eff"
    @State private var selectedIcon = "folder.fill"
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false

    enum ListType: String, CaseIterable {
        case area = "Area"
        case project = "Project"

        var description: String {
            switch self {
            case .area:    return "Ongoing responsibility, no end date"
            case .project: return "Finite effort with a clear outcome"
            }
        }
        var defaultIcon: String {
            switch self {
            case .area:    return "folder.fill"
            case .project: return "checklist"
            }
        }
        var defaultColor: String {
            switch self {
            case .area:    return "#4a9eff"
            case .project: return "#4ecb71"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New List")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("in \(context.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Type
                    fieldLabel("Type")
                    HStack(spacing: 8) {
                        ForEach(ListType.allCases, id: \.self) { type in
                            TypeButton(type: type, isSelected: listType == type) {
                                listType = type
                                selectedIcon = type.defaultIcon
                                selectedColor = type.defaultColor
                            }
                        }
                    }

                    // Name
                    fieldLabel("Name")
                    TextField("List name…", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Due date (projects only)
                    if listType == .project {
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
                    }

                    // Color
                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    // Icon
                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Button("Create") { create() }
                    .buttonStyle(.cadencePlain)
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
        .frame(width: 420, height: listType == .project ? 660 : 620)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch listType {
        case .area:
            let area = Area(name: trimmed, context: context, colorHex: selectedColor, icon: selectedIcon)
            area.order = (context.areas ?? []).count
            modelContext.insert(area)
        case .project:
            let project = Project(name: trimmed, context: context, colorHex: selectedColor)
            project.icon = selectedIcon
            project.order = (context.projects ?? []).count
            if hasDueDate { project.dueDate = DateFormatters.dateKey(from: dueDate) }
            modelContext.insert(project)
        }
        dismiss()
    }
}

// MARK: - Type Button

private struct TypeButton: View {
    let type: CreateListSheet.ListType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.blue : Theme.text)
                Text(type.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.1) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.5) : Theme.borderSubtle)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
