import Foundation
import SwiftData
import Testing
@testable import Cadence

// Targeted regression coverage for a deep audit of Goal progress calculation
// (Cadence/Models/GoalContributionSummary.swift, Goal.swift) plus the pure Gantt
// date/position math in Cadence/macOS/Views/GoalTimelineDateMath.swift. See commit message
// for the concrete bug found and fixed: `GoalContributionSummary.progress` (read by every UI
// surface via `summary.progress`, and by `Goal.progress`) previously ignored `progressType`
// entirely and always computed a subtask completion ratio, even for goals configured with
// `progressType == .hours`.
@MainActor
struct GoalProgressAuditTests {
    // MARK: - 1. Cancelled tasks are excluded from both the numerator and denominator

    @Test func cancelledListLinkedTaskIsExcludedFromSubtaskProgressEntirely() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Health", context: context)
        let goal = Goal(title: "Get fit", context: context)
        let link = GoalListLink(goal: goal, area: area)

        let doneTask = AppTask(title: "Workout 1")
        doneTask.area = area
        doneTask.status = .done
        doneTask.completedAt = Date()

        let openTask = AppTask(title: "Workout 2")
        openTask.area = area

        let cancelledTask = AppTask(title: "Workout 3 (skipped)")
        cancelledTask.area = area
        cancelledTask.status = .cancelled

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(link)
        modelContext.insert(doneTask)
        modelContext.insert(openTask)
        modelContext.insert(cancelledTask)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal)

        // The cancelled task must not appear at all — not counted as "not done" (which would
        // drag progress down) and not counted as "done" either.
        #expect(summary.totalTasks == 2)
        #expect(summary.completedTasks == 1)
        #expect(summary.progress == 0.5)
    }

    // MARK: - 2. "hours" progress type: loggedHours + task actualMinutes accumulate, capped at 1.0

    @Test func hoursProgressTypeCombinesManualLoggedHoursAndTaskActualMinutes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Thesis", context: context)
        let goal = Goal(title: "Finish thesis", context: context)
        goal.progressType = .hours
        goal.targetHours = 2 // 120 minutes
        goal.loggedHours = 1 // 60 minutes logged manually (e.g. before Focus-session tracking existed)
        let link = GoalListLink(goal: goal, area: area)

        // Focus-session logging writes to AppTask.actualMinutes (see FocusManager.swift /
        // FocusSessionSupport.swift), not directly to Goal.loggedHours — both sources should
        // roll up into the goal's hours progress.
        let task = AppTask(title: "Write chapter 1")
        task.area = area
        task.actualMinutes = 30 // 30 minutes tracked via Focus

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(link)
        modelContext.insert(task)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal)
        #expect(summary.focusMinutes == 90) // 60 manual + 30 tracked
        #expect(summary.progress == 0.75) // 90 / 120

        // Push logged hours past the target — progress must cap at 1.0, not exceed 100% or
        // produce a nonsensical ratio.
        goal.loggedHours = 10 // 600 minutes, way past the 120-minute target
        try modelContext.save()
        let overTarget = GoalContributionResolver.summary(for: goal)
        #expect(overTarget.focusMinutes == 630)
        #expect(overTarget.progress == 1.0)
    }

    // MARK: - 3. Zero linked tasks / zero target hours never divides by zero or crashes

    @Test func zeroLinkedTasksOrZeroTargetHoursYieldsZeroProgressWithoutCrashing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let subtasksGoal = Goal(title: "No tasks yet")
        // progressType defaults to .subtasks, no linked lists/subgoals/tasks at all.
        modelContext.insert(subtasksGoal)

        let hoursGoal = Goal(title: "No target set")
        hoursGoal.progressType = .hours
        hoursGoal.targetHours = 0
        hoursGoal.loggedHours = 5 // logged time with no target should still not divide by zero
        modelContext.insert(hoursGoal)

        try modelContext.save()

        let subtasksSummary = GoalContributionResolver.summary(for: subtasksGoal)
        #expect(subtasksSummary.totalTasks == 0)
        #expect(subtasksSummary.progress == 0)

        let hoursSummary = GoalContributionResolver.summary(for: hoursGoal)
        #expect(hoursSummary.progress == 0)
        #expect(subtasksGoal.progress == 0)
        #expect(hoursGoal.progress == 0)
    }

    // MARK: - 4. Moving a task between goal-linked lists recalculates both goals' progress live

    @Test func movingTaskBetweenGoalLinkedAreasRecalculatesBothGoalsProgressLive() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let areaA = Area(name: "Goal A Area", context: context)
        let areaB = Area(name: "Goal B Area", context: context)
        let goalA = Goal(title: "Goal A", context: context)
        let goalB = Goal(title: "Goal B", context: context)
        let linkA = GoalListLink(goal: goalA, area: areaA)
        let linkB = GoalListLink(goal: goalB, area: areaB)

        // Goal A starts with one done task (100%); Goal B starts empty (0%).
        let task = AppTask(title: "Shared work item")
        task.area = areaA
        task.status = .done
        task.completedAt = Date()

        modelContext.insert(context)
        modelContext.insert(areaA)
        modelContext.insert(areaB)
        modelContext.insert(goalA)
        modelContext.insert(goalB)
        modelContext.insert(linkA)
        modelContext.insert(linkB)
        modelContext.insert(task)
        try modelContext.save()

        #expect(GoalContributionResolver.summary(for: goalA).totalTasks == 1)
        #expect(goalA.progress == 1.0)
        #expect(GoalContributionResolver.summary(for: goalB).totalTasks == 0)
        #expect(goalB.progress == 0)

        // Reassign the task's list — this is the "reassign to a different goal-linked list"
        // scenario. Progress is computed live from the current relationship graph (not cached),
        // so both goals must immediately reflect the move with no stale reference to the task
        // remaining on Goal A.
        task.area = areaB
        try modelContext.save()

        let afterA = GoalContributionResolver.summary(for: goalA)
        #expect(afterA.totalTasks == 0)
        #expect(goalA.progress == 0)

        let afterB = GoalContributionResolver.summary(for: goalB)
        #expect(afterB.totalTasks == 1)
        #expect(afterB.completedTasks == 1)
        #expect(goalB.progress == 1.0)
    }

    // MARK: - 5. Deleting a milestone or habit leaves no dangling reference on its parent goal

    @Test func deletingSubGoalOrHabitLeavesNoDanglingParentGoalReference() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Personal")
        let parentGoal = Goal(title: "Get healthy", context: context)
        parentGoal.kind = .ongoing

        let keepGoal = Goal(title: "Keep", context: context)
        keepGoal.parentGoal = parentGoal
        let deleteGoal = Goal(title: "Delete me", context: context)
        deleteGoal.parentGoal = parentGoal

        let keepHabit = Habit(title: "Keep habit", context: context, goal: parentGoal)
        let deleteHabit = Habit(title: "Delete me habit", context: context, goal: parentGoal)

        modelContext.insert(context)
        modelContext.insert(parentGoal)
        modelContext.insert(keepGoal)
        modelContext.insert(deleteGoal)
        modelContext.insert(keepHabit)
        modelContext.insert(deleteHabit)
        try modelContext.save()

        #expect((parentGoal.subGoals ?? []).count == 2)
        #expect((parentGoal.habits ?? []).count == 2)

        modelContext.delete(deleteGoal)
        modelContext.delete(deleteHabit)
        try modelContext.save()

        let refetchedGoal = try #require(try modelContext.fetch(FetchDescriptor<Goal>()).first { $0.id == parentGoal.id })
        let remainingGoalIDs = (refetchedGoal.subGoals ?? []).map(\.id)
        let remainingHabitIDs = (refetchedGoal.habits ?? []).map(\.id)

        #expect(remainingGoalIDs == [keepGoal.id])
        #expect(remainingHabitIDs == [keepHabit.id])
        #expect(!remainingGoalIDs.contains(deleteGoal.id))
        #expect(!remainingHabitIDs.contains(deleteHabit.id))

        // Aggregate views over the goal's remaining milestones/habits must not crash after the
        // deletion (e.g. goal-detail nextActionTitle / dueHabitsToday-style rollups).
        _ = GoalContributionResolver.summary(for: refetchedGoal)
        for goal in refetchedGoal.subGoals ?? [] {
            _ = GoalContributionResolver.summary(for: goal)
            _ = GoalHabitMomentumResolver.summary(for: goal)
        }
        for habit in refetchedGoal.habits ?? [] {
            _ = habit.isDueToday
        }
    }

    // MARK: - 6. Habit momentum recalculates live from completion history and never touches progress

    @Test func habitMomentumRecalculatesLiveAndNeverDoubleCountsIntoGoalProgress() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let goal = Goal(title: "Wellness")
        let habit = Habit(title: "Walk", goal: goal)
        habit.frequencyType = .daily

        modelContext.insert(goal)
        modelContext.insert(habit)
        try modelContext.save()

        let now = DateFormatters.date(from: "2026-04-30") ?? Date()

        let before = GoalHabitMomentumResolver.summary(for: goal, now: now)
        #expect(before.linkedHabitCount == 1)
        #expect(before.dueTodayCount == 1)
        #expect(before.doneTodayCount == 0)
        // Habit momentum is a separate signal from task-based progress — it must never feed
        // into Goal.progress (no linked tasks exist here, so progress stays 0 regardless of
        // habit activity).
        #expect(goal.progress == 0)

        // Completion history changes; momentum must recompute live (no caching/staleness) and
        // still not affect progress.
        let completion = HabitCompletion(date: "2026-04-30", habit: habit)
        modelContext.insert(completion)
        try modelContext.save()

        let after = GoalHabitMomentumResolver.summary(for: goal, now: now)
        #expect(after.doneTodayCount == 1)
        #expect(after.last7DayCount == 1)
        #expect(goal.progress == 0)

        // Removing the completion again must be reflected immediately too.
        modelContext.delete(completion)
        try modelContext.save()
        let afterRemoval = GoalHabitMomentumResolver.summary(for: goal, now: now)
        #expect(afterRemoval.doneTodayCount == 0)
        #expect(goal.progress == 0)
    }
}

#if os(macOS)
// MARK: - 7. Gantt timeline pure date/position math edge cases (GoalTimelineDateMath.swift)

struct GoalTimelineDateMathAuditTests {
    @Test func barFrameNormalizesReversedDateRangeInsteadOfProducingNegativeWidth() {
        let calendar = Calendar.current
        let rangeStart = DateFormatters.date(from: "2026-01-01") ?? Date()
        // startDate is AFTER endDate — an invalid/reversed range a user could create via manual
        // date entry.
        let reversedStart = DateFormatters.date(from: "2026-03-10") ?? Date()
        let reversedEnd = DateFormatters.date(from: "2026-03-01") ?? Date()

        let frame = GoalTimelineDateMath.barFrame(
            start: reversedStart,
            end: reversedEnd,
            rangeStart: rangeStart,
            dayWidth: 10,
            calendar: calendar
        )

        // Must normalize to the earlier date as the visual start, with a strictly positive width.
        let expectedNormalizedFrame = GoalTimelineDateMath.barFrame(
            start: reversedEnd,
            end: reversedStart,
            rangeStart: rangeStart,
            dayWidth: 10,
            calendar: calendar
        )
        #expect(frame.width > 0)
        #expect(frame.x == expectedNormalizedFrame.x)
        #expect(frame.width == expectedNormalizedFrame.width)
    }

    /// `barFrame` deliberately does **not** window or clamp: it is a pure day-offset × dayWidth
    /// map, and the scroll view it feeds is what decides what is on screen. So the thing to assert
    /// for a bar ten years past `rangeStart` is the exact offset, not that it is positive and
    /// finite — every one of those four old assertions was structurally satisfied by a 30-day span
    /// starting after `rangeStart`, which is to say by arithmetic, not by this function.
    @Test func barFramePlacesARangeFarPastTheWindowAtItsExactUnclampedOffset() throws {
        let calendar = Calendar.current
        let rangeStart = try #require(DateFormatters.date(from: "2026-01-01"))
        // A goal spanning far in the future relative to the visible window (e.g. viewing "2W"
        // scale but the goal is 10 years out).
        let farStart = try #require(calendar.date(byAdding: .year, value: 10, to: rangeStart))
        let farEnd = try #require(calendar.date(byAdding: .day, value: 30, to: farStart))

        let frame = GoalTimelineDateMath.barFrame(
            start: farStart,
            end: farEnd,
            rangeStart: rangeStart,
            dayWidth: 48,
            calendar: calendar
        )

        // 2026-01-01 -> 2036-01-01 is 3,652 days: ten 365-day years plus 2028-02-29 and
        // 2032-02-29 (2036's leap day falls after the end date).
        let dayOffset = try #require(
            calendar.dateComponents([.day], from: rangeStart, to: farStart).day
        )
        #expect(dayOffset == 3_652)
        #expect(frame.x == CGFloat(3_652) * 48)
        // Inclusive of both end days: 31 columns, not 30.
        #expect(frame.width == CGFloat(31) * 48)
    }

    /// The floor on the other side of the same function: a bar whose start and end land on the
    /// same day still has to be one full column wide, or a one-day milestone draws as nothing.
    @Test func barFrameNeverCollapsesASingleDayRangeBelowOneColumn() throws {
        let calendar = Calendar.current
        let rangeStart = try #require(DateFormatters.date(from: "2026-01-01"))
        let day = try #require(DateFormatters.date(from: "2026-01-11"))

        let frame = GoalTimelineDateMath.barFrame(
            start: day,
            end: day,
            rangeStart: rangeStart,
            dayWidth: 48,
            calendar: calendar
        )

        #expect(frame.x == CGFloat(10) * 48)
        #expect(frame.width == 48)

        // A reversed range is read as the range it describes, not as a negative width.
        let reversed = GoalTimelineDateMath.barFrame(
            start: try #require(DateFormatters.date(from: "2026-01-21")),
            end: day,
            rangeStart: rangeStart,
            dayWidth: 48,
            calendar: calendar
        )
        #expect(reversed.x == CGFloat(10) * 48)
        #expect(reversed.width == CGFloat(11) * 48)
    }

    @Test func monthMarkersReturnsEmptyForReversedVisibleRangeInsteadOfCrashing() {
        let calendar = Calendar.current
        let rangeStart = DateFormatters.date(from: "2026-06-01") ?? Date()
        let rangeEnd = DateFormatters.date(from: "2026-01-01") ?? Date() // before rangeStart

        let markers = GoalTimelineDateMath.monthMarkers(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            dayWidth: 26,
            calendar: calendar
        )

        #expect(markers.isEmpty)
    }

    @Test func dayDeltaGuardsAgainstZeroDayWidthInsteadOfDividingByZero() {
        #expect(GoalTimelineDateMath.dayDelta(for: 100, dayWidth: 0) == 0)
        #expect(GoalTimelineDateMath.dayDelta(for: -100, dayWidth: 0) == 0)
    }
}
#endif
