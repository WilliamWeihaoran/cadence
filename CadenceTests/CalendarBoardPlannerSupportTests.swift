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

        let result = CalendarBoardPlannerSupport.tasks(on: "2026-06-01", from: [task])

        #expect(result.map(\.id) == [task.id])
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

        let result = CalendarBoardPlannerSupport.tasks(
            on: "2026-06-01",
            from: [untimedMedium, untimedHigh, timedLow]
        )

        #expect(result.map(\.title) == ["Timed low", "Untimed high", "Untimed medium"])
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
        let start = CalendarBoardPlannerSupport.plannerWindowStart(for: anchor, calendar: calendar)

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

    @Test func boardTaskDateBucketsMatchPerDayLookup() {
        let scheduled = AppTask(title: "Scheduled")
        scheduled.scheduledDate = "2026-06-01"

        let dueOnly = AppTask(title: "Due")
        dueOnly.dueDate = "2026-06-02"

        let grouped = CalendarBoardPlannerSupport.tasksByBoardDate(from: [dueOnly, scheduled])

        #expect(grouped["2026-06-01"]?.map(\.id) == CalendarBoardPlannerSupport.tasks(on: "2026-06-01", from: [dueOnly, scheduled]).map(\.id))
        #expect(grouped["2026-06-02"]?.map(\.id) == CalendarBoardPlannerSupport.tasks(on: "2026-06-02", from: [dueOnly, scheduled]).map(\.id))
    }
}
