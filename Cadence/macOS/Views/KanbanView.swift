#if os(macOS)
import SwiftUI
import SwiftData

private let kanbanSectionDragPrefix = "kanban-section::"
private let kanbanSectionColorOptions: [String] = [
    "#6b7a99", "#4a9eff", "#4ecb71", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316"
]
private let kanbanColumnReorderAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12)
private let kanbanColumnStateAnimation = Animation.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
private let kanbanColumnWidth: CGFloat = 248

struct TaskListsKanbanView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TaskListBoardSection(
                    title: "Inbox",
                    icon: "tray.fill",
                    color: Theme.dim,
                    taskCount: inboxTasks.count
                ) {
                    ListSectionsKanbanView(
                        tasks: inboxTasks,
                        explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
                    )
                }

                ForEach(areas) { area in
                    TaskListBoardSection(
                        title: area.name,
                        icon: area.icon,
                        color: Color(hex: area.colorHex),
                        taskCount: tasks(for: area).count
                    ) {
                        ListSectionsKanbanView(tasks: tasks(for: area), area: area)
                    }
                }

                ForEach(projects) { project in
                    TaskListBoardSection(
                        title: project.name,
                        icon: project.icon,
                        color: Color(hex: project.colorHex),
                        taskCount: tasks(for: project).count
                    ) {
                        ListSectionsKanbanView(tasks: tasks(for: project), project: project)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .clipped()
    }

    private var activeTasks: [AppTask] {
        allTasks.filter { !$0.isCancelled }
    }

    private var inboxTasks: [AppTask] {
        activeTasks.filter { $0.area == nil && $0.project == nil }
    }

    private func tasks(for area: Area) -> [AppTask] {
        activeTasks.filter { $0.area?.id == area.id }
    }

    private func tasks(for project: Project) -> [AppTask] {
        activeTasks.filter { $0.project?.id == project.id }
    }
}

struct ListSectionsKanbanView: View {
    let tasks: [AppTask]
    var area: Area? = nil
    var project: Project? = nil
    var explicitSectionConfigs: [TaskSectionConfig]? = nil
    var showArchived: Binding<Bool>? = nil

    @State private var localShowArchived = false
    @State private var draggingSectionName: String?

    private var baseSectionConfigs: [TaskSectionConfig] {
        explicitSectionConfigs ?? area?.sectionConfigs ?? project?.sectionConfigs ?? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
    }

    private var sectionConfigs: [TaskSectionConfig] {
        let configs = baseSectionConfigs
        return showArchivedBinding.wrappedValue ? configs.filter(\.isArchived) : configs.filter { !$0.isArchived }
    }

    private var allowsSectionEditing: Bool {
        area != nil || project != nil
    }

    private var showArchivedBinding: Binding<Bool> {
        showArchived ?? $localShowArchived
    }

    var body: some View {
        ZStack {
            Theme.bg

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(sectionConfigs, id: \.id) { section in
                        ListSectionKanbanColumn(
                            section: section,
                            tasks: tasks.filter { !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame },
                            area: area,
                            project: project,
                            isBeingDragged: draggingSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                            isAnotherSectionBeingDragged: draggingSectionName != nil && draggingSectionName?.caseInsensitiveCompare(section.name) != .orderedSame,
                            onReorderBefore: { movingName in
                                reorderSection(named: movingName, before: section.name)
                                DispatchQueue.main.async {
                                    draggingSectionName = nil
                                }
                            }
                        )
                        .onDrag {
                            draggingSectionName = section.name
                            return NSItemProvider(object: NSString(string: "\(kanbanSectionDragPrefix)\(section.name)"))
                        } preview: {
                            columnDragPreview(for: section)
                        }
                    }

                    if allowsSectionEditing && !showArchivedBinding.wrappedValue {
                        addSectionRail
                    }
                }
                .padding(20)
                .background(Theme.bg)
            }
            .background(Theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var addSectionRail: some View {
        Button {
            addSection()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface.opacity(0.72))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.borderSubtle.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 42)
            .frame(minHeight: 360)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.cadencePlain)
    }

    private func addSection() {
        let trimmed = nextSectionName()
        if let area {
            var configs = area.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: area.colorHex))
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: project.colorHex))
            project.sectionConfigs = configs
        }
    }

    private func nextSectionName() -> String {
        let existingNames = Set(baseSectionConfigs.map { $0.name.lowercased() })
        if !existingNames.contains("new section") {
            return "New Section"
        }

        var index = 2
        while existingNames.contains("new section \(index)") {
            index += 1
        }
        return "New Section \(index)"
    }

    private func reorderSection(named movingName: String, before targetName: String) {
        guard movingName.caseInsensitiveCompare(targetName) != .orderedSame else { return }

        func reordered(_ configs: [TaskSectionConfig]) -> [TaskSectionConfig] {
            guard let from = configs.firstIndex(where: { $0.name.caseInsensitiveCompare(movingName) == .orderedSame }),
                  let to = configs.firstIndex(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) else { return configs }
            var updated = configs
            let item = updated.remove(at: from)
            let insertAt = from < to ? to - 1 : to
            updated.insert(item, at: max(0, insertAt))
            if let defaultIndex = updated.firstIndex(where: \.isDefault), defaultIndex != 0 {
                let def = updated.remove(at: defaultIndex)
                updated.insert(def, at: 0)
            }
            return updated
        }

        if let area {
            withAnimation(kanbanColumnReorderAnimation) {
                area.sectionConfigs = reordered(area.sectionConfigs)
            }
        } else if let project {
            withAnimation(kanbanColumnReorderAnimation) {
                project.sectionConfigs = reordered(project.sectionConfigs)
            }
        }
    }

    @ViewBuilder
    private func columnDragPreview(for section: TaskSectionConfig) -> some View {
        let tint = section.isDefault ? Theme.dim : Color(hex: section.colorHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(section.isDefault ? 0.55 : 0.9))
                    .frame(width: 8, height: 8)
                Text(section.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surfaceElevated.opacity(0.95))
                .frame(height: 54)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(section.isDefault ? 0.18 : 0.24))
                        .frame(width: 86, height: 10)
                        .padding(10)
                }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(section.isDefault ? 0.06 : 0.11))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }
}

// MARK: - Column

private struct ListSectionKanbanColumn: View {
    let section: TaskSectionConfig
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    let isBeingDragged: Bool
    let isAnotherSectionBeingDragged: Bool
    let onReorderBefore: (String) -> Void

    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(HoveredSectionManager.self) private var hoveredSectionManager
    @Environment(SectionCompletionAnimationManager.self) private var sectionCompletionAnimationManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @State private var isTargeted = false
    @State private var showDoneTasks = false
    @State private var showEditor = false
    @State private var editorName = ""
    @State private var editorColorHex = TaskSectionDefaults.defaultColorHex
    @State private var editorDueDate = Date()
    @State private var isHovered = false
    @Query private var allTasks: [AppTask]

    private var activeTasks: [AppTask] {
        tasks.filter { !$0.isDone }
    }

    private var completedTasks: [AppTask] {
        tasks.filter { $0.isDone }
    }

    private var columnColor: Color {
        section.isDefault ? Theme.dim : Color(hex: section.colorHex)
    }

    private var sectionHoverID: String {
        "kanban-column-\(section.id.uuidString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggleSectionCompletion()
                } label: {
                    Image(systemName: section.isCompleted ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section.isCompleted || isPendingCompletion ? Theme.green : columnColor.opacity(section.isDefault ? 0.75 : 0.9))
                }
                .buttonStyle(.cadencePlain)
                .padding(.trailing, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 5) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Text(section.dueDate.isEmpty ? "No due date" : DateFormatters.relativeDate(from: section.dueDate))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                section.dueDate.isEmpty
                                    ? Theme.dim
                                    : (sectionDueDateIsOverdue ? Theme.red : Theme.dim)
                            )
                            .lineLimit(1)
                    }
                    if section.isCompleted {
                        Text("Completed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.green)
                    } else if isPendingCompletion {
                        Text("Completing…")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.green)
                    }
                }

                Spacer()
                Text("\(activeTasks.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                Button {
                    editorName = section.name
                    editorColorHex = section.colorHex
                    editorDueDate = DateFormatters.date(from: section.dueDate) ?? Date()
                    showEditor = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22, height: 22)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.cadencePlain)
                .popover(isPresented: $showEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    columnEditor
                }
                Button {
                    presentNewTaskPanel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22, height: 22)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeTasks.sorted { $0.order < $1.order }) { task in
                        KanbanCard(task: task)
                            .draggable(task.id.uuidString)
                    }

                    if !completedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showDoneTasks.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: showDoneTasks ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Completed")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("\(completedTasks.count)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.green.opacity(0.12))
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Theme.surface.opacity(0.5))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Theme.borderSubtle.opacity(0.75))
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                            if showDoneTasks {
                                VStack(spacing: 6) {
                                    ForEach(completedTasks.sorted { $0.order < $1.order }) { task in
                                        KanbanCard(task: task)
                                            .draggable(task.id.uuidString)
                                    }
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                                        removal: .opacity
                                    )
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(8)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(minHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(Theme.surface)
            )
        }
        .frame(width: kanbanColumnWidth)
        .background(columnBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted
                        ? columnColor.opacity(0.6)
                        : (isHovered ? columnColor.opacity(section.isDefault ? 0.3 : 0.4) : columnColor.opacity(section.isDefault ? 0.14 : 0.2))
                )
        )
        .scaleEffect(isBeingDragged ? 0.972 : (isTargeted ? 1.018 : 1))
        .offset(y: isTargeted ? -6 : 0)
        .opacity(isBeingDragged ? 0.42 : 1)
        .zIndex(isBeingDragged ? 3 : (isTargeted ? 2 : 0))
        .animation(kanbanColumnStateAnimation, value: isBeingDragged)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .overlay(alignment: .top) {
            if isTargeted && isAnotherSectionBeingDragged {
                RoundedRectangle(cornerRadius: 3)
                    .fill(columnColor.opacity(0.9))
                    .frame(height: 4)
                    .padding(.horizontal, 26)
                    .offset(y: -7)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            if payload.hasPrefix(kanbanSectionDragPrefix) {
                let movingName = String(payload.dropFirst(kanbanSectionDragPrefix.count))
                onReorderBefore(movingName)
                return true
            }
            guard let uuid = UUID(uuidString: payload),
                  let task = allTasks.first(where: { $0.id == uuid }) else { return false }
            task.sectionName = section.name
            return true
        } isTargeted: { isTargeted = $0 }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredKanbanColumnManager.beginHovering(id: sectionHoverID) {
                    presentNewTaskPanel()
                }
                hoveredSectionManager.beginHovering(id: section.id) {
                    toggleSectionCompletion()
                }
                hoveredEditableManager.beginHovering(id: sectionHoverID) {
                    editorName = section.name
                    editorColorHex = section.colorHex
                    editorDueDate = DateFormatters.date(from: section.dueDate) ?? Date()
                    showEditor = true
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: sectionHoverID)
                hoveredSectionManager.endHovering(id: section.id)
                hoveredEditableManager.endHovering(id: sectionHoverID)
            }
        }
    }

    private func presentNewTaskPanel() {
        let container: TaskContainerSelection
        if let area {
            container = .area(area.id)
        } else if let project {
            container = .project(project.id)
        } else {
            container = .inbox
        }

        taskCreationManager.present(
            container: container,
            sectionName: section.name
        )
    }

    @ViewBuilder
    private var columnEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.isDefault ? "Default Column" : "Edit Column")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            if section.isDefault {
                Text("Default always stays available and cannot be renamed, archived, or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Column name", text: $editorName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    ForEach(kanbanSectionColorOptions, id: \.self) { hex in
                        Button {
                            editorColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle()
                                        .stroke(editorColorHex == hex ? Theme.text : .clear, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                CadenceDatePicker(selection: $editorDueDate)

                HStack(spacing: 10) {
                    Button(section.dueDate.isEmpty ? "Set Due Date" : "Update Due Date") {
                        updateSection { config in
                            config.dueDate = DateFormatters.dateKey(from: editorDueDate)
                        }
                    }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.blue)

                    if !section.dueDate.isEmpty {
                        Button("Clear Due Date") {
                            updateSection { config in
                                config.dueDate = ""
                            }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.red)
                    }
                }
            }

            Divider().background(Theme.borderSubtle)

            Button(section.isCompleted ? "Mark Section Active" : "Mark Section Completed") {
                toggleSectionCompletion()
                showEditor = false
            }
            .buttonStyle(.cadencePlain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(section.isCompleted ? Theme.blue : Theme.green)

            if !section.isDefault {
                Button(section.isArchived ? "Unarchive Column" : "Archive Column") {
                    updateSection { config in
                        config.isArchived.toggle()
                        if !config.isArchived {
                            config.isCompleted = false
                        }
                    }
                    showEditor = false
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

                Button("Delete Column") {
                    deleteConfirmationManager.present(
                        title: "Delete Column?",
                        message: "This will delete the column \"\(section.name)\" and move its tasks into Default."
                    ) {
                        moveTasks(from: section.name, to: TaskSectionDefaults.defaultName)
                        removeSection()
                        showEditor = false
                    }
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.red)
            }

            HStack {
                Spacer()
                Button("Done") {
                    saveSectionChanges()
                    showEditor = false
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.surface)
    }

    private func updateSection(_ mutate: (inout TaskSectionConfig) -> Void) {
        if let area {
            var configs = area.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == section.id }) else { return }
            mutate(&configs[idx])
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == section.id }) else { return }
            mutate(&configs[idx])
            project.sectionConfigs = configs
        }
    }

    private func saveSectionChanges() {
        let trimmed = section.isDefault ? section.name : editorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let area {
            var configs = area.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == section.id }) else { return }
            if trimmed.caseInsensitiveCompare(section.name) != .orderedSame,
               configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return
            }
            configs[idx].name = trimmed
            configs[idx].colorHex = editorColorHex
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == section.id }) else { return }
            if trimmed.caseInsensitiveCompare(section.name) != .orderedSame,
               configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return
            }
            configs[idx].name = trimmed
            configs[idx].colorHex = editorColorHex
            project.sectionConfigs = configs
        }
        if trimmed.caseInsensitiveCompare(section.name) != .orderedSame {
            moveTasks(from: section.name, to: trimmed)
        }
    }

    private func moveTasks(from oldName: String, to newName: String) {
        for task in allTasks where task.resolvedSectionName.caseInsensitiveCompare(oldName) == .orderedSame {
            if area != nil, task.area?.id != area?.id { continue }
            if project != nil, task.project?.id != project?.id { continue }
            task.sectionName = newName
        }
    }

    private func removeSection() {
        if let area {
            area.sectionConfigs = area.sectionConfigs.filter { $0.id != section.id }
        } else if let project {
            project.sectionConfigs = project.sectionConfigs.filter { $0.id != section.id }
        }
    }

    private func toggleSectionCompletion() {
        sectionCompletionAnimationManager.toggleCompletion(
            for: section,
            getCurrent: currentSection,
            save: saveSection
        )
    }

    private func currentSection() -> TaskSectionConfig? {
        if let area {
            return area.sectionConfigs.first(where: { $0.id == section.id })
        }
        if let project {
            return project.sectionConfigs.first(where: { $0.id == section.id })
        }
        return nil
    }

    private func saveSection(_ updatedSection: TaskSectionConfig) {
        if let area {
            var configs = area.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.id == updatedSection.id }) else { return }
            configs[index] = updatedSection
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.id == updatedSection.id }) else { return }
            configs[index] = updatedSection
            project.sectionConfigs = configs
        }
    }

    private var isPendingCompletion: Bool {
        sectionCompletionAnimationManager.isPending(section)
    }

    private var sectionDueDateIsOverdue: Bool {
        !section.dueDate.isEmpty && !section.isCompleted && section.dueDate < DateFormatters.todayKey()
    }

    @ViewBuilder
    private var columnBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(columnColor.opacity(isHovered ? (section.isDefault ? 0.18 : 0.24) : (section.isDefault ? 0.12 : 0.18)))
            }
            .overlay {
                if isPendingCompletion {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.green.opacity(0.22))
                                .frame(
                                    width: proxy.size.width * sectionCompletionAnimationManager.progress(for: section, now: context.date),
                                    alignment: .leading
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isHovered || isTargeted ? 0.024 : 0.01))
            }
    }
}
#endif
