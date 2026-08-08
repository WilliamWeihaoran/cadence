#if os(macOS)
import SwiftUI

struct TaskListKanbanColumn: View {
    let title: String
    let icon: String
    let color: Color
    let tasks: [AppTask]
    let universeTasks: [AppTask]
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let container: TaskContainerSelection
    let onAssignTask: (AppTask) -> Void

    @Environment(TaskCreationManager.self) private var taskCreationManager
    @State private var isTargeted = false
    @State private var dragOverTaskID: UUID?
    @State private var isHovered = false

    private var sortedTasks: [AppTask] {
        tasks.taskSorted(by: sortField, direction: sortDirection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            columnTaskScroll
        }
        .frame(width: kanbanColumnWidth)
        // The column has no fill or border any more, so it needs an explicit
        // transparent-but-hit-testable region: without this the drop destination and the
        // column hover state would only register on top of actual glyphs.
        // `columnDropSurface` supplies `Color.clear` + `contentShape`, and the outer
        // `contentShape` guarantees the whole 236pt column is a drop target.
        .background(columnDropSurface)
        .contentShape(Rectangle())
        .zIndex(isTargeted ? 2 : 0)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let droppedID = taskID(from: payload),
                  let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
            moveTask(droppedTask, before: nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .onHover { isHovered = $0 }
    }

    /// Column containers are gone, so the header is the only place the list's color
    /// survives — a single 7pt dot. Everything else is neutral, quiet type.
    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text("\(sortedTasks.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var columnTaskScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                taskCards
                // Replaces the old header "+" chip; always last in the column.
                KanbanColumnAddTaskRow(isColumnHovered: isHovered, action: presentNewTaskPanel)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keeps the empty area under the last card a live drop target now that the
            // column itself paints nothing.
            .contentShape(Rectangle())
        }
        .frame(minHeight: 200)
        .background(
            Color.clear.contentShape(Rectangle())
        )
    }

    @ViewBuilder
    private var taskCards: some View {
        ForEach(sortedTasks) { task in
            KanbanCard(task: task)
                .overlay(alignment: .top) {
                    if dragOverTaskID == task.id {
                        Rectangle()
                            .fill(Theme.blue)
                            .frame(height: 2)
                            .transition(.opacity)
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
                    if isOver {
                        dragOverTaskID = task.id
                    } else if dragOverTaskID == task.id {
                        dragOverTaskID = nil
                    }
                }
        }
    }

    /// The column is containerless at rest: no fill, no stroke. This layer only supplies a
    /// transparent hit-test region plus the *transient* drag-over wash, so a wall of
    /// columns never reads as a wall of color.
    @ViewBuilder
    private var columnDropSurface: some View {
        ZStack {
            Color.clear

            if isTargeted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .fill(color.opacity(0.07))
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .strokeBorder(
                        color.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.14), value: isTargeted)
    }

    private func presentNewTaskPanel() {
        taskCreationManager.present(container: container)
    }

    private func moveTask(_ task: AppTask, before target: AppTask?) {
        onAssignTask(task)

        var columnTasks = sortedTasks
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

    private func taskID(from payload: String) -> UUID? {
        KanbanBoardSupport.taskID(from: payload)
    }
}
#endif
