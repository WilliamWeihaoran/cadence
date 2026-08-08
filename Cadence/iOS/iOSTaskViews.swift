#if os(iOS)
import SwiftData
import SwiftUI

enum iOSTaskRowDensity {
    case regular
    case compact
}

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    var density: iOSTaskRowDensity = .regular
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isCompact: Bool {
        density == .compact
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    var body: some View {
        rowContent
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.35))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showDetail = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens task details")
            .sheet(isPresented: $showDetail) {
                iOSTaskDetailSheet(task: task)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                iOSTaskRowTrailingSwipeActions(
                    task: task,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                iOSTaskRowLeadingSwipeActions(task: task)
            }
            .contextMenu {
                iOSTaskRowContextMenu(
                    task: task,
                    allTasks: allTasks,
                    activeAreas: activeAreas,
                    activeProjects: activeProjects,
                    showDetail: $showDetail,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    pendingRecurrenceRule: $pendingRecurrenceRule
                )
            }
            .iOSTaskRowRecurrenceScopeDialog(
                task: task,
                allTasks: allTasks,
                pendingRecurrenceRule: $pendingRecurrenceRule
            )
            .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteTask)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
            .onAppear(perform: handlePendingDeepLink)
            .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
                handlePendingDeepLink()
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: isCompact ? 9 : (isRegularWidth ? 12 : 9)) {
            completionButton
            taskSummary

            Image(systemName: "chevron.right")
                .font(.system(size: isCompact ? 10 : (isRegularWidth ? 12 : 10), weight: .semibold))
                .foregroundStyle(rowTint.opacity(0.62))
                .padding(.top, 4)
        }
    }

    private var rowHorizontalPadding: CGFloat {
        if isCompact { return 11 }
        return isRegularWidth ? 14 : 11
    }

    private var rowVerticalPadding: CGFloat {
        if isCompact { return 8 }
        return isRegularWidth ? 12 : 9
    }

    private var completionButton: some View {
        Button {
            toggleCompletion()
        } label: {
            iOSTaskCompletionCircle(isDone: task.isDone, tint: rowTint)
                .frame(width: isCompact ? 20 : (isRegularWidth ? 24 : 20), height: isCompact ? 20 : (isRegularWidth ? 24 : 20))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")
    }

    private var taskSummary: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : (isRegularWidth ? 8 : 6)) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .strikethrough(task.isDone, color: Theme.dim)
                .lineLimit(isCompact ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: secondaryFontSize, weight: .medium))
                    .foregroundStyle(Theme.dim.opacity(task.isDone ? 0.58 : 0.82))
                    .lineLimit(isCompact ? 1 : (isRegularWidth ? 2 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            taskBadges

            if !isCompact {
                tagScroller
            }
        }
    }

    private var secondaryFontSize: CGFloat {
        if isCompact { return 10.5 }
        return isRegularWidth ? 12 : 11
    }

    private var taskBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isCompact ? 4 : (isRegularWidth ? 6 : 5)) {
                taskBadgeContent
            }
            .padding(.trailing, 1)
        }
    }

    private var secondaryLine: String? {
        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewLimit = isCompact ? 80 : (isRegularWidth ? 120 : 64)
        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: task.notes, limit: previewLimit)

        if !container.isEmpty && !preview.isEmpty {
            return "\(container) - \(preview)"
        }
        if !container.isEmpty {
            return container
        }
        if !preview.isEmpty {
            return preview
        }
        return nil
    }

    @ViewBuilder
    private var taskBadgeContent: some View {
        if task.status == .inProgress {
            taskBadge(
                systemImage: "play.fill",
                text: "In Progress",
                color: Theme.blue
            )
        }

        if task.priority != .none || !isCompact {
            priorityBadge
        }

        if task.recurrenceRule != .none {
            taskBadge(
                systemImage: task.recurrenceRule.systemImage,
                text: task.recurrenceRule.shortLabel,
                color: Theme.purple
            )
        }

        if CadenceTaskPresentationSupport.hasNotes(task) {
            taskBadge(
                systemImage: "doc.text",
                text: "Notes",
                color: Theme.dim
            )
        }

        if let subtaskProgress = CadenceTaskPresentationSupport.subtaskProgress(for: task) {
            taskBadge(
                systemImage: "checklist",
                text: isCompact ? subtaskProgress.compactLabel : subtaskProgress.label,
                color: subtaskProgress.completed == subtaskProgress.total ? Theme.green : Theme.dim
            )
        }

        if let goal = task.goal {
            taskBadge(
                systemImage: goal.icon,
                text: goal.title.isEmpty ? "Goal" : goal.title,
                color: Color(hex: goal.colorHex)
            )
        }

        if !task.scheduledDate.isEmpty {
            taskBadge(
                systemImage: task.scheduledStartMin >= 0 ? "clock.fill" : "sun.max.fill",
                text: scheduledDateLabel,
                color: task.scheduledDate == DateFormatters.todayKey() ? Theme.amber : Theme.dim
            )
        }

        if !task.dueDate.isEmpty {
            taskBadge(
                systemImage: "flag.fill",
                text: CadenceTaskPresentationSupport.dueDateLabel(for: task),
                color: isOverdue ? Theme.red : Theme.dim
            )
        }

        if task.estimatedMinutes > 0 {
            taskBadge(
                systemImage: "clock",
                text: estimateLabel,
                color: Theme.dim
            )
        }
    }

    @ViewBuilder
    private var tagScroller: some View {
        if !task.sortedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(task.sortedTags.prefix(4)) { tag in
                        iOSTagChip(tag: tag)
                    }

                    if task.sortedTags.count > 4 {
                        Text("+\(task.sortedTags.count - 4)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Theme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var priorityBadge: some View {
        taskBadge(
            systemImage: "circle.fill",
            text: task.priority.label,
            color: Theme.priorityColor(task.priority)
        )
    }

    private var rowTint: Color {
        switch task.priority {
        case .high:
            return Theme.red
        case .medium:
            return Theme.amber
        case .low:
            return Theme.blue
        case .none:
            if !task.containerName.isEmpty {
                return Color(hex: task.containerColor)
            }
            return Theme.blue
        }
    }

    private var isOverdue: Bool {
        !task.dueDate.isEmpty && task.dueDate < DateFormatters.todayKey()
    }

    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes)
    }

    private var scheduledDateLabel: String {
        CadenceTaskPresentationSupport.scheduledDateLabel(for: task)
    }

    private func taskBadge(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
            Text(text)
                .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, isCompact ? 5 : 6)
        .padding(.vertical, isCompact ? 2 : 3)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }

    private func deleteTask() {
        CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        showDetail = true
        deepLinkManager.clearPendingTask(task.id)
    }
}

struct iOSTaskListRow: View {
    @Bindable var task: AppTask
    var opacity: Double = 1

    var body: some View {
        iOSTaskRow(task: task)
            .opacity(opacity)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct iOSTaskSectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .kerning(0.8)
            .textCase(.uppercase)
            .padding(.top, 6)
    }
}

struct iOSTaskViewOptionsBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    var completedCount: Int
    @State private var showSortPicker = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showSortPicker = true
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 12 : 10)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(Theme.blue.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSortPicker) {
                iOSChoicePopoverList(
                    rows: CadenceTaskSortMode.allCases.map { mode in
                        iOSChoiceRow(value: mode, title: mode.title, color: Theme.blue)
                    },
                    selection: $sortMode,
                    isPresented: $showSortPicker
                )
            }

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, isRegularWidth ? 12 : 10)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(showCompleted ? Theme.surfaceElevated.opacity(0.72) : Theme.surfaceElevated.opacity(0.36))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)
            .opacity(completedCount == 0 ? 0.45 : 1)
        }
        .tint(Theme.blue)
    }
}

struct iOSTaskCaptureBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let placeholder: String
    @Binding var title: String
    let action: () -> Void

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: isRegularWidth ? 15 : 15))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, isRegularWidth ? 13 : 12)
                .frame(minHeight: isRegularWidth ? 44 : 42)
                .background(Theme.surfaceElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 11, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: isRegularWidth ? 16 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isRegularWidth ? 44 : 42, height: isRegularWidth ? 44 : 42)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 11, style: .continuous))
            }
            .disabled(TaskTitleSupport.isEmpty(title))
            .opacity(TaskTitleSupport.isEmpty(title) ? 0.45 : 1)
        }
    }
}

let iOSPanelHeaderHeight: CGFloat = 92

struct iOSPanelHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    var count: Int? = nil

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: isRegularWidth ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: isRegularWidth ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 10 : 8)
                    .padding(.vertical, isRegularWidth ? 6 : 4)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, isRegularWidth ? 20 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
    }
}

struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
#endif
