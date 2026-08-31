#if os(macOS)
import SwiftUI
import SwiftData

/// One case, and deliberately still an enum.
///
/// `.byDoDate` — this panel's All Tasks shape — was **unreachable**: `TodayView` builds the only
/// `TasksPanel` in the repository and takes the `.todayOverview` default, so nothing but a test
/// ever constructed the other one. It is gone (T-487), along with its grouping control, its four
/// section builders, its frozen list/flat snapshots and an empty state that still spelled two
/// strings the app retired, because nobody could see it to notice. Collapsing the enum itself is
/// a further design change and has not been made here.
enum TasksPanelMode {
    case todayOverview
}

// `TaskSortField` and `TaskSortDirection` live in `Cadence/Models/TaskOrdering.swift`, next to
// the comparator that reads them, so `CadenceWidgets` and `CadenceMCPServer` can reach both.
// `TaskGroupingMode` stays here: grouping is a macOS list-surface concern with no comparator
// behind it, and no other target has a grouped task list.

enum TaskGroupingMode: String, CaseIterable, Identifiable {
    case none = "None"
    case byDate = "By Date"
    case byList = "By List"
    case byPriority = "By Priority"
    var id: String { rawValue }
}

// `TodayOverdueListSummary` and `TodayOverdueSectionSummary` were declared here, and derived in
// `TasksPanelDerivedState.init`, with zero readers under `Cadence/iOS/`. Both are
// `CadenceTodayOverdueListSummary` / `CadenceTodayOverdueSectionSummary` in
// `Shared/CadenceTodayOverdueSummarySupport.swift` now (T-195, second half), together with the
// `sectionConfigs` walk that builds them — and this panel is rewired onto them rather than left
// beside them. They carry the list's `colorHex` rather than a resolved `Color`, which is what lets
// `CadenceTodayOverdueSummarySurfaceTests` recompute the whole derivation without SwiftUI.

/// What a `MacTaskRow` suppresses, and it is down to one thing.
///
/// **`.list` is gone (T-290), because it had stopped meaning anything.** Its only effect was to
/// hide the list chip on a list's own Tasks tab — a *surface* answer that
/// `CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail)` now gives, through the row's
/// `showsContainer`. With the chip moved off this axis, `.list` and `.standard` compiled to the
/// same row, and a case that draws nothing is how the page header's `subtitle` parameter survived
/// three deletions.
///
/// `.todayGrouped` earns its keep: it drops the **do-date pill**, because the section it appears in
/// is the day.
enum MacTaskRowStyle {
    case standard
    case todayGrouped
}

/// Shared, pure index math for the inline "picker badge" style controls
/// (`ContainerPickerBadge`, `TaskSectionPickerBadge`, the CreateTaskSheet tilde
/// list/section pickers). Kept separate from any specific view so the
/// highlight-index arithmetic can be unit tested without SwiftUI.
enum TaskPickerHighlightSupport {
    /// Clamps `index` into the valid `0..<count` range. Returns 0 when `count <= 0`
    /// (an empty filtered list), which callers should additionally treat as "no
    /// selection" rather than a real highlighted row.
    static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// Moves `index` by `offset` and clamps at the ends (arrow key navigation stops
    /// at the first/last row). Used by `ContainerPickerBadge` / `TaskSectionPickerBadge`.
    ///
    /// The starting `index` is clamped into range *before* the offset is applied.
    /// This matters when a fast-typed search query has just shrunk the filtered
    /// list out from under a stale `highlightIdx`: without pre-clamping, the very
    /// next arrow press could land on the same edge row twice before recovering.
    static func clampedMovedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
        clampedIndex(clampedIndex(index, count: count) + offset, count: count)
    }

    /// Moves `index` by `offset`, wrapping around at the ends (cycling navigation).
    /// Used by the CreateTaskSheet tilde (`~`) inline list/section pickers.
    static func wrappedMovedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (clampedIndex(index, count: count) + offset + count) % count
    }
}

/// One field a drop key asks `TasksPanelSupport.assignTask` to set.
///
/// It exists so the parse and the mutation are separable. A drop key is compound — Today's list
/// headers say `list:p_<uuid>|date:today` — and reading the whole of one as a single `list:` value
/// was a bug nothing could catch, because the only way to observe the parse was to drag a row in
/// the running app and notice it had not moved (T-591). Resolving to these first makes the parse a
/// value a test can read.
enum TasksPanelDropAssignment: Equatable {
    case inbox
    case area(UUID)
    case project(UUID)
    case scheduleToday
    case pushToScheduled
    case clearSchedule
    case priority(TaskPriority)
}

enum TasksPanelSupport {
    /// `CadenceTaskQuerySupport.listGroupOrder`, not a second copy of it. Today groups by list too
    /// now (T-305), and two by-list surfaces that ordered their groups differently is exactly the
    /// drift moving the rule out of here prevents.
    static func sidebarListOrder(contexts: [Context]) -> [String] {
        CadenceTaskQuerySupport.listGroupOrder(contexts: contexts)
    }

    static func listGroups(
        from tasks: [AppTask],
        contexts: [Context],
        taskOrder: ([AppTask]) -> [AppTask] = { $0 }
    ) -> [TodayTaskGroup] {
        var groups: [String: TodayTaskGroup] = [:]

        for task in tasks {
            let key = listGroupKey(for: task)
            if groups[key] == nil {
                groups[key] = listGroupShell(for: task, key: key)
            }
            groups[key]?.tasks.append(task)
        }

        let orderedKeys = sidebarListOrder(contexts: contexts).filter { groups[$0] != nil }
        let unorderedKeys = groups.keys
            .filter { !orderedKeys.contains($0) }
            .sorted()

        return (orderedKeys + unorderedKeys).compactMap { key in
            guard var group = groups[key] else { return nil }
            group.tasks = taskOrder(group.tasks)
            return group
        }
    }

    /// `CadenceTaskQuerySupport.listGroupKey`, for the same reason `sidebarListOrder` above is the
    /// shared one. Note that the shared rule reads **project before area**, which this one did not:
    /// see that function for why the more specific container wins on a row repaired into holding
    /// both. `listGroupShell` below now agrees with it, so a group's key and the list its header
    /// draws cannot name different containers.
    private static func listGroupKey(for task: AppTask) -> String {
        CadenceTaskQuerySupport.listGroupKey(for: task)
    }

    private static func listGroupShell(for task: AppTask, key: String) -> TodayTaskGroup {
        if let project = task.project {
            return TodayTaskGroup(
                id: key,
                contextIcon: project.context?.icon,
                contextColor: project.context.map { Color(hex: $0.colorHex) },
                listIcon: project.icon,
                listName: project.name,
                listColor: Color(hex: project.colorHex),
                tasks: []
            )
        }
        if let area = task.area {
            return TodayTaskGroup(
                id: key,
                contextIcon: area.context?.icon,
                contextColor: area.context.map { Color(hex: $0.colorHex) },
                listIcon: area.icon,
                listName: area.name,
                listColor: Color(hex: area.colorHex),
                tasks: []
            )
        }
        return TodayTaskGroup(
            id: "inbox",
            contextIcon: nil,
            contextColor: nil,
            listIcon: "tray.fill",
            listName: "Inbox",
            listColor: Theme.dim,
            tasks: []
        )
    }

    /// Counts through `AppTask.isOverdue(todayKey:)` rather than re-deriving the comparison, so a
    /// finished task with a past due date stops inflating a group header. `regularCount` subtracts
    /// this from the not-done total, so the two only add up when both exclude completed tasks.
    static func overdueCount(in tasks: [AppTask], todayKey: String) -> Int? {
        let count = tasks.filter { $0.isOverdue(todayKey: todayKey) }.count
        return count > 0 ? count : nil
    }

    static func regularCount(in tasks: [AppTask], todayKey: String) -> Int {
        tasks.filter { !$0.isDone }.count - (overdueCount(in: tasks, todayKey: todayKey) ?? 0)
    }

    static func taskDragPayload(for task: AppTask) -> String {
        TaskDragPayload.string(for: task.id)
    }

    static func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }

    /// The tap target for a past-due **list** card.
    ///
    /// *Which* list and *which* page is `CadenceTodayOverdueSummarySupport.openRequest(for:)`, so
    /// iOS's Today lands on the same page from the same card. What stays here is the hop —
    /// `ListNavigationManager` is macOS-only, and is the one genuinely platform-shaped piece of
    /// this feature.
    static func openOverdueListSummary(
        _ summary: CadenceTodayOverdueListSummary,
        listNavigationManager: ListNavigationManager
    ) {
        guard let request = CadenceTodayOverdueSummarySupport.openRequest(for: summary) else { return }
        open(request, listNavigationManager: listNavigationManager)
    }

    static func openOverdueSectionSummary(
        _ summary: CadenceTodayOverdueSectionSummary,
        listNavigationManager: ListNavigationManager
    ) {
        guard let request = CadenceTodayOverdueSummarySupport.openRequest(for: summary) else { return }
        open(request, listNavigationManager: listNavigationManager)
    }

    /// One translation from the shared request to the macOS router, so the two cards above cannot
    /// disagree about how a request is spent.
    private static func open(_ request: CadenceListOpenRequest, listNavigationManager: ListNavigationManager) {
        switch request.target {
        case .project(let projectID):
            listNavigationManager.open(projectID: projectID, page: request.page, sectionName: request.sectionName)
        case .area(let areaID):
            listNavigationManager.open(areaID: areaID, page: request.page, sectionName: request.sectionName)
        }
    }

    static func reorderTask(
        droppedID: UUID,
        targetID: UUID,
        scopeTasks: [AppTask],
        modelContext: ModelContext
    ) {
        var sorted = scopeTasks.sorted { $0.order < $1.order }
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = sorted.remove(at: fromIndex)
        sorted.insert(moved, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (idx, task) in sorted.enumerated() {
                task.order = idx
            }
        }
        try? modelContext.save()
    }

    /// Moves `task` to everything `dropKey` names, and reports whether any of it landed.
    ///
    /// **A drop key is compound.** Today's group headers hand out `list:p_<uuid>|date:today` — the
    /// list *and* the day, because a task dropped on a Today list group has to be filed in that
    /// list without vanishing off the page it was dropped on
    /// (`CadenceTaskDropSupport.dropKey(forGroup:)` explains why the header says both). This read
    /// the whole string as one `list:` value, hunted for a project whose `uuidString` was
    /// `"<uuid>|date:today"`, found none, and fell out of every branch — every Today list header
    /// accepted drops and moved nothing (T-591). Parts are split on
    /// `CadenceTaskDropSupport.separator` and applied one at a time now, the same way
    /// `CadenceTaskDropSupport.seed(forDropKey:)` has always read them for the *seed* path.
    ///
    /// **The return value is what stops that going quiet again.** A key that resolves to nothing —
    /// an unknown vocabulary, or a list id no longer in `areas`/`projects` — must not be reported
    /// as a drop that happened; see `TasksPanelDropCoordinator.handleSectionDrop`, which used to
    /// answer `true` unconditionally and is the reason this was invisible for so long.
    @discardableResult
    static func assignTask(
        _ task: AppTask,
        for dropKey: String,
        todayKey: String,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) -> Bool {
        var applied = false
        for assignment in dropAssignments(forDropKey: dropKey) {
            let didApply = apply(
                assignment,
                to: task,
                todayKey: todayKey,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
            applied = applied || didApply
        }
        guard applied else { return false }
        try? modelContext.save()
        return true
    }

    /// What a drop key asks for, resolved before anything is touched.
    ///
    /// Pure on purpose: the parse is the whole of T-591 and it needs to be pinnable without a
    /// `ModelContext`, a task, or a live store. Parts the macOS assign vocabulary does not speak —
    /// `section:`, `due:` — are dropped rather than failing the key, so a compound key that also
    /// names something this surface *can* apply still applies it.
    static func dropAssignments(forDropKey dropKey: String) -> [TasksPanelDropAssignment] {
        dropKey
            .split(separator: CadenceTaskDropSupport.separator)
            .map(String.init)
            .compactMap { assignment(fromDropKeyPart: $0) }
    }

    private static func assignment(fromDropKeyPart part: String) -> TasksPanelDropAssignment? {
        if part.hasPrefix("list:") {
            let listID = String(part.dropFirst(5))
            if listID == "inbox" { return .inbox }
            if listID.hasPrefix("a_"), let id = UUID(uuidString: String(listID.dropFirst(2))) {
                return .area(id)
            }
            if listID.hasPrefix("p_"), let id = UUID(uuidString: String(listID.dropFirst(2))) {
                return .project(id)
            }
            return nil
        }
        switch part {
        case "date:today": return .scheduleToday
        case "date:scheduled": return .pushToScheduled
        case "date:unscheduled": return .clearSchedule
        default: break
        }
        if part.hasPrefix("priority:"), let priority = TaskPriority(rawValue: String(part.dropFirst(9))) {
            return .priority(priority)
        }
        return nil
    }

    /// `false` means the assignment named a list that is not here any more — the one case the
    /// parse cannot see and the caller still needs to know about.
    private static func apply(
        _ assignment: TasksPanelDropAssignment,
        to task: AppTask,
        todayKey: String,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) -> Bool {
        switch assignment {
        case .inbox:
            task.area = nil
            task.project = nil
            task.context = nil
        case .area(let areaID):
            guard let target = areas.first(where: { $0.id == areaID }) else { return false }
            task.area = target
            task.project = nil
            task.context = target.context
        case .project(let projectID):
            guard let target = projects.first(where: { $0.id == projectID }) else { return false }
            task.project = target
            task.area = nil
            task.context = target.resolvedContext
        case .scheduleToday:
            CadenceTaskDateEditing.setScheduledDate(todayKey, for: task, in: modelContext)
        case .pushToScheduled:
            // Already scheduled past today: the drop resolved, and leaving the later date alone is
            // the assignment, not a failure to make one. Still `true` — see `assignTask`.
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                CadenceTaskDateEditing.setScheduledDate(
                    DateFormatters.dateKey(from: tomorrow),
                    for: task,
                    in: modelContext
                )
            }
        case .clearSchedule:
            CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
        case .priority(let priority):
            task.priority = priority
        }
        return true
    }
}
#endif
