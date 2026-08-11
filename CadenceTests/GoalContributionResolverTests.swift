import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct GoalContributionResolverTests {
    @Test func contributionSummaryCountsBothLinkedListsAndDirectTaskLinks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Goals Area", context: context)
        let project = Project(name: "Side Project", context: context)
        let goal = Goal(title: "Ship Goals", context: context)
        goal.loggedHours = 1.5

        let directDone = AppTask(title: "Direct done")
        directDone.area = area
        directDone.context = context
        directDone.goal = goal
        directDone.status = .done
        directDone.actualMinutes = 30
        directDone.completedAt = Date()

        let cancelledDirect = AppTask(title: "Cancelled")
        cancelledDirect.goal = goal
        cancelledDirect.status = .cancelled

        let directOnly = AppTask(title: "Direct only")
        directOnly.goal = goal
        directOnly.status = .done
        directOnly.actualMinutes = 999

        let areaOpen = AppTask(title: "Area open")
        areaOpen.area = area
        areaOpen.context = context
        areaOpen.priority = .high
        areaOpen.dueDate = "2026-04-01"

        let areaDone = AppTask(title: "Area done")
        areaDone.area = area
        areaDone.context = context
        areaDone.status = .done

        let unrelatedProjectTask = AppTask(title: "Unrelated")
        unrelatedProjectTask.project = project
        unrelatedProjectTask.context = context

        let link = GoalListLink(goal: goal, area: area)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)
        modelContext.insert(directDone)
        modelContext.insert(cancelledDirect)
        modelContext.insert(directOnly)
        modelContext.insert(areaOpen)
        modelContext.insert(areaDone)
        modelContext.insert(unrelatedProjectTask)
        modelContext.insert(link)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: "2026-04-30") ?? Date())

        // `directDone` is reachable both ways (area link *and* `task.goal`) and must be counted
        // once; `cancelledDirect` is excluded like any cancelled task; `directOnly` is the case
        // that used to vanish entirely.
        #expect(summary.totalTasks == 4)
        #expect(summary.completedTasks == 3)
        #expect(summary.directTaskCount == 2)
        #expect(summary.linkedListCount == 1)
        // 90m logged on the goal + 30m on `directDone` + 999m on `directOnly`.
        #expect(summary.focusMinutes == 1119)
        #expect(summary.overdueTaskCount == 1)
        #expect(summary.nextActionTitle == "Area open")
        #expect(goal.progress == 3.0 / 4.0)
    }

    /// `directTaskCount` is a subset of `totalTasks`, never an addition to it. A task that is both
    /// directly assigned and inside a linked list is one contribution, not two.
    @Test func directTaskCountNeverDoubleCountsATaskReachableBothWays() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Overlap", context: context)
        let goal = Goal(title: "Ship", context: context)

        let both = AppTask(title: "In the area and on the goal")
        both.area = area
        both.context = context
        both.goal = goal

        let link = GoalListLink(goal: goal, area: area)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(both)
        modelContext.insert(link)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal)

        #expect(summary.totalTasks == 1)
        #expect(summary.directTaskCount == 1)
    }

    /// The `!task.isDone` guard in `overdueTasks` had no test that could fail without it: every
    /// existing done task in the suite carried an empty `dueDate`, so the *second* guard caught
    /// them regardless. A finished task with a past due date is the only shape that distinguishes
    /// the two, and it is the shape a goal linked to a wrapped-up project is full of.
    @Test func completedTasksWithPastDueDatesAreNotOverdue() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Wrapped up", context: context)
        let goal = Goal(title: "Last quarter", context: context)

        let doneButPastDue = AppTask(title: "Shipped late but shipped")
        doneButPastDue.area = area
        doneButPastDue.context = context
        doneButPastDue.dueDate = "2026-04-01"
        doneButPastDue.status = .done

        let stillOpen = AppTask(title: "Never finished")
        stillOpen.area = area
        stillOpen.context = context
        stillOpen.dueDate = "2026-04-02"

        let link = GoalListLink(goal: goal, area: area)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(doneButPastDue)
        modelContext.insert(stillOpen)
        modelContext.insert(link)
        try modelContext.save()

        let now = DateFormatters.date(from: "2026-04-30") ?? Date()
        #expect(GoalContributionResolver.summary(for: goal, now: now).overdueTaskCount == 1)
        #expect(
            GoalContributionResolver.overdueTasks(for: goal, now: now).map(\.title) == ["Never finished"]
        )
    }

    /// Next Action has to name something the user can actually open. Archived and completed lists
    /// are hidden from the sidebar, All Tasks, and every picker — but their tasks still count
    /// toward progress, so archiving a finished project cannot walk a goal's percentage backwards.
    @Test func nextActionSkipsArchivedListsWhileProgressStillCountsThem() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let archived = Project(name: "Legacy Migration", context: context)
        archived.status = .archived
        let live = Area(name: "Current Work", context: context)
        let goal = Goal(title: "Ship v1", context: context)

        // Higher priority and an earlier due date, so it would win the sort if it were eligible.
        let buriedTask = AppTask(title: "Task in an archived project")
        buriedTask.project = archived
        buriedTask.context = context
        buriedTask.priority = .high
        buriedTask.dueDate = "2026-01-01"

        let reachableTask = AppTask(title: "Task you can open")
        reachableTask.area = live
        reachableTask.context = context

        modelContext.insert(context)
        modelContext.insert(archived)
        modelContext.insert(live)
        modelContext.insert(goal)
        modelContext.insert(buriedTask)
        modelContext.insert(reachableTask)
        modelContext.insert(GoalListLink(goal: goal, project: archived))
        modelContext.insert(GoalListLink(goal: goal, area: live))
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: "2026-04-30") ?? Date())

        #expect(summary.nextActionTitle == "Task you can open")
        #expect(summary.totalTasks == 2)
        #expect(summary.overdueTaskCount == 1)
    }

    /// Habits attach to milestones as readily as to directions — both editors offer them — so a
    /// direction that reported "0 habits" was hiding work its own percentage was already counting.
    @Test func habitMomentumRollsUpHabitsAttachedToMilestones() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Get healthy")
        let milestone = Goal(title: "Run a 10k")
        milestone.parentGoal = direction

        let habit = Habit(title: "Run", goal: milestone)
        habit.frequencyType = .daily

        modelContext.insert(direction)
        modelContext.insert(milestone)
        modelContext.insert(habit)
        modelContext.insert(HabitCompletion(date: "2026-04-30", habit: habit))
        try modelContext.save()

        let summary = GoalHabitMomentumResolver.summary(
            for: direction,
            now: DateFormatters.date(from: "2026-04-30") ?? Date()
        )

        #expect(summary.linkedHabitCount == 1)
        #expect(summary.dueTodayCount == 1)
        #expect(summary.doneTodayCount == 1)
    }

    @Test func taskContainerNamePrefersListOverGoal() {
        let context = Context(name: "Personal")
        let area = Area(name: "Life", context: context, colorHex: "#22cc88")
        let goal = Goal(title: "Health", context: context)
        goal.colorHex = "#ff55aa"

        let task = AppTask(title: "Book appointment")
        task.area = area
        task.goal = goal

        #expect(task.containerName == "Life")
        #expect(task.containerColor == "#22cc88")

        let goalOnlyTask = AppTask(title: "Loose contributor")
        goalOnlyTask.goal = goal

        #expect(goalOnlyTask.containerName == "")
        #expect(goalOnlyTask.containerColor == "#6b7a99")
    }

    @Test func contributionSummaryRollsUpNestedSubGoals() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let parentArea = Area(name: "Parent Area", context: context)
        let childArea = Area(name: "Child Area", context: context)
        let parent = Goal(title: "Launch", context: context)
        parent.loggedHours = 1
        let child = Goal(title: "Beta", context: context)
        child.loggedHours = 0.5
        child.parentGoal = parent

        let parentTask = AppTask(title: "Parent task")
        parentTask.area = parentArea
        parentTask.context = context
        parentTask.status = .done
        parentTask.actualMinutes = 30

        let childTask = AppTask(title: "Child task")
        childTask.area = childArea
        childTask.context = context
        childTask.priority = .high
        childTask.dueDate = "2026-04-01"

        let cancelledChildTask = AppTask(title: "Cancelled child")
        cancelledChildTask.area = childArea
        cancelledChildTask.context = context
        cancelledChildTask.status = .cancelled

        let parentLink = GoalListLink(goal: parent, area: parentArea)
        let childLink = GoalListLink(goal: child, area: childArea)

        modelContext.insert(context)
        modelContext.insert(parentArea)
        modelContext.insert(childArea)
        modelContext.insert(parent)
        modelContext.insert(child)
        modelContext.insert(parentTask)
        modelContext.insert(childTask)
        modelContext.insert(cancelledChildTask)
        modelContext.insert(parentLink)
        modelContext.insert(childLink)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: parent, now: DateFormatters.date(from: "2026-04-30") ?? Date())

        #expect(parent.subGoals?.map(\.id).contains(child.id) == true)
        #expect(child.parentGoal?.id == parent.id)
        #expect(summary.totalTasks == 2)
        #expect(summary.completedTasks == 1)
        #expect(summary.linkedListCount == 2)
        #expect(summary.focusMinutes == 120)
        #expect(summary.overdueTaskCount == 1)
        #expect(summary.nextActionTitle == "Child task")
        #expect(parent.progress == 0.5)
    }

    @Test func habitMomentumSummarizesLinkedHabitsWithoutChangingProgress() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let goal = Goal(title: "Health")
        let daily = Habit(title: "Walk", goal: goal)
        daily.frequencyType = .daily
        let weekly = Habit(title: "Lift", goal: goal)
        weekly.frequencyType = .daysOfWeek
        weekly.frequencyDays = [2, 4]
        let unrelated = Habit(title: "Read")
        unrelated.frequencyType = .daily

        let today = HabitCompletion(date: "2026-04-30", habit: daily)
        let yesterday = HabitCompletion(date: "2026-04-29", habit: weekly)
        let unrelatedToday = HabitCompletion(date: "2026-04-30", habit: unrelated)

        modelContext.insert(goal)
        modelContext.insert(daily)
        modelContext.insert(weekly)
        modelContext.insert(unrelated)
        modelContext.insert(today)
        modelContext.insert(yesterday)
        modelContext.insert(unrelatedToday)
        try modelContext.save()

        let summary = GoalHabitMomentumResolver.summary(
            for: goal,
            now: DateFormatters.date(from: "2026-04-30") ?? Date()
        )

        #expect(summary.linkedHabitCount == 2)
        #expect(summary.dueTodayCount == 2)
        #expect(summary.doneTodayCount == 1)
        #expect(summary.thisWeekCount == 2)
        #expect(summary.last7DayCount == 2)
        #expect(goal.progress == 0)
    }

    @Test func monthlyHabitDueDateClampsToLastDayOfShortMonth() {
        let habit = Habit(title: "Month end review")
        habit.frequencyType = .monthly
        habit.frequencyDays = [31]

        #expect(habit.isDue(on: DateFormatters.date(from: "2026-04-30") ?? Date()) == true)
        #expect(habit.isDue(on: DateFormatters.date(from: "2026-04-29") ?? Date()) == false)
        #expect(habit.isDue(on: DateFormatters.date(from: "2026-05-31") ?? Date()) == true)
    }
}
