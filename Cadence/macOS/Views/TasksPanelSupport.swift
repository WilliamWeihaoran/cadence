#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
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

enum TasksPanelSupport {
    /// `CadenceTaskQuerySupport.listGroupOrder`, not a second copy of it. Today groups by list too
    /// now (T-305), and two by-list surfaces that ordered their groups differently is exactly the
    /// drift moving the rule out of here prevents.
    static func sidebarListOrder(contexts: [Context]) -> [String] {
        CadenceTaskQuerySupport.listGroupOrder(contexts: contexts)
    }

    static func makeFlatSection(
        id: String,
        title: String,
        tasks: [AppTask],
        dropKey: String? = nil
    ) -> FrozenFlatTaskSection? {
        guard !tasks.isEmpty else { return nil }
        return FrozenFlatTaskSection(
            id: id,
            title: title,
            dropKey: dropKey,
            taskIDs: tasks.map(\.id)
        )
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

    static func assignTask(
        _ task: AppTask,
        for dropKey: String,
        todayKey: String,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) {
        if dropKey.hasPrefix("list:") {
            let listID = String(dropKey.dropFirst(5))
            if listID == "inbox" {
                task.area = nil
                task.project = nil
                task.context = nil
            } else if listID.hasPrefix("a_") {
                let areaID = String(listID.dropFirst(2))
                if let target = areas.first(where: { $0.id.uuidString == areaID }) {
                    task.area = target
                    task.project = nil
                    task.context = target.context
                }
            } else if listID.hasPrefix("p_") {
                let projectID = String(listID.dropFirst(2))
                if let target = projects.first(where: { $0.id.uuidString == projectID }) {
                    task.project = target
                    task.area = nil
                    task.context = target.resolvedContext
                }
            }
        } else if dropKey == "date:today" {
            CadenceTaskDateEditing.setScheduledDate(todayKey, for: task, in: modelContext)
        } else if dropKey == "date:scheduled" {
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                CadenceTaskDateEditing.setScheduledDate(
                    DateFormatters.dateKey(from: tomorrow),
                    for: task,
                    in: modelContext
                )
            }
        } else if dropKey == "date:unscheduled" {
            CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
        } else if dropKey.hasPrefix("priority:") {
            let raw = String(dropKey.dropFirst(9))
            if let priority = TaskPriority(rawValue: raw) {
                task.priority = priority
            }
        }
        try? modelContext.save()
    }
}
#endif
