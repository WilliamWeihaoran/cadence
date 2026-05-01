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

struct GoalHabitMomentumSummary {
    let linkedHabitCount: Int
    let dueTodayCount: Int
    let doneTodayCount: Int
    let thisWeekCount: Int
    let last7DayCount: Int

    var dueTodayLabel: String {
        guard dueTodayCount > 0 else { return "No habits due" }
        return "\(doneTodayCount)/\(dueTodayCount) today"
    }

    var weeklyLabel: String {
        "\(thisWeekCount) this week"
    }
}

enum GoalContributionResolver {
    static func contributingTasks(for goal: Goal) -> [AppTask] {
        contributingTasks(for: goal, visitedGoalIDs: [])
    }

    private static func contributingTasks(for goal: Goal, visitedGoalIDs: Set<UUID>) -> [AppTask] {
        guard !visitedGoalIDs.contains(goal.id) else { return [] }
        let nextVisited = visitedGoalIDs.union([goal.id])
        let listTasks = (goal.listLinks ?? []).flatMap(\.tasks)
        let subGoalTasks = (goal.subGoals ?? []).flatMap {
            contributingTasks(for: $0, visitedGoalIDs: nextVisited)
        }
        return dedupe(listTasks + subGoalTasks).filter { !$0.isCancelled }
    }

    private static func linkedListCount(for goal: Goal, visitedGoalIDs: Set<UUID> = []) -> Int {
        guard !visitedGoalIDs.contains(goal.id) else { return 0 }
        let nextVisited = visitedGoalIDs.union([goal.id])
        let ownCount = (goal.listLinks ?? []).filter { $0.area != nil || $0.project != nil }.count
        return (goal.subGoals ?? []).reduce(ownCount) {
            $0 + linkedListCount(for: $1, visitedGoalIDs: nextVisited)
        }
    }

    private static func loggedMinutes(for goal: Goal, visitedGoalIDs: Set<UUID> = []) -> Int {
        guard !visitedGoalIDs.contains(goal.id) else { return 0 }
        let nextVisited = visitedGoalIDs.union([goal.id])
        let ownMinutes = Int(goal.loggedHours * 60)
        return (goal.subGoals ?? []).reduce(ownMinutes) {
            $0 + loggedMinutes(for: $1, visitedGoalIDs: nextVisited)
        }
    }

    static func summary(for goal: Goal, now: Date = Date()) -> GoalContributionSummary {
        let tasks = contributingTasks(for: goal)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let openTasks = tasks.filter { !$0.isDone }

        let nextAction = openTasks
            .sorted { lhs, rhs in
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
            directTaskCount: 0,
            linkedListCount: linkedListCount(for: goal),
            focusMinutes: tasks.reduce(loggedMinutes(for: goal)) { $0 + max(0, $1.actualMinutes) },
            overdueTaskCount: overdueCount,
            recentCompletedCount: recentCompleted,
            nextActionTitle: nextAction
        )
    }

    private static func dedupe(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
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

enum GoalHabitMomentumResolver {
    static func summary(for goal: Goal, now: Date = Date()) -> GoalHabitMomentumSummary {
        let habits = goal.habits ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayKey = DateFormatters.dateKey(from: today)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        var dueToday = 0
        var doneToday = 0
        var thisWeek = 0
        var last7Days = 0

        for habit in habits {
            let keys = Set((habit.completions ?? []).map(\.date))
            if isHabit(habit, dueOn: today, calendar: calendar) {
                dueToday += 1
                if keys.contains(todayKey) {
                    doneToday += 1
                }
            }

            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                if keys.contains(DateFormatters.dateKey(from: date)) {
                    last7Days += 1
                }
            }

            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart), date <= today else { continue }
                if keys.contains(DateFormatters.dateKey(from: date)) {
                    thisWeek += 1
                }
            }
        }

        return GoalHabitMomentumSummary(
            linkedHabitCount: habits.count,
            dueTodayCount: dueToday,
            doneTodayCount: doneToday,
            thisWeekCount: thisWeek,
            last7DayCount: last7Days
        )
    }

    private static func isHabit(_ habit: Habit, dueOn date: Date, calendar: Calendar) -> Bool {
        switch habit.frequencyType {
        case .daily:
            return true
        case .daysOfWeek:
            return habit.frequencyDays.contains(Habit.weekdayIndex(for: date, calendar: calendar))
        case .timesPerWeek:
            return true
        case .monthly:
            let day = calendar.component(.day, from: date)
            let target = habit.frequencyDays.first ?? 1
            let range = calendar.range(of: .day, in: .month, for: date)
            let lastDay = range?.upperBound.advanced(by: -1) ?? 31
            return day == min(max(1, target), lastDay)
        }
    }
}
