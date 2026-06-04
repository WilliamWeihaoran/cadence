import Foundation
import Testing
#if os(macOS)
import EventKit
import SwiftUI
#endif
@testable import Cadence

#if os(macOS)
@Suite(.serialized)
@MainActor
struct CalendarBehaviorRegressionTests {
    @Test func timelineHeaderRangeTracksBodyLeadingDay() {
        let colWidth: CGFloat = 120
        let offsetX = CGFloat(2.4) * colWidth
        let leadingDay = CalendarTimelineScrollSupport.clampedDayIndex(
            offsetX: offsetX,
            colWidth: colWidth
        )
        let range = calendarTimelineHeaderVisibleRange(
            headerOffset: -offsetX,
            colWidth: colWidth,
            viewportWidth: 3 * colWidth,
            renderDays: 20
        )

        #expect(leadingDay == 2)
        #expect(range.contains(leadingDay))
        #expect(range.contains(leadingDay + 3))
    }

    @Test func horizontalJumpOnlyFinishesAtTheTargetOffset() {
        let colWidth: CGFloat = 100

        #expect(CalendarTimelineScrollSupport.shouldFinishHorizontalJump(
            offsetX: 300,
            targetDay: 3,
            colWidth: colWidth
        ))
        #expect(CalendarTimelineScrollSupport.shouldFinishHorizontalJump(
            offsetX: 300.9,
            targetDay: 3,
            colWidth: colWidth
        ))
        #expect(!CalendarTimelineScrollSupport.shouldFinishHorizontalJump(
            offsetX: 298.5,
            targetDay: 3,
            colWidth: colWidth
        ))
        #expect(!CalendarTimelineScrollSupport.shouldFinishHorizontalJump(
            offsetX: 300,
            targetDay: nil,
            colWidth: colWidth
        ))
    }

    @Test func syncHeaderOffsetUsesTheSameDayWidthAsTimelineBody() {
        let scrollState = CalendarTimelineScrollState()

        CalendarTimelineScrollSupport.syncHeaderOffset(
            to: 4,
            scrollState: scrollState,
            colWidth: 125
        )

        #expect(scrollState.headerOffset == -500)
    }

    @Test func timelineJumpApplicationUpdatesVisibleAndExternalStateTogether() {
        var visibleDay: Int?
        var visibleHour: Int?
        var externalDay: Int?
        var externalHour: Int?
        var externalToken: UUID? = UUID()
        var anchorDateKey = "2026-06-01"
        let target = CalendarTimelineJumpTarget(
            dateKey: "2026-06-03",
            dayIndex: 42,
            hour: 9
        )

        CalendarPageInteractionSupport.applyTimelineJump(
            target,
            token: nil,
            visibleTimelineDayIndex: &visibleDay,
            visibleTimelineHour: &visibleHour,
            externalJumpDayIndex: &externalDay,
            externalJumpHour: &externalHour,
            externalJumpToken: &externalToken,
            anchorDateKey: &anchorDateKey
        )

        #expect(anchorDateKey == "2026-06-03")
        #expect(visibleDay == 42)
        #expect(visibleHour == 9)
        #expect(externalDay == 42)
        #expect(externalHour == 9)
        #expect(externalToken == nil)
    }

    @Test func externalTimelineJumpTargetMatchesStateSupportClamp() throws {
        let calendar = Calendar.current
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let request = CalendarNavigationManager.Request(
            dateKey: "2026-06-03",
            preferredHour: 2,
            token: UUID()
        )
        let expected = CalendarPageStateSupport.timelineJumpTarget(
            request: request,
            bufferStart: bufferStart,
            todayDayIdx: 12,
            calendar: calendar
        )

        let target = CalendarPageInteractionSupport.externalTimelineJumpTarget(
            request: request,
            calendar: calendar,
            bufferStart: bufferStart,
            todayDayIdx: 12
        )

        #expect(target.dateKey == "2026-06-03")
        #expect(target.dayIndex == expected.day)
        #expect(target.hour == expected.hour)
    }

    @Test func timelineCreateRowGeometryConvertsLocalDragPointsToTimelineMinutes() {
        let metrics = TimelineMetrics(startHour: 8, endHour: 18, hourHeight: 120)

        #expect(TimelineCreateRowGeometrySupport.absoluteY(
            hour: 10,
            metrics: metrics,
            localY: 60
        ) == CGFloat(300))
        #expect(TimelineCreateRowGeometrySupport.absoluteMinute(
            hour: 10,
            metrics: metrics,
            localY: 60
        ) == 10 * 60 + 30)
    }

    @Test func timelineCreateRowGeometryDetectsBlockedTimelineFrames() {
        let metrics = TimelineMetrics(startHour: 8, endHour: 18, hourHeight: 60)
        let blockedFrames = [
            TimelineBlockFrame(x: 20, y: 120, width: 180, height: 60)
        ]
        let pointInside = TimelineCreateRowGeometrySupport.absolutePoint(
            hour: 10,
            metrics: metrics,
            localPoint: CGPoint(x: 60, y: 15)
        )
        let pointOutside = TimelineCreateRowGeometrySupport.absolutePoint(
            hour: 11,
            metrics: metrics,
            localPoint: CGPoint(x: 60, y: 15)
        )

        #expect(TimelineCreateRowGeometrySupport.isInsideBlockedBlock(
            point: pointInside,
            blockedFrames: blockedFrames
        ))
        #expect(!TimelineCreateRowGeometrySupport.isInsideBlockedBlock(
            point: pointOutside,
            blockedFrames: blockedFrames
        ))
    }

    @Test func workHoursDefaultToNineToFiveAndClampToVisibleTimeline() {
        #expect(CalendarWorkHoursPreferences.defaultStartMinute == 9 * 60)
        #expect(CalendarWorkHoursPreferences.defaultEndMinute == 17 * 60)
        #expect(CalendarWorkHoursPreferences.selectableStartMinutes.contains(9 * 60))
        #expect(CalendarWorkHoursPreferences.selectableEndMinutes.contains(17 * 60))

        let visibleRange = CalendarWorkHoursPreferences.visibleMinuteRange(
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            timelineStartHour: 8,
            timelineEndHour: 12
        )

        #expect(visibleRange == (9 * 60)...(12 * 60))
        #expect(CalendarWorkHoursPreferences.displayLabel(
            startMinute: 9 * 60,
            endMinute: 17 * 60
        ) == "9 AM – 5 PM")
    }

    @Test func workHoursRepairInvalidRanges() {
        let range = CalendarWorkHoursPreferences.normalizedRange(
            startMinute: 26 * 60,
            endMinute: 9 * 60
        )

        #expect(range.startMinute == 23 * 60 + 30)
        #expect(range.endMinute == 24 * 60)
        #expect(CalendarWorkHoursPreferences.visibleMinuteRange(
            startMinute: 5 * 60,
            endMinute: 6 * 60,
            timelineStartHour: 8,
            timelineEndHour: 17
        ) == nil)
    }

    @Test func workHoursPickerUpdatesKeepAtLeastThirtyMinutes() {
        let startMovedAfterEnd = CalendarWorkHoursPreferences.rangeByUpdatingStart(
            16 * 60 + 45,
            currentEndMinute: 16 * 60
        )
        let endMovedBeforeStart = CalendarWorkHoursPreferences.rangeByUpdatingEnd(
            8 * 60,
            currentStartMinute: 9 * 60
        )

        #expect(startMovedAfterEnd.startMinute == 16 * 60 + 45)
        #expect(startMovedAfterEnd.endMinute == 17 * 60 + 15)
        #expect(endMovedBeforeStart.startMinute == 9 * 60)
        #expect(endMovedBeforeStart.endMinute == 9 * 60 + 30)
    }

    @Test func workHoursHighlightFrameUsesTimelineCoordinates() {
        let clippedFrame = CalendarWorkHoursPreferences.highlightFrame(
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            timelineStartHour: 8,
            timelineEndHour: 12,
            hourHeight: 60
        )
        let fullFrame = CalendarWorkHoursPreferences.highlightFrame(
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            timelineStartHour: 0,
            timelineEndHour: 24,
            hourHeight: 48
        )

        #expect(clippedFrame != nil)
        #expect(fullFrame != nil)

        guard let clippedFrame, let fullFrame else { return }

        #expect(clippedFrame.y == CGFloat(60))
        #expect(clippedFrame.height == CGFloat(180))
        #expect(fullFrame.y == CGFloat(9 * 48))
        #expect(fullFrame.height == CGFloat(8 * 48))
    }

    @Test func boardOrderingIsSequentialAcrossEventsBundlesAndTasks() {
        let earlyTask = AppTask(title: "9 am task")
        earlyTask.scheduledDate = "2026-06-02"
        earlyTask.scheduledStartMin = 9 * 60

        let laterTask = AppTask(title: "11 am task")
        laterTask.scheduledDate = "2026-06-02"
        laterTask.scheduledStartMin = 11 * 60

        let bundle = TaskBundle(
            title: "10 am bundle",
            dateKey: "2026-06-02",
            startMin: 10 * 60,
            durationMinutes: 30
        )
        let event = CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: "event-9-30",
            startMinute: 9 * 60 + 30,
            isAllDay: false,
            kindRank: 0
        )
        let untimedTask = AppTask(title: "Untimed planned task")
        untimedTask.scheduledDate = "2026-06-02"

        let ordered = [
            CalendarBoardPlannerSupport.sortKey(for: untimedTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: laterTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1),
            event,
            CalendarBoardPlannerSupport.sortKey(for: earlyTask, kindRank: 2)
        ].sorted()

        #expect(ordered == [
            CalendarBoardPlannerSupport.sortKey(for: earlyTask, kindRank: 2),
            event,
            CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1),
            CalendarBoardPlannerSupport.sortKey(for: laterTask, kindRank: 2),
            CalendarBoardPlannerSupport.sortKey(for: untimedTask, kindRank: 2)
        ])
    }

    @Test func boardDueTaskScheduledOnSameDayDoesNotDuplicateAcrossLookups() {
        let task = AppTask(title: "Scheduled and due")
        task.scheduledDate = "2026-06-02"
        task.dueDate = "2026-06-02"

        let perDay = CalendarBoardPlannerSupport.tasks(on: "2026-06-02", from: [task])
        let grouped = CalendarBoardPlannerSupport.tasksByBoardDate(from: [task])

        #expect(perDay.map(\.id) == [task.id])
        #expect(grouped["2026-06-02"]?.map(\.id) == [task.id])
    }

    @Test func boardTaskLookupKeepsCompletedForFooterAndExcludesCancelledOrBundledTasks() {
        let active = AppTask(title: "Active")
        active.scheduledDate = "2026-06-02"

        let completed = AppTask(title: "Completed")
        completed.scheduledDate = "2026-06-02"
        completed.status = .done
        completed.completedAt = Date()

        let cancelled = AppTask(title: "Cancelled")
        cancelled.scheduledDate = "2026-06-02"
        cancelled.status = .cancelled

        let bundled = AppTask(title: "Bundled")
        bundled.scheduledDate = "2026-06-02"
        let bundle = TaskBundle(
            title: "Bundle",
            dateKey: "2026-06-02",
            startMin: 9 * 60,
            durationMinutes: 30
        )
        SchedulingActions.addTask(bundled, to: bundle)

        let result = CalendarBoardPlannerSupport.tasks(
            on: "2026-06-02",
            from: [cancelled, bundled, completed, active]
        )

        #expect(result.map(\.title) == ["Active", "Completed"])
    }

    @Test func crossMidnightTimedEventSegmentsOnlyRenderOnTouchedDays() throws {
        let store = EKEventStore()
        let calendar = Calendar.current
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        let secondDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let unrelatedDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 18)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 6)))
        let event = EKEvent(eventStore: store)
        event.title = "Overnight work"
        event.startDate = start
        event.endDate = end
        event.isAllDay = false

        let firstSegments = CalendarEventItem.timedSegments(from: [event], for: firstDay, calendar: calendar)
        let secondSegments = CalendarEventItem.timedSegments(from: [event], for: secondDay, calendar: calendar)
        let unrelatedSegments = CalendarEventItem.timedSegments(from: [event], for: unrelatedDay, calendar: calendar)

        #expect(firstSegments.map(\.startMin) == [18 * 60])
        #expect(firstSegments.map(\.durationMinutes) == [6 * 60])
        #expect(secondSegments.map(\.startMin) == [0])
        #expect(secondSegments.map(\.durationMinutes) == [6 * 60])
        #expect(unrelatedSegments.isEmpty)
    }
}
#endif
