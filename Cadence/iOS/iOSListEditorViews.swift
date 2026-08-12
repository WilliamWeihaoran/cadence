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
    @State private var sectionDrafts: [CadenceSectionDraft] = [CadenceSectionDraft(name: TaskSectionDefaults.defaultName)]
    @State private var originalSectionConfigs: [TaskSectionConfig] = []
    @State private var hideEmptyDueDates = true
    @State private var hasProjectDueDate = false
    @State private var projectDueDate = Date()
    @State private var hasLoaded = false
    @State private var showContextPicker = false
    @State private var showAreaPicker = false

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

    private var contextTitle: String {
        guard selectedContextID != "none",
              let context = activeContexts.first(where: { $0.id.uuidString == selectedContextID }),
              !context.name.isEmpty
        else { return "None" }
        return context.name
    }

    private var areaTitle: String {
        guard selectedAreaID != "none",
              let area = activeAreas.first(where: { $0.id.uuidString == selectedAreaID }),
              !area.name.isEmpty
        else { return "None" }
        return area.name
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSectionConfigs: [TaskSectionConfig] {
        CadenceSectionEditingSupport.configs(from: sectionDrafts)
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
                    HStack {
                        Text("Context")
                        Spacer()
                        iOSChoiceValueButton(title: contextTitle, color: Theme.text) {
                            showContextPicker = true
                        }
                        .popover(isPresented: $showContextPicker) {
                            iOSChoicePopoverList(
                                rows: [iOSChoiceRow(value: "none", title: "None", color: Theme.dim)]
                                    + activeContexts.map { context in
                                        iOSChoiceRow(value: context.id.uuidString, title: context.name.isEmpty ? "Untitled Context" : context.name, color: Color(hex: context.colorHex))
                                    },
                                selection: $selectedContextID,
                                isPresented: $showContextPicker
                            )
                        }
                    }

                    if isProjectMode {
                        HStack {
                            Text("Area")
                            Spacer()
                            iOSChoiceValueButton(title: areaTitle, color: Theme.text) {
                                showAreaPicker = true
                            }
                            .popover(isPresented: $showAreaPicker) {
                                iOSChoicePopoverList(
                                    rows: [iOSChoiceRow(value: "none", title: "None", color: Theme.dim)]
                                        + activeAreas.map { area in
                                            iOSChoiceRow(value: area.id.uuidString, title: area.name.isEmpty ? "Untitled Area" : area.name, color: Color(hex: area.colorHex))
                                        },
                                    selection: $selectedAreaID,
                                    isPresented: $showAreaPicker
                                )
                            }
                        }
                    }

                    if isProjectMode {
                        Toggle("Due date", isOn: $hasProjectDueDate)
                        if hasProjectDueDate {
                            HStack {
                                Text("Due")
                                Spacer()
                                CadenceDatePicker(selection: $projectDueDate)
                            }
                        }
                    }
                }

                Section("Sections") {
                    ForEach($sectionDrafts) { $draft in
                        iOSSectionDraftRow(draft: $draft)
                    }
                    .onDelete { offsets in
                        sectionDrafts.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        sectionDrafts.move(fromOffsets: source, toOffset: destination)
                    }

                    Button {
                        sectionDrafts.append(CadenceSectionDraft(name: ""))
                    } label: {
                        Label("Add Section", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }

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
            originalSectionConfigs = area.sectionConfigs
            sectionDrafts = CadenceSectionEditingSupport.drafts(from: originalSectionConfigs)
            hideEmptyDueDates = area.hideDueDateIfEmpty
        case .editProject(let project):
            name = project.name
            details = project.desc
            icon = project.icon
            colorHex = project.colorHex
            selectedContextID = project.context?.id.uuidString ?? "none"
            selectedAreaID = project.area?.id.uuidString ?? "none"
            originalSectionConfigs = project.sectionConfigs
            sectionDrafts = CadenceSectionEditingSupport.drafts(from: originalSectionConfigs)
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
            area.sectionConfigs = normalizedSectionConfigs
            area.hideDueDateIfEmpty = hideEmptyDueDates
            modelContext.insert(area)
        case .newProject:
            let project = Project(name: trimmedName, context: selectedContext, area: selectedArea, colorHex: normalizedColor)
            project.desc = details
            project.icon = normalizedIcon
            project.order = nextProjectOrder()
            project.sectionConfigs = normalizedSectionConfigs
            project.hideDueDateIfEmpty = hideEmptyDueDates
            project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
            modelContext.insert(project)
        case .editArea(let area):
            area.name = trimmedName
            area.desc = details
            area.icon = normalizedIcon
            area.colorHex = normalizedColor
            area.context = selectedContext
            reassignTasks(in: area.tasks ?? [])
            area.sectionConfigs = normalizedSectionConfigs
            area.hideDueDateIfEmpty = hideEmptyDueDates
        case .editProject(let project):
            project.name = trimmedName
            project.desc = details
            project.icon = normalizedIcon
            project.colorHex = normalizedColor
            project.context = selectedContext
            project.area = selectedArea
            reassignTasks(in: project.tasks ?? [])
            project.sectionConfigs = normalizedSectionConfigs
            project.hideDueDateIfEmpty = hideEmptyDueDates
            project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
        }

        try? modelContext.save()
        dismiss()
    }

    /// A renamed or removed column leaves `AppTask.sectionName` pointing at a name no column has
    /// any more — nothing in SwiftData re-points a plain string. macOS's kanban column calls
    /// `moveTasks`; this is the same rule, applied to every column the editor changed at once.
    private func reassignTasks(in tasks: [AppTask]) {
        CadenceSectionEditingSupport.applySectionNameChanges(
            renames: CadenceSectionEditingSupport.renames(in: sectionDrafts),
            removedNames: CadenceSectionEditingSupport.removedNames(
                original: originalSectionConfigs,
                drafts: sectionDrafts
            ),
            to: tasks
        )
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

/// One kanban column in the list editor.
///
/// iOS read `sectionConfigs` in no production file at all — the editor was a newline-separated
/// list of names, so a column's colour, due date, completion and archived flag were invisible
/// here and a rename silently discarded all four. These are the same four properties macOS's
/// column editor exposes.
private struct iOSSectionDraftRow: View {
    @Binding var draft: CadenceSectionDraft
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: draft.colorHex))
                    .frame(width: 12, height: 12)

                TextField("Section name", text: $draft.name)
                    .font(.system(size: 15, weight: .medium))
            }

            iOSSectionColorPicker(selectedHex: $draft.colorHex)

            Toggle("Due date", isOn: $hasDueDate)
                .font(.system(size: 13))

            if hasDueDate {
                HStack {
                    Text("Due")
                        .font(.system(size: 13))
                    Spacer()
                    CadenceDatePicker(selection: $dueDate)
                }
            }

            HStack(spacing: 16) {
                Toggle("Completed", isOn: $draft.isCompleted)
                    .font(.system(size: 13))
                Toggle("Archived", isOn: $draft.isArchived)
                    .font(.system(size: 13))
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            hasDueDate = !draft.dueDate.isEmpty
            dueDate = DateFormatters.date(from: draft.dueDate) ?? Date()
        }
        .onChange(of: hasDueDate) { _, isOn in
            draft.dueDate = isOn ? DateFormatters.dateKey(from: dueDate) : ""
        }
        .onChange(of: dueDate) { _, newValue in
            guard hasDueDate else { return }
            draft.dueDate = DateFormatters.dateKey(from: newValue)
        }
    }
}

/// The section palette is `TagSupport.colorOptions` plus the section default, so the swatch row
/// can always show the colour a column already has rather than silently offering to change it.
private struct iOSSectionColorPicker: View {
    @Binding var selectedHex: String

    private var options: [String] {
        var options = [TaskSectionDefaults.defaultColorHex] + TagSupport.colorOptions
        if !options.contains(where: { $0.caseInsensitiveCompare(selectedHex) == .orderedSame }) {
            options.append(selectedHex)
        }
        return options
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selectedHex = option
                    } label: {
                        Circle()
                            .fill(Color(hex: option))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if selectedHex.caseInsensitiveCompare(option) == .orderedSame {
                                    Circle().strokeBorder(Theme.text.opacity(0.78), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
#endif
