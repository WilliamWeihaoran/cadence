import Foundation
import SwiftData
import Testing
@testable import Cadence

/// `Goal`'s date-range derivations lived in a `#if os(macOS)` block inside a views file, reading
/// `Date()` and `Calendar.current` inline — so nothing could assert them, and iOS, the widgets and
/// the MCP target could not see them at all. Now that they take an injected `now` and `calendar`,
/// these are the assertions that were impossible before.
@MainActor
struct GoalPresentationTests {
    private func goal(start: String = "", end: String = "", status: GoalStatus = .active) -> Goal {
        let goal = Goal(title: "Ship it")
        goal.startDate = start
        goal.endDate = end
        goal.status = status
        return goal
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    @Test func daysSummaryCountsWholeDaysToTheEndDate() throws {
        let now = try #require(DateFormatters.date(from: "2026-08-11", in: utc))

        #expect(goal(end: "2026-08-18").daysSummary(asOf: now, calendar: utc) == "7d left")
        #expect(goal(end: "2026-08-11").daysSummary(asOf: now, calendar: utc) == "Due today")
        #expect(goal(end: "2026-08-08").daysSummary(asOf: now, calendar: utc) == "3d late")
        #expect(goal(end: "").daysSummary(asOf: now, calendar: utc) == "No end date")
    }

    /// A finished goal is never late, however long ago its window closed — the status has to be
    /// checked before the arithmetic, not after.
    @Test func aDoneGoalReportsCompletedRatherThanLate() throws {
        let now = try #require(DateFormatters.date(from: "2026-08-11", in: utc))
        let finished = goal(end: "2026-01-01", status: .done)

        #expect(finished.daysSummary(asOf: now, calendar: utc) == "Completed")
        #expect(finished.isOverdue(asOf: now, calendar: utc) == false)
    }

    @Test func aGoalIsOverdueOnlyOnceItsEndDateHasPassed() throws {
        let now = try #require(DateFormatters.date(from: "2026-08-11", in: utc))

        #expect(goal(end: "2026-08-10").isOverdue(asOf: now, calendar: utc))
        #expect(goal(end: "2026-08-11").isOverdue(asOf: now, calendar: utc) == false)
        #expect(goal(end: "2026-08-12").isOverdue(asOf: now, calendar: utc) == false)
        // No end date is not a missed one.
        #expect(goal(end: "").isOverdue(asOf: now, calendar: utc) == false)
    }

    /// The original parsed through `DateFormatters.ymd`, a shared formatter with no pinned time
    /// zone, while the day arithmetic beside it used `Calendar.current`. Parsing and measuring in
    /// the same calendar is what stops the two disagreeing by a day at a zone boundary.
    @Test func datesResolveInTheCalendarTheyAreMeasuredIn() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let subject = goal(start: "2026-08-01", end: "2026-08-31")
        let start = try #require(subject.startDate(in: tokyo))
        let end = try #require(subject.endDate(in: tokyo))

        #expect(DateFormatters.dateKey(from: start, calendar: tokyo) == "2026-08-01")
        #expect(DateFormatters.dateKey(from: end, calendar: tokyo) == "2026-08-31")

        // And the summary measured in that same zone agrees with those keys.
        let now = try #require(DateFormatters.date(from: "2026-08-21", in: tokyo))
        #expect(subject.daysSummary(asOf: now, calendar: tokyo) == "10d left")
    }

    /// The iOS goal detail serves milestones as well as directions, and its "Milestone" action was
    /// unconditional — so from a milestone you could create a goal nested two levels deep. Nothing
    /// draws a third level: it is absent from the goals list (which renders top-level rows plus
    /// their milestones) and from the habit editor's goal picker, and on iPad the save even
    /// selected it, showing a detail pane for a goal with no row.
    @Test func onlyATopLevelGoalCanOwnMilestones() {
        let direction = Goal(title: "Get healthy")
        let milestone = Goal(title: "Run a 10k")
        milestone.parentGoal = direction
        direction.subGoals = [milestone]

        #expect(GoalAssignmentRules.canOwnMilestones(direction) == true)
        #expect(GoalAssignmentRules.canOwnMilestones(milestone) == false)

        // The rule has to agree with what the two-level list actually renders: every goal that is
        // drawn somewhere is either top-level or the child of a top-level goal.
        let all = [direction, milestone]
        let drawn = GoalAssignmentRules.topLevelGoals(from: all)
            .flatMap { [$0] + GoalAssignmentRules.milestones(of: $0) }
        #expect(drawn.count == all.count)
        for goal in all where !GoalAssignmentRules.canOwnMilestones(goal) {
            #expect(GoalAssignmentRules.milestones(of: goal).isEmpty)
        }
    }

    // MARK: - T-541: the detail pane may not show what the list filtered away

    /// **Every goal completed empties both sides of the Goals screen.**
    ///
    /// The iOS Goals list draws rows for active goals and counts them, and `iOSFeatureListPane`
    /// swaps in its empty panel when that count is zero. The detail pane beside it used to resolve
    /// a selected id against the *unfiltered* collection and end `?? goals.first`, so with every
    /// goal completed the chooser said "No goals yet" while the pane rendered a completed goal in
    /// full — the mirror image of T-514/T-534.
    ///
    /// The claim the pane's own comment makes is now an equality rather than an implication:
    /// `nil` here holds **exactly** when `activeGoals` is empty, which is exactly the count the
    /// chooser draws its empty panel on.
    @Test func aCompletedGoalIsNeverTheGoalsDetailPanesSubject() {
        let shipped = goal(status: .done)
        let launched = goal(status: .done)
        let finished = [shipped, launched]

        #expect(GoalAssignmentRules.activeGoals(from: finished).isEmpty)
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: finished).isEmpty)
        // Nothing selected, and a selection pointing straight at a completed goal: neither may
        // resurrect it.
        #expect(GoalAssignmentRules.selectedGoal(id: nil, from: finished) == nil)
        #expect(GoalAssignmentRules.selectedGoal(id: shipped.id, from: finished) == nil)

        // With one goal still active the same two questions both answer with that goal, so the
        // `nil` above is the emptiness and not a rule that refuses to select anything.
        let running = goal()
        let mixed = [shipped, running, launched]
        #expect(GoalAssignmentRules.selectedGoal(id: nil, from: mixed)?.id == running.id)
        #expect(GoalAssignmentRules.selectedGoal(id: shipped.id, from: mixed)?.id == running.id)
        #expect(GoalAssignmentRules.selectedGoal(id: running.id, from: mixed)?.id == running.id)
    }

    /// **The fall-through the deleted-out-from-under-you case needs survives the filtering.**
    ///
    /// A selected id that no longer resolves — the goal deleted on the Mac and arriving over
    /// CloudKit, or deleted from the compact list — still lands on a default rather than on `nil`,
    /// which is what kept the iPad detail pane from reading as permanently unselectable. What it
    /// no longer does is reach a goal the list refuses to draw.
    @Test func anUnresolvableGoalSelectionStillFallsThroughToARowThatExists() {
        let direction = goal()
        let second = goal()
        let all = [direction, second]

        #expect(GoalAssignmentRules.selectedGoal(id: UUID(), from: all)?.id == direction.id)
    }

    /// **The fallback prefers a row the list actually draws at the top level.**
    ///
    /// An active milestone under a *completed* direction is a top-level row — the list would
    /// otherwise have nowhere to nest it — and it is reachable as the default when its parent is
    /// the only other goal.
    @Test func theGoalsFallbackPrefersATopLevelRowAndAcceptsAnOrphanedMilestone() {
        let direction = goal(status: .done)
        let milestone = goal()
        milestone.parentGoal = direction
        direction.subGoals = [milestone]
        let all = [direction, milestone]

        #expect(GoalAssignmentRules.activeTopLevelGoals(from: all).map(\.id) == [milestone.id])
        #expect(GoalAssignmentRules.selectedGoal(id: nil, from: all)?.id == milestone.id)
        #expect(GoalAssignmentRules.selectedGoal(id: direction.id, from: all)?.id == milestone.id)

        // With the direction active, it is the top-level row and the milestone nests under it.
        direction.status = .active
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: all).map(\.id) == [direction.id])
        #expect(GoalAssignmentRules.selectedGoal(id: nil, from: all)?.id == direction.id)
    }

    /// **Why the second rung of the fallback is not dead code.**
    ///
    /// `activeTopLevelGoals` is empty while `activeGoals` is not in exactly one situation: every
    /// active goal has an active parent, which needs a cycle in the `parentGoal` chain. A corrupted
    /// chain arriving over CloudKit is a case this codebase already guards for —
    /// `GoalAssignmentRules.deletionCascade` and `GoalContributionResolver` both carry a `visited`
    /// set for it — and dropping the `?? activeGoals.first` rung would blank the detail pane there
    /// while the chooser's count still says two.
    @Test func aCycleInTheParentChainStillResolvesToAnActiveGoal() {
        let first = goal()
        let second = goal()
        first.parentGoal = second
        second.parentGoal = first
        let all = [first, second]

        #expect(GoalAssignmentRules.activeGoals(from: all).count == 2)
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: all).isEmpty)
        #expect(GoalAssignmentRules.selectedGoal(id: nil, from: all)?.id == first.id)
        // A live selection is answered from the active set directly, cycle or no cycle.
        #expect(GoalAssignmentRules.selectedGoal(id: second.id, from: all)?.id == second.id)
    }

    @Test func rangeLabelNeedsBothEndsBeforeItClaimsARange() {
        #expect(goal(start: "2026-08-01", end: "").rangeLabel == "No date range")
        #expect(goal(start: "", end: "2026-08-31").rangeLabel == "No date range")
        #expect(goal(start: "2026-08-01", end: "2026-08-31").rangeLabel.contains("-"))
    }
}
