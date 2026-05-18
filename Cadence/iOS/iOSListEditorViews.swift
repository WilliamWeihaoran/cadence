#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListEditorMode: Identifiable {
    case newArea
    case newProject
    case editArea(Area)
    case editProject(Project)

    var id: String {
        switch self {
        case .newArea: return "new-area"
        case .newProject: return "new-project"
        case .editArea(let area): return "area-\(area.id)"
        case .editProject(let project): return "project-\(project.id)"
        }
    }
}

struct iOSListEditorSheet: View {
    let mode: iOSListEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var name = ""
    @State private var details = ""
    @State private var icon = ""
    @State private var colorHex = ""
    @State private var selectedContextID = "none"
    @State private var selectedAreaID = "none"
    @State private var sectionText = TaskSectionDefaults.defaultName
    @State private var hideEmptyDueDates = true
    @State private var hasProjectDueDate = false
    @State private var projectDueDate = Date()
    @State private var hasLoaded = false

    private var isProjectMode: Bool {
        switch mode {
        case .newProject, .editProject:
            return true
        case .newArea, .editArea:
            return false
        }
    }

    private var isEditing: Bool {
        switch mode {
        case .editArea, .editProject:
            return true
        case .newArea, .newProject:
            return false
        }
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSections: [String] {
        let values = sectionText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [TaskSectionDefaults.defaultName] : values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isProjectMode ? "Project" : "Area") {
                    TextField(isProjectMode ? "Project name" : "Area name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Appearance") {
                    TextField("SF Symbol", text: $icon)
                        .textInputAutocapitalization(.never)
                    TextField("Color hex", text: $colorHex)
                        .textInputAutocapitalization(.never)
                }

                Section("Organize") {
                    Picker("Context", selection: $selectedContextID) {
                        Text("None").tag("none")
                        ForEach(activeContexts) { context in
                            Text(context.name.isEmpty ? "Untitled Context" : context.name)
                                .tag(context.id.uuidString)
                        }
                    }

                    if isProjectMode {
                        Picker("Area", selection: $selectedAreaID) {
                            Text("None").tag("none")
                            ForEach(activeAreas) { area in
                                Text(area.name.isEmpty ? "Untitled Area" : area.name)
                                    .tag(area.id.uuidString)
                            }
                        }
                    }

                    if isProjectMode {
                        Toggle("Due date", isOn: $hasProjectDueDate)
                        if hasProjectDueDate {
                            DatePicker("Due", selection: $projectDueDate, displayedComponents: .date)
                        }
                    }
                }

                Section("Sections") {
                    TextEditor(text: $sectionText)
                        .frame(minHeight: 120)
                    Toggle("Hide empty due dates", isOn: $hideEmptyDueDates)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isEditing ? "Edit List" : "New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .newArea:
            name = ""
            details = ""
            icon = "folder.fill"
            colorHex = "#4a9eff"
            hasProjectDueDate = false
            projectDueDate = Date()
        case .newProject:
            name = ""
            details = ""
            icon = "checklist"
            colorHex = "#4ecb71"
            hasProjectDueDate = false
            projectDueDate = Date()
        case .editArea(let area):
            name = area.name
            details = area.desc
            icon = area.icon
            colorHex = area.colorHex
            selectedContextID = area.context?.id.uuidString ?? "none"
            sectionText = area.sectionNames.joined(separator: "\n")
            hideEmptyDueDates = area.hideDueDateIfEmpty
        case .editProject(let project):
            name = project.name
            details = project.desc
            icon = project.icon
            colorHex = project.colorHex
            selectedContextID = project.context?.id.uuidString ?? "none"
            selectedAreaID = project.area?.id.uuidString ?? "none"
            sectionText = project.sectionNames.joined(separator: "\n")
            hideEmptyDueDates = project.hideDueDateIfEmpty
            if let date = DateFormatters.date(from: project.dueDate) {
                projectDueDate = date
                hasProjectDueDate = true
            } else {
                projectDueDate = Date()
                hasProjectDueDate = false
            }
        }
    }

    private func save() {
        switch mode {
        case .newArea:
            let area = Area(name: trimmedName, context: selectedContext, colorHex: normalizedColor, icon: normalizedIcon)
            area.desc = details
            area.order = nextAreaOrder()
            area.sectionNames = normalizedSections
            area.hideDueDateIfEmpty = hideEmptyDueDates
            modelContext.insert(area)
        case .newProject:
            let project = Project(name: trimmedName, context: selectedContext, area: selectedArea, colorHex: normalizedColor)
            project.desc = details
            project.icon = normalizedIcon
            project.order = nextProjectOrder()
            project.sectionNames = normalizedSections
            project.hideDueDateIfEmpty = hideEmptyDueDates
            project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
            modelContext.insert(project)
        case .editArea(let area):
            area.name = trimmedName
            area.desc = details
            area.icon = normalizedIcon
            area.colorHex = normalizedColor
            area.context = selectedContext
            area.sectionNames = normalizedSections
            area.hideDueDateIfEmpty = hideEmptyDueDates
        case .editProject(let project):
            project.name = trimmedName
            project.desc = details
            project.icon = normalizedIcon
            project.colorHex = normalizedColor
            project.context = selectedContext
            project.area = selectedArea
            project.sectionNames = normalizedSections
            project.hideDueDateIfEmpty = hideEmptyDueDates
            project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
        }

        try? modelContext.save()
        dismiss()
    }

    private var selectedContext: Context? {
        guard let id = UUID(uuidString: selectedContextID) else { return nil }
        return contexts.first { $0.id == id }
    }

    private var selectedArea: Area? {
        guard let id = UUID(uuidString: selectedAreaID) else { return nil }
        return areas.first { $0.id == id }
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isProjectMode ? "checklist" : "folder.fill"
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return isProjectMode ? "#4ecb71" : "#4a9eff"
        }
        return trimmed
    }

    private func nextAreaOrder() -> Int {
        (areas.map(\.order).max() ?? -1) + 1
    }

    private func nextProjectOrder() -> Int {
        (projects.map(\.order).max() ?? -1) + 1
    }
}
#endif
