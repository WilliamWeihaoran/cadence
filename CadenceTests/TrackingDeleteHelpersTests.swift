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
    /// switches; the enum owns it now, and **nothing forwards to it any more** — every caller
    /// reads `priority.rank`.
    ///
    /// This used to end in a loop over `TaskPriority.allCases` asserting each surviving
    /// free-function spelling against the enum, because a forwarder that drifts is a sort that
    /// silently disagrees with every other sort. T-1011 inlined the last four call sites and
    /// deleted both forwarders, so there is nothing left for that loop to name — the empty
    /// declaring set is asserted directly by
    /// `everyPriorityRankSpellingInProductionSourceIsOneTheRankLoopReaches` below, which is now
    /// the whole of the anti-drift guard.
    ///
    /// What stays here is the property the rest of the codebase cites this test by name for:
    /// `TaskPriority.rank` is **ordered and injective**. `CadenceTaskQuerySupport.sortKeyOrder`
    /// and `MobileTaskSortStabilityTests` both lean on the injectivity to treat
    /// `lhs.priority != rhs.priority` and a rank comparison as the same question.
    ///
    /// A third spelling used to be asserted here: `taskPriorityRank` in
    /// `macOS/Views/TaskSortHelpers.swift`, described above as "the spelling that drives every
    /// macOS task sort". It drove nothing — `TaskOrdering.precedes` reads `priority.rank`
    /// directly — and the file is gone (T-639).
    @Test func priorityRankIsOneOrderingSharedByEveryCaller() {
        #expect(TaskPriority.high.rank > TaskPriority.medium.rank)
        #expect(TaskPriority.medium.rank > TaskPriority.low.rank)
        #expect(TaskPriority.low.rank > TaskPriority.none.rank)

        // The ordering is total: no two priorities may share a rank.
        #expect(Set(TaskPriority.allCases.map(\.rank)).count == TaskPriority.allCases.count)
    }

    /// **The declaring set is empty, and that is now the whole guard.**
    ///
    /// The history is a shrinking list. Eight hand-written priority switches became one enum
    /// property plus forwarders; T-670 removed the two forwarders no test could *reach*
    /// (`CadenceTodayWidgetSupport` and `GoalContributionSummary`, both `private static`, both
    /// correct — the state that precedes drift, and the widget's was the dangerous one because
    /// `CadenceWidgets` compiles `Services/` and `Models/` but not `Shared/`, so a divergence
    /// there ships to the Home Screen with this suite green). T-1011 removed the last two, in
    /// `CadenceTaskQuerySupport` and `CalendarBoardPlannerSupport`: between them they had four
    /// call sites, all now spelling `priority.rank` directly.
    ///
    /// So there is no longer a set of "blessed" forwarders to keep honest against the enum, and
    /// the loop that did that is gone with them. What remains is stronger and cheaper: **no**
    /// `func priorityRank(` may exist in production source at all. A re-grown forwarder — private
    /// or not, correct or not — fails here the day it is written, rather than the day it drifts.
    @Test func everyPriorityRankSpellingInProductionSourceIsOneTheRankLoopReaches() throws {
        let readStripped = CadenceSourceScan.strippedSourceReader()
        var declaringFiles: [String] = []
        var scannedFiles = 0

        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                scannedFiles += 1
                if try readStripped(path).contains("func priorityRank(") {
                    declaringFiles.append(path)
                }
            }
        }

        #expect(declaringFiles.sorted() == [String]())

        // Non-vacuity matters more for an empty expectation than for any other kind, because a
        // walk that opened nothing produces exactly the same answer as a walk that found nothing.
        // Three separate ways for this to have been a real sweep:
        //
        // 1. It really walked the tree, not an empty directory list.
        #expect(scannedFiles > 400)
        // 2. The two files that lost a forwarder are still readable and still hold their other
        //    contents, so the paths did not silently stop resolving.
        #expect(try readStripped("Cadence/Shared/CadenceTaskQuerySupport.swift")
            .contains("static func sortKeyOrder("))
        #expect(try readStripped("Cadence/Shared/CadenceCalendarPlanningSupport.swift")
            .contains("static func railTaskSort("))
        // 3. The needle itself still matches when a file really does declare a function that way,
        //    which the stripped reader is what decides — so a stripper that started returning
        //    empty strings cannot pass this test.
        #expect(try readStripped("Cadence/Shared/CadenceCalendarPlanningSupport.swift")
            .contains("func railAnchorKey("))
    }

    /// Asserting the rank forwarders is not enough on its own — the comparator could stop calling
    /// them. This pins the pair the rank loop above cannot reach: `.low` against `.none`, through
    /// `TaskOrdering.precedes` itself.
    ///
    /// It used to go through `taskSortPrecedes`, a macOS-only forwarder with no production caller
    /// of its own, deleted by T-639. The assertions are the same ones; only the spelling under
    /// test changed, from a wrapper nothing ran to the comparator every surface runs.
    @Test func prioritySortRanksALowPriorityTaskAboveAnUnprioritisedOne() {
        let low = AppTask(title: "Low")
        low.priority = .low
        low.order = 1
        let unset = AppTask(title: "Unset")
        unset.priority = TaskPriority.none
        unset.order = 0

        #expect(TaskOrdering.precedes(low, unset, field: .priority, direction: .descending))
        #expect(!TaskOrdering.precedes(unset, low, field: .priority, direction: .descending))
        // Ascending is the same ordering read backwards, not a different ordering.
        #expect(TaskOrdering.precedes(unset, low, field: .priority, direction: .ascending))
    }
}
