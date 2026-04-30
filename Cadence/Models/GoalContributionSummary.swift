import Foundation

struct GoalContributionSummary {
    let totalTasks: Int
    let completedTasks: Int
    let directTaskCount: Int
    let linkedListCount: Int
    let focusMinutes: Int
    let overdueTaskCount: Int
    let recentCompletedCount: Int
    let nextActionTitle: String?

    var progress: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var percentLabel: String {
        "\(Int((progress * 100).rounded()))%"
    }

    var taskCountLabel: String {
        "\(completedTasks)/\(totalTasks)"
    }

    var focusLabel: String {
        guard focusMinutes > 0 else { return "0m" }
        let hours = focusMinutes / 60
        let minutes = focusMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

enum GoalContributionResolver {
    static func contributingTasks(for goal: Goal) -> [AppTask] {
        let directTasks = goal.tasks ?? []
        let listTasks = (goal.listLinks ?? []).flatMap(\.tasks)
        return dedupe(directTasks + listTasks).filter { !$0.isCancelled }
    }

    static func summary(for goal: Goal, now: Date = Date()) -> GoalContributionSummary {
        let tasks = contributingTasks(for: goal)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let openTasks = tasks.filter { !$0.isDone }

        let nextAction = openTasks
            .sorted(by: taskSort)
            .first?
            .title

        let overdueCount = openTasks.filter { task in
            guard !task.dueDate.isEmpty, let due = DateFormatters.date(from: task.dueDate) else { return false }
            return due < today
        }.count

        let recentCompleted = tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return completedAt >= recentStart
        }.count

        return GoalContributionSummary(
            totalTasks: tasks.count,
            completedTasks: tasks.filter(\.isDone).count,
            directTaskCount: (goal.tasks ?? []).filter { !$0.isCancelled }.count,
            linkedListCount: (goal.listLinks ?? []).filter { $0.area != nil || $0.project != nil }.count,
            focusMinutes: tasks.reduce(Int(goal.loggedHours * 60)) { $0 + max(0, $1.actualMinutes) },
            overdueTaskCount: overdueCount,
            recentCompletedCount: recentCompleted,
            nextActionTitle: nextAction
        )
    }

    private static func dedupe(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }

    private static func taskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.priority != rhs.priority {
            return priorityRank(lhs.priority) > priorityRank(rhs.priority)
        }
        let lhsDue = lhs.dueDate.isEmpty ? "9999-12-31" : lhs.dueDate
        let rhsDue = rhs.dueDate.isEmpty ? "9999-12-31" : rhs.dueDate
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        if lhs.scheduledDate != rhs.scheduledDate {
            let lhsDo = lhs.scheduledDate.isEmpty ? "9999-12-31" : lhs.scheduledDate
            let rhsDo = rhs.scheduledDate.isEmpty ? "9999-12-31" : rhs.scheduledDate
            return lhsDo < rhsDo
        }
        return lhs.order < rhs.order
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}
