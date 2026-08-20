#if os(macOS)
import SwiftUI

/// One of Cadence's **two** kanban column implementations: this one renders the *list* columns
/// of the All Tasks board. The other is `ListSectionKanbanColumn` in
/// `KanbanSectionColumnView.swift`, which renders the *section* columns of a list/project board.
/// The two must stay visually identical — all shared chrome lives in
/// `KanbanColumnSupportViews.swift` / `KanbanBoardSupport.swift`, so change it there, not here.
struct TaskListKanbanColumn: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    let universeTasks: [AppTask]
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let container: TaskContainerSelection
    let onAssignTask: (AppTask) -> Void

    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @State private var isTargeted = false
    @State private var dragOverTaskID: UUID?
    @State private var isHovered = false
    @State private var isComposing = false
    @State private var frozenTasks: [AppTask]? = nil

    private var unfrozenSortedTasks: [AppTask] {
        tasks.taskSorted(by: sortField, direction: sortDirection)
    }

    /// Hovering a card must not let the board resort rows out from under the cursor.
    private var sortedTasks: [AppTask] {
        applyFrozenTaskOrder(unfrozenSortedTasks, frozen: frozenTasks)
    }

    private var columnHoverID: String {
        switch container {
        case .inbox:
            return "kanban-list-column-inbox"
        case .area(let id):
            return "kanban-list-column-area-\(id.uuidString)"
        case .project(let id):
            return "kanban-list-column-project-\(id.uuidString)"
        }
    }

    var body: some View {
        columnBody
            .background {
                KanbanFreezeObserver(
                    frozenTasks: $frozenTasks,
                    columnTaskIDs: Set(unfrozenSortedTasks.map(\.id)),
                    capturedTasks: unfrozenSortedTasks
                )
            }
    }

    private var columnBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            columnTaskScroll
        }
        .kanbanColumnChrome(tint: color, isTargeted: isTargeted)
        .zIndex(isTargeted ? 2 : 0)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let droppedID = KanbanBoardSupport.taskID(from: payload),
                  let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
            moveTask(droppedTask, before: nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredKanbanColumnManager.beginHovering(id: columnHoverID) {
                    isComposing = true
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: columnHoverID)
            }
        }
    }

    private var header: some View {
        CadenceBoardColumnHeader(dotColor: color, title: title, count: sortedTasks.count)
    }

    /// List columns intentionally do *not* name a section — only section columns do — so the
    /// composer opens on the column's list with the default section, which is what this column's
    /// old create-sheet call did by omission.
    private var columnTaskScroll: some View {
        KanbanColumnScroll(
            isColumnHovered: isHovered,
            add: .compose(.column(container: container, sectionName: TaskSectionDefaults.defaultName)),
            isComposing: $isComposing
        ) {
            taskCards
        }
    }

    @ViewBuilder
    private var taskCards: some View {
        ForEach(sortedTasks) { task in
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

    private func handleTaskDrop(items: [String], before target: AppTask) -> Bool {
        guard let payload = items.first,
              let droppedID = KanbanBoardSupport.taskID(from: payload),
              droppedID != target.id,
              let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
        moveTask(droppedTask, before: target)
        return true
    }

    private func moveTask(_ task: AppTask, before target: AppTask?) {
        onAssignTask(task)
        // Deliberately the *unfrozen* ordering: the hover freeze is a display-only concern and
        // must never be what gets written back into `order`.
        KanbanBoardSupport.reorder(unfrozenSortedTasks, moving: task, before: target)
    }
}
#endif
