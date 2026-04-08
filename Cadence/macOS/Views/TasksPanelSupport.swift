#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

enum TaskFilterDoDate: String, CaseIterable, Identifiable {
    case any = "Any Do Date"
    case today = "Do Today"
    case overdue = "Overdue"
    case scheduled = "Scheduled"
    case unscheduled = "Unscheduled"
    var id: String { rawValue }
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

    static func overdueCount(in tasks: [AppTask], todayKey: String) -> Int? {
        let count = tasks.filter { !$0.isDone && !$0.dueDate.isEmpty && $0.dueDate < todayKey }.count
        return count > 0 ? count : nil
    }

    static func regularCount(in tasks: [AppTask], todayKey: String) -> Int {
        tasks.filter { !$0.isDone }.count - (overdueCount(in: tasks, todayKey: todayKey) ?? 0)
    }

    static func taskDragPayload(for task: AppTask) -> String {
        "listTask:\(task.id.uuidString)"
    }

    static func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix("listTask:") {
            return UUID(uuidString: String(payload.dropFirst(9)))
        }
        return UUID(uuidString: payload)
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
