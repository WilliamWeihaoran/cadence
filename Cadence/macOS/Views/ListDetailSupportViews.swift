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
    let allTasks: [AppTask]
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let onReorderTask: (UUID, UUID) -> Void

    private let headerHorizontalInset: CGFloat = 24
    private let taskLeadingInset: CGFloat = 52
    private let taskTrailingInset: CGFloat = 12

    var body: some View {
        Group {
            ListTasksGroupHeader(
                title: group.title,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: group.accent,
                onToggle: onToggle
            )
            .padding(.horizontal, headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(group.tasks) { task in
                    MacTaskRow(task: task, style: .list)
                        .padding(.leading, taskLeadingInset)
                        .padding(.trailing, taskTrailingInset)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                        .overlay(alignment: .top) {
                            if dragOverTaskID == task.id {
                                Rectangle()
                                    .fill(Theme.blue)
                                    .frame(height: 2)
                                    .padding(.leading, taskLeadingInset)
                                    .padding(.trailing, taskTrailingInset)
                                    .transition(.opacity)
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
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void

    private let headerHorizontalInset: CGFloat = 24
    private let taskLeadingInset: CGFloat = 52
    private let taskTrailingInset: CGFloat = 12

    var body: some View {
        Group {
            ListTasksGroupHeader(
                title: "Completed",
                count: tasks.count,
                isCollapsed: isCollapsed,
                accent: Theme.green,
                onToggle: onToggle
            )
            .padding(.horizontal, headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .list)
                        .padding(.leading, taskLeadingInset)
                        .padding(.trailing, taskTrailingInset)
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

private struct ListTasksGroupHeader: View {
    let title: String
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    var accent: Color = Theme.dim
    let onToggle: () -> Void

    init(
        title: String,
        isCollapsed: Bool,
        overdueCount: Int? = nil,
        regularCount: Int,
        accent: Color = Theme.dim,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.overdueCount = overdueCount
        self.regularCount = regularCount
        self.accent = accent
        self.onToggle = onToggle
    }

    init(
        title: String,
        count: Int,
        isCollapsed: Bool,
        accent: Color,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            title: title,
            isCollapsed: isCollapsed,
            overdueCount: nil,
            regularCount: count,
            accent: accent,
            onToggle: onToggle
        )
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3, height: 18)

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let overdueCount, overdueCount > 0 {
                    HStack(spacing: 3) {
                        Text("\(overdueCount)")
                            .foregroundStyle(Theme.red)
                        Text("/")
                            .foregroundStyle(Theme.dim.opacity(0.7))
                    }
                    .font(.system(size: 11, weight: .semibold))
                }

                Text("\(regularCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 4)
                    .background(accent.opacity(0.16))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated.opacity(0.62))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.borderSubtle.opacity(0.95))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .onTapGesture(count: 2, perform: onToggle)
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
