#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Column

struct ListSectionKanbanColumn: View {
    let section: TaskSectionConfig
    let tasks: [AppTask]
    let universeTasks: [AppTask]
    var area: Area?
    var project: Project?
    var onTaskDroppedIntoColumn: ((AppTask, String) -> Void)? = nil
    var assignSectionOnDrop: Bool = true
    let isBeingDragged: Bool
    let isAnotherSectionBeingDragged: Bool
    let isHighlighted: Bool
    let onReorderBefore: (String) -> Void

    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(HoveredSectionManager.self) private var hoveredSectionManager
    @Environment(SectionCompletionAnimationManager.self) private var sectionCompletionAnimationManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @State private var isTargeted = false
    @State private var dragOverTaskID: UUID? = nil
    @State private var frozenTasks: [AppTask]? = nil
    @State private var showDoneTasks = false
    @State private var showEditor = false
    @State private var editorName = ""
    @State private var editorColorHex = TaskSectionDefaults.defaultColorHex
    @State private var editorDueDate = Date()
    @State private var editorHasDueDate = false
    @State private var showHeaderDueDatePicker = false
    @State private var headerDueDate = Date()
    @State private var headerDueDateViewMonth = Date()
    @State private var isHovered = false
    private var unfrozenActiveTasks: [AppTask] {
        tasks.filter { !$0.isDone }
    }

    private var activeTasks: [AppTask] {
        guard let frozen = frozenTasks else { return unfrozenActiveTasks }
        let activeFrozen = frozen.filter { !$0.isDone }
        let frozenIDs = Set(activeFrozen.map(\.id))
        return activeFrozen + unfrozenActiveTasks.filter { !frozenIDs.contains($0.id) }
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

    private var sectionEditHoverID: String {
        "kanban-section-edit-\(section.id.uuidString)"
    }

    private var hideColumnDueDateIfEmpty: Bool {
        if let area { return area.hideSectionDueDateIfEmpty }
        if let project { return project.hideSectionDueDateIfEmpty }
        return false
    }

    var body: some View {
        columnBody
            .background {
                KanbanFreezeObserver(
                    frozenTasks: $frozenTasks,
                    columnTaskIDs: Set(unfrozenActiveTasks.map(\.id)),
                    capturedTasks: unfrozenActiveTasks
                )
            }
    }

    private var columnBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            KanbanColumnHeader(
                section: section,
                activeTaskCount: activeTasks.count,
                columnColor: columnColor,
                hideColumnDueDateIfEmpty: hideColumnDueDateIfEmpty,
                sectionDueDateIsOverdue: sectionDueDateIsOverdue,
                isPendingCompletion: isPendingCompletion,
                showHeaderDueDatePicker: $showHeaderDueDatePicker,
                showEditor: $showEditor,
                onToggleCompletion: toggleSectionCompletion,
                onOpenDueDatePicker: openHeaderDueDatePicker,
                onOpenEditor: openSectionEditor,
                onCreateTask: presentNewTaskPanel,
                onHoverChanged: { hovering in
                    if hovering {
                        hoveredEditableManager.beginHovering(id: sectionEditHoverID) {
                            openSectionEditor()
                        }
                    } else {
                        hoveredEditableManager.endHovering(id: sectionEditHoverID)
                    }
                },
                dueDatePopover: {
                    sectionDueDatePickerPopover
                },
                editorPopover: {
                    columnEditor
                }
            )

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeTasks) { task in
                        KanbanCard(task: task)
                            .overlay(alignment: .top) {
                                if dragOverTaskID == task.id {
                                    Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                            .draggable(task.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let payload = items.first,
                                      let droppedID = taskID(from: payload),
                                      droppedID != task.id,
                                      let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
                                moveTask(droppedTask, before: task)
                                return true
                            } isTargeted: { isOver in
                                if isOver { dragOverTaskID = task.id }
                                else if dragOverTaskID == task.id { dragOverTaskID = nil }
                            }
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
                                    ForEach(completedTasks) { task in
                                        KanbanCard(task: task)
                                            .draggable(task.id.uuidString)
                                            .dropDestination(for: String.self) { items, _ in
                                                guard let payload = items.first,
                                                      let droppedID = taskID(from: payload),
                                                      droppedID != task.id,
                                                      let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
                                                moveTask(droppedTask, before: task)
                                                return true
                                            }
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
            }
            .frame(minHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(.clear)
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
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(columnColor.opacity(0.9), lineWidth: 2.5)
                    .padding(-2)
                    .shadow(color: columnColor.opacity(0.32), radius: 14)
            }
        }
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
                  let task = universeTasks.first(where: { $0.id == uuid }) else { return false }
            moveTask(task, before: nil)
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
            } else {
                hoveredKanbanColumnManager.endHovering(id: sectionHoverID)
                hoveredSectionManager.endHovering(id: section.id)
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

    private func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix("listTask:") {
            return UUID(uuidString: String(payload.dropFirst(9)))
        }
        return UUID(uuidString: payload)
    }

    private func moveTask(_ task: AppTask, before target: AppTask?) {
        if let area {
            task.area = area
            task.project = nil
            task.context = area.context
        } else if let project {
            task.project = project
            task.area = nil
            task.context = project.context
        } else {
            task.area = nil
            task.project = nil
        }
        onTaskDroppedIntoColumn?(task, section.name)
        if assignSectionOnDrop {
            task.sectionName = section.name
        }

        var columnTasks = tasks.sorted { $0.order < $1.order }
        columnTasks.removeAll { $0.id == task.id }
        if let target, let targetIndex = columnTasks.firstIndex(where: { $0.id == target.id }) {
            columnTasks.insert(task, at: targetIndex)
        } else {
            columnTasks.append(task)
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (index, item) in columnTasks.enumerated() {
                item.order = index
            }
        }
    }

    private func openSectionEditor() {
        editorName = section.name
        editorColorHex = section.colorHex
        editorDueDate = DateFormatters.date(from: section.dueDate) ?? Date()
        editorHasDueDate = !section.dueDate.isEmpty
        showEditor = true
    }

    private func openHeaderDueDatePicker() {
        let resolved = DateFormatters.date(from: section.dueDate) ?? Date()
        headerDueDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        headerDueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showHeaderDueDatePicker = true
    }

    @ViewBuilder
    private var sectionDueDatePickerPopover: some View {
        KanbanSectionDueDatePickerPopover(
            dueDateKey: section.dueDate,
            selection: Binding(
                get: { headerDueDate },
                set: { newDate in
                    headerDueDate = newDate
                    updateSection { config in
                        config.dueDate = DateFormatters.dateKey(from: newDate)
                    }
                }
            ),
            viewMonth: $headerDueDateViewMonth,
            isPresented: $showHeaderDueDatePicker,
            onClear: {
                updateSection { config in
                    config.dueDate = ""
                }
                showHeaderDueDatePicker = false
            }
        )
    }

    @ViewBuilder
    private var columnEditor: some View {
        KanbanSectionEditorPopover(
            section: section,
            editorColorOptions: kanbanSectionColorOptions,
            editorName: $editorName,
            editorColorHex: $editorColorHex,
            editorDueDate: $editorDueDate,
            editorHasDueDate: $editorHasDueDate,
            onNameChanged: saveSectionChanges,
            onColorSelected: saveSectionChanges,
            onDueDateChanged: saveSectionChanges,
            onClearDate: {
                editorHasDueDate = false
                saveSectionChanges()
            },
            onToggleCompletion: {
                toggleSectionCompletion()
                showEditor = false
            },
            onToggleArchive: {
                updateSection { config in
                    config.isArchived.toggle()
                    if !config.isArchived {
                        config.isCompleted = false
                    }
                }
                showEditor = false
            },
            onDelete: {
                deleteConfirmationManager.present(
                    title: "Delete Column?",
                    message: "This will delete the column \"\(section.name)\" and move its tasks into Default."
                ) {
                    moveTasks(from: section.name, to: TaskSectionDefaults.defaultName)
                    removeSection()
                    showEditor = false
                }
            }
        )
    }

    private func updateSection(_ mutate: (inout TaskSectionConfig) -> Void) {
        KanbanSectionStateSupport.updateSection(sectionID: section.id, area: area, project: project, mutate: mutate)
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
            configs[idx].dueDate = editorHasDueDate ? DateFormatters.dateKey(from: editorDueDate) : ""
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
            configs[idx].dueDate = editorHasDueDate ? DateFormatters.dateKey(from: editorDueDate) : ""
            project.sectionConfigs = configs
        }
        if trimmed.caseInsensitiveCompare(section.name) != .orderedSame {
            moveTasks(from: section.name, to: trimmed)
        }
    }

    private func moveTasks(from oldName: String, to newName: String) {
        KanbanSectionStateSupport.moveTasks(
            universeTasks: universeTasks,
            area: area,
            project: project,
            from: oldName,
            to: newName
        )
    }

    private func removeSection() {
        KanbanSectionStateSupport.removeSection(sectionID: section.id, area: area, project: project)
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
        KanbanSectionStateSupport.saveSection(updatedSection: updatedSection, area: area, project: project)
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
            .fill(columnColor.opacity(isHovered ? (section.isDefault ? 0.2 : 0.3) : (section.isDefault ? 0.14 : 0.24)))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surface.opacity(section.isDefault ? 0.78 : 0.7))
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
