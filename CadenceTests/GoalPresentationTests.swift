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

    @Test func rangeLabelNeedsBothEndsBeforeItClaimsARange() {
        #expect(goal(start: "2026-08-01", end: "").rangeLabel == "No date range")
        #expect(goal(start: "", end: "2026-08-31").rangeLabel == "No date range")
        #expect(goal(start: "2026-08-01", end: "2026-08-31").rangeLabel.contains("-"))
    }
}
