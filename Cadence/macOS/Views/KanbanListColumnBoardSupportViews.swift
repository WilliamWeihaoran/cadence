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

    private var sortedTasks: [AppTask] {
        tasks.taskSorted(by: sortField, direction: sortDirection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Theme.borderSubtle.opacity(0.82))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if sortedTasks.isEmpty {
                        emptyColumn
                    } else {
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
                }
                .padding(8)
            }
            .frame(minHeight: 360)
        }
        .frame(width: kanbanColumnWidth)
        .background(columnBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? color.opacity(0.66) : color.opacity(0.22), lineWidth: isTargeted ? 1.4 : 1)
        }
        .scaleEffect(isTargeted ? 1.012 : 1)
        .offset(y: isTargeted ? -4 : 0)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let droppedID = taskID(from: payload),
                  let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
            moveTask(droppedTask, before: nil)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(sortedTasks.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.surfaceElevated.opacity(0.95))
                .clipShape(Capsule())

            Button {
                taskCreationManager.present(container: container)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var emptyColumn: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color.opacity(0.68))
            Text("No active tasks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Theme.surface.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    private var columnBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(color.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surface.opacity(0.84))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isTargeted ? 0.028 : 0.012))
            }
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
