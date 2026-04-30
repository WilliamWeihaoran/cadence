#if os(macOS)
import SwiftUI

let kanbanSectionDragPrefix = "kanban-section::"
let kanbanSectionColorOptions: [String] = [
    "#6b7a99", "#4a9eff", "#4ecb71", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316"
]
let kanbanColumnReorderAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12)
let kanbanColumnStateAnimation = Animation.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
let kanbanColumnWidth: CGFloat = 248

struct KanbanDateBucket: Identifiable {
    let title: String
    let icon: String
    let color: Color
    let tasks: [AppTask]

    var id: String { title }
}

struct KanbanListColumnModel: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let tasks: [AppTask]
    let container: TaskContainerSelection
    let onAssignTask: (AppTask) -> Void
}

enum KanbanBoardSupport {
    static func activeTasks(from allTasks: [AppTask]) -> [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled }
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
                icon: "tray.fill",
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

        columns += areas.map { area in
            KanbanListColumnModel(
                id: "area-\(area.id.uuidString)",
                title: area.name,
                icon: area.icon,
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

        columns += projects.map { project in
            KanbanListColumnModel(
                id: "project-\(project.id.uuidString)",
                title: project.name,
                icon: project.icon,
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

    static func dateBuckets(
        activeTasks: [AppTask],
        todayKey: String,
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [KanbanDateBucket] {
        let overdue = activeTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let doToday = activeTasks.filter { $0.scheduledDate == todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let scheduled = activeTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let unscheduled = activeTasks.filter { $0.scheduledDate.isEmpty || $0.scheduledStartMin < 0 }.taskSorted(by: sortField, direction: sortDirection)
        return [
            KanbanDateBucket(title: "Overdue", icon: "exclamationmark.triangle.fill", color: Theme.red, tasks: overdue),
            KanbanDateBucket(title: "Do Today", icon: "sun.max.fill", color: Theme.blue, tasks: doToday),
            KanbanDateBucket(title: "Scheduled", icon: "calendar", color: Theme.dim, tasks: scheduled),
            KanbanDateBucket(title: "Unscheduled", icon: "questionmark.circle", color: Theme.amber, tasks: unscheduled)
        ]
    }

    static func applyDateBucketDrop(task: AppTask, bucketTitle: String, todayKey: String, now: Date = Date()) {
        switch bucketTitle {
        case "Do Today":
            task.scheduledDate = todayKey
        case "Scheduled":
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
            }
        case "Unscheduled":
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        case "Overdue":
            if task.dueDate.isEmpty || task.dueDate >= todayKey {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
                task.dueDate = DateFormatters.dateKey(from: yesterday)
            }
        default:
            break
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
