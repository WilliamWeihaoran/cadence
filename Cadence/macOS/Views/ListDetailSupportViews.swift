#if os(macOS)
import SwiftUI

struct ListTasksGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
}

struct ListTasksGroupSectionView: View {
    let group: ListTasksGroup
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let onReorderTask: (UUID, UUID) -> Void

    var body: some View {
        Group {
            CollapsibleTaskGroupHeader(
                title: group.title,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: group.accent,
                onToggle: onToggle
            )
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(group.tasks) { task in
                    MacTaskRow(task: task, style: .list)
                        .padding(.leading, 16)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                        .overlay(alignment: .top) {
                            if dragOverTaskID == task.id {
                                Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 16).transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                        .draggable("listTask:\(task.id.uuidString)")
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first,
                                  payload.hasPrefix("listTask:"),
                                  let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                                  droppedID != task.id else { return false }
                            onReorderTask(droppedID, task.id)
                            return true
                        } isTargeted: { isOver in
                            if isOver { dragOverTaskID = task.id }
                            else if dragOverTaskID == task.id { dragOverTaskID = nil }
                        }
                }
            }
        }
    }
}

struct ListTasksCompletedSectionView: View {
    let tasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Group {
            CompletedSectionHeader(
                count: tasks.count,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .list)
                        .padding(.leading, 16)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }
}

struct ListLogView: View {
    let tasks: [AppTask]

    private var doneTasks: [AppTask] {
        tasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var body: some View {
        ZStack {
            Theme.bg

            if doneTasks.isEmpty {
                EmptyStateView(message: "No completed tasks", subtitle: "Completed tasks will appear here", icon: "checkmark.circle")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(doneTasks.count) COMPLETED")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .kerning(0.8)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(doneTasks) { task in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.dim)
                                        .strikethrough(true, color: Theme.dim)
                                    if !task.dueDate.isEmpty {
                                        Text(task.dueDate)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.dim.opacity(0.6))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(height: 0.5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
    }
}

struct TabButton: View {
    let tab: ListDetailPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            .frame(minWidth: 78, minHeight: 34)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
