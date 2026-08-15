import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Deletion for goals and habits. Neither model had a delete path at all before this: the only
/// code that removed either was the whole-context cascade and the privacy reset, so a mistakenly
/// created goal or habit was permanent, and a habit with no context and no goal was unreachable
/// by every path.
@MainActor
struct TrackingDeleteHelpersTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// The tree goes; the user's actual work does not. Lists, habits and tasks outlive any goal
    /// that organised them — the relationships are severed, the objects survive.
    @Test func deletingAGoalTakesItsMilestonesAndLinksButKeepsTheWork() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Work")
        let area = Area(name: "Thesis", context: context)
        let direction = Goal(title: "Finish thesis", context: context)
        let milestone = Goal(title: "Chapter 1", context: context)
        milestone.parentGoal = direction
        let grandchild = Goal(title: "Section 1.1", context: context)
        grandchild.parentGoal = milestone

        let task = AppTask(title: "Draft")
        task.area = area
        task.goal = milestone

        let habit = Habit(title: "Write daily", goal: direction)
        let link = GoalListLink(goal: direction, area: area)

        for model in [context as any PersistentModel, area, direction, milestone, grandchild, task, habit, link] {
            modelContext.insert(model)
        }
        try modelContext.save()

        modelContext.deleteGoal(direction)

        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)

        // Survivors, with their goal reference cleared.
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.goal == nil)
        #expect(tasks.first?.area?.name == "Thesis")

        let habits = try modelContext.fetch(FetchDescriptor<Habit>())
        #expect(habits.count == 1)
        #expect(habits.first?.goal == nil)

        #expect(try modelContext.fetch(FetchDescriptor<Area>()).count == 1)
    }

    /// Deleting a milestone must not take its parent with it.
    @Test func deletingAMilestoneLeavesItsDirectionIntact() throws {
        let modelContext = try makeContext()

        let direction = Goal(title: "Get healthy")
        let milestone = Goal(title: "Run a 10k")
        milestone.parentGoal = direction

        modelContext.insert(direction)
        modelContext.insert(milestone)
        try modelContext.save()

        modelContext.deleteGoal(milestone)

        let remaining = try modelContext.fetch(FetchDescriptor<Goal>())
        #expect(remaining.map(\.title) == ["Get healthy"])
        #expect(remaining.first?.subGoals?.isEmpty != false)
    }

    /// The confirmation alert must name what actually goes.
    ///
    /// It counted `GoalAssignmentRules.milestones(of:)` — direct children only — while the delete
    /// collected the whole subtree, so a goal → milestone → sub-milestone tree was announced as
    /// "its 1 milestone" and then took two. Both now read the same walk.
    @Test func theNestedGoalCountMatchesWhatDeletingActuallyRemoves() throws {
        let modelContext = try makeContext()

        let direction = Goal(title: "Finish thesis")
        let milestone = Goal(title: "Chapter 1")
        milestone.parentGoal = direction
        let subMilestone = Goal(title: "Section 1.1")
        subMilestone.parentGoal = milestone
        let unrelated = Goal(title: "Learn guitar")

        for goal in [direction, milestone, subMilestone, unrelated] {
            modelContext.insert(goal)
        }
        try modelContext.save()

        let announced = GoalAssignmentRules.nestedGoalCount(under: direction)
        #expect(announced == 2)

        let before = try modelContext.fetch(FetchDescriptor<Goal>()).count
        modelContext.deleteGoal(direction)
        let after = try modelContext.fetch(FetchDescriptor<Goal>()).count

        // The goal itself, plus everything the alert promised.
        #expect(before - after == announced + 1)
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.title) == ["Learn guitar"])
    }

    /// A leaf goal announces nothing nested.
    @Test func aGoalWithNoMilestonesCountsNone() throws {
        let modelContext = try makeContext()

        let goal = Goal(title: "Read more")
        modelContext.insert(goal)
        try modelContext.save()

        #expect(GoalAssignmentRules.nestedGoalCount(under: goal) == 0)
    }

    /// A corrupted `parentGoal` chain must not spin the collection walk forever.
    @Test func deletingAGoalTerminatesOnACycle() throws {
        let modelContext = try makeContext()

        let first = Goal(title: "A")
        let second = Goal(title: "B")
        second.parentGoal = first
        modelContext.insert(first)
        modelContext.insert(second)
        try modelContext.save()

        // Force the cycle the visited-set guard exists for.
        first.parentGoal = second
        try modelContext.save()

        modelContext.deleteGoal(first)

        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
    }

    @Test func deletingAHabitTakesItsCompletions() throws {
        let modelContext = try makeContext()

        let habit = Habit(title: "Meditate")
        let other = Habit(title: "Read")
        modelContext.insert(habit)
        modelContext.insert(other)
        modelContext.insert(HabitCompletion(date: "2026-08-10", habit: habit))
        modelContext.insert(HabitCompletion(date: "2026-08-11", habit: habit))
        modelContext.insert(HabitCompletion(date: "2026-08-11", habit: other))
        try modelContext.save()

        modelContext.deleteHabit(habit)

        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).map(\.title) == ["Read"])

        // The other habit's history is untouched, and no orphan rows are left behind.
        let completions = try modelContext.fetch(FetchDescriptor<HabitCompletion>())
        #expect(completions.count == 1)
        #expect(completions.first?.habit?.title == "Read")
    }

    /// The case that had no escape at all: `CreateHabitSheet` with neither a context nor a goal
    /// picked produces a habit that the whole-context cascade can never reach.
    @Test func aHabitWithNoContextAndNoGoalCanBeDeleted() throws {
        let modelContext = try makeContext()

        let orphan = Habit(title: "Stretch")
        #expect(orphan.context == nil)
        #expect(orphan.goal == nil)

        modelContext.insert(orphan)
        try modelContext.save()

        modelContext.deleteHabit(orphan)

        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).isEmpty)
    }

    /// Deleting a habit must not delete the goal it pointed at.
    @Test func deletingAHabitLeavesItsGoalIntact() throws {
        let modelContext = try makeContext()

        let goal = Goal(title: "Get healthy")
        let habit = Habit(title: "Run", goal: goal)
        modelContext.insert(goal)
        modelContext.insert(habit)
        try modelContext.save()

        modelContext.deleteHabit(habit)

        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.title) == ["Get healthy"])
    }

    /// Every "sort by priority" in the app means one ordering. It existed as eight independent
    /// switches; the enum owns it now, and the surviving free-function spellings delegate.
    ///
    /// The point of the loop is that it names **every** spelling a test can reach, over **every**
    /// case. The previous version asserted the enum's own constants and exactly one forwarder, so
    /// swapping `.none` and `.low` inside `taskPriorityRank` — the spelling that drives every
    /// macOS task sort — left the suite green while a low-priority task sorted below an
    /// unprioritised one. Anything that re-grows a hand-written switch has to fail here.
    @Test func priorityRankIsOneOrderingSharedByEveryCaller() {
        #expect(TaskPriority.high.rank > TaskPriority.medium.rank)
        #expect(TaskPriority.medium.rank > TaskPriority.low.rank)
        #expect(TaskPriority.low.rank > TaskPriority.none.rank)

        // The ordering is total: no two priorities may share a rank.
        #expect(Set(TaskPriority.allCases.map(\.rank)).count == TaskPriority.allCases.count)

        for priority in TaskPriority.allCases {
            #expect(CadenceTaskQuerySupport.priorityRank(priority) == priority.rank)
            #expect(CalendarBoardPlannerSupport.priorityRank(priority) == priority.rank)
#if os(macOS)
            #expect(taskPriorityRank(priority) == priority.rank)
#endif
        }
    }

    /// `taskSortPrecedes` is the comparator behind every macOS "sort by priority", and it is the
    /// only consumer of `taskPriorityRank`. Asserting the forwarder is not enough on its own —
    /// the comparator could stop calling it. This pins the pair `TaskSortHelperTests` never
    /// compares: `.low` against `.none`.
    @Test func macOSPrioritySortRanksALowPriorityTaskAboveAnUnprioritisedOne() {
#if os(macOS)
        let low = AppTask(title: "Low")
        low.priority = .low
        low.order = 1
        let unset = AppTask(title: "Unset")
        unset.priority = TaskPriority.none
        unset.order = 0

        #expect(taskSortPrecedes(low, unset, field: .priority, direction: .descending))
        #expect(!taskSortPrecedes(unset, low, field: .priority, direction: .descending))
        // Ascending is the same ordering read backwards, not a different ordering.
        #expect(taskSortPrecedes(unset, low, field: .priority, direction: .ascending))
#endif
    }
}
