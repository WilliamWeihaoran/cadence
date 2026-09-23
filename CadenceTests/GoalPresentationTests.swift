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

    /// **The same rule asked of the goal being edited, and asked by both editors ([[T-1327]]).**
    ///
    /// `canOwnMilestones` above answers for a candidate *parent*. `mustStayTopLevel` answers for
    /// the goal that would be **nested**, and it is the half that keeps the third level from being
    /// built: give a goal that owns milestones a parent and its milestones land on a level nothing
    /// draws. `CadenceTrackingMutationSupport.saveGoal` will not stop it — it guards the
    /// self-parenting cycle and says nothing about depth — so the picker is the only gate.
    ///
    /// The two answers are complements over a two-level tree and this asserts them as such: a goal
    /// may be a parent, or may be given one, and the only goal that is neither is one that already
    /// owns milestones.
    @Test func aGoalThatOwnsMilestonesMayNotBeGivenAParent() {
        let direction = Goal(title: "Get healthy")
        let milestone = Goal(title: "Run a 10k")
        milestone.parentGoal = direction
        direction.subGoals = [milestone]
        let leaf = Goal(title: "Learn to cook")

        #expect(GoalAssignmentRules.mustStayTopLevel(direction) == true)
        // A milestone keeps its picker, so an existing parent can still be changed or cleared.
        #expect(GoalAssignmentRules.mustStayTopLevel(milestone) == false)
        #expect(GoalAssignmentRules.mustStayTopLevel(leaf) == false)
        // The create path, where there is no goal yet and nothing to keep top-level.
        #expect(GoalAssignmentRules.mustStayTopLevel(nil) == false)

        // Promoting the milestone out makes the direction offerable again, and the milestone —
        // which now owns nothing — remains so.
        milestone.parentGoal = nil
        direction.subGoals = []
        #expect(GoalAssignmentRules.mustStayTopLevel(direction) == false)
    }

    /// **Both parent pickers ask that one function, which is the whole of [[T-1327]]'s second
    /// half.**
    ///
    /// The rule was `iOSGoalEditorSheet.mustStayTopLevel`, a private computed property, and
    /// `CreateGoalSheet.parentGoalChoices` had no equivalent — so macOS offered a parent for a goal
    /// with milestones under it and was the way a three-deep tree came to exist at all. Neither
    /// picker is reachable from this target (iOS is entirely inside `#if os(iOS)`, and both are
    /// view bodies), so the call sites are read from source, exactly as
    /// `CadenceGoalListLinkSurfaceTests` reads iOS's link calls.
    @Test func bothGoalEditorsRefuseToNestAGoalThatOwnsMilestones() throws {
        let macSheet = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Sheets/CreateGoalSheet.swift")
        let iosSheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSTrackingEditorSheets.swift")

        // One spelling of the rule per platform, and it is the shared one.
        for (name, source) in [("macOS", macSheet), ("iOS", iosSheet)] {
            #expect(
                CadenceSourceScan.matchCount("GoalAssignmentRules\\.mustStayTopLevel\\(", in: source) == 1,
                "\(name) does not ask the shared rule exactly once"
            )
            #expect(
                source.contains("GoalAssignmentRules.mustStayTopLevelNotice"),
                "\(name) writes the notice out by hand instead of reading the one beside the rule"
            )
            #expect(
                !source.contains("parentGoal == nil && !("),
                "\(name) kept a hand-written copy of the rule"
            )
        }

        // And the guard is in the choices, not only in the label: a picker that draws the notice
        // and still offers the parents underneath it is the same defect with a caption.
        let choices = try #require(
            CadenceSourceScan.declarationBody("private var parentGoalChoices: [Goal]", in: macSheet),
            "parentGoalChoices is no longer declared that way"
        )
        #expect(choices.contains("guard !mustStayTopLevel else { return [] }"))
        #expect(choices.contains("GoalAssignmentRules"), "the scan read something other than the picker")

        let iosChoices = try #require(
            CadenceSourceScan.declarationBody("private var parentChoices: [Goal]", in: iosSheet),
            "iOS's parentChoices is no longer declared that way"
        )
        #expect(iosChoices.contains("guard !mustStayTopLevel else { return [] }"))
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

    // MARK: - The third level ([[T-1337]])
    //
    // A goal -> milestone -> sub-milestone tree cannot be created any more — `mustStayTopLevel`
    // and `canOwnMilestones` above — but [[T-1327]] only closed the door. Stores written before
    // it, and archive imports, hold such trees; they sync through CloudKit; and
    // `GoalContributionResolver.contributingTasks` recurses `subGoals` with no depth limit, so a
    // sub-milestone's tasks move its grandparent's percentage. The branch taken is **render it**:
    // macOS already flattened descendants into the milestone tier (`GoalMissionGrouping`), so the
    // rule moved to `GoalAssignmentRules` and the iOS list reads the same shape. Nothing is
    // written, nothing is promoted, and no percentage changes — the rows the percentage is made of
    // are simply drawn.

    /// The whole subtree is drawn under the direction, and it is drawn **once**.
    ///
    /// The two halves have to be asserted together: flattening descendants into the milestone tier
    /// without widening `activeTopLevelGoals` from "parent" to "ancestor" would draw a
    /// sub-milestone under its direction *and* as a top-level row of its own.
    @Test func aThirdLevelGoalIsDrawnUnderItsDirectionExactlyOnce() {
        let direction = goal()
        let milestone = goal()
        let subMilestone = goal()
        milestone.parentGoal = direction
        subMilestone.parentGoal = milestone
        direction.subGoals = [milestone]
        milestone.subGoals = [subMilestone]
        let all = [direction, milestone, subMilestone]

        let topLevel = GoalAssignmentRules.activeTopLevelGoals(from: all)
        #expect(topLevel.map(\.id) == [direction.id])

        let nested = GoalAssignmentRules.activeNestedGoals(under: direction)
        #expect(nested.map(\.id) == [milestone.id, subMilestone.id])

        // The rows the iOS Goals list draws are exactly the goals in the store, each once.
        let drawn = topLevel.flatMap { [$0] + GoalAssignmentRules.activeNestedGoals(under: $0) }
        #expect(drawn.map(\.id) == all.map(\.id))
        #expect(Set(drawn.map(\.id)).count == drawn.count)
    }

    /// **The row and the percentage are made of the same goals.** This is the ticket's actual
    /// complaint: the sub-milestone's task moved the direction's progress bar from a row no screen
    /// drew. The contribution walk is deliberately left alone — what changes is that every goal it
    /// reaches now has somewhere to appear.
    @Test func everyGoalMovingADirectionsPercentageHasARowUnderThatDirection() {
        let direction = goal()
        let milestone = goal()
        let subMilestone = goal()
        milestone.parentGoal = direction
        subMilestone.parentGoal = milestone
        direction.subGoals = [milestone]
        milestone.subGoals = [subMilestone]

        let buried = AppTask(title: "Buried work")
        buried.goal = subMilestone
        subMilestone.tasks = [buried]

        let summary = GoalContributionResolver.summary(for: direction)
        #expect(summary.totalTasks == 1, "the sub-milestone's task no longer reaches the direction")

        let drawnUnderDirection = GoalAssignmentRules.activeNestedGoals(under: direction)
        #expect(drawnUnderDirection.contains { $0.id == subMilestone.id })
    }

    /// A completed goal partway down the chain does not hide what is under it, and still does not
    /// produce a duplicate row.
    @Test func aCompletedMilestoneDoesNotHideItsOwnActiveMilestones() {
        let direction = goal()
        let milestone = goal(status: .done)
        let subMilestone = goal()
        milestone.parentGoal = direction
        subMilestone.parentGoal = milestone
        direction.subGoals = [milestone]
        milestone.subGoals = [subMilestone]
        let all = [direction, milestone, subMilestone]

        #expect(GoalAssignmentRules.activeTopLevelGoals(from: all).map(\.id) == [direction.id])
        #expect(GoalAssignmentRules.activeNestedGoals(under: direction).map(\.id) == [subMilestone.id])

        // With the direction completed too, the sub-milestone has no drawn ancestor left and
        // becomes the top-level row itself rather than dropping off the screen.
        direction.status = .done
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: all).map(\.id) == [subMilestone.id])
    }

    /// **One definition of the walk, so the two platforms cannot disagree again.** macOS read the
    /// third level and iOS did not, for the same reason `mustStayTopLevel` was iOS-only in
    /// [[T-1327]] and macOS could therefore build the tree: the rule lived on one platform.
    @Test func bothPlatformsFlattenTheSubtreeThroughOneRule() {
        let direction = goal()
        let milestone = goal()
        let subMilestone = goal()
        milestone.parentGoal = direction
        subMilestone.parentGoal = milestone
        direction.subGoals = [milestone]
        milestone.subGoals = [subMilestone]

        #expect(
            GoalMissionGrouping.nestedGoals(under: direction).map(\.id)
                == GoalAssignmentRules.nestedGoals(under: direction).map(\.id)
        )
        #expect(GoalAssignmentRules.nestedGoals(under: direction).count == 2)
    }

    /// A `parentGoal` cycle arriving over CloudKit terminates the walk rather than hanging the
    /// Goals list, the same guard `deletionCascade` and `GoalContributionResolver` carry.
    @Test func theSubtreeWalkTerminatesOnACorruptedParentChain() {
        let first = goal()
        let second = goal()
        first.subGoals = [second]
        second.subGoals = [first]
        first.parentGoal = second
        second.parentGoal = first

        #expect(GoalAssignmentRules.nestedGoals(under: first).map(\.id) == [second.id])
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: [first, second]).isEmpty)
    }

    /// `CadenceTests` builds on macOS, so the iOS list is read rather than run. It has to ask for
    /// the flattened subtree; `milestones(of:)` — direct children — is the spelling that left the
    /// third level with no row.
    @Test func theIOSGoalsListDrawsTheFlattenedSubtree() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureViews.swift")
        let source = CadenceSourceScan.codeOnly(raw)
        #expect(source != raw, "nothing was stripped, so this scan is reading prose as code")
        #expect(source.count == raw.count)

        let body = try #require(
            CadenceSourceScan.functionBody(named: "milestones", in: source),
            "the iOS Goals list no longer declares milestones(of:); re-point this scan"
        )
        #expect(body.contains("GoalAssignmentRules.activeNestedGoals(under: goal)"))
        #expect(!body.contains("GoalAssignmentRules.milestones(of: goal)"))
    }

    @Test func rangeLabelNeedsBothEndsBeforeItClaimsARange() {
        #expect(goal(start: "2026-08-01", end: "").rangeLabel == "No date range")
        #expect(goal(start: "", end: "2026-08-31").rangeLabel == "No date range")
        #expect(goal(start: "2026-08-01", end: "2026-08-31").rangeLabel.contains("-"))
    }
}
