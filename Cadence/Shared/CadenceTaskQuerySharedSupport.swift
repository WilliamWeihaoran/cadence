import Foundation

nonisolated extension CadenceTaskQuerySupport {
    static func openTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { !$0.isDone && !$0.isCancelled }
    }

    /// "This task is over" — done **or** cancelled. The one predicate every completed/logbook
    /// surface reads, and the exact complement of `isOpenTask`.
    ///
    /// T-147: the completed queries used to spell this `isDone && !isCancelled`, which a cancelled
    /// task satisfies *neither* half of. So it was excluded from the active lists for not being
    /// open and from the Completed sections for not being done, and cancelling a task on iOS
    /// removed it from every list in the app — deleting it without saying so. macOS had already
    /// arrived at the right spelling three times independently (`ListLogView`, `TasksListView`,
    /// `TasksPanelDerivedState` all filter `isDone || isCancelled`); naming it once here is what
    /// stops a fourth completed surface getting it wrong.
    ///
    /// Cancelled is deliberately **not** folded into `completedTaskCount`, which backs the "N done"
    /// summary line and the Settings Completed tile. That number counts work finished, and a
    /// cancellation is not an accomplishment; what a Completed *section* owes you is reachability.
    static func isFinishedTask(_ task: AppTask) -> Bool {
        task.isDone || task.isCancelled
    }

    static func finishedTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { isFinishedTask($0) }
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

    /// The whole Inbox — open work **and** finished work, because the surface built on it draws
    /// both halves.
    ///
    /// The `!$0.isCancelled` that used to be here was an upstream filter defeating a downstream
    /// one: `TasksListView` splits this universe into `openTasks` and `isDone || isCancelled`, so a
    /// cancelled Inbox task was gone before either branch saw it, while the same view's All Tasks
    /// scope (`filter(\.isInActiveContainer)`) let one through to its Completed section. One list
    /// showing cancelled work and the next one not was the asymmetry, not the policy. Both count
    /// callers (`openTaskCount`, and the sidebar badge in `macOSRootSupportViews`) re-filter to open
    /// work, so no badge changed.
    static func inboxTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.area == nil && $0.project == nil }
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
