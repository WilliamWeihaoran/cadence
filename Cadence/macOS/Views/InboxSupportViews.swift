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
        DesktopPageHeader(
            eyebrow: "Tasks",
            title: "Inbox",
            subtitle: "Unsorted tasks and Apple Reminders land here.",
            count: activeTaskCount
        ) {
            DesktopPrimaryActionButton(title: "New Task", systemImage: "plus", action: onNewTask)
        }
    }
}

struct InboxAppleRemindersSectionView: View {
    let reminders: [AppleReminderItem]
    let isAuthorized: Bool
    let isDenied: Bool
    let isLoading: Bool
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
    let onComplete: (String) -> Void

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: "Apple Reminders",
                isCollapsed: false,
                regularCount: reminders.count,
                accent: Theme.purple,
                isToggleEnabled: false,
                onToggle: { }
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if isAuthorized {
                if isLoading && reminders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading reminders...")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
                } else {
                    ForEach(reminders) { reminder in
                        AppleReminderTaskRow(reminder: reminder, onComplete: onComplete)
                            .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                            .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init())
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else {
                AppleRemindersAccessRow(
                    isDenied: isDenied,
                    action: isDenied ? onOpenSettings : onRequestAccess
                )
                .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(.init())
            }
        }
    }
}

private struct AppleReminderTaskRow: View {
    let reminder: AppleReminderItem
    let onComplete: (String) -> Void
    @State private var isHovered = false
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(priorityColor)
                .frame(width: 3)
                .padding(.leading, 8)
                .padding(.vertical, 3)

            Button(action: complete) {
                ZStack {
                    Circle()
                        .strokeBorder(isCompleting ? Theme.green : Theme.muted, lineWidth: 1.8)
                    if isCompleting {
                        Circle().fill(Theme.green)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.cadencePlain)
            .disabled(!reminder.allowsCompletion || isCompleting)
            .help(reminder.allowsCompletion ? "Complete in Apple Reminders" : "This reminder list is read-only")
            .padding(.horizontal, 8)

            Text(reminder.title.isEmpty ? "Untitled Reminder" : reminder.title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let dueDate = reminder.dueDate {
                reminderDueDateBadge(dueDate)
            }

            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 9, weight: .semibold))
                Text(reminder.listTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.purple)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.leading, 6)
            .padding(.trailing, 6)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Theme.purple.opacity(0.06) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.purple.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.22)).frame(height: 0.5)
        }
        .opacity(isCompleting ? 0.65 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isCompleting)
    }

    private var priorityColor: Color {
        switch reminder.priority {
        case 1...4: return Theme.red
        case 5: return Theme.amber
        case 6...9: return Theme.blue
        default: return Theme.dim
        }
    }

    private func reminderDueDateBadge(_ date: Date) -> some View {
        let dateKey = DateFormatters.dateKey(from: date)
        let dayOffset = DateFormatters.dayOffset(from: dateKey)
        let color = (dayOffset ?? 0) < 0 ? Theme.red : ((dayOffset ?? 1) == 0 ? Theme.amber : Theme.dim)

        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
            Text(DateFormatters.relativeDate(from: dateKey))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func complete() {
        guard reminder.allowsCompletion, !isCompleting else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            isCompleting = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onComplete(reminder.id)
        }
    }
}

private struct AppleRemindersAccessRow: View {
    let isDenied: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.purple)
                .frame(width: 32, height: 32)
                .background(Theme.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(isDenied ? "Reminders access is off" : "Show Apple Reminders in Inbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(isDenied
                     ? "Allow Cadence in Privacy & Security to show your active reminders."
                     : "Cadence can display active reminders and mark them complete here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 12)

            CadenceActionButton(
                title: isDenied ? "Open Settings" : "Connect",
                role: .primary,
                size: .compact,
                action: action
            )
        }
        .padding(12)
        .background(Theme.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.purple.opacity(0.16), lineWidth: 1)
        }
    }
}

struct InboxControlsBarView: View {
    @Binding var sortField: TaskSortField
    @Binding var sortDirection: TaskSortDirection
    @Binding var groupingMode: TaskGroupingMode

    var body: some View {
        DesktopControlBar {
            CadenceEnumPickerBadge(title: "Sort", selection: $sortField)
            CadenceEnumPickerBadge(title: "Order", selection: $sortDirection)
            CadenceEnumPickerBadge(title: "Group", selection: $groupingMode)
        }
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
    let onNewTask: () -> Void

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
                    Text("Unsorted tasks and Apple Reminders appear here.\nCreate something to get started.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                Button(action: onNewTask) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New Task")
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
