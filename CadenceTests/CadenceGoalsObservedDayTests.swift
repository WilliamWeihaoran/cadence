import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5050]] — a goal's "Next" line is answered against a day KEY, not the clock.** Also
/// [[T-5080]], the macOS timeline's today line.
///
/// iOSGoalDetail.nextActionLine computed `DateFormatters.todayKey()` in `body` for the due label
/// and the overdue tint, in a body whose inputs are the same on both sides of midnight, so a goal
/// detail left open overnight kept yesterday's "Today" and yesterday's red. T-5050 gave the page
/// one `CadenceObservedDay` and handed its key down; T-5080 did the same for the timeline's line.
///
/// **[[T-5002]] deleted every view either ticket wired.** `iOSGoalsView`, `iOSGoalDetail`,
/// `GoalsView`, `GoalTimelineView` and `GoalTimelineTodayLine` are gone, so the four wire tests
/// this suite carried have no subject left; their absence is pinned by
/// `CadenceCodexTrackingUIRetirementTests.codexRetiredTrackingViewsAreGoneFromTheTree` rather than
/// left to the next reader to notice. The RULE those views fed their key into is not a view's and
/// is still live — `GoalContributionResolver` is read by `CadenceMilestoneWidgetSupport` and by the
/// MCP read surface — so it keeps its test here.
@MainActor
struct CadenceGoalsObservedDayTests {

    @Test func theNextActionTurnsOverdueOnceTheObservedDayPassesItsDueDate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Launch", context: context)
        let goal = Goal(title: "Ship", context: context)
        let task = AppTask(title: "Write the notes")
        task.area = area
        task.context = context
        task.goal = goal
        task.dueDate = "2026-10-22"

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(task)
        try modelContext.save()

        func summary(on key: String) throws -> GoalContributionSummary {
            GoalContributionResolver.summary(for: goal, now: try #require(DateFormatters.date(from: key)))
        }

        let before = try summary(on: "2026-10-22")
        let after = try summary(on: "2026-10-23")
        #expect(before.nextActionDueDate == "2026-10-22")
        #expect(before.overdueTaskCount == 0)
        #expect(after.overdueTaskCount == 1)

        #expect(!CadenceFocusSupport.isOverdue(dueDateKey: "2026-10-22", todayKey: "2026-10-22"))
        #expect(CadenceFocusSupport.isOverdue(dueDateKey: "2026-10-22", todayKey: "2026-10-23"))
        #expect(
            CadenceFocusSupport.dueLabel(forDueDateKey: "2026-10-22", todayKey: "2026-10-22")
                != CadenceFocusSupport.dueLabel(forDueDateKey: "2026-10-22", todayKey: "2026-10-23")
        )
    }
}
