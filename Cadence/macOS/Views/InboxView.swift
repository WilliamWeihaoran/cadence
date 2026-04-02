#if os(macOS)
import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var newTitle = ""
    @State private var isCompletedCollapsed = true
    @AppStorage("inboxSortField") private var sortField: TaskSortField = .custom
    @AppStorage("inboxSortDirection") private var sortDirection: TaskSortDirection = .ascending
    @AppStorage("inboxGroupingMode") private var groupingMode: TaskGroupingMode = .none
    struct FrozenInboxGroup {
        let id: String
        let title: String
        let tasks: [AppTask]
        let color: Color
    }

    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroups: [FrozenInboxGroup]? = nil
    @State private var dragOverTaskID: UUID? = nil
    @FocusState private var captureFocused: Bool

    private var inboxTasks: [AppTask] {
        allTasks.filter { $0.area == nil && $0.project == nil && !$0.isCancelled }
    }
    private var activeTasks: [AppTask] {
        let sorted = inboxTasks.filter { !$0.isDone }.taskSorted(by: sortField, direction: sortDirection)
        guard let frozen = frozenTaskOrder else { return sorted }
        let activeFrozen = frozen.filter { !$0.isDone }
        let frozenIDs = Set(activeFrozen.map(\.id))
        return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
    }
    private var doneTasks: [AppTask] { inboxTasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    private var groupedActiveTasks: [(id: String, title: String, tasks: [AppTask], color: Color)] {
        if let frozenGroups {
            return frozenGroups.compactMap { group in
                let activeTasks = group.tasks.filter { !$0.isDone }
                guard !activeTasks.isEmpty else { return nil }
                return (group.id, group.title, activeTasks, group.color)
            }
        }
        let todayKey = DateFormatters.todayKey()
        switch groupingMode {
        case .none:
            return [("all", "Tasks", activeTasks, Theme.dim)]
        case .byDate:
            let overdue = activeTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
            let doToday = activeTasks.filter { $0.scheduledDate == todayKey }
            let scheduled = activeTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey }
            let unscheduled = activeTasks.filter { $0.scheduledDate.isEmpty || $0.scheduledStartMin < 0 }
            return [
                ("overdue", "Overdue", overdue, Theme.red),
                ("do-today", "Do Today", doToday, Theme.blue),
                ("scheduled", "Scheduled", scheduled, Theme.dim),
                ("unscheduled", "Unscheduled", unscheduled, Theme.amber)
            ].filter { !$0.tasks.isEmpty }
        case .byList:
            return [("inbox", "Inbox", activeTasks, Theme.dim)]
        case .byPriority:
            return TaskPriority.allCases.reversed().compactMap { p in
                let bucket = activeTasks.filter { $0.priority == p }
                return bucket.isEmpty ? nil : ("p-\(p.rawValue)", p.label, bucket, Theme.priorityColor(p))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.borderSubtle)
            captureBar
            Divider().background(Theme.borderSubtle)
            controlsBar
            Divider().background(Theme.borderSubtle)

            if activeTasks.isEmpty && doneTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedActiveTasks, id: \.id) { group in
                        CollapsibleTaskGroupHeader(
                            title: group.title,
                            isCollapsed: false,
                            overdueCount: nil,
                            regularCount: group.tasks.count,
                            accent: group.color,
                            onToggle: { }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())

                        ForEach(group.tasks) { task in
                            MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
                                .listRowInsets(.init())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                                .overlay(alignment: .top) {
                                    if dragOverTaskID == task.id {
                                        Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                                .draggable("listTask:\(task.id.uuidString)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let payload = items.first,
                                          payload.hasPrefix("listTask:"),
                                          let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                                          droppedID != task.id else { return false }
                                    reorderTask(droppedID: droppedID, targetID: task.id)
                                    return true
                                } isTargeted: { isOver in
                                    if isOver { dragOverTaskID = task.id }
                                    else if dragOverTaskID == task.id { dragOverTaskID = nil }
                                }
                        }
                    }

                    if !doneTasks.isEmpty {
                        CompletedSectionHeader(
                            count: doneTasks.count,
                            isCollapsed: isCompletedCollapsed,
                            onToggle: { isCompletedCollapsed.toggle() }
                        )
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 6)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init())
                        if !isCompletedCollapsed {
                            ForEach(doneTasks) { task in
                                MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .cadenceSoftPageBounce()
                .background(Theme.bg)
                .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.bg)
        .onAppear {
            isCompletedCollapsed = true
        }
        .background {
            HoverFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroups,
                naturalTasks: inboxTasks.filter { !$0.isDone }.taskSorted(by: sortField, direction: sortDirection),
                groupSnapshot: groupedActiveTasks.map { FrozenInboxGroup(id: $0.id, title: $0.title, tasks: $0.tasks, color: $0.color) }
            )
        }
    }

    private var controlsBar: some View {
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

    // MARK: - Header

    private var header: some View {
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
                    if !activeTasks.isEmpty {
                        Text("\(activeTasks.count)")
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
            Button {
                taskCreationManager.present()
            } label: {
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

    // MARK: - Capture Bar

    private var captureBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(captureFocused ? Theme.blue : Theme.dim)
                .animation(.easeInOut(duration: 0.15), value: captureFocused)

            TextField("Capture a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($captureFocused)
                .onSubmit { captureTask() }

            if !newTitle.isEmpty {
                Button(action: captureTask) {
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

    // MARK: - Empty State

    private var emptyState: some View {
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

    // MARK: - Actions

    private func captureTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.order = activeTasks.count
        modelContext.insert(task)
        newTitle = ""
    }

    private func reorderTask(droppedID: UUID, targetID: UUID) {
        var sorted = activeTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, t) in sorted.enumerated() { t.order = i }
        }
    }

}

private struct HoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    @Binding var frozenGroups: [InboxView.FrozenInboxGroup]?
    let naturalTasks: [AppTask]
    let groupSnapshot: [InboxView.FrozenInboxGroup]
    @State private var isPointerInsideSurface = false
    private let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    if frozenOrder == nil { frozenOrder = naturalTasks }
                    if frozenGroups == nil { frozenGroups = groupSnapshot }
                } else if !isPointerInsideSurface, frozenOrder != nil || frozenGroups != nil {
                    withAnimation(releaseAnimation) {
                        frozenOrder = nil
                        frozenGroups = nil
                    }
                }
            }
            .onHover { isPointerInsideSurface = $0 }
    }
}

#endif
