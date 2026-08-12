#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

enum TaskSortField: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case date = "Date"
    case priority = "Priority"
    var id: String { rawValue }
}

enum TaskSortDirection: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"
    var id: String { rawValue }
}

enum TaskGroupingMode: String, CaseIterable, Identifiable {
    case none = "None"
    case byDate = "By Date"
    case byList = "By List"
    case byPriority = "By Priority"
    var id: String { rawValue }
}

struct TodayOverdueListSummary: Identifiable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let title: String
    let icon: String
    let color: Color
    let dueDateKey: String
    let activeTaskCount: Int
}

struct TodayOverdueSectionSummary: Identifiable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let sectionName: String
    let parentName: String
    let parentIcon: String
    let parentColor: Color
    let dueDateKey: String
    let openTaskCount: Int
    let completedTaskCount: Int
}

enum MacTaskRowStyle {
    case standard
    case todayGrouped
    case list
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
    static func sidebarListOrder(contexts: [Context]) -> [String] {
        var order: [String] = ["inbox"]
        for context in contexts.sorted(by: { $0.order < $1.order }) {
            let sortedAreas = (context.areas ?? []).sorted { $0.order < $1.order }
            let sortedProjects = (context.projects ?? []).sorted { $0.order < $1.order }
            order.append(contentsOf: sortedAreas.map { "a_\($0.id.uuidString)" })
            order.append(contentsOf: sortedProjects.map { "p_\($0.id.uuidString)" })
        }
        return order
    }

    static func makeFlatSection(
        id: String,
        title: String,
        tasks: [AppTask],
        labelColor: Color,
        dropKey: String? = nil
    ) -> FrozenFlatTaskSection? {
        guard !tasks.isEmpty else { return nil }
        return FrozenFlatTaskSection(
            id: id,
            title: title,
            labelColor: labelColor,
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

    private static func listGroupKey(for task: AppTask) -> String {
        if let area = task.area {
            return "a_\(area.id.uuidString)"
        }
        if let project = task.project {
            return "p_\(project.id.uuidString)"
        }
        return "inbox"
    }

    private static func listGroupShell(for task: AppTask, key: String) -> TodayTaskGroup {
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

    static func openOverdueListSummary(_ summary: TodayOverdueListSummary, listNavigationManager: ListNavigationManager) {
        if let projectID = summary.projectID {
            listNavigationManager.open(projectID: projectID, page: .tasks)
        } else if let areaID = summary.areaID {
            listNavigationManager.open(areaID: areaID, page: .tasks)
        }
    }

    static func openOverdueSectionSummary(_ summary: TodayOverdueSectionSummary, listNavigationManager: ListNavigationManager) {
        if let projectID = summary.projectID {
            listNavigationManager.open(projectID: projectID, page: .kanban, sectionName: summary.sectionName)
        } else if let areaID = summary.areaID {
            listNavigationManager.open(areaID: areaID, page: .kanban, sectionName: summary.sectionName)
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
                    task.context = target.context
                }
            }
        } else if dropKey == "date:today" {
            task.scheduledDate = todayKey
        } else if dropKey == "date:scheduled" {
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
            }
        } else if dropKey == "date:unscheduled" {
            task.scheduledDate = ""
            task.scheduledStartMin = -1
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
