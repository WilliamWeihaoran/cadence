import Foundation
import Testing
@testable import Cadence

@MainActor
struct CalendarBoardPlannerSupportTests {
    @Test func titleFormatsSevenDayRangeAcrossMonthBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 5, day: 29))!

        #expect(CalendarBoardPlannerSupport.title(for: anchor, calendar: calendar) == "May 29 - Jun 4")
    }

    @Test func boardTasksIncludeDueOnlyWithoutMutatingSchedule() {
        let task = AppTask(title: "Due task")
        task.dueDate = "2026-06-01"

        let result = CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [task])

        #expect(result["2026-06-01"]?.map(\.id) == [task.id])
        #expect(task.scheduledDate.isEmpty)
        #expect(task.scheduledStartMin == -1)
    }

    @Test func boardTasksSortTimedBeforeUntimedThenPriority() {
        let untimedHigh = AppTask(title: "Untimed high")
        untimedHigh.scheduledDate = "2026-06-01"
        untimedHigh.priority = .high

        let timedLow = AppTask(title: "Timed low")
        timedLow.scheduledDate = "2026-06-01"
        timedLow.scheduledStartMin = 14 * 60
        timedLow.priority = .low

        let untimedMedium = AppTask(title: "Untimed medium")
        untimedMedium.scheduledDate = "2026-06-01"
        untimedMedium.priority = .medium

        let result = CalendarBoardPlannerSupport.tasksByBoardDate(
            from: [untimedMedium, untimedHigh, timedLow]
        )

        #expect(result["2026-06-01"]?.map(\.title) == ["Timed low", "Untimed high", "Untimed medium"])
    }

    @Test func sharedBoardSortKeyOrdersAllDayTimedAndUntimedItems() {
        let allDay = CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: "all-day",
            startMinute: 0,
            isAllDay: true,
            kindRank: 0
        )
        let event = CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: "event",
            startMinute: 9 * 60,
            isAllDay: false,
            kindRank: 0
        )

        let bundle = TaskBundle(title: "Bundle", dateKey: "2026-06-01", startMin: 9 * 60, durationMinutes: 60)
        let timedTask = AppTask(title: "Task")
        timedTask.scheduledDate = "2026-06-01"
        timedTask.scheduledStartMin = 9 * 60
        let untimedTask = AppTask(title: "Untimed")
        untimedTask.scheduledDate = "2026-06-01"

        let ordered = [
            CalendarBoardPlannerSupport.sortKey(for: untimedTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: timedTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1),
            event,
            allDay
        ].sorted()

        #expect(ordered == [
            allDay,
            event,
            CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1),
            CalendarBoardPlannerSupport.sortKey(for: timedTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: untimedTask, kindRank: 2)
        ])
    }

    @Test func plannerWindowStartsBeforeAnchorByLeadingDayCount() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        // The today-forward floor is opt-in, so the leading buffer only shrinks when a caller asks
        // for it — see `CalendarBoardRailTests` for the floored case.
        let today = calendar.date(byAdding: .day, value: -CalendarBoardPlannerSupport.plannerLeadingDayCount, to: anchor)!
        let start = CalendarBoardPlannerSupport.plannerWindowStart(for: anchor, notBefore: today, calendar: calendar)

        #expect(
            CalendarBoardPlannerSupport.dayIndex(
                for: anchor,
                bufferStart: start,
                calendar: calendar,
                renderDays: CalendarBoardPlannerSupport.plannerRenderDayCount
            ) == CalendarBoardPlannerSupport.plannerLeadingDayCount
        )
    }

    @Test func plannerRecenterTriggersNearEitherWindowEdge() {
        let renderDays = CalendarBoardPlannerSupport.plannerRenderDayCount
        let threshold = CalendarBoardPlannerSupport.plannerRecenterThreshold

        #expect(CalendarBoardPlannerSupport.shouldRecenter(dayIndex: threshold, renderDays: renderDays))
        #expect(CalendarBoardPlannerSupport.shouldRecenter(dayIndex: renderDays - threshold - 1, renderDays: renderDays))
        #expect(!CalendarBoardPlannerSupport.shouldRecenter(dayIndex: CalendarBoardPlannerSupport.plannerLeadingDayCount, renderDays: renderDays))
    }

    /// The two lookups agree on do-dated work and deliberately disagree on due-only work:
    /// the folding lookup puts it in its due column for a board with no Unscheduled rail (iOS),
    /// while `tasksByBoardDate` leaves it out so the macOS board's rail can own it.
    @Test func boardTaskDateBucketsMatchFoldingLookupForDoDatedWork() {
        let scheduled = AppTask(title: "Scheduled")
        scheduled.scheduledDate = "2026-06-01"

        let dueOnly = AppTask(title: "Due")
        dueOnly.dueDate = "2026-06-02"

        let grouped = CalendarBoardPlannerSupport.tasksByBoardDate(from: [dueOnly, scheduled])
        let folded = CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [dueOnly, scheduled])

        #expect(grouped["2026-06-01"]?.map(\.id) == folded["2026-06-01"]?.map(\.id))
        #expect(grouped["2026-06-02"] == nil)
        #expect(folded["2026-06-02"]?.map(\.id) == [dueOnly.id])
    }

    // MARK: - Boards with no rails

    /// A board with no Unscheduled rail — the iOS one — has nothing to catch work that falls out of
    /// its day columns, so due-only work must fold into its due day rather than vanish.
    @Test func raillessBoardKeepsDueOnlyWorkInItsDueColumn() {
        let dueOnly = AppTask(title: "Due only")
        dueOnly.dueDate = "2026-06-02"

        let folded = CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [dueOnly])

        #expect(folded["2026-06-02"]?.map(\.id) == [dueOnly.id])
    }

    /// The invariant a railless board has to hold: every dated open task appears in exactly one
    /// day column. Bucketing strictly on the do date — which is right for the macOS board, whose
    /// rails cover the remainder — silently drops due-only work off this one entirely.
    @Test func raillessBoardShowsEveryDatedTaskInExactlyOneColumn() {
        let doDated = AppTask(title: "Do dated")
        doDated.scheduledDate = "2026-06-01"

        let bothDates = AppTask(title: "Both")
        bothDates.scheduledDate = "2026-06-01"
        bothDates.dueDate = "2026-06-05"

        let dueOnly = AppTask(title: "Due only")
        dueOnly.dueDate = "2026-06-02"

        let all = [doDated, bothDates, dueOnly]
        let folded = CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: all)
        let placements = folded.values.flatMap { $0 }.map(\.id)

        #expect(Set(placements) == Set(all.map(\.id)))
        #expect(placements.count == all.count)
        // A task with both dates belongs to its *do* day only — the due date is a fallback, not a
        // second home, or the card would show up twice.
        #expect(folded["2026-06-05"] == nil)
    }
}
