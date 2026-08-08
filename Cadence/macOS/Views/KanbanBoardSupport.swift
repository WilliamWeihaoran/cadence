#if os(macOS)
import SwiftUI

let kanbanSectionDragPrefix = "kanban-section::"
let kanbanSectionColorOptions: [String] = [
    "#6b7a99", "#4a9eff", "#4ecb71", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316"
]
let kanbanColumnReorderAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12)
let kanbanColumnStateAnimation = Animation.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
let kanbanColumnWidth: CGFloat = 236
/// Kanban columns are containerless (no fill, no border). This radius is only used for the
/// transient drop-target wash / dashed outline and the search-navigation highlight ring.
let kanbanColumnCornerRadius: CGFloat = 10
/// Cards keep a container so they read as objects sitting directly on the canvas.
let kanbanCardCornerRadius: CGFloat = 7

// MARK: - Shared column chrome constants
//
// Both kanban column implementations (`ListSectionKanbanColumn` and `TaskListKanbanColumn`)
// render through the shared components in `KanbanColumnSupportViews.swift`, which read these
// values. Nothing should re-spell these literals inline — that is exactly how the two columns
// drifted apart before.

/// The single dot of color that survives in an otherwise containerless column header.
let kanbanColumnDotSize: CGFloat = 7
/// Transient drag-over wash behind a targeted column.
let kanbanColumnDropFillOpacity: Double = 0.07
/// Transient drag-over dashed outline around a targeted column.
let kanbanColumnDropStrokeOpacity: Double = 0.55
let kanbanColumnDropDash: [CGFloat] = [5, 4]
let kanbanColumnDropAnimation = Animation.easeInOut(duration: 0.14)
/// Applied when card `order` values are reassigned after a drop.
let kanbanCardReorderAnimation = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)

struct KanbanListColumnModel: Identifiable {
    let id: String
    let title: String
    let color: Color
    let tasks: [AppTask]
    let container: TaskContainerSelection
    let onAssignTask: (AppTask) -> Void
}

enum KanbanBoardSupport {
    static func activeTasks(from allTasks: [AppTask]) -> [AppTask] {
        let tasksInActiveContainers = allTasks.filter { task in
            if let project = task.project {
                return project.isActive
            }
            if let area = task.area {
                return area.isActive
            }
            return true
        }
        return CadenceTaskQuerySupport.openTasks(from: tasksInActiveContainers)
    }

    static func inboxTasks(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [AppTask] {
        activeTasks
            .filter { $0.area == nil && $0.project == nil }
            .taskSorted(by: sortField, direction: sortDirection)
    }

    static func groupedTasksByAreaID(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let areaID = task.area?.id else { return nil }
            return (areaID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    static func groupedTasksByProjectID(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let projectID = task.project?.id else { return nil }
            return (projectID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    static func listColumns(
        areas: [Area],
        projects: [Project],
        activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [KanbanListColumnModel] {
        let groupedAreas = groupedTasksByAreaID(from: activeTasks, sortField: sortField, sortDirection: sortDirection)
        let groupedProjects = groupedTasksByProjectID(from: activeTasks, sortField: sortField, sortDirection: sortDirection)
        var columns: [KanbanListColumnModel] = [
            KanbanListColumnModel(
                id: "inbox",
                title: "Inbox",
                color: Theme.dim,
                tasks: inboxTasks(from: activeTasks, sortField: sortField, sortDirection: sortDirection),
                container: .inbox,
                onAssignTask: { task in
                    task.area = nil
                    task.project = nil
                    task.context = nil
                }
            )
        ]

        columns += areas.filter(\.isActive).map { area in
            KanbanListColumnModel(
                id: "area-\(area.id.uuidString)",
                title: area.name,
                color: Color(hex: area.colorHex),
                tasks: groupedAreas[area.id] ?? [],
                container: .area(area.id),
                onAssignTask: { task in
                    task.area = area
                    task.project = nil
                    task.context = area.context
                }
            )
        }

        columns += projects.filter(\.isActive).map { project in
            KanbanListColumnModel(
                id: "project-\(project.id.uuidString)",
                title: project.name,
                color: Color(hex: project.colorHex),
                tasks: groupedProjects[project.id] ?? [],
                container: .project(project.id),
                onAssignTask: { task in
                    task.project = project
                    task.area = nil
                    task.context = project.context
                }
            )
        }

        return columns
    }

    /// Reassigns `order` across a column after a card was dropped into it.
    ///
    /// `columnTasks` is the column's current ordering *as the caller presents it* (section
    /// columns sort by `order`, list columns by the board's active sort), `task` is the card
    /// that was dropped, and `target` is the card it was dropped in front of — `nil` means
    /// "append to the end", which is what a drop on empty column space produces.
    static func reorder(_ columnTasks: [AppTask], moving task: AppTask, before target: AppTask?) {
        var ordered = columnTasks
        ordered.removeAll { $0.id == task.id }
        if let target, let targetIndex = ordered.firstIndex(where: { $0.id == target.id }) {
            ordered.insert(task, at: targetIndex)
        } else {
            ordered.append(task)
        }
        withAnimation(kanbanCardReorderAnimation) {
            for (index, item) in ordered.enumerated() {
                item.order = index
            }
        }
    }

    static func nextSectionName(from sectionConfigs: [TaskSectionConfig]) -> String {
        let existingNames = Set(sectionConfigs.map { $0.name.lowercased() })
        if !existingNames.contains("new section") {
            return "New Section"
        }

        var index = 2
        while existingNames.contains("new section \(index)") {
            index += 1
        }
        return "New Section \(index)"
    }

    static func reorderedSectionConfigs(
        _ sectionConfigs: [TaskSectionConfig],
        movingName: String,
        targetName: String
    ) -> [TaskSectionConfig] {
        guard movingName.caseInsensitiveCompare(targetName) != .orderedSame else {
            return sectionConfigs
        }
        guard let fromIndex = sectionConfigs.firstIndex(where: { $0.name.caseInsensitiveCompare(movingName) == .orderedSame }),
              let toIndex = sectionConfigs.firstIndex(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame })
        else {
            return sectionConfigs
        }

        var updated = sectionConfigs
        let moved = updated.remove(at: fromIndex)
        let insertAt = fromIndex < toIndex ? toIndex - 1 : toIndex
        updated.insert(moved, at: max(0, insertAt))

        if let defaultIndex = updated.firstIndex(where: \.isDefault), defaultIndex != 0 {
            let defaultSection = updated.remove(at: defaultIndex)
            updated.insert(defaultSection, at: 0)
        }

        return updated
    }

    static func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }
}
#endif
