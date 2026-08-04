#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var isCompletedCollapsed = true
    @AppStorage("inboxSortField") private var sortField: TaskSortField = .custom
    @AppStorage("inboxSortDirection") private var sortDirection: TaskSortDirection = .ascending
    @AppStorage("inboxGroupingMode") private var groupingMode: TaskGroupingMode = .none
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroups: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil

    private var inboxTasks: [AppTask] {
        CadenceTaskQuerySupport.inboxTasks(from: allTasks)
    }
    private var activeTasks: [AppTask] {
        let sorted = CadenceTaskQuerySupport.openTasks(from: inboxTasks).taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    private var doneTasks: [AppTask] { inboxTasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    private var inboxItemCount: Int { activeTasks.count + remindersManager.reminders.count }
    private var shouldShowRemindersSection: Bool {
        !remindersManager.isAuthorized || remindersManager.isLoading || !remindersManager.reminders.isEmpty
    }
    private var isInboxEmpty: Bool {
        activeTasks.isEmpty &&
            doneTasks.isEmpty &&
            remindersManager.reminders.isEmpty &&
            remindersManager.isAuthorized &&
            !remindersManager.isLoading
    }
    private var groupedActiveTasks: [InboxTaskGroup] {
        if let frozenGroups = resolveFrozenTaskGroups(frozenGroups, from: allTasks) {
            return frozenGroups.map { group in
                InboxTaskGroup(id: group.id, title: group.title, tasks: group.tasks, color: group.accent)
            }
        }
        let todayKey = DateFormatters.todayKey()
        switch groupingMode {
        case .none:
            return [InboxTaskGroup(id: "all", title: "Tasks", tasks: activeTasks, color: Theme.dim)]
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: activeTasks, todayKey: todayKey)
                .map { InboxTaskGroup(id: $0.id, title: $0.title, tasks: $0.tasks, color: $0.accent) }
        case .byList:
            return [InboxTaskGroup(id: "inbox", title: "Inbox", tasks: activeTasks, color: Theme.dim)]
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: activeTasks)
                .map { InboxTaskGroup(id: $0.id, title: $0.title, tasks: $0.tasks, color: $0.accent) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            InboxHeaderView(activeTaskCount: inboxItemCount) {
                taskCreationManager.present()
            }
            Divider().background(Theme.borderSubtle)
            InboxControlsBarView(sortField: $sortField, sortDirection: $sortDirection, groupingMode: $groupingMode)
            Divider().background(Theme.borderSubtle)

            if isInboxEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedActiveTasks.filter { !$0.tasks.isEmpty }) { group in
                        InboxTaskGroupSectionView(
                            group: group,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            dragOverTaskID: $dragOverTaskID,
                            onReorderTask: reorderTask
                        )
                    }

                    if shouldShowRemindersSection {
                        InboxAppleRemindersSectionView(
                            reminders: remindersManager.reminders,
                            isAuthorized: remindersManager.isAuthorized,
                            isDenied: remindersManager.isDenied,
                            isLoading: remindersManager.isLoading,
                            onRequestAccess: requestRemindersAccess,
                            onOpenSettings: openRemindersPrivacySettings,
                            onComplete: remindersManager.completeReminder
                        )
                    }

                    if !doneTasks.isEmpty {
                        InboxCompletedSectionView(
                            tasks: doneTasks,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            isCollapsed: isCompletedCollapsed,
                            onToggle: { isCompletedCollapsed.toggle() }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .cadenceSoftPageBounce()
                .background(Theme.bg)
                .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
                .animation(.easeOut(duration: 0.26), value: remindersManager.reminders.map(\.id))
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.bg)
        .onAppear {
            isCompletedCollapsed = true
            remindersManager.refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            remindersManager.refreshAuthorizationState()
        }
        .background {
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroups,
                naturalTasks: inboxTasks.filter { !$0.isDone }.taskSorted(by: sortField, direction: sortDirection),
                // Intentional: Inbox has no real multi-list grouping (byList here is always a
                // single "Inbox" bucket), and date/priority buckets must stay live while hovering
                // — freezing them swaps the section tree under the pointer and causes jitter.
                // Row order is still preserved separately via frozenTaskOrder.
                groupSnapshot: []
            )
        }
    }

    private var emptyState: some View {
        InboxEmptyStateView {
            taskCreationManager.present()
        }
    }

    // MARK: - Actions

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

    private func requestRemindersAccess() {
        Task { await remindersManager.requestAccess() }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }

}

#endif
