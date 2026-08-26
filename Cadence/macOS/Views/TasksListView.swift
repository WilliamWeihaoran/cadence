#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

/// One section of the merged Tasks list: a header, its rows, and what a task dropped on the header
/// becomes.
private struct TasksListSection: Identifiable {
    let id: String
    let title: String
    let accent: Color
    /// The `TasksPanelSupport.assignTask` key a drop on this header applies, or `nil` when the
    /// section names nothing a task can be moved *into* — Overdue and Due Today are defined by a
    /// day that has already passed, so a drop there would light up and do nothing.
    let dropKey: String?
    let tasks: [AppTask]
    /// Set only for `.byList` grouping, where the header carries the list's icon and its context's.
    let listGroup: TodayTaskGroup?
}

/// **The** macOS task-collection list. All Tasks and Inbox, one implementation, one `scope`.
///
/// These were two files — `AllTasksListView` and `InboxView` — over one universe of work: Inbox is
/// All Tasks with a single predicate (`area == nil && project == nil`), which is why the All Tasks
/// *board* had already merged them by rendering Inbox as one of its list columns. The list halves
/// had drifted in every dimension nobody decided:
///
/// - **Scroll container.** All Tasks drew `ScrollView` + `LazyVStack`; Inbox drew a `List` with
///   every service it renders switched off row by row (`listRowBackground(.clear)`,
///   `listRowSeparator(.hidden)`, `listRowInsets(.init())`). The `LazyVStack` won, for the reason
///   `iOSTaskCollectionPage` gives at length on the other platform: nothing was being bought.
/// - **Group headers.** All Tasks' collapsed; Inbox's were pinned open (`isToggleEnabled: false`)
///   for no stated reason. Collapsible everywhere.
/// - **Date buckets.** Inbox used the shared `CadenceTaskQuerySupport.dateDisplayGroups` — Overdue,
///   Due Today, Do Today, Scheduled, Unscheduled — and so does the area/project Tasks tab. All
///   Tasks hand-rolled three of its own. Two of the three surfaces already agreed; All Tasks was
///   the odd one out, so it moves.
/// - **Drag decode.** Inbox took the strict `listTask:` decode, All Tasks the lenient one that also
///   accepts a bare UUID (which the kanban card and the month-grid chip really do emit). Lenient
///   wins here because the dropped id is then looked up in this surface's *own* universe, which is
///   a stronger check than the prefix was: a foreign task fails the lookup and the drop is refused.
///
/// What is scope-specific is stated as such and nothing else: the universe, the empty state, and
/// the Apple Reminders strip.
struct TasksListView: View {
    let scope: CadenceTasksPageScope
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let groupingMode: TaskGroupingMode

    @Environment(\.modelContext) private var modelContext
    @Environment(RemindersManager.self) private var remindersManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var collapsedSectionIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var dragOverTaskID: UUID?
    @State private var frozenTaskOrder: [AppTask]? = nil

    private var todayKey: String { DateFormatters.todayKey() }

    /// What this page offers, asked of the surface rather than decided here (T-290). `scope.surface`
    /// is the desktop twin of `CadenceTaskCollection.surface`, which iOS's one page for both scopes
    /// already reads.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: scope.surface)
    }

    /// The scope, and the only thing it decides about the rows.
    ///
    /// All Tasks hides work inside a completed or archived list, the same scope its sidebar count
    /// uses. Inbox's predicate makes that moot — a task with no list is always in an active
    /// container — so the two filters compose rather than compete.
    private var visibleTaskUniverse: [AppTask] {
        switch scope {
        case .all: return allTasks.filter(\.isInActiveContainer)
        case .inbox: return CadenceTaskQuerySupport.inboxTasks(from: allTasks)
        }
    }

    private var naturalActiveTasks: [AppTask] {
        CadenceTaskQuerySupport.openTasks(from: visibleTaskUniverse)
            .taskSorted(by: sortField, direction: sortDirection)
    }

    private var activeTasks: [AppTask] {
        applyFrozenTaskOrder(naturalActiveTasks, frozen: frozenTaskOrder)
    }

    /// The logbook, through `CadenceTaskSurfaceOptions` on the **desktop** tier, which is uncapped.
    /// The value's own doc carries the argument; the short of it is that this section is the only
    /// place a Mac lists finished work, `completedTaskCount` beside it states the true total, and
    /// there is no "show more" to reach the rest behind a cap.
    private var completedTasks: [AppTask] {
        CadenceTaskSurfaceOptions.completedRows(
            from: visibleTaskUniverse
                .filter { $0.isDone || $0.isCancelled }
                .taskCompletionSorted(),
            tier: .desktop
        )
    }

    private var completedTaskCount: Int {
        visibleTaskUniverse.reduce(into: 0) { count, task in
            if task.isDone || task.isCancelled { count += 1 }
        }
    }

    private var tasksByID: [UUID: AppTask] {
        Dictionary(uniqueKeysWithValues: visibleTaskUniverse.map { ($0.id, $0) })
    }

    /// The Reminders strip is Inbox's and only Inbox's. It is what makes an inbox an *inbox* —
    /// unprocessed things, including ones captured outside Cadence — and it is the only place in
    /// the app that shows Apple Reminders at all. It stays behind the scope, not behind the
    /// destination, so the merge does not quietly delete it.
    private var showsRemindersSection: Bool {
        CadenceTasksPageScope.showsRemindersStrip(
            scope: scope,
            isAuthorized: remindersManager.isAuthorized,
            isLoading: remindersManager.isLoading,
            hasReminders: !remindersManager.reminders.isEmpty
        )
    }

    private var isEmpty: Bool {
        guard activeTasks.isEmpty, completedTaskCount == 0 else { return false }
        guard scope == .inbox else { return true }
        return remindersManager.reminders.isEmpty
            && remindersManager.isAuthorized
            && !remindersManager.isLoading
    }

    // MARK: - Sections

    private func sections(from tasks: [AppTask]) -> [TasksListSection] {
        switch groupingMode {
        case .none:
            return [
                TasksListSection(id: "tasks", title: "Tasks", accent: Theme.dim, dropKey: nil, tasks: tasks, listGroup: nil)
            ].filter { !$0.tasks.isEmpty }
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey).map { group in
                TasksListSection(
                    id: group.id,
                    title: group.title,
                    accent: group.accent,
                    dropKey: Self.dateDropKey(forGroupID: group.id),
                    tasks: group.tasks,
                    listGroup: nil
                )
            }
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: tasks).map { group in
                TasksListSection(
                    id: group.id,
                    title: group.title,
                    accent: group.accent,
                    dropKey: group.dropKey,
                    tasks: group.tasks,
                    listGroup: nil
                )
            }
        case .byList:
            return TasksPanelSupport.listGroups(from: tasks, contexts: contexts).map { group in
                TasksListSection(
                    id: group.id,
                    title: group.listName,
                    accent: group.listColor,
                    dropKey: "list:\(group.id)",
                    tasks: group.tasks,
                    listGroup: group
                )
            }
        }
    }

    /// The three date buckets a task can be *moved into*.
    ///
    /// `CadenceTaskQuerySupport.dateDisplayGroups` leaves `dropKey` nil for all five — deliberately,
    /// per `CadenceTaskDropSupport`, which says a group header that lights up and then applies
    /// nothing is noise. Overdue and Due Today are exactly that: both are defined by a day that has
    /// already gone by, and there is no "make this late" assignment. The other three map onto the
    /// keys `TasksPanelSupport.assignTask` has always read, so All Tasks' droppable date sections
    /// survive the move to the shared buckets unchanged.
    private static func dateDropKey(forGroupID id: String) -> String? {
        switch id {
        case "do-today": return "date:today"
        case "scheduled": return "date:scheduled"
        case "unscheduled": return "date:unscheduled"
        default: return nil
        }
    }

    // MARK: - Body

    var body: some View {
        let visibleTasks = activeTasks
        let completedCount = completedTaskCount
        let visibleCompletedTasks = isCompletedCollapsed ? [] : completedTasks
        let taskLookup = tasksByID

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections(from: visibleTasks)) { section in
                    TasksListSectionView(
                        section: section,
                        showsContainer: options.showsContainerChip,
                        isCollapsed: collapsedSectionIDs.contains(section.id),
                        overdueCount: overdueCount(in: section.tasks),
                        regularCount: regularCount(in: section.tasks),
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        dragOverTaskID: $dragOverTaskID,
                        onToggle: { toggleSection(section.id) },
                        taskDragPayload: taskDragPayload,
                        onDropOnSectionPayload: { payload in
                            guard let dropKey = section.dropKey,
                                  let droppedID = taskID(from: payload),
                                  let droppedTask = taskLookup[droppedID] else { return false }
                            assignTask(droppedTask, for: dropKey)
                            return true
                        },
                        onDropOnTaskPayload: { payload, targetTask in
                            guard let droppedID = taskID(from: payload),
                                  droppedID != targetTask.id,
                                  let droppedTask = taskLookup[droppedID] else { return false }
                            if let dropKey = section.dropKey {
                                assignTask(droppedTask, for: dropKey)
                            }
                            reorderTask(droppedID: droppedID, targetID: targetTask.id, scopeTasks: section.tasks)
                            return true
                        }
                    )
                }

                if showsRemindersSection {
                    InboxAppleRemindersSectionView(
                        // **T-254.** One value, not four booleans the caller could combine
                        // differently from the way the other three surfaces combine them.
                        // Also unblocks the type-checker: four independent Bools in a view
                        // body this size timed the solver out.
                        state: remindersManager.connectionState,
                        reminders: remindersManager.reminders,
                        isLoading: remindersManager.isLoading,
                        onAccessAction: { action in
                            switch action {
                            case .requestAccess: requestRemindersAccess()
                            case .openSystemSettings: openRemindersPrivacySettings()
                            }
                        },
                        onComplete: remindersManager.completeReminder
                    )
                }

                if options.showsCompletedToggle, completedCount > 0 {
                    TasksListCompletedSectionView(
                        tasks: visibleCompletedTasks,
                        showsContainer: options.showsContainerChip,
                        count: completedCount,
                        isCollapsed: isCompletedCollapsed,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        onToggle: { isCompletedCollapsed.toggle() },
                        taskDragPayload: taskDragPayload
                    )
                }

                if isEmpty {
                    emptyState
                }
            }
            .padding(.bottom, 16)
        }
        .cadenceSoftPageBounce()
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.bg)
        .animation(.easeOut(duration: 0.26), value: visibleTasks.map(\.id))
        .animation(.easeOut(duration: 0.26), value: remindersManager.reminders.map(\.id))
        .onAppear {
            isCompletedCollapsed = true
        }
        // **T-253.** Appearance *and* foreground return, through the one shared modifier the
        // other three reminders surfaces apply — this view carried its own hand-written pair.
        // `isEnabled` is the scope, not `showsRemindersSection`: that gate reads `isAuthorized`,
        // so a page that is not yet authorized would never re-derive and could never notice a
        // grant. All Tasks has no reminders strip, so re-reading EventKit from it is work with
        // nothing behind it.
        .remindersAuthorizationLifecycle(remindersManager, isEnabled: scope == .inbox)
        .background {
            // Inbox's hover-freeze, now on both scopes: ticking a task off must not reshuffle the
            // row under the pointer before the click lands. Row order only, never the group tree —
            // capturing a date or priority snapshot swaps the section tree under the pointer and
            // jitters, which is the note `InboxView` and `ListTasksView` both carried.
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: .constant(nil),
                naturalTasks: naturalActiveTasks,
                groupSnapshot: []
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .all:
            EmptyStateView(
                message: "No tasks yet",
                // Not "above": the header pill this pointed at is gone, and the page's
                // create control is the floating "+" below.
                subtitle: "Create a task to get started",
                icon: "checkmark.circle"
            )
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        case .inbox:
            InboxEmptyStateView()
                .frame(minHeight: 320)
        }
    }

    // MARK: - Actions

    private func toggleSection(_ id: String) {
        if collapsedSectionIDs.contains(id) {
            collapsedSectionIDs.remove(id)
        } else {
            collapsedSectionIDs.insert(id)
        }
    }

    private func overdueCount(in tasks: [AppTask]) -> Int? {
        TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey)
    }

    private func taskDragPayload(for task: AppTask) -> String {
        TasksPanelSupport.taskDragPayload(for: task)
    }

    private func taskID(from payload: String) -> UUID? {
        TasksPanelSupport.taskID(from: payload)
    }

    private func reorderTask(droppedID: UUID, targetID: UUID, scopeTasks: [AppTask]) {
        TasksPanelSupport.reorderTask(
            droppedID: droppedID,
            targetID: targetID,
            scopeTasks: scopeTasks,
            modelContext: modelContext
        )
    }

    private func assignTask(_ task: AppTask, for dropKey: String) {
        TasksPanelSupport.assignTask(
            task,
            for: dropKey,
            todayKey: todayKey,
            areas: areas,
            projects: projects,
            modelContext: modelContext
        )
    }

    private func requestRemindersAccess() {
        Task { await remindersManager.requestAccess() }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One section, whatever it is grouping by.
///
/// This replaced two structs — `AllTasksFlatSectionView` and `AllTasksListGroupView` — that
/// differed in exactly two things: whether the header drew the list's icon pair, and which row
/// style the tasks used. Both are now properties of the section.
private struct TasksListSectionView: View {
    let section: TasksListSection
    /// The page's answer. Composed with the section's below: this surface mixes lists, but a
    /// by-list section's *header* already names the one it is.
    let showsContainer: Bool
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnSectionPayload: (String) -> Bool
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskListGroupHeader(
                title: section.title,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: section.accent,
                onToggle: onToggle
            ) {
                if let group = section.listGroup {
                    HStack(spacing: 8) {
                        if let contextIcon = group.contextIcon, let contextColor = group.contextColor {
                            Image(systemName: contextIcon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(contextColor)
                                .frame(width: 22, height: 22)
                                .background(contextColor.opacity(0.15))
                                .clipShape(Circle())
                        }

                        Image(systemName: group.listIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(group.listColor)
                    }
                }
            }
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, section.listGroup == nil ? 16 : 20)
            .padding(.bottom, 8)
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return onDropOnSectionPayload(payload)
            }

            if !isCollapsed {
                ForEach(section.tasks) { task in
                    TaskListInteractiveRow(
                        task: task,
                        style: section.listGroup == nil ? .standard : .todayGrouped,
                        showsContainer: showsContainer && section.listGroup == nil,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        dragOverTaskID: $dragOverTaskID,
                        taskDragPayload: taskDragPayload,
                        onDropOnTaskPayload: onDropOnTaskPayload
                    )
                }
            }
        }
    }
}

private struct TasksListCompletedSectionView: View {
    let tasks: [AppTask]
    let showsContainer: Bool
    let count: Int
    let isCollapsed: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskListGroupHeader(
                title: "Completed",
                count: count,
                isCollapsed: isCollapsed,
                accent: Theme.green,
                onToggle: onToggle
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if !isCollapsed {
                ForEach(tasks) { task in
                    TaskListDisplayRow(
                        task: task,
                        style: .standard,
                        showsContainer: showsContainer,
                        contexts: contexts,
                        areas: areas,
                        projects: projects
                    )
                    .draggable(taskDragPayload(task))
                }
            }
        }
    }
}
#endif
