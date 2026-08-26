#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Column

/// One of Cadence's **two** kanban column implementations: this one renders the *section*
/// columns of a list/project board. The other is `TaskListKanbanColumn` in
/// `KanbanListColumnView.swift`, which renders the *list* columns of the All Tasks board.
/// The two must stay visually identical — all shared chrome lives in
/// `KanbanColumnSupportViews.swift` / `KanbanBoardSupport.swift`, so change it there, not here.
struct ListSectionKanbanColumn: View {
    let section: TaskSectionConfig
    let tasks: [AppTask]
    let universeTasks: [AppTask]
    var area: Area?
    var project: Project?
    let isBeingDragged: Bool
    let isAnotherSectionBeingDragged: Bool
    let isHighlighted: Bool
    let onReorderBefore: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(HoveredSectionManager.self) private var hoveredSectionManager
    @Environment(SectionCompletionAnimationManager.self) private var sectionCompletionAnimationManager
    @State private var isTargeted = false
    @State private var isComposing = false
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
        applyFrozenTaskOrder(unfrozenActiveTasks, frozen: frozenTasks)
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
            // The hairline under the header is part of `CadenceBoardColumnHeader` itself, so all three
            // boards close their header the same way without each column remembering to.
            columnHeader

            columnTaskScroll
        }
        .kanbanColumnChrome(tint: columnColor, isTargeted: isTargeted) {
            // Section columns can be "completing…" — that sweep layers on top of the shared
            // drag-over wash.
            if isPendingCompletion {
                TimelineView(.animation) { context in
                    TaskCompletionPendingOverlay(
                        progress: sectionCompletionAnimationManager.progress(for: section, now: context.date),
                        tint: Theme.green,
                        cornerRadius: kanbanColumnCornerRadius
                    )
                }
            }
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .strokeBorder(columnColor.opacity(0.9), lineWidth: 2)
                    .padding(-4)
                    .shadow(color: columnColor.opacity(0.28), radius: 14)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isBeingDragged ? 0.972 : 1)
        .opacity(isBeingDragged ? 0.42 : 1)
        .zIndex(isBeingDragged ? 3 : (isTargeted ? 2 : 0))
        .animation(kanbanColumnStateAnimation, value: isBeingDragged)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .overlay(alignment: .top) {
            if isTargeted && isAnotherSectionBeingDragged {
                RoundedRectangle(cornerRadius: 3)
                    .fill(columnColor.opacity(0.9))
                    .frame(height: 3)
                    .padding(.horizontal, 4)
                    .offset(y: -8)
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
            // Same payload parsing as the card-level drop and as the list board's column, so a
            // drop on empty column space accepts exactly what a drop on a card accepts.
            guard let uuid = KanbanBoardSupport.taskID(from: payload),
                  let task = universeTasks.first(where: { $0.id == uuid }) else { return false }
            moveTask(task, before: nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredKanbanColumnManager.beginHovering(id: sectionHoverID) {
                    isComposing = true
                }
                // Cmd+Return over a column is the third route to completion, and the only one
                // with no visible control to hide. Default does not register at all rather than
                // registering a no-op: `triggerToggleComplete()` reports whether it handled the
                // key, so a registered target would swallow Cmd+Return instead of letting it
                // through (T-268).
                if section.supportsLifecycle {
                    hoveredSectionManager.beginHovering(id: section.id) {
                        toggleSectionCompletion()
                    }
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: sectionHoverID)
                hoveredSectionManager.endHovering(id: section.id)
            }
        }
    }

    /// The `TimelineView` must stay *conditional*: an unconditional one re-renders every
    /// visible column on every display frame, forever.
    @ViewBuilder
    private var columnHeader: some View {
        if isPendingCompletion {
            TimelineView(.animation) { context in
                header(completionProgress: sectionCompletionAnimationManager.progress(for: section, now: context.date))
            }
        } else {
            header(completionProgress: 0)
        }
    }

    private func header(completionProgress: Double) -> some View {
        KanbanColumnHeader(
            section: section,
            activeTaskCount: activeTasks.count,
            columnColor: columnColor,
            hideColumnDueDateIfEmpty: hideColumnDueDateIfEmpty,
            isPendingCompletion: isPendingCompletion,
            completionProgress: completionProgress,
            showHeaderDueDatePicker: $showHeaderDueDatePicker,
            showEditor: $showEditor,
            onToggleCompletion: toggleSectionCompletion,
            onOpenDueDatePicker: openHeaderDueDatePicker,
            onOpenEditor: openSectionEditor,
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
    }

    private var columnTaskScroll: some View {
        KanbanColumnScroll(
            isColumnHovered: isHovered,
            add: .compose(.column(container: taskContainerSelection, sectionName: section.name)),
            isComposing: $isComposing
        ) {
            activeTaskCards
            completedTaskSection
        }
    }

    @ViewBuilder
    private var activeTaskCards: some View {
        ForEach(activeTasks) { task in
            KanbanDraggableCard(
                task: task,
                showsDropIndicator: dragOverTaskID == task.id,
                onDropTargetedChanged: { isOver in
                    if isOver { dragOverTaskID = task.id }
                    else if dragOverTaskID == task.id { dragOverTaskID = nil }
                },
                onDropBefore: { items in
                    handleTaskDrop(items: items, before: task)
                }
            )
        }
    }

    @ViewBuilder
    private var completedTaskSection: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                completedTasksToggle

                if showDoneTasks {
                    completedTaskCards
                }
            }
            .padding(.top, 6)
        }
    }

    private var completedTasksToggle: some View {
        KanbanCompletedTasksToggle(count: completedTasks.count, isExpanded: showDoneTasks) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showDoneTasks.toggle()
            }
        }
    }

    private var completedTaskCards: some View {
        VStack(spacing: 6) {
            ForEach(completedTasks) { task in
                KanbanDraggableCard(task: task) { items in
                    handleTaskDrop(items: items, before: task)
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

    private func handleTaskDrop(items: [String], before target: AppTask) -> Bool {
        guard let payload = items.first,
              let droppedID = KanbanBoardSupport.taskID(from: payload),
              droppedID != target.id,
              let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
        moveTask(droppedTask, before: target)
        return true
    }

    /// The list this board belongs to — the "where does this go" half that the column's composer
    /// seeds, alongside `section.name`.
    private var taskContainerSelection: TaskContainerSelection {
        if let area {
            return .area(area.id)
        }
        if let project {
            return .project(project.id)
        }
        return .inbox
    }

    private func moveTask(_ task: AppTask, before target: AppTask?) {
        if let area {
            task.area = area
            task.project = nil
            task.context = area.context
        } else if let project {
            task.project = project
            task.area = nil
            task.context = project.resolvedContext
        } else {
            task.area = nil
            task.project = nil
        }
        task.sectionName = section.name

        KanbanBoardSupport.reorder(
            tasks.sorted { $0.order < $1.order },
            moving: task,
            before: target
        )
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
            editorColorOptions: CadenceColorPalette.offeredSectionColors(for: editorColorHex),
            editorName: $editorName,
            editorColorHex: $editorColorHex,
            editorDueDate: $editorDueDate,
            editorHasDueDate: $editorHasDueDate,
            onNameChanged: saveSectionChanges,
            onColorSelected: saveSectionChanges,
            onDueDateChanged: saveSectionChanges,
            onClearDate: {
                editorHasDueDate = false
                updateSection { config in
                    config.dueDate = ""
                }
            },
            onToggleCompletion: {
                toggleSectionCompletion()
                showEditor = false
            },
            onToggleArchive: {
                var shouldCancelActiveTasks = false
                updateSection { config in
                    let willArchive = !config.isArchived
                    config.isArchived.toggle()
                    shouldCancelActiveTasks = willArchive && !config.isCompleted
                    if !config.isArchived {
                        config.isCompleted = false
                    }
                }
                if shouldCancelActiveTasks {
                    TaskContainerLifecycleService.cancelRemainingActiveTasks(in: section, area: area, project: project, in: modelContext)
                }
                try? modelContext.save()
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

    /// **The Default column has no lifecycle, and this is where every route to one converges** —
    /// the header glyph, the editor's "Mark Section Completed", and Cmd+Return over the hovered
    /// column. All three are gated at their own site so the affordance is never *offered*; this
    /// guard is what makes a fourth route safe by default rather than only the three that exist.
    ///
    /// The damage it prevents is not a no-op. `Area.normalizedSectionConfigs` /
    /// `Project.normalizedSectionConfigs` force `isCompleted` and `isArchived` false on Default on
    /// every read *and* every write, so the flag is discarded — but `saveSection` has already run
    /// `TaskContainerLifecycleService.completeRemainingActiveTasks` by then and marked every open
    /// card in the column done. The column re-renders Active with its cards gone, which is worse
    /// than either refusing or persisting: the tasks stay done and nothing on screen says so
    /// (`docs/TODO.md` T-268).
    private func toggleSectionCompletion() {
        guard section.supportsLifecycle else { return }
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
        let current = currentSection()
        KanbanSectionStateSupport.saveSection(updatedSection: updatedSection, area: area, project: project)
        if updatedSection.isCompleted && current?.isCompleted != true {
            TaskContainerLifecycleService.completeRemainingActiveTasks(in: updatedSection, area: area, project: project, in: modelContext)
        } else if updatedSection.isArchived && !updatedSection.isCompleted && current?.isArchived != true {
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: updatedSection, area: area, project: project, in: modelContext)
        }
        try? modelContext.save()
    }

    private var isPendingCompletion: Bool {
        sectionCompletionAnimationManager.isPending(section)
    }

    // `sectionDueDateIsOverdue` used to live here and is now
    // `CadenceBoardColumnDueDatePlan.isOverdue`, so the iOS board gets the same answer instead of
    // no answer at all (T-331).
}
#endif
