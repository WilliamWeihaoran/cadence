import Foundation

extension CadenceTaskQuerySupport {
    static func openTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { !$0.isDone && !$0.isCancelled }
    }

    static func openTaskCount(from tasks: [AppTask]) -> Int {
        tasks.reduce(into: 0) { count, task in
            if isOpenTask(task) { count += 1 }
        }
    }

    static func completedTaskCount(from tasks: [AppTask]) -> Int {
        tasks.reduce(into: 0) { count, task in
            if task.isDone { count += 1 }
        }
    }

    static func inboxTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.area == nil && $0.project == nil && !$0.isCancelled }
    }

    static func openInboxTaskCount(from tasks: [AppTask]) -> Int {
        tasks.reduce(into: 0) { count, task in
            if isOpenTask(task) && task.area == nil && task.project == nil {
                count += 1
            }
        }
    }

    static func scheduledOrDueTodayCount(from tasks: [AppTask], todayKey: String) -> Int {
        tasks.reduce(into: 0) { count, task in
            guard isOpenTask(task) else { return }
            if task.scheduledDate == todayKey || task.dueDate == todayKey {
                count += 1
            }
        }
    }

    static func badgeCount(_ count: Int) -> Int? {
        count > 0 ? count : nil
    }

    static func tasks(for area: Area?, project: Project?, in tasks: [AppTask]) -> [AppTask] {
        if let area {
            return tasks.filter { $0.area?.id == area.id }
        }
        if let project {
            return tasks.filter { $0.project?.id == project.id }
        }
        return []
    }

    static func openTaskCount(for area: Area) -> Int {
        openTaskCount(from: area.tasks ?? [])
    }

    static func openTaskCount(for project: Project) -> Int {
        openTaskCount(from: project.tasks ?? [])
    }

    private static func isOpenTask(_ task: AppTask) -> Bool {
        !task.isDone && !task.isCancelled
    }
}
