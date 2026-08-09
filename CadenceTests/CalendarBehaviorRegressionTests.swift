import Foundation
import Testing
#if os(macOS)
import EventKit
import SwiftUI
import SwiftData
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

    @Test func workHoursHighlightSkipsWeekendDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let weekend = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13))!

        #expect(CalendarWorkHoursPreferences.shouldShowHighlight(on: weekday, calendar: calendar))
        #expect(!CalendarWorkHoursPreferences.shouldShowHighlight(on: weekend, calendar: calendar))
    }

    @Test func recurringTaskCompletionStampsSeriesMetadataOnNextTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Daily review")
        task.recurrenceRule = .daily
        task.scheduledDate = DateFormatters.todayKey()
        task.scheduledStartMin = 540
        context.insert(task)

        TaskWorkflowService.markDone(task, in: context)
        try context.save()

        let spawnedID = try #require(task.recurrenceSpawnedTaskID)
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = try context.fetch(descriptor)
        let next = try #require(tasks.first { $0.id == spawnedID })

        let expectedNextDate = DateFormatters.dateKey(
            from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        #expect(task.recurrenceSeriesID == task.id)
        #expect(next.recurrenceSeriesID == task.recurrenceSeriesID)
        #expect(next.recurrenceSourceTaskID == task.id)
        #expect(next.recurrenceOccurrenceIndex == 1)
        #expect(next.scheduledDate == expectedNextDate)
    }

    @Test func recurrenceRuleScopeCanTargetOnlyCurrentOrFutureTasks() {
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let third = AppTask(title: "Third")
        first.recurrenceRule = .daily
        second.recurrenceRule = .daily
        third.recurrenceRule = .daily
        first.scheduledDate = "2026-06-08"
        second.scheduledDate = "2026-06-09"
        third.scheduledDate = "2026-06-10"
        first.recurrenceSpawnedTaskID = second.id
        second.recurrenceSpawnedTaskID = third.id
        let seriesID = first.id.uuidString
        first.recurrenceSeriesIDRaw = seriesID
        second.recurrenceSeriesIDRaw = seriesID
        third.recurrenceSeriesIDRaw = seriesID

        TaskWorkflowService.applyRecurrenceRule(.weekly, to: second, allTasks: [first, second, third], scope: .thisTask)
        #expect(first.recurrenceRule == .daily)
        #expect(second.recurrenceRule == .weekly)
        #expect(third.recurrenceRule == .daily)

        TaskWorkflowService.applyRecurrenceRule(.monthly, to: second, allTasks: [first, second, third], scope: .thisAndFuture)
        #expect(first.recurrenceRule == .daily)
        #expect(second.recurrenceRule == .monthly)
        #expect(third.recurrenceRule == .monthly)
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

    @Test func crossMidnightTimedEventSegmentsKeepFullEventRangeForSaving() throws {
        let store = EKEventStore()
        let calendar = Calendar.current
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        let secondDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 18)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 6)))
        let event = EKEvent(eventStore: store)
        event.title = "Overnight work"
        event.startDate = start
        event.endDate = end
        event.isAllDay = false

        let firstSegment = try #require(CalendarEventItem(event: event, clippedTo: firstDay, calendar: calendar))
        let secondSegment = try #require(CalendarEventItem(event: event, clippedTo: secondDay, calendar: calendar))
        let unchangedSecondDayRange = try #require(secondSegment.eventDateRangeForEditedSegment(
            startMin: secondSegment.startMin,
            durationMinutes: secondSegment.durationMinutes,
            calendar: calendar
        ))
        let movedSecondDayRange = try #require(secondSegment.eventDateRangeForMovedSegment(
            startMin: secondSegment.startMin + 60,
            calendar: calendar
        ))
        let movedStart = try #require(calendar.date(byAdding: .minute, value: 60, to: start))
        let movedEnd = try #require(calendar.date(byAdding: .minute, value: 60, to: end))

        #expect(firstSegment.isMultiDayTimedEvent)
        #expect(firstSegment.isFirstSegment)
        #expect(!firstSegment.isLastSegment)
        #expect(secondSegment.isMultiDayTimedEvent)
        #expect(!secondSegment.isFirstSegment)
        #expect(secondSegment.isLastSegment)
        #expect(secondSegment.eventDateKey == "2026-06-11")
        #expect(secondSegment.eventStartMin == 18 * 60)
        #expect(secondSegment.eventDurationMinutes == 12 * 60)
        #expect(unchangedSecondDayRange.start == start)
        #expect(unchangedSecondDayRange.end == end)
        #expect(movedSecondDayRange.start == movedStart)
        #expect(movedSecondDayRange.end == movedEnd)
    }

    @Test func monthIndexForOffsetClampsAtBoundariesAndPastTheEnd() {
        let offsets: [CGFloat] = [0, 100, 250, 400, 600]
        let totalMonths = offsets.count

        // Just before a boundary stays on the earlier month.
        #expect(monthIndexForOffset(y: 99, offsets: offsets, totalMonths: totalMonths) == 0)
        #expect(monthIndexForOffset(y: 99.9, offsets: offsets, totalMonths: totalMonths) == 0)
        // Exactly on a boundary advances to the new month.
        #expect(monthIndexForOffset(y: 0, offsets: offsets, totalMonths: totalMonths) == 0)
        #expect(monthIndexForOffset(y: 100, offsets: offsets, totalMonths: totalMonths) == 1)
        #expect(monthIndexForOffset(y: 250, offsets: offsets, totalMonths: totalMonths) == 2)
        // Past the last recorded offset clamps to the final month instead of crashing.
        #expect(monthIndexForOffset(y: 10_000, offsets: offsets, totalMonths: totalMonths) == totalMonths - 1)
        // Negative offsets (e.g. rubber-band overscroll) clamp to the first month.
        #expect(monthIndexForOffset(y: -50, offsets: offsets, totalMonths: totalMonths) == 0)
    }

    @Test func monthIndexClampsFarOutOfWindowAnchorDatesToSharedWindowBounds() throws {
        let calendar = Calendar.current
        let currentMonthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let farPast = try #require(calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)))
        let farFuture = try #require(calendar.date(from: DateComponents(year: 2200, month: 1, day: 1)))

        let pastIndex = monthIndex(
            for: farPast,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: CalendarMonthGridMetrics.todayMonthIndex,
            calendar: calendar
        )
        let futureIndex = monthIndex(
            for: farFuture,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: CalendarMonthGridMetrics.todayMonthIndex,
            calendar: calendar
        )

        #expect(pastIndex == 0)
        #expect(futureIndex == CalendarMonthGridMetrics.totalMonths - 1)

        // An anchor date inside the window should never be clamped.
        let insideIndex = monthIndex(
            for: currentMonthStart,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: CalendarMonthGridMetrics.todayMonthIndex,
            calendar: calendar
        )
        #expect(insideIndex == CalendarMonthGridMetrics.todayMonthIndex)
    }

    @Test func cumulativeOffsetsTableMatchesPerMonthWeekHeights() {
        let calendar = Calendar.current
        let currentMonthStart = CalendarMonthGridSupport.currentMonthStart(calendar: calendar)
        let totalMonths = 6
        let todayMonthIdx = 0
        let cellHeight = CalendarMonthGridMetrics.cellHeight

        let offsets = CalendarMonthGridSupport.cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            cellHeight: cellHeight,
            calendar: calendar
        )

        #expect(offsets.count == totalMonths)
        #expect(offsets[0] == 0)

        for idx in 0..<(totalMonths - 1) {
            let month = calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
            let expectedHeight = CGFloat(CalendarMonthGridSupport.weeksInMonth(month, calendar: calendar)) * cellHeight
            #expect(offsets[idx + 1] - offsets[idx] == expectedHeight)
        }
    }

    @Test func handleScrollLeavesVisibleMonthIdxUntouchedUntilSettledOrDuringProgrammaticJump() {
        var visibleMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
        let offsets: [CGFloat] = stride(from: CGFloat(0), through: CGFloat(1200), by: 100).map { $0 }

        // Before the initial scroll position has settled, scroll-geometry callbacks must not
        // move visibleMonthIdx (this is what let the header show the wrong month transiently).
        CalendarMonthGridInteractionSupport.handleScroll(
            y: 500,
            offsets: offsets,
            totalMonths: offsets.count,
            visibleMonthIdx: &visibleMonthIdx,
            didInitialPosition: false,
            isProgrammaticScroll: false
        )
        #expect(visibleMonthIdx == CalendarMonthGridMetrics.todayMonthIndex)

        // While a programmatic scroll (e.g. a "Today" jump) is in flight, callbacks reflecting
        // the stale pre-jump offset must not stomp the value the jump just set.
        CalendarMonthGridInteractionSupport.handleScroll(
            y: 500,
            offsets: offsets,
            totalMonths: offsets.count,
            visibleMonthIdx: &visibleMonthIdx,
            didInitialPosition: true,
            isProgrammaticScroll: true
        )
        #expect(visibleMonthIdx == CalendarMonthGridMetrics.todayMonthIndex)

        // Once settled and no programmatic scroll is in flight, user scrolling updates normally.
        CalendarMonthGridInteractionSupport.handleScroll(
            y: 500,
            offsets: offsets,
            totalMonths: offsets.count,
            visibleMonthIdx: &visibleMonthIdx,
            didInitialPosition: true,
            isProgrammaticScroll: false
        )
        #expect(visibleMonthIdx == 5)
    }

    // MARK: - Month header / row height

    /// Reproduces the reported symptom: the title bar reads "September 2026" while the grid is
    /// showing August 2026 with today circled.
    ///
    /// `visibleMonthIdx` was read out of a *model* of the layout — a table of cumulative month
    /// heights built from a flat 130pt row — while the rows themselves were only
    /// `minHeight: 130`. A day cell holding a full chip stack measured about 134pt, so any week
    /// row containing one such day rendered taller than the table said it did, and the error
    /// accumulates in one direction across the window. The scroll offset the header is looked up
    /// with is measured from the top of the *first* month in the 120-month buffer, five years
    /// back, so by the time you reach today's month the accumulated surplus is what is being
    /// looked up — not today's true offset.
    @Test func monthHeaderRanAheadOfTheGridWhenRenderedRowsOutgrewTheOffsetTable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let currentMonthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let totalMonths = CalendarMonthGridMetrics.totalMonths
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        func offsets(rowHeight: CGFloat) -> [CGFloat] {
            CalendarMonthGridSupport.cumulativeOffsets(
                totalMonths: totalMonths,
                todayMonthIdx: todayMonthIdx,
                currentMonthStart: currentMonthStart,
                cellHeight: rowHeight,
                calendar: calendar
            )
        }

        // What the header consulted.
        let modelled = offsets(rowHeight: CalendarMonthGridMetrics.cellHeight)
        // What the grid actually laid out, averaged over rows that could only grow, never shrink.
        let rendered = offsets(rowHeight: CalendarMonthGridMetrics.cellHeight + 2.5)

        // Scrolled so that August 2026 — today's month — sits at the top of the viewport...
        let headerIndex = monthIndexForOffset(
            y: rendered[todayMonthIdx],
            offsets: modelled,
            totalMonths: totalMonths
        )
        // ...and the header names the month after it.
        #expect(headerIndex == todayMonthIdx + 1)

        // The overshoot required is not exotic. Today's month is 261 rows into the buffer, so a
        // couple of points per row — well under the ~4pt a full chip stack added — is enough to
        // swallow a whole month.
        let rowsBeforeTodaysMonth = (0..<todayMonthIdx).reduce(0) { partial, idx in
            let month = calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
            return partial + CalendarMonthGridSupport.weeksInMonth(month, calendar: calendar)
        }
        let todaysMonthHeight = modelled[todayMonthIdx + 1] - modelled[todayMonthIdx]
        #expect(todaysMonthHeight / CGFloat(rowsBeforeTodaysMonth) < 3)
    }

    /// The fix, stated as an invariant: rows and the offset table are now generated by the same
    /// function of the viewport height, so the model cannot drift away from the layout — at any
    /// month in the window, the offset the grid actually scrolls to resolves back to that month.
    @Test func viewportSizedMonthBlocksKeepTheOffsetTableExactAcrossTheWholeWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let currentMonthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let totalMonths = CalendarMonthGridMetrics.totalMonths
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
        let viewportHeight: CGFloat = 720

        let offsets = CalendarMonthGridSupport.cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            viewportHeight: viewportHeight,
            calendar: calendar
        )

        var renderedTop: CGFloat = 0
        for idx in 0..<totalMonths {
            let month = try #require(calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart))
            let weeks = CalendarMonthGridSupport.weeksInMonth(month, calendar: calendar)
            let rowHeight = CalendarMonthGridMetrics.rowHeight(weeksInMonth: weeks, viewportHeight: viewportHeight)

            // Even rows, and the month is exactly one screen tall: no dead band, no scrolling
            // inside a month.
            #expect(abs(CGFloat(weeks) * rowHeight - viewportHeight) < 0.0001)
            #expect(abs(offsets[idx] - renderedTop) < 0.0001)
            #expect(dominantMonthIndex(
                topY: renderedTop,
                viewportHeight: viewportHeight,
                offsets: offsets,
                totalMonths: totalMonths
            ) == idx)

            renderedTop += CGFloat(weeks) * rowHeight
        }
    }

    /// A window too short for a month keeps rows legible and lets the month scroll instead.
    @Test func monthRowsStopShrinkingAtTheMinimumRowHeight() {
        let rowHeight = CalendarMonthGridMetrics.rowHeight(weeksInMonth: 6, viewportHeight: 200)
        #expect(rowHeight == CalendarMonthGridMetrics.minimumRowHeight)
        #expect(CalendarMonthGridMetrics.monthHeight(weeksInMonth: 6, viewportHeight: 200) > 200)
        // An unmeasured viewport falls back to the fixed height rather than collapsing to zero.
        #expect(CalendarMonthGridMetrics.rowHeight(weeksInMonth: 5, viewportHeight: 0) == CalendarMonthGridMetrics.cellHeight)
    }

    @Test func dominantMonthIndexNamesTheMonthFillingTheViewportNotItsTopPixel() {
        let offsets: [CGFloat] = [0, 600, 1200, 1800]
        let viewportHeight: CGFloat = 600

        // One pixel short of the boundary the top row still belongs to the earlier month, but
        // 599 of 600 points on screen are the later one. Top-anchored labelling names the month
        // that owns a single row; overlap names the month the reader is looking at.
        #expect(monthIndexForOffset(y: 599, offsets: offsets, totalMonths: offsets.count) == 0)
        #expect(dominantMonthIndex(topY: 599, viewportHeight: viewportHeight, offsets: offsets, totalMonths: offsets.count) == 1)

        // Just past a boundary the previous month still owns the screen.
        #expect(dominantMonthIndex(topY: 1, viewportHeight: viewportHeight, offsets: offsets, totalMonths: offsets.count) == 0)
        // Exactly on a boundary the new month owns all of it.
        #expect(dominantMonthIndex(topY: 600, viewportHeight: viewportHeight, offsets: offsets, totalMonths: offsets.count) == 1)
        // Overscroll clamps rather than reading off the front of the table.
        #expect(dominantMonthIndex(topY: -80, viewportHeight: viewportHeight, offsets: offsets, totalMonths: offsets.count) == 0)
        // An unmeasured viewport degrades to the top-anchored answer instead of guessing.
        #expect(dominantMonthIndex(topY: 599, viewportHeight: 0, offsets: offsets, totalMonths: offsets.count) == 0)
    }

    @Test func monthCellChipCapacityFollowsTheRowHeightItWasGiven() {
        let tallCapacity = CalendarMonthCellLayout.chipCapacity(rowHeight: 180)
        let shortCapacity = CalendarMonthCellLayout.chipCapacity(rowHeight: 96)
        #expect(tallCapacity > shortCapacity)
        #expect(shortCapacity > 0)
        // A row with no room for even one chip caps at zero rather than going negative.
        #expect(CalendarMonthCellLayout.chipCapacity(rowHeight: 20) == 0)

        // Everything fits: no overflow label.
        let exact = CalendarMonthCellLayout.chipLayout(totalItems: tallCapacity, rowHeight: 180)
        #expect(exact.visible == tallCapacity)
        #expect(exact.overflow == 0)

        // One item too many: the "+N more" line takes a chip slot, so the stack still fits the
        // row, and the count it reports covers every hidden item.
        let spilling = CalendarMonthCellLayout.chipLayout(totalItems: tallCapacity + 3, rowHeight: 180)
        #expect(spilling.visible == tallCapacity - 1)
        #expect(spilling.visible + spilling.overflow == tallCapacity + 3)

        // The same day in a shorter row simply shows fewer chips and a bigger remainder.
        let squeezed = CalendarMonthCellLayout.chipLayout(totalItems: tallCapacity + 3, rowHeight: 96)
        #expect(squeezed.visible < spilling.visible)
        #expect(squeezed.visible + squeezed.overflow == tallCapacity + 3)
    }

    @Test func chipDueMarkerReadsAsADateRatherThanACount() {
        let calendar = Calendar.current

        // Inside the cell's own month: an ordinal, so it can never be mistaken for "7 items".
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-07", dayKey: "2026-08-12", calendar: calendar) == "7th")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-01", dayKey: "2026-08-12", calendar: calendar) == "1st")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-02", dayKey: "2026-08-12", calendar: calendar) == "2nd")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-03", dayKey: "2026-08-12", calendar: calendar) == "3rd")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-11", dayKey: "2026-08-12", calendar: calendar) == "11th")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-13", dayKey: "2026-08-12", calendar: calendar) == "13th")
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-21", dayKey: "2026-08-12", calendar: calendar) == "21st")

        // Across a month boundary the month comes along, since a bare day would be ambiguous.
        let crossMonth = CalendarChipDueMarkerSupport.label(dueDateKey: "2026-09-02", dayKey: "2026-08-31", calendar: calendar)
        #expect(crossMonth == "\(calendar.shortMonthSymbols[8]) 2")

        // Nothing at all when the chip already sits on its deadline, or has none: the grid
        // position already says the date.
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "2026-08-12", dayKey: "2026-08-12", calendar: calendar) == nil)
        #expect(CalendarChipDueMarkerSupport.label(dueDateKey: "", dayKey: "2026-08-12", calendar: calendar) == nil)
    }
}
#endif
