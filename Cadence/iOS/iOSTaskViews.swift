#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    var body: some View {
        rowContent
            .padding(.horizontal, isRegularWidth ? 14 : 11)
            .padding(.vertical, isRegularWidth ? 12 : 9)
            .background(Theme.surfaceElevated.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous)
                    .stroke(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
            .onTapGesture {
                showDetail = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens task details")
            .sheet(isPresented: $showDetail) {
                iOSTaskDetailSheet(task: task)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                trailingSwipeActions
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                leadingSwipeActions
            }
            .contextMenu {
                taskContextMenu
            }
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
        HStack(alignment: .top, spacing: isRegularWidth ? 12 : 9) {
            completionButton
            taskSummary

            Image(systemName: "chevron.right")
                .font(.system(size: isRegularWidth ? 12 : 10, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.65))
                .padding(.top, 4)
        }
    }

    private var completionButton: some View {
        Button {
            toggleCompletion()
        } label: {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: isRegularWidth ? 19 : 16, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim.opacity(0.68))
                .frame(width: isRegularWidth ? 24 : 20, height: isRegularWidth ? 24 : 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")
    }

    private var taskSummary: some View {
        VStack(alignment: .leading, spacing: isRegularWidth ? 8 : 6) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: isRegularWidth ? 15 : 13, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .strikethrough(task.isDone, color: Theme.dim)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            taskBadges
            tagScroller
        }
    }

    private var taskBadges: some View {
        HStack(spacing: 6) {
            if task.status == .inProgress {
                taskBadge(
                    systemImage: "play.fill",
                    text: "In Progress",
                    color: Theme.blue
                )
            }

            priorityBadge

            if let goal = task.goal {
                taskBadge(
                    systemImage: "flag.fill",
                    text: goal.title.isEmpty ? "Milestone" : goal.title,
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
                    text: DateFormatters.relativeDate(from: task.dueDate),
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

    @ViewBuilder
    private var trailingSwipeActions: some View {
        Button {
            toggleCompletion()
        } label: {
            Label(task.isDone ? "Todo" : "Done",
                  systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
        }
        .tint(task.isDone ? Theme.blue : Theme.green)

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var leadingSwipeActions: some View {
        Button {
            scheduleToday()
        } label: {
            Label("Today", systemImage: "sun.max.fill")
        }
        .tint(Theme.amber)

        Button {
            scheduleTomorrow()
        } label: {
            Label("Tomorrow", systemImage: "calendar")
        }
        .tint(Theme.blue)

        Button {
            dueToday()
        } label: {
            Label("Due", systemImage: "flag.fill")
        }
        .tint(Theme.red)

        if !task.scheduledDate.isEmpty {
            Button {
                clearScheduledDate()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .tint(Theme.dim)
        }
    }

    @ViewBuilder
    private var taskContextMenu: some View {
        Button {
            showDetail = true
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }

        statusMenu
        priorityMenu
        doDateMenu
        dueDateMenu
        sectionMenu
        moveToListMenu

        Button {
            duplicateTask()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Task", systemImage: "trash")
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button {
                    setStatus(status)
                } label: {
                    Label(status.label, systemImage: status.systemImage)
                }
            }
        } label: {
            Label(task.status.label, systemImage: task.status.systemImage)
        }
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    setPriority(priority)
                } label: {
                    Label(priority.label, systemImage: priority == task.priority ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label("Priority: \(task.priority.label)", systemImage: "flag.fill")
        }
    }

    private var doDateMenu: some View {
        Menu {
            Button {
                scheduleToday()
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }

            Button {
                scheduleTomorrow()
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                scheduleNextWeek()
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    clearScheduledDate()
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Do Date", systemImage: "sun.max.fill")
        }
    }

    private var dueDateMenu: some View {
        Menu {
            Button {
                dueToday()
            } label: {
                Label("Today", systemImage: "flag.fill")
            }

            Button {
                dueTomorrow()
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                dueNextWeek()
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.dueDate.isEmpty {
                Button {
                    clearDueDate()
                } label: {
                    Label("Clear Due Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Due Date", systemImage: "flag.fill")
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        let names = availableSectionNames
        if names.count > 1 {
            Menu {
                ForEach(names, id: \.self) { section in
                    Button {
                        moveToSection(section)
                    } label: {
                        Label(section, systemImage: section.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame ? "checkmark.circle.fill" : "rectangle.split.3x1")
                    }
                }
            } label: {
                Label("Move Section", systemImage: "rectangle.split.3x1.fill")
            }
        }
    }

    private var moveToListMenu: some View {
        Menu {
            Button {
                moveToContainer(area: nil, project: nil)
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : "tray.fill")
            }

            if !activeAreas.isEmpty {
                Divider()

                ForEach(activeAreas) { area in
                    Button {
                        moveToContainer(area: area, project: nil)
                    } label: {
                        Label(area.name.isEmpty ? "Untitled Area" : area.name, systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : area.icon)
                    }
                }
            }

            if !activeProjects.isEmpty {
                Divider()

                ForEach(activeProjects) { project in
                    Button {
                        moveToContainer(area: nil, project: project)
                    } label: {
                        Label(project.name.isEmpty ? "Untitled Project" : project.name, systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : project.icon)
                    }
                }
            }
        } label: {
            Label("Move to List", systemImage: "folder.fill")
        }
    }

    private var priorityBadge: some View {
        taskBadge(
            systemImage: "circle.fill",
            text: task.priority.label,
            color: Theme.priorityColor(task.priority)
        )
    }

    private var isOverdue: Bool {
        !task.dueDate.isEmpty && task.dueDate < DateFormatters.todayKey()
    }

    private var estimateLabel: String {
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
    }

    private var scheduledDateLabel: String {
        if task.scheduledStartMin >= 0 {
            let time = TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)
            if task.scheduledDate == DateFormatters.todayKey() {
                return time
            }
            return "\(DateFormatters.relativeDate(from: task.scheduledDate)) at \(time)"
        }
        return DateFormatters.relativeDate(from: task.scheduledDate)
    }

    private var availableSectionNames: [String] {
        let rawNames = task.area?.sectionNames ?? task.project?.sectionNames ?? []
        let names = rawNames.isEmpty ? [TaskSectionDefaults.defaultName] : rawNames
        if names.contains(where: { $0.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame }) {
            return names
        }
        return names + [task.resolvedSectionName]
    }

    private func taskBadge(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }

    private func setStatus(_ status: TaskStatus) {
        CadenceTaskMutationSupport.setStatus(status, for: task, modelContext: modelContext)
    }

    private func setPriority(_ priority: TaskPriority) {
        CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext)
    }

    private func scheduleToday() {
        CadenceTaskMutationSupport.scheduleToday(task, modelContext: modelContext)
    }

    private func scheduleTomorrow() {
        CadenceTaskMutationSupport.scheduleTomorrow(task, modelContext: modelContext)
    }

    private func scheduleNextWeek() {
        CadenceTaskMutationSupport.scheduleNextWeek(task, modelContext: modelContext)
    }

    private func clearScheduledDate() {
        CadenceTaskMutationSupport.clearScheduledDate(task, modelContext: modelContext)
    }

    private func dueToday() {
        CadenceTaskMutationSupport.dueToday(task, modelContext: modelContext)
    }

    private func dueTomorrow() {
        CadenceTaskMutationSupport.dueTomorrow(task, modelContext: modelContext)
    }

    private func dueNextWeek() {
        CadenceTaskMutationSupport.dueNextWeek(task, modelContext: modelContext)
    }

    private func clearDueDate() {
        CadenceTaskMutationSupport.clearDueDate(task, modelContext: modelContext)
    }

    private func moveToSection(_ section: String) {
        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext)
    }

    private func moveToContainer(area: Area?, project: Project?) {
        CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        )
    }

    private func duplicateTask() {
        _ = try? CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext)
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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(CadenceTaskSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 11 : 9)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(Theme.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous)
                            .strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, isRegularWidth ? 11 : 9)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(showCompleted ? Theme.surfaceElevated.opacity(0.72) : Theme.surfaceElevated.opacity(0.36))
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(showCompleted ? 0.54 : 0.28), lineWidth: 1)
                    }
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
                .font(.system(size: isRegularWidth ? 15 : 13))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, isRegularWidth ? 13 : 10)
                .frame(minHeight: isRegularWidth ? 44 : 34)
                .background(Theme.surfaceElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: isRegularWidth ? 16 : 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isRegularWidth ? 44 : 34, height: isRegularWidth ? 44 : 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
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
