#if os(macOS)
import SwiftUI
import SwiftData

struct ListTasksView: View {
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let groupingMode: TaskGroupingMode

    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(\.modelContext) private var modelContext
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroupedTasks: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil
    /// Set when the store refused a row drop (T-869). The rows are already back where they were by
    /// then, so this tab and this sentence agree.
    @State private var reorderFailureNotice: String? = nil
    /// Set when a row drop **landed** and the tab's active sort does not show it where it was
    /// dropped (T-1077). See `TasksListView` for why it is a second flag and not a second value.
    @State private var reorderOffScreenNotice: String? = nil
    /// The day this tab groups and flags against ([[T-5012]]). The date buckets, the red overdue
    /// flags and every row's lateness were clock reads in a body whose inputs do not change at
    /// midnight, so a list left open overnight kept yesterday's Overdue / Due Today split. One
    /// observer here, for the page; the rows are handed the key.
    @State private var observedDay = CadenceObservedDay()

    private var activeTasks: [AppTask] {
        let sorted = CadenceTaskQuerySupport.openTasks(from: tasks).taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    /// See `TasksListView.completedTasks`: the **desktop** tier, which
    /// `CadenceTaskSurfaceOptions` leaves uncapped, asked rather than assumed (T-290).
    private var doneTasks: [AppTask] {
        CadenceTaskSurfaceOptions.completedRows(
            from: tasks.filter { $0.isDone || $0.isCancelled }.taskCompletionSorted(),
            tier: .desktop
        )
    }

    /// What a list's own Tasks tab offers, from the shared table.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: .listDetail)
    }
    private var sectionNames: [String] { area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName] }
    private var todayKey: String { observedDay.todayKey }

    private var groupedActiveTasks: [ListTasksGroup] {
        if let frozenGroupedTasks = resolveFrozenTaskGroups(frozenGroupedTasks, from: tasks) {
            let frozen = frozenGroupedTasks.map { group in
                ListTasksGroup(id: group.id, title: group.title, tasks: group.tasks)
            }
            guard groupingMode == .byList else { return frozen }
            return ListTasksSectionGroups.keepingEmptySections(frozen, live: liveSectionGroups)
        }

        switch groupingMode {
        case .none:
            return [
                ListTasksGroup(id: "all", title: "Tasks", tasks: activeTasks)
            ]
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: activeTasks, todayKey: todayKey)
                .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
        case .byList:
            return liveSectionGroups
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: activeTasks)
                .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
        }
    }

    /// The By List groups as the store has them now ([[T-5832]]).
    private var liveSectionGroups: [ListTasksGroup] {
        ListTasksSectionGroups.groups(
            from: activeTasks,
            sectionNames: sectionNames,
            pageIsEmpty: activeTasks.isEmpty && doneTasks.isEmpty
        )
    }

    var body: some View {
        // Read once, in `body` itself, so the observed day is a dependency of this pass and not
        // only of the `ForEach` closures below, which SwiftUI may run outside it.
        let todayKey = self.todayKey
        return List {
            if let reorderFailureNotice {
                CadenceInlineFailureNotice(text: reorderFailureNotice)
                    .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
                    .padding(.top, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
            if let reorderOffScreenNotice {
                CadenceInlineNotice(text: reorderOffScreenNotice, tone: .informational)
                    .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
                    .padding(.top, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
            if activeTasks.isEmpty && doneTasks.isEmpty {
                // The subtitle is the shared one because this page and `iOSListDetailView` are one
                // page at two widths, and because the copy that was here — "Create a task to get
                // started" — is a string T-285 retired from the Mac's task page and pinned only
                // against `TasksListView.swift`, which is how it survived in this file.
                EmptyStateView(
                    message: CadenceEmptyStateCopy.listDetailTitle,
                    subtitle: CadenceEmptyStateCopy.listDetailSubtitle,
                    icon: "checkmark.circle"
                )
                .padding(.top, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groupedActiveTasks) { group in
                ListTasksGroupSectionView(
                    group: group,
                    isCollapsed: collapsedGroupIDs.contains(group.id),
                    overdueCount: overdueCount(in: group.tasks),
                    todayKey: todayKey,
                    dragOverTaskID: $dragOverTaskID,
                    onToggle: { toggleGroup(group.id) },
                    onReorderTask: { dropTask(droppedID: $0, targetID: $1, into: group) }
                )
            }

            if options.showsCompletedToggle, !doneTasks.isEmpty {
                ListTasksCompletedSectionView(
                    tasks: doneTasks,
                    isCollapsed: isCompletedCollapsed,
                    todayKey: todayKey,
                    onToggle: { isCompletedCollapsed.toggle() }
                )
            }
            // [[T-5832]] (b). **Only By List draws sections, so only By List offers the row that
            // makes one.** Under By Date (the Mac default), None and By Priority the row created
            // the section and nothing appeared, because those groupings build their groups from
            // dates and priorities and never read `sectionNames` — so the control read as broken.
            // The owner declined the alternative, switching the tab to By List when a section is
            // added: that moves the view under the user. A control that appears to fail is worse
            // than a control that is not there.
            if groupingMode == .byList {
                CadenceSectionCreationRow(area: area, project: project)
                    .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Keeps the last row reachable from under the floating "+".
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .cadenceSoftPageBounce()
        .cadenceTracksDayChanges($observedDay)
        .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
        .floatingNewTaskButton {
            taskCreationManager.present(
                container: taskContainerSelection,
                sectionName: sectionNames.first ?? TaskSectionDefaults.defaultName
            )
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
        .onAppear {
            isCompletedCollapsed = true
        }
        .background {
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroupedTasks,
                naturalTasks: tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection),
                // Intentional: only freeze the group snapshot for byList (section) grouping.
                // Date/priority section trees must stay live while hovering — capturing those
                // snapshots swaps the row tree under the pointer and causes visible jitter.
                // Row order is still preserved separately via frozenTaskOrder.
                groupSnapshot: groupingMode == .byList
                    ? groupedActiveTasks.map { group in
                        FrozenTaskGroupSnapshot(
                            id: group.id,
                            title: group.title,
                            taskIDs: group.tasks.map(\.id)
                        )
                    }
                    : []
            )
        }
    }

    private var taskContainerSelection: TaskContainerSelection {
        if let area {
            return .area(area.id)
        }
        if let project {
            return .project(project.id)
        }
        return .inbox
    }

    /// A row dropped on another row: into that row's group first, then into its place ([[T-5358]]).
    ///
    /// Only the renumber ran here, so a task dropped on a row under another section, date bucket
    /// or priority took a new `order` and sprang back into the group it came from. The refiling is
    /// `ListTasksGroupDrop`'s, the same assign-then-reorder order as All Tasks; a refused refile
    /// stops before the renumber, because the store still files the task where it was.
    ///
    /// The hover freeze is let go on a refile: it holds each group's membership as it was when the
    /// pointer arrived, so it would keep drawing the moved row in its old group until the pointer
    /// left the list — the spring-back this fixes, for as long as the user stays on the page.
    private func dropTask(droppedID: UUID, targetID: UUID, into group: ListTasksGroup) -> Bool {
        if let dropped = tasks.first(where: { $0.id == droppedID }),
           let target = tasks.first(where: { $0.id == targetID }),
           let refiling = ListTasksGroupDrop.refiling(
               dropping: dropped,
               onto: target,
               in: group,
               groupingMode: groupingMode
           ) {
            guard ListTasksGroupDrop.refile(dropped, refiling, todayKey: todayKey, modelContext: modelContext) else {
                reorderOffScreenNotice = nil
                reorderFailureNotice = CadencePendingChangePersistence.editFailureNotice
                return false
            }
            frozenGroupedTasks = nil
            frozenTaskOrder = nil
        }
        return reorderTask(droppedID: droppedID, targetID: targetID)
    }

    /// Drag a row into a new place on a list's own Tasks tab.
    ///
    /// **It reached no commit at all until T-869** — this whole file contained no `save()` — and the
    /// row nevertheless stayed where it was dropped until the next launch put it back. That is the
    /// failure T-614's rule is about, and it was invisible to `CadenceSaveCommitDisciplineTests`
    /// because there was no swallowed commit in the frame for half 2 to hang the rule on and no
    /// insert or delete for half 3 to see.
    ///
    /// **It renumbered the *displayed* order until T-884**, which is why it did not call
    /// `TasksPanelSupport.reorderTask`: `activeTasks` is the tab's active sort plus its hover
    /// freeze, and the two surfaces therefore meant different things by the same gesture. That is
    /// settled now, in favour of the sequence Today and All Tasks renumber — see
    /// `TasksPanelSupport.reorderTask` for the whole argument, which is about what a drag under a
    /// date sort may cost, not about which spelling was shorter.
    ///
    /// **`tasks`, not `activeTasks`**, so neither the freeze nor the sort reaches `order`. The
    /// freeze half is not even a judgement call: `TaskListKanbanColumn.moveTask` already recorded
    /// that "the hover freeze is a display-only concern and must never be what gets written back
    /// into `order`", and this site was writing exactly that back.
    ///
    /// - Returns: Whether the new order is in the store, so the row springs back on a refusal
    ///   rather than sitting in a place nothing holds.
    private func reorderTask(droppedID: UUID, targetID: UUID) -> Bool {
        // **Asked before the drop lands, not after it (T-1119).** The question is about the
        // arrangement this drop is leaving, and these are live rows — by the time `reorderTask` has
        // answered, they carry the orders it just wrote, so a notice computed afterwards is asked
        // about the wrong sequence. It is still *reported* afterwards, and only on a drop the store
        // took.
        //
        // **The same array the renumber gets, and that is not cosmetic (T-1174).** This handed the
        // notice the list's whole `tasks` while handing the renumber only its open ones, so the two
        // were asked about different sequences: a drop whose open rows are already in the order it
        // asks for, but which passes a *finished* row on the way, writes nothing and was told
        // "Moved, but this sort doesn't show it there" — the false claim this type exists to avoid,
        // one surface in. `CadenceReorderVisibility` reads `tasks` only to resolve the two ids and
        // to ask the span rule, and both questions are about the rows the drop renumbers.
        let landing = CadenceReorderVisibility.notice(
            droppedID: droppedID,
            targetID: targetID,
            in: CadenceTaskQuerySupport.openTasks(from: tasks),
            sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: sortField, direction: sortDirection) }
        )
        let reordered = TasksPanelSupport.reorderTask(
            droppedID: droppedID,
            targetID: targetID,
            scopeTasks: CadenceTaskQuerySupport.openTasks(from: tasks),
            // The tab draws its open rows and files its finished ones under a toggle, so the slice
            // above is a strict subset of this list — and a renumber of the slice alone handed the
            // open rows the orders the finished ones were holding (T-1175). `tasks` is this list,
            // whole.
            spanTasks: tasks,
            modelContext: modelContext
        )
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
        reorderOffScreenNotice = reordered ? landing : nil
        return reordered
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    // Forwards to `TasksPanelSupport`, the same counts Today and All Tasks show. This file used to
    // carry its own bodies, and they had drifted: neither excluded completed tasks, so a finished
    // task with a past due date was counted as overdue here and not on the other two screens — the
    // same list reporting two different numbers depending on which screen you were on. It is
    // reachable in normal use because the hover-freeze snapshot keeps a just-completed task in its
    // group for a moment after you tick it.
    private func overdueCount(in tasks: [AppTask]) -> Int? {
        TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)
    }

    private func openCount(in tasks: [AppTask]) -> Int {
        TasksPanelSupport.openCount(in: tasks)
    }
}
/// A list's Tasks tab under By List: every configured section, the empty ones included ([[T-5832]]).
///
/// The "+ Section" row at the foot of the tab adds a section that is empty by definition, and
/// `sectionGroups` drops an empty section by default — so the row created a section and nothing
/// new appeared, while iOS's list Tasks tab (`iOSListDetailView.sectionGroups`) drew it at once.
/// **Since [[T-6201]] that holds on a page with no tasks at all as well**, by the owner's ruling,
/// and the rule is the shared one both platforms read: the empty state stays, the user's own
/// sections are drawn under it, and Default is left out so a new list still reads as empty.
enum ListTasksSectionGroups {
    static func groups(from activeTasks: [AppTask], sectionNames: [String], pageIsEmpty: Bool) -> [ListTasksGroup] {
        CadenceTaskQuerySupport.listSectionGroups(
            from: activeTasks,
            sectionNames: sectionNames,
            pageIsEmpty: pageIsEmpty
        )
        .map { ListTasksGroup(id: $0.id, title: $0.title, tasks: $0.tasks) }
    }

    /// The hover freeze's groups, with the live empty sections put back in their places.
    ///
    /// The freeze holds each group's rows while the pointer is over the list, and
    /// `resolveFrozenTaskGroups` drops a group with no rows — so without this, an empty section
    /// would vanish the moment a row was hovered, and the one "+ Section" just made (reached, almost
    /// always, by crossing a row) would not appear until the pointer left the list. A live empty
    /// section is placed after the nearest live group before it that is already drawn.
    static func keepingEmptySections(_ frozen: [ListTasksGroup], live: [ListTasksGroup]) -> [ListTasksGroup] {
        var result = frozen
        var drawnIDs = Set(frozen.map(\.id))
        var insertionIndex = 0
        for group in live {
            if let index = result.firstIndex(where: { $0.id == group.id }) {
                insertionIndex = index + 1
            } else if group.tasks.isEmpty, !drawnIDs.contains(group.id) {
                result.insert(group, at: insertionIndex)
                drawnIDs.insert(group.id)
                insertionIndex += 1
            }
        }
        return result
    }
}

#endif
