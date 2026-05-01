#if os(macOS)
import SwiftUI

struct InboxTaskGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [AppTask]
    let color: Color
}

struct InboxHeaderView: View {
    let activeTaskCount: Int
    let onNewTask: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TASKS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Inbox")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if activeTaskCount > 0 {
                        Text("\(activeTaskCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button(action: onNewTask) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("New Task").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Theme.surface)
    }
}

struct InboxCaptureBarView: View {
    @Binding var newTitle: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(isFocused ? Theme.blue : Theme.dim)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

            TextField("Capture a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .onSubmit { onSubmit() }

            if !newTitle.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.cadencePlain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.surfaceElevated)
        .animation(.easeInOut(duration: 0.15), value: newTitle.isEmpty)
    }
}

struct InboxControlsBarView: View {
    @Binding var sortField: TaskSortField
    @Binding var sortDirection: TaskSortDirection
    @Binding var groupingMode: TaskGroupingMode

    var body: some View {
        HStack(spacing: 8) {
            CadenceEnumPickerBadge(title: "Sort", selection: $sortField)
            CadenceEnumPickerBadge(title: "Order", selection: $sortDirection)
            CadenceEnumPickerBadge(title: "Group", selection: $groupingMode)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }
}

struct InboxTaskGroupSectionView: View {
    let group: InboxTaskGroup
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    @Binding var dragOverTaskID: UUID?
    let onReorderTask: (UUID, UUID) -> Void

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: group.title,
                isCollapsed: false,
                overdueCount: nil,
                regularCount: group.tasks.count,
                accent: group.color,
                isToggleEnabled: false,
                onToggle: { }
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            ForEach(group.tasks) { task in
                TaskListInteractiveRow(
                    task: task,
                    style: .standard,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    dragOverTaskID: $dragOverTaskID,
                    taskDragPayload: { "listTask:\($0.id.uuidString)" },
                    onDropOnTaskPayload: { payload, targetTask in
                        guard payload.hasPrefix("listTask:"),
                              let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                              droppedID != targetTask.id else { return false }
                        onReorderTask(droppedID, targetTask.id)
                        return true
                    }
                )
            }
        }
    }
}

struct InboxCompletedSectionView: View {
    let tasks: [AppTask]
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: "Completed",
                count: tasks.count,
                isCollapsed: isCollapsed,
                accent: Theme.green,
                onToggle: onToggle
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(tasks) { task in
                    TaskListDisplayRow(
                        task: task,
                        style: .standard,
                        contexts: contexts,
                        areas: areas,
                        projects: projects
                    )
                }
            }
        }
    }
}

struct InboxEmptyStateView: View {
    @FocusState.Binding var captureFocused: Bool

    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.blue.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "tray")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.blue.opacity(0.6))
                }
                VStack(spacing: 6) {
                    Text("Inbox is empty")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Tasks without a list land here.\nCapture something to get started.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                Button {
                    captureFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Capture a task")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
