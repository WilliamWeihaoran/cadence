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

        try modelContext.deleteGoal(direction)

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

        try modelContext.deleteGoal(milestone)

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
        try modelContext.deleteGoal(direction)
        let after = try modelContext.fetch(FetchDescriptor<Goal>()).count

        // The goal itself, plus everything the alert promised.
        #expect(before - after == announced + 1)
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.title) == ["Learn guitar"])
    }

    /// **The macOS confirmation's own sentence, measured against what the delete removes
    /// ([[T-1327]]).**
    ///
    /// `theNestedGoalCountMatchesWhatDeletingActuallyRemoves` above pins the shared *walk*, and
    /// that was the whole of it: neither platform's confirmation **string** was measured against
    /// it, and macOS's was built from `(goal.subGoals ?? []).count` inside a view body — direct
    /// children — so a goal -> milestone -> sub-milestone tree was announced as "1 milestone" and
    /// lost two. Under-promising a delete is the direction [[T-433]] forbids.
    ///
    /// The number is read back **out of the sentence** rather than recomputed, so the assertion is
    /// the one the user experiences: what the alert says, plus the goal it names, is what the store
    /// loses. A sentence that stopped interpolating the count fails here too.
    @Test func theMacOSGoalDeleteConfirmationNamesTheWholeSubtreeItRemoves() throws {
        let modelContext = try makeContext()

        let direction = Goal(title: "Finish thesis")
        let milestone = Goal(title: "Chapter 1")
        milestone.parentGoal = direction
        let subMilestone = Goal(title: "Section 1.1")
        subMilestone.parentGoal = milestone
        for goal in [direction, milestone, subMilestone] {
            modelContext.insert(goal)
        }
        try modelContext.save()

        let message = CadenceTrackingMutationSupport.goalDeleteConfirmationMessage(for: direction)
        #expect(
            message == "\"Finish thesis\" and its 2 milestones will be deleted. "
                + "Linked lists, habits and tasks are kept. This cannot be undone.",
            "the macOS confirmation reads: \(message)"
        )

        let announced = try #require(
            message.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first,
            "the sentence names no number at all"
        )
        let before = try modelContext.fetch(FetchDescriptor<Goal>()).count
        try modelContext.deleteGoal(direction)
        let after = try modelContext.fetch(FetchDescriptor<Goal>()).count

        #expect(
            before - after == announced + 1,
            "the alert promised \(announced) milestones and the delete took \(before - after - 1)"
        )
    }

    /// The count of one, and the goal that has none — the two cases the sentence branches on.
    ///
    /// "1 milestones" is the [[T-844]] defect this sentence was one interpolation away from, which
    /// is why it goes through `CadencePluralization.phrase`; a leaf goal names no count at all
    /// rather than promising "0 milestones".
    @Test func theMacOSGoalDeleteConfirmationPluralisesAndSaysNothingAtZero() throws {
        let modelContext = try makeContext()

        let direction = Goal(title: "Finish thesis")
        let milestone = Goal(title: "Chapter 1")
        milestone.parentGoal = direction
        let leaf = Goal(title: "Read more")
        for goal in [direction, milestone, leaf] {
            modelContext.insert(goal)
        }
        try modelContext.save()

        let nested = CadenceTrackingMutationSupport.goalDeleteConfirmationMessage(for: direction)
        #expect(nested.contains("and its 1 milestone will be deleted"))
        #expect(!nested.contains("1 milestones"), "the count of one reads as a plural")

        let none = CadenceTrackingMutationSupport.goalDeleteConfirmationMessage(for: leaf)
        #expect(
            none == "\"Read more\" will be deleted. "
                + "Linked lists, habits and tasks are kept. This cannot be undone."
        )
        #expect(!none.contains("milestone"), "a leaf goal's sentence still names milestones")
    }

    /// **The sheet reads the shared sentence rather than counting its own.**
    ///
    /// The two tests above measure the function; this one measures the *site*, which is where the
    /// defect was. `requestDelete` is inside a `View`, so the string it hands
    /// `DeleteConfirmationManager` is unreachable from this target — and reverting it to
    /// `(goal.subGoals ?? []).count` would leave both tests above green.
    @Test func theMacOSGoalDeleteSheetReadsTheSharedSentenceRatherThanCountingItsOwn() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Sheets/CreateGoalSheet.swift")
        let body = try #require(
            CadenceSourceScan.functionBody(named: "requestDelete", in: sheet),
            "requestDelete is no longer a function in CreateGoalSheet"
        )

        #expect(body.contains("CadenceTrackingMutationSupport.goalDeleteConfirmationMessage(for: goal)"))
        #expect(
            !body.contains("subGoals"),
            "the confirmation is counting goals for itself again"
        )
        #expect(
            !body.contains("milestone"),
            "the confirmation is building its own sentence again"
        )
        // Non-vacuity: the body really is the one that raises the confirmation, so a scan that
        // returned the wrong declaration cannot pass the three assertions above by being empty.
        #expect(body.contains("DeleteConfirmationManager.shared.presentRefusable("))
        #expect(body.contains("try modelContext.deleteGoal(goal)"))
    }

    /// A leaf goal announces nothing nested.
    @Test func aGoalWithNoMilestonesCountsNone() throws {
        let modelContext = try makeContext()

        let goal = Goal(title: "Read more")
        modelContext.insert(goal)
        try modelContext.save()

        #expect(GoalAssignmentRules.nestedGoalCount(under: goal) == 0)
    }

    /// **The nesting half of the question [[T-1312]] settled for tasks, decided the other way and
    /// deliberately so ([[T-1324]]).** `deleteGoal` walks `GoalAssignmentRules.deletionCascade`
    /// with no container filter, so a milestone whose own `context` is *Life* goes with its *Work*
    /// parent; `deleteContext(Work)` would have left that same milestone alive. The two readings
    /// are not the same disagreement T-1312 fixed, and the argument that settled that one does not
    /// transfer:
    ///
    /// * T-1312's fourth leg was **redundant** — a task that was really the context's own arrived
    ///   through its area, its project or its own `context`, so dropping the leg subtracted
    ///   nothing but somebody else's rows. `subGoals` is the only leg that reaches a milestone at
    ///   all, so filtering it would not remove a double count, it would redefine the delete.
    /// * `AppTask.goal` is **free** of `AppTask.context`; `Goal.parentGoal` *derives* it —
    ///   `CadenceTrackingMutationSupport.saveGoal` writes `context ?? parentGoal?.context`, so a
    ///   milestone's context defaults to its parent's and a differing one is an explicit override.
    /// * A task severed from a goal stays the object it was, in a list it already had. A milestone
    ///   severed from its parent is not: `GoalMissionGrouping.groups` builds the Goals page out of
    ///   top-level goals and the milestones nested under them, and `canOwnMilestones` keeps the
    ///   hierarchy two deep, so a surviving milestone is **promoted to a top-level direction** —
    ///   a row the user never created, with equal billing to their real directions.
    ///
    /// What T-1312 protects is protected here too, and that is the second half of this test: the
    /// foreign milestone's task and habit are the user's real work, and they survive with the
    /// reference severed exactly as they survive `deleteContext`.
    @Test func deletingAGoalTakesAMilestoneWhoseOwnContextIsElsewhere() throws {
        let modelContext = try makeContext()

        let work = Context(name: "Work")
        let life = Context(name: "Life")
        let direction = Goal(title: "Ship the thesis", context: work)
        let ownMilestone = Goal(title: "Chapter 1", context: work)
        ownMilestone.parentGoal = direction
        // The row this ticket is about: parented under a Work direction, filed under Life. The
        // editor offers both pickers, so it takes one deliberate change to build.
        let foreignMilestone = Goal(title: "Chapter 2", context: life)
        foreignMilestone.parentGoal = direction
        let unrelated = Goal(title: "Learn to sail", context: life)

        let lifeTask = AppTask(title: "Life task")
        lifeTask.context = life
        lifeTask.goal = foreignMilestone
        let lifeHabit = Habit(title: "Read nightly", context: life, goal: foreignMilestone)

        for model in [
            work as any PersistentModel, life, direction, ownMilestone, foreignMilestone,
            unrelated, lifeTask, lifeHabit
        ] {
            modelContext.insert(model)
        }
        try modelContext.save()

        // The confirmation counts the same walk, so the milestone filed elsewhere is named to the
        // user before it goes — `nestedGoalCount` is `deletionCascade`'s count.
        #expect(GoalAssignmentRules.nestedGoalCount(under: direction) == 2)

        try modelContext.deleteGoal(direction)
        try modelContext.save()

        #expect(
            try modelContext.fetch(FetchDescriptor<Goal>()).map(\.title) == ["Learn to sail"],
            "deleteGoal stopped taking the whole nested subtree (T-1324)"
        )

        // Neither context is touched, and neither is the work filed under the foreign milestone.
        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 2)

        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.map(\.title) == ["Life task"])
        #expect(tasks.first?.goal == nil, "a surviving task still points at a deleted milestone")
        #expect(tasks.first?.context?.id == life.id, "the survivor lost its own context")

        let habits = try modelContext.fetch(FetchDescriptor<Habit>())
        #expect(habits.map(\.title) == ["Read nightly"])
        #expect(habits.first?.goal == nil, "a surviving habit still points at a deleted milestone")
        #expect(habits.first?.context?.id == life.id)
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

        try modelContext.deleteGoal(first)

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

        try modelContext.deleteHabit(habit)

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

        try modelContext.deleteHabit(orphan)

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

        try modelContext.deleteHabit(habit)

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
