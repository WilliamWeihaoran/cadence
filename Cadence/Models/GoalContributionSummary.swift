import Foundation

struct GoalContributionSummary {
    let progressType: GoalProgressType
    let targetHours: Double
    let totalTasks: Int
    let completedTasks: Int
    let directTaskCount: Int
    let linkedListCount: Int
    let focusMinutes: Int
    let overdueTaskCount: Int
    let recentCompletedCount: Int
    let nextActionTitle: String?
    /// `yyyy-MM-dd` due date of the `nextActionTitle` task, `nil` when it has none. The next
    /// action is picked partly *by* due date, so surfaces that show the title can show why.
    let nextActionDueDate: String?

    /// Bug fix: this previously ignored `progressType` entirely and always computed a
    /// subtask completion ratio, even for goals configured with `progressType == .hours`.
    /// That meant an "hours" goal's progress bar (GoalsView/GoalInspectorView/widgets, all of
    /// which read `summary.progress`) never reflected `loggedHours`/`targetHours` at all.
    var progress: Double {
        switch progressType {
        case .hours:
            guard targetHours > 0 else { return 0 }
            let targetMinutes = targetHours * 60
            guard targetMinutes > 0 else { return 0 }
            return min(1.0, Double(focusMinutes) / targetMinutes)
        case .subtasks:
            guard totalTasks > 0 else { return 0 }
            return min(1.0, Double(completedTasks) / Double(totalTasks))
        }
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
        // `goal.tasks` — the inverse of `AppTask.goal` — was omitted here, so a task assigned
        // straight to a goal contributed nothing to its progress. iOS's task sheet writes exactly
        // that relationship, recurrence and duplication copy it forward, and `CadenceReadService`
        // already counts those tasks, so the same goal reported different numbers depending on
        // which surface asked. Directly-assigned work is the most explicit statement a user can
        // make about what a goal is made of; it counts.
        let directTasks = goal.tasks ?? []
        let listTasks = (goal.listLinks ?? []).flatMap(\.tasks)
        let subGoalTasks = (goal.subGoals ?? []).flatMap {
            contributingTasks(for: $0, visitedGoalIDs: nextVisited)
        }
        return dedupe(directTasks + listTasks + subGoalTasks).filter { !$0.isCancelled }
    }

    /// Tasks pointed straight at this goal (or one of its sub-goals) rather than reached through a
    /// linked list. Deduped and cancel-filtered the same way `contributingTasks` is, so this is a
    /// true subset of it and can never exceed `totalTasks`.
    static func directTasks(for goal: Goal, visitedGoalIDs: Set<UUID> = []) -> [AppTask] {
        guard !visitedGoalIDs.contains(goal.id) else { return [] }
        let nextVisited = visitedGoalIDs.union([goal.id])
        let own = goal.tasks ?? []
        let nested = (goal.subGoals ?? []).flatMap { directTasks(for: $0, visitedGoalIDs: nextVisited) }
        return dedupe(own + nested).filter { !$0.isCancelled }
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

    /// The goal's open, past-due contributing tasks. Exposed as tasks rather than only as a count
    /// so callers that roll several goals up can union them: `contributingTasks` already walks
    /// sub-goals, so a direction's tasks include its milestones' tasks and adding the two counts
    /// together reports each overdue task twice.
    static func overdueTasks(for goal: Goal, now: Date = Date()) -> [AppTask] {
        overdueTasks(among: contributingTasks(for: goal), now: now)
    }

    private static func overdueTasks(among tasks: [AppTask], now: Date) -> [AppTask] {
        let today = Calendar.current.startOfDay(for: now)
        return tasks.filter { task in
            guard !task.isDone else { return false }
            guard !task.dueDate.isEmpty, let due = DateFormatters.date(from: task.dueDate) else { return false }
            return due < today
        }
    }

    static func summary(for goal: Goal, now: Date = Date()) -> GoalContributionSummary {
        let tasks = contributingTasks(for: goal)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let openTasks = tasks.filter { !$0.isDone }

        // Next Action is a suggestion to go do something, so it has to be something you can reach.
        // Completed and archived lists are hidden from the sidebar, All Tasks, and every picker —
        // a next action inside one names a task the user cannot navigate to. Progress deliberately
        // still counts those tasks: archiving a finished project must not walk a goal backwards.
        let actionableTasks = openTasks.filter(\.isInActiveContainer)

        let nextAction = actionableTasks
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
            .first

        let overdueCount = overdueTasks(among: tasks, now: now).count

        let recentCompleted = tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return completedAt >= recentStart
        }.count

        return GoalContributionSummary(
            progressType: goal.progressType,
            targetHours: goal.targetHours,
            totalTasks: tasks.count,
            completedTasks: tasks.filter(\.isDone).count,
            directTaskCount: directTasks(for: goal).count,
            linkedListCount: linkedListCount(for: goal),
            focusMinutes: tasks.reduce(loggedMinutes(for: goal)) { $0 + max(0, $1.actualMinutes) },
            overdueTaskCount: overdueCount,
            recentCompletedCount: recentCompleted,
            nextActionTitle: nextAction?.title,
            nextActionDueDate: nextAction.map(\.dueDate).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func dedupe(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }
}

enum GoalHabitMomentumResolver {
    /// Habits attached to this goal *and* to its sub-goals.
    ///
    /// This used to read `goal.habits` flat while `GoalContributionResolver` recursed sub-goals,
    /// so a habit attached to a milestone showed up nowhere on its direction — "0 habits" on the
    /// same card whose percentage that milestone's tasks were moving. Both habit editors offer
    /// milestones as attachment targets, so this is the normal way to attach one.
    static func linkedHabits(for goal: Goal, visitedGoalIDs: Set<UUID> = []) -> [Habit] {
        guard !visitedGoalIDs.contains(goal.id) else { return [] }
        let nextVisited = visitedGoalIDs.union([goal.id])
        let own = goal.habits ?? []
        let nested = (goal.subGoals ?? []).flatMap { linkedHabits(for: $0, visitedGoalIDs: nextVisited) }
        var seen = Set<UUID>()
        return (own + nested).filter { seen.insert($0.id).inserted }
    }

    static func summary(for goal: Goal, now: Date = Date()) -> GoalHabitMomentumSummary {
        let habits = linkedHabits(for: goal)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayKey = DateFormatters.dateKey(from: today)
        // `Habit.weeklyStreak` forces ISO 8601 Monday weeks, and `Habit.weekdayIndex` is Monday=1.
        // Reading `Calendar.current`'s week here instead put "this week" on a Sunday boundary in
        // en_US, so a Mon/Wed/Fri habit reported 0 completions this week on the Sunday that the
        // streak still counted as satisfied. One vocabulary for "week", and it is the habit's.
        let isoCalendar = Habit.isoWeekCalendar(inheritingTimeZoneFrom: calendar)
        let weekStart = isoCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        var dueToday = 0
        var doneToday = 0
        var thisWeek = 0
        var last7Days = 0

        for habit in habits {
            let keys = Set((habit.completions ?? []).map(\.date))
            if habit.isDue(on: today, calendar: calendar) {
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

    // `isHabit(_:dueOn:calendar:)` used to live here as a line-for-line fork of `Habit.isDue`.
    // The fork had a real reason once — `isDue` lived in `HabitInsights.swift`, which the
    // `CadenceMCPServer` target does not compile — but `isDue` moved into `Habit.swift`, which
    // that target *does* compile, so since then the copy has been pure drift risk. It is gone;
    // this resolver now asks the habit itself, and any change to due-ness reaches both surfaces.
}
