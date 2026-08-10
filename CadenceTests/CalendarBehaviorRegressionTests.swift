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

        let folded = CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [task])
        let grouped = CalendarBoardPlannerSupport.tasksByBoardDate(from: [task])

        #expect(folded["2026-06-02"]?.map(\.id) == [task.id])
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

        let result = CalendarBoardPlannerSupport.tasksByBoardDate(
            from: [cancelled, bundled, completed, active]
        )

        #expect(result["2026-06-02"]?.map(\.title) == ["Active", "Completed"])
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

    @Test func monthChipTimeFollowsWhichSegmentOfTheEventTheDayIs() {
        // A single-day event is its own first and last segment: plain start time.
        #expect(CalendarEventChipTimeSupport.label(
            isAllDay: false,
            isMultiDayTimedEvent: false,
            isFirstSegment: true,
            isLastSegment: true,
            eventStartMin: 22 * 60 + 29,
            eventEndMin: 23 * 60 + 30
        ) == "10:29 PM")

        // Day it starts: the start time, even though the day it draws on has no end.
        #expect(CalendarEventChipTimeSupport.label(
            isAllDay: false,
            isMultiDayTimedEvent: true,
            isFirstSegment: true,
            isLastSegment: false,
            eventStartMin: 22 * 60 + 29,
            eventEndMin: 12 * 60 + 55
        ) == "10:29 PM")

        // Day it finishes: the end time, labelled so it cannot be read as a start.
        #expect(CalendarEventChipTimeSupport.label(
            isAllDay: false,
            isMultiDayTimedEvent: true,
            isFirstSegment: false,
            isLastSegment: true,
            eventStartMin: 22 * 60 + 29,
            eventEndMin: 12 * 60 + 55
        ) == "ends 12:55 PM")

        // A middle day runs midnight to midnight, so neither endpoint is a fact about it.
        #expect(CalendarEventChipTimeSupport.label(
            isAllDay: false,
            isMultiDayTimedEvent: true,
            isFirstSegment: false,
            isLastSegment: false,
            eventStartMin: 22 * 60 + 29,
            eventEndMin: 12 * 60 + 55
        ) == nil)

        // All-day events have no time to show at any position.
        #expect(CalendarEventChipTimeSupport.label(
            isAllDay: true,
            isMultiDayTimedEvent: false,
            isFirstSegment: true,
            isLastSegment: true,
            eventStartMin: 0,
            eventEndMin: 0
        ) == nil)
    }

    // MARK: - Rendering block vs calendar month

    private static func gridCalendar(_ zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? calendar.timeZone
        return calendar
    }

    /// Every day the grid draws for one month block, in the order it draws them.
    private static func renderedDays(month: Date, calendar: Calendar) -> [Date] {
        CalendarMonthGridSupport.weeks(for: month, calendar: calendar)
            .flatMap { $0 }
            .compactMap { $0 }
    }

    /// The worked example, pinned: Aug 1 2026 is a Saturday, so August's block opens on Sun Aug 2
    /// and Aug 1 is drawn as the final trailing cell of July's block. A "which month is this
    /// date in" answer and a "which page draws it" answer differ here by one.
    @Test func augustFirst2026IsDrawnOnJulysPageBecauseAugustOpensOnItsFirstSunday() throws {
        let calendar = Self.gridCalendar()
        let july = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let august = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        // July 2026 starts Wed Jul 1, so its page runs Jul 5-31 — 27 days, padded by exactly
        // one, and that pad is Aug 1.
        let julyDays = Self.renderedDays(month: july, calendar: calendar)
        #expect(julyDays.count == 28)
        #expect(DateFormatters.dateKey(from: julyDays[0], calendar: calendar) == "2026-07-05")
        #expect(DateFormatters.dateKey(from: julyDays[27], calendar: calendar) == "2026-08-01")

        // August's own page therefore starts on Aug 2 and never draws Aug 1.
        let augustDays = Self.renderedDays(month: august, calendar: calendar)
        #expect(DateFormatters.dateKey(from: augustDays[0], calendar: calendar) == "2026-08-02")
        #expect(!augustDays.contains { calendar.isDate($0, inSameDayAs: august) })

        // The rendering block for Aug 1 is July's; the calendar month is still August.
        let block = CalendarMonthGridSupport.blockMonthStart(for: august, calendar: calendar)
        #expect(calendar.isDate(block, equalTo: july, toGranularity: .month))
        #expect(calendar.isDate(monthStart(for: august, calendar: calendar), equalTo: august, toGranularity: .month))

        // And in index terms: standing in August, Aug 1 lives one block back.
        let currentMonthStart = monthStart(for: august, calendar: calendar)
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
        #expect(blockIndex(for: august, currentMonthStart: currentMonthStart, todayMonthIdx: todayMonthIdx, calendar: calendar) == todayMonthIdx - 1)
        #expect(monthIndex(for: august, currentMonthStart: currentMonthStart, todayMonthIdx: todayMonthIdx, calendar: calendar) == todayMonthIdx)
    }

    /// One case per weekday a month can open on. The carry is 0 for a Sunday-start month and 6
    /// for a Monday-start one, so June 2026 is the worst case: six of its days are drawn on
    /// May's page before June's page begins.
    @Test func everyStartingWeekdayCarriesTheRightNumberOfDaysOntoThePreviousPage() throws {
        let calendar = Self.gridCalendar()
        // 2026 happens to contain a month opening on each of the seven weekdays.
        let cases: [(month: Int, weekday: Int, expectedCarry: Int)] = [
            (2, 1, 0),  // Sunday
            (6, 2, 6),  // Monday  - worst case
            (9, 3, 5),  // Tuesday
            (4, 4, 4),  // Wednesday
            (1, 5, 3),  // Thursday
            (5, 6, 2),  // Friday
            (8, 7, 1),  // Saturday
        ]

        for testCase in cases {
            let first = try #require(calendar.date(from: DateComponents(year: 2026, month: testCase.month, day: 1)))
            #expect(calendar.component(.weekday, from: first) == testCase.weekday)

            let carry = CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: first, calendar: calendar)
            #expect(carry == testCase.expectedCarry)

            // The page opens on the first Sunday, which is `carry` days in...
            let days = Self.renderedDays(month: first, calendar: calendar)
            let firstDrawn = try #require(days.first)
            #expect(calendar.component(.weekday, from: firstDrawn) == 1)
            #expect(calendar.isDate(firstDrawn, inSameDayAs: CalendarMonthGridSupport.blockFirstDay(of: first, calendar: calendar)))
            #expect(calendar.component(.day, from: firstDrawn) == testCase.expectedCarry + 1)

            let previousMonth = try #require(calendar.date(byAdding: .month, value: -1, to: first))
            let previousDays = Self.renderedDays(month: previousMonth, calendar: calendar)

            // ...and each carried day is drawn on the previous page instead, with
            // `blockMonthStart` agreeing about where it went.
            for day in 1...max(1, testCase.expectedCarry) where day <= testCase.expectedCarry {
                let date = try #require(calendar.date(from: DateComponents(year: 2026, month: testCase.month, day: day)))
                #expect(!days.contains { calendar.isDate($0, inSameDayAs: date) })
                #expect(previousDays.contains { calendar.isDate($0, inSameDayAs: date) })
                #expect(calendar.isDate(
                    CalendarMonthGridSupport.blockMonthStart(for: date, calendar: calendar),
                    equalTo: previousMonth,
                    toGranularity: .month
                ))
            }
        }
    }

    /// Leap Februaries, including a Sunday-start one whose 29 days overflow four weeks by a
    /// single day and pull six days of March onto February's page.
    @Test func leapFebruariesTileWithoutLosingOrRepeatingADay() throws {
        let calendar = Self.gridCalendar()

        for year in [2024, 2028, 2032] {
            let february = try #require(calendar.date(from: DateComponents(year: year, month: 2, day: 1)))
            #expect(calendar.range(of: .day, in: .month, for: february)?.count == 29)

            let days = Self.renderedDays(month: february, calendar: calendar)
            #expect(days.count % 7 == 0)
            // Whole weeks, opening on a Sunday and closing on a Saturday.
            #expect(calendar.component(.weekday, from: try #require(days.first)) == 1)
            #expect(calendar.component(.weekday, from: try #require(days.last)) == 7)

            // Feb 29 is drawn exactly once, on the page `blockMonthStart` names.
            let leapDay = try #require(calendar.date(from: DateComponents(year: year, month: 2, day: 29)))
            let leapDayBlock = CalendarMonthGridSupport.blockMonthStart(for: leapDay, calendar: calendar)
            let leapDayPage = Self.renderedDays(month: leapDayBlock, calendar: calendar)
            #expect(leapDayPage.filter { calendar.isDate($0, inSameDayAs: leapDay) }.count == 1)
        }

        // Feb 2032 opens on a Sunday, so it carries nothing forward but still spills into March.
        let feb2032 = try #require(calendar.date(from: DateComponents(year: 2032, month: 2, day: 1)))
        #expect(CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: feb2032, calendar: calendar) == 0)
        let feb2032Days = Self.renderedDays(month: feb2032, calendar: calendar)
        #expect(feb2032Days.count == 35)
        #expect(DateFormatters.dateKey(from: try #require(feb2032Days.last), calendar: calendar) == "2032-03-06")
    }

    /// The property that would have caught this: over a wide window, the block index a date maps
    /// to must be a block whose `weeks(for:)` actually draws that date — and only that one.
    ///
    /// Nothing tied the two notions together before, which is why "which month is this date in"
    /// could stand in for "which page draws it" for years without anyone noticing that they part
    /// company about three days a month.
    @Test func everyDateResolvesToTheBlockThatActuallyDrawsIt() throws {
        let calendar = Self.gridCalendar()
        let windowMonths = 60
        let currentMonthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        // Every day each block draws, keyed by block index.
        var drawnBy: [Int: Set<String>] = [:]
        for idx in (todayMonthIdx - windowMonths)...(todayMonthIdx + windowMonths) {
            let month = try #require(calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart))
            drawnBy[idx] = Set(
                Self.renderedDays(month: month, calendar: calendar)
                    .map { DateFormatters.dateKey(from: $0, calendar: calendar) }
            )
        }

        // Walk every day of the interior of the window, so each date has both neighbours' blocks
        // built and "drawn exactly once" is a meaningful claim.
        var date = try #require(calendar.date(byAdding: .month, value: -(windowMonths - 1), to: currentMonthStart))
        let end = try #require(calendar.date(byAdding: .month, value: windowMonths - 1, to: currentMonthStart))
        var checkedDays = 0
        var daysDrawnOffTheirOwnMonthsPage = 0

        while date < end {
            let key = DateFormatters.dateKey(from: date, calendar: calendar)
            let idx = blockIndex(
                for: date,
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            )

            // The block it maps to draws it...
            #expect(drawnBy[idx]?.contains(key) == true, "\(key) mapped to block \(idx), which does not draw it")
            // ...and no other block does, so the tiling neither repeats nor drops a day.
            #expect(drawnBy.filter { $0.value.contains(key) }.count == 1, "\(key) is drawn by more than one block")

            let calendarMonthIdx = monthIndex(
                for: date,
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            )
            if idx != calendarMonthIdx {
                daysDrawnOffTheirOwnMonthsPage += 1
                // Only ever one block early, never later, never further.
                #expect(idx == calendarMonthIdx - 1)
            }

            checkedDays += 1
            date = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        }

        #expect(checkedDays > 3_500)
        // Roughly three days a month, i.e. the bug's blast radius — and emphatically not zero,
        // which is what the old code assumed.
        #expect(daysDrawnOffTheirOwnMonthsPage > checkedDays / 20)
    }

    /// The regression itself: the id "Today" scrolls to has to be an id the grid emits.
    ///
    /// `ScrollViewProxy.scrollTo` ignores an unknown id in silence, so keying the day id off
    /// today's calendar month simply did nothing on the days when that is not the block drawing
    /// today — and the month anchor beside it parked the reader on a page without today on it.
    @Test func todayJumpTargetsAreIdsTheGridActuallyTags() throws {
        let calendar = Self.gridCalendar()
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        // Every day of a year that contains a month opening on each weekday, plus the worked
        // example, each treated in turn as "today".
        var today = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let end = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        var jumpsLandingOnAnEarlierBlock = 0

        while today < end {
            let todayKey = DateFormatters.dateKey(from: today, calendar: calendar)
            let currentMonthStart = CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: today)

            let targets = CalendarMonthGridInteractionSupport.todayJumpTargets(
                todayKey: todayKey,
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            )

            // Rebuild the ids `MonthWeeksView` tags its cells with, for the block the jump
            // anchors and its neighbours.
            var tagged: Set<String> = []
            for idx in (todayMonthIdx - 1)...(todayMonthIdx + 1) {
                let month = try #require(calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart))
                for day in Self.renderedDays(month: month, calendar: calendar) {
                    tagged.insert(CalendarMonthGridIdentifiers.day(
                        monthIndex: idx,
                        dateKey: DateFormatters.dateKey(from: day, calendar: calendar)
                    ))
                }
            }

            #expect(tagged.contains(targets.dayID), "no cell is tagged \(targets.dayID)")

            // The month anchor and the day id name the same block, so the two scrolls agree.
            let anchoredIdx = blockIndex(
                for: today,
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            )
            #expect(targets.monthID == CalendarMonthGridIdentifiers.month(anchoredIdx))
            #expect(targets.dayID == CalendarMonthGridIdentifiers.day(monthIndex: anchoredIdx, dateKey: todayKey))

            if anchoredIdx != todayMonthIdx {
                jumpsLandingOnAnEarlierBlock += 1
                // What the old code emitted on these days: an id no cell carries.
                let staleID = CalendarMonthGridIdentifiers.day(monthIndex: todayMonthIdx, dateKey: todayKey)
                #expect(!tagged.contains(staleID))
            }

            today = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        }

        // 2026 has 33 such days — the "roughly three days a month" the bug was live for.
        #expect(jumpsLandingOnAnEarlierBlock == 33)
    }

    /// Aug 1 2026 end to end: pressing "Today" anchors July's block, and — deliberately — the
    /// header says July.
    ///
    /// `visibleMonthIdx` is a block index everywhere else in the page (it is what
    /// `dominantMonthIndex` writes on every scroll), so the header naming the anchored block is
    /// the only self-consistent choice. Naming August instead would misdescribe the 27 July
    /// cells filling the page and would have to snap back to July on the first scroll event.
    @Test func todayJumpOnAugustFirst2026AnchorsJulysBlockAndTheHeaderSaysJuly() throws {
        let calendar = Self.gridCalendar()
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9)))
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        let anchoredIdx = CalendarPageStateSupport.monthIndexForToday(
            todayMonthIdx: todayMonthIdx,
            calendar: calendar,
            today: today
        )
        #expect(anchoredIdx == todayMonthIdx - 1)

        // The header is derived from the same index the grid is scrolled to, so it names the
        // page on screen rather than the month the highlighted cell belongs to.
        let currentMonthStart = CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: today)
        let anchoredMonth = try #require(calendar.date(byAdding: .month, value: anchoredIdx - todayMonthIdx, to: currentMonthStart))
        #expect(calendar.component(.month, from: anchoredMonth) == 7)

        // ...and the page it names does contain today, which is the whole point.
        let drawn = Self.renderedDays(month: anchoredMonth, calendar: calendar)
        #expect(drawn.contains { calendar.isDate($0, inSameDayAs: today) })
    }

    /// The inverse has to actually invert: leaving a block and coming back must land on the same
    /// block. Returning the 1st of the block's month would not, since for a month that opens
    /// mid-week the 1st is drawn on the page before.
    @Test func blockToDateKeyRoundTripsBackToTheSameBlock() throws {
        let calendar = Self.gridCalendar()
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 9)))
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
        let currentMonthStart = CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: today)

        for idx in (todayMonthIdx - 24)...(todayMonthIdx + 24) {
            let key = CalendarPageStateSupport.dateKeyForVisibleMonth(
                visibleMonthIdx: idx,
                todayMonthIdx: todayMonthIdx,
                currentMonthStart: currentMonthStart,
                calendar: calendar,
                today: today
            )
            let returned = CalendarPageStateSupport.monthIndexForTimelineAnchor(
                anchorDateKey: key,
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            )
            #expect(returned == idx, "block \(idx) round-tripped through \(key) to block \(returned)")

            // The date it hands back is one the block draws, not merely one in its month.
            let month = try #require(calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart))
            let drawnKeys = Set(Self.renderedDays(month: month, calendar: calendar).map {
                DateFormatters.dateKey(from: $0, calendar: calendar)
            })
            #expect(drawnKeys.contains(key))
        }
    }

    /// Parsing a key in one zone and measuring it in another is how this codebase has been bitten
    /// before, so the date -> block mapping is pinned across zones either side of UTC.
    @Test func blockMappingIsStableAcrossTimeZones() throws {
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        for zone in ["America/New_York", "Asia/Shanghai", "UTC", "Pacific/Kiritimati"] {
            let calendar = Self.gridCalendar(zone)
            let currentMonthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

            // Aug 1 sits on July's page; Aug 2, the first Sunday, opens August's.
            #expect(CalendarPageStateSupport.monthIndexForTimelineAnchor(
                anchorDateKey: "2026-08-01",
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            ) == todayMonthIdx - 1, "wrong block in \(zone)")

            #expect(CalendarPageStateSupport.monthIndexForTimelineAnchor(
                anchorDateKey: "2026-08-02",
                currentMonthStart: currentMonthStart,
                todayMonthIdx: todayMonthIdx,
                calendar: calendar
            ) == todayMonthIdx, "wrong block in \(zone)")
        }
    }

    // MARK: - Out-of-month day labelling

    /// May 2026 opens on a Friday, so its block runs Sun May 3 -> Sat Jun 6: six carried June
    /// days on a page headed "May 2026". The worst case in the calendar, and the fixture for
    /// everything below.
    private static func may2026(_ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// Every day drawn outside its block's own month names that month — not only the 1st.
    ///
    /// Apple's paged grid can mark just the 1st, because a paged grid always draws the 1st on its
    /// own month's page. This grid tiles without overlap, so June 2026's first six days are drawn
    /// on May's page and only one of them is the 1st; the other five used to be bare numbers.
    @Test func everyCarriedDayNamesItsOwnMonthNotOnlyTheFirst() throws {
        let calendar = Self.gridCalendar()
        let may = try Self.may2026(calendar)
        let june = try Self.day(2026, 6, 1, calendar)

        // The fixture itself: May's block is May 3 -> Jun 6, and June's block never draws them.
        let mayDays = Self.renderedDays(month: may, calendar: calendar)
        #expect(DateFormatters.dateKey(from: try #require(mayDays.first), calendar: calendar) == "2026-05-03")
        #expect(DateFormatters.dateKey(from: try #require(mayDays.last), calendar: calendar) == "2026-06-06")
        #expect(CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: june, calendar: calendar) == 6)

        let expectedJune = calendar.shortMonthSymbols[5]
        for dayNumber in 1...6 {
            let date = try Self.day(2026, 6, dayNumber, calendar)
            let emphasis = CalendarMonthDayLabelSupport.emphasis(
                for: date,
                displayMonth: may,
                today: try Self.day(2026, 5, 20, calendar),
                calendar: calendar
            )
            #expect(emphasis == .outOfMonth)
            #expect(CalendarMonthDayLabelSupport.monthAbbreviation(
                for: date,
                emphasis: emphasis,
                calendar: calendar
            ) == expectedJune, "Jun \(dayNumber) drew a bare number on May's page")
        }

        // A day of the page's own month still says nothing extra — only the 1st ever did, and
        // that is unchanged.
        let mayThird = try Self.day(2026, 5, 3, calendar)
        let mayThirdEmphasis = CalendarMonthDayLabelSupport.emphasis(
            for: mayThird,
            displayMonth: may,
            today: try Self.day(2026, 5, 20, calendar),
            calendar: calendar
        )
        #expect(mayThirdEmphasis == .inMonth)
        #expect(CalendarMonthDayLabelSupport.monthAbbreviation(
            for: mayThird,
            emphasis: mayThirdEmphasis,
            calendar: calendar
        ) == nil)

        // February 2026 opens on a Sunday, so its 1st is drawn on its own page — the one case
        // where an in-month cell is the 1st. It keeps its abbreviation.
        let february = try Self.day(2026, 2, 1, calendar)
        let februaryEmphasis = CalendarMonthDayLabelSupport.emphasis(
            for: february,
            displayMonth: february,
            today: try Self.day(2026, 2, 20, calendar),
            calendar: calendar
        )
        #expect(februaryEmphasis == .inMonth)
        #expect(CalendarMonthDayLabelSupport.monthAbbreviation(
            for: february,
            emphasis: februaryEmphasis,
            calendar: calendar
        ) == calendar.shortMonthSymbols[1])
    }

    /// The defect, stated exactly: on Jun 3 2026 "Today" anchors May's block, and that page shows
    /// two cells labelled "3" — May 3 in the first row, Jun 3 in the last.
    ///
    /// The old styling asked `isToday` first and returned early, so Jun 3 was drawn as an
    /// ordinary in-month today: full-strength label, filled disc, no month marker, nothing at all
    /// saying it belonged to the next month.
    @Test func aCarriedDayThatIsAlsoTodayStillReadsAsOutOfMonth() throws {
        let calendar = Self.gridCalendar()
        let may = try Self.may2026(calendar)
        let today = try Self.day(2026, 6, 3, calendar)

        // Both cells really are on the same page, both really are labelled "3".
        let drawnKeys = Set(Self.renderedDays(month: may, calendar: calendar).map {
            DateFormatters.dateKey(from: $0, calendar: calendar)
        })
        #expect(drawnKeys.contains("2026-05-03"))
        #expect(drawnKeys.contains("2026-06-03"))

        let carriedToday = CalendarMonthDayLabelSupport.emphasis(
            for: today,
            displayMonth: may,
            today: today,
            calendar: calendar
        )
        let ownMonthDay = CalendarMonthDayLabelSupport.emphasis(
            for: try Self.day(2026, 5, 3, calendar),
            displayMonth: may,
            today: today,
            calendar: calendar
        )

        #expect(carriedToday == .outOfMonthToday)
        #expect(ownMonthDay == .inMonth)

        // Both signals at once: still today, still out of month.
        #expect(carriedToday.isToday)
        #expect(carriedToday.isOutOfMonth)

        // The today marker survives — as a ring rather than a filled disc.
        #expect(carriedToday.todayRingStroke != nil)
        #expect(carriedToday.todayDiscFill == nil)
        #expect(CalendarMonthDayEmphasis.inMonthToday.todayDiscFill != nil)
        #expect(CalendarMonthDayEmphasis.inMonthToday.todayRingStroke == nil)

        // ...and it is not styled as an in-month today, which is precisely what it used to be.
        #expect(carriedToday.dateLabelColor != CalendarMonthDayEmphasis.inMonthToday.dateLabelColor)
        #expect(carriedToday.dateLabelWeight != CalendarMonthDayEmphasis.inMonthToday.dateLabelWeight)
        #expect(carriedToday.cellBackground != CalendarMonthDayEmphasis.inMonthToday.cellBackground)

        // The month marker is the unambiguous half of the answer: the ringed "3" says "Jun 3".
        #expect(CalendarMonthDayLabelSupport.monthAbbreviation(
            for: today,
            emphasis: carriedToday,
            calendar: calendar
        ) == calendar.shortMonthSymbols[5])
        // The other "3" on the page carries no marker, so the two cannot be confused.
        #expect(CalendarMonthDayLabelSupport.monthAbbreviation(
            for: try Self.day(2026, 5, 3, calendar),
            emphasis: ownMonthDay,
            calendar: calendar
        ) == nil)

        // Carried today shares the out-of-month plate, so the "not this month" band is unbroken.
        #expect(carriedToday.cellBackground == CalendarMonthDayEmphasis.outOfMonth.cellBackground)
    }

    /// Marker shape and label colour per state. Backgrounds are pinned separately, in
    /// `outOfMonthCellsAreOnAVisiblyDifferentPlateFromTheDisplayedMonth`.
    @Test func eachEmphasisStateKeepsItsOwnMarkerAndLabel() {
        #expect(CalendarMonthDayEmphasis.inMonth.dateLabelColor == Theme.text)
        #expect(CalendarMonthDayEmphasis.inMonth.dateLabelWeight == .medium)
        #expect(CalendarMonthDayEmphasis.inMonth.todayDiscFill == nil)
        #expect(CalendarMonthDayEmphasis.inMonth.todayRingStroke == nil)

        #expect(CalendarMonthDayEmphasis.inMonthToday.dateLabelColor == Theme.onColor)
        #expect(CalendarMonthDayEmphasis.inMonthToday.dateLabelWeight == .bold)
        #expect(CalendarMonthDayEmphasis.inMonthToday.todayDiscFill == Theme.blue)

        // Carried days stay dimmed and never borrow an in-month colour.
        #expect(CalendarMonthDayEmphasis.outOfMonth.dateLabelColor != Theme.text)
        #expect(CalendarMonthDayEmphasis.outOfMonth.dateLabelColor != Theme.onColor)
        #expect(CalendarMonthDayEmphasis.outOfMonth.dateLabelWeight == .regular)
        #expect(CalendarMonthDayEmphasis.outOfMonthToday.dateLabelColor == Theme.blue)
    }

    /// The greying is a *band*, and a band only exists if the two plates actually differ.
    ///
    /// The failure this pins: in-month `Theme.bg` (#09090b) against out-of-month
    /// `Theme.surfaceRecessed` (#0d0d0f) — four units on a near-black plate, and inverted, with
    /// the "recessed" cell drawn lighter than the page it sat on. `Theme.bg` has no room below
    /// it, so the displayed month is what moves: it takes `Theme.surface` and the carried days
    /// fall back to the app background.
    @Test func outOfMonthCellsAreOnAVisiblyDifferentPlateFromTheDisplayedMonth() {
        let inMonth = CalendarMonthDayEmphasis.inMonth.cellBackground
        let outOfMonth = CalendarMonthDayEmphasis.outOfMonth.cellBackground

        #expect(inMonth != outOfMonth)
        #expect(inMonth == Theme.surface)
        #expect(outOfMonth == Theme.bg)
        // Specifically not the old pairing, in either direction.
        #expect(inMonth != Theme.surfaceRecessed)
        #expect(outOfMonth != Theme.surfaceRecessed)

        // Today does not opt out of its own month's plate: it is the wash, layered on top, that
        // marks it — so a washed today still reads as part of the page it belongs to.
        #expect(CalendarMonthDayEmphasis.inMonthToday.cellBackground == inMonth)
        #expect(CalendarMonthDayEmphasis.inMonthToday.cellWash != nil)
        #expect(CalendarMonthDayEmphasis.inMonth.cellWash == nil)
        #expect(CalendarMonthDayEmphasis.outOfMonth.cellWash == nil)
        // A carried today must not pick up the wash — that would break the grey band it belongs
        // to and leave two cells on the page washed as "today's month".
        #expect(CalendarMonthDayEmphasis.outOfMonthToday.cellWash == nil)
        #expect(CalendarMonthDayEmphasis.outOfMonthToday.cellBackground == outOfMonth)
    }

    /// The rule as a property, over every day the grid actually draws for two years: a cell
    /// names a month exactly when the page it sits on does not already say which month it is.
    @Test func everyRenderedDayNamesAMonthExactlyWhenItsPageDoesNot() throws {
        let calendar = Self.gridCalendar()
        let start = try Self.day(2026, 1, 1, calendar)
        var carriedDaysSeen = 0
        var markedInMonthFirsts = 0

        for offset in 0..<24 {
            let month = try #require(calendar.date(byAdding: .month, value: offset, to: start))
            let monthNumber = calendar.component(.month, from: month)

            for date in Self.renderedDays(month: month, calendar: calendar) {
                let emphasis = CalendarMonthDayLabelSupport.emphasis(
                    for: date,
                    displayMonth: month,
                    // A date the window never contains, so nothing here is today.
                    today: try Self.day(1970, 1, 1, calendar),
                    calendar: calendar
                )
                let abbreviation = CalendarMonthDayLabelSupport.monthAbbreviation(
                    for: date,
                    emphasis: emphasis,
                    calendar: calendar
                )
                let dayNumber = calendar.component(.day, from: date)
                let ownMonth = calendar.component(.month, from: date)
                let key = DateFormatters.dateKey(from: date, calendar: calendar)

                #expect(emphasis.isOutOfMonth == (ownMonth != monthNumber), "\(key) misclassified")

                if emphasis.isOutOfMonth {
                    carriedDaysSeen += 1
                    // Names its *own* month, not the page's.
                    #expect(abbreviation == calendar.shortMonthSymbols[ownMonth - 1], "\(key) named the wrong month")
                } else if dayNumber == 1 {
                    markedInMonthFirsts += 1
                    #expect(abbreviation == calendar.shortMonthSymbols[ownMonth - 1])
                } else {
                    #expect(abbreviation == nil, "\(key) named a month its page already states")
                }
            }
        }

        // Two years of blocks carry plenty of days, and a handful of Sunday-start months put
        // their own 1st on their own page.
        #expect(carriedDaysSeen > 50)
        #expect(markedInMonthFirsts > 0)
    }

    // MARK: - Window boundary and board hand-off

    /// The one place `blockIndex(for:)` returns a block that does not draw the date it was asked
    /// about, pinned rather than papered over.
    ///
    /// For a day in the leading 1–6 days of the window's earliest month, the rendering block is
    /// the month *before* the window — index `-1` — and no block in the window draws that day at
    /// all. The clamp lands on block 0, knowingly a non-drawing block, because there is no honest
    /// alternative. Unreachable in production (the window is 120 months centred on today), but if
    /// this ever changes it should change on purpose.
    @Test func blockIndexClampsBelowTheWindowToAKnowinglyNonDrawingBlock() throws {
        let calendar = Self.gridCalendar()
        let currentMonthStart = try Self.day(2026, 7, 1, calendar)
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        // Block 0 is the earliest month the window holds: 60 months before the centre.
        let earliestMonth = try #require(calendar.date(byAdding: .month, value: -todayMonthIdx, to: currentMonthStart))
        let carry = CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: earliestMonth, calendar: calendar)
        #expect(carry > 0, "fixture needs an earliest month that does not open on a Sunday")

        let carriedDay = earliestMonth  // the 1st, which that block does not draw
        let idx = blockIndex(
            for: carriedDay,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
        #expect(idx == 0)

        // The documented gap: block 0 does not draw it, and neither does any other block.
        let block0Keys = Set(Self.renderedDays(month: earliestMonth, calendar: calendar).map {
            DateFormatters.dateKey(from: $0, calendar: calendar)
        })
        #expect(!block0Keys.contains(DateFormatters.dateKey(from: carriedDay, calendar: calendar)))

        // One day later the answer is honest again, which is why the gap is exactly this wide.
        let firstDrawn = CalendarMonthGridSupport.blockFirstDay(of: earliestMonth, calendar: calendar)
        #expect(blockIndex(
            for: firstDrawn,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        ) == 0)
        #expect(block0Keys.contains(DateFormatters.dateKey(from: firstDrawn, calendar: calendar)))
    }

    /// Leaving the month grid for the board planner opens on the block's **first rendered day**,
    /// not the 1st of its month — a day the page the reader came from actually drew.
    ///
    /// July 2026's block opens Jul 5; Jul 1 is drawn on June's page. Opening the planner on Jul 1
    /// would name a day the reader was not looking at, and would round-trip back one block early.
    @Test func boardAnchorForAMonthBlockOpensOnTheBlocksFirstRenderedDay() throws {
        let calendar = Self.gridCalendar()
        let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex

        // `boardAnchorDateKey` reads the real clock (it has no `today:` seam), so the block
        // indices under test are taken relative to today's own block — never equal to it, so the
        // "you were on today's page" shortcut cannot fire and the test cannot rot.
        let currentMonthStart = CalendarMonthGridSupport.currentMonthStart(calendar: calendar)
        let todayBlockIdx = blockIndex(
            for: Date(),
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )

        var carriedMonthsChecked = 0
        for offset in 1...12 {
            let idx = todayBlockIdx + offset
            let month = try #require(calendar.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart))

            let key = CalendarPageStateSupport.boardAnchorDateKey(
                viewMode: .month,
                visibleMonthIdx: idx,
                // Deliberately non-nil: in month mode the timeline day must be ignored.
                visibleTimelineDayIndex: 12,
                anchorDateKey: "1970-01-01",
                bufferStart: currentMonthStart,
                currentMonthStart: currentMonthStart,
                calendar: calendar
            )

            let drawn = Self.renderedDays(month: month, calendar: calendar)
            let firstDrawnKey = DateFormatters.dateKey(from: try #require(drawn.first), calendar: calendar)
            #expect(key == firstDrawnKey, "block \(idx) opened the board on \(key), which it does not draw first")

            if CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: month, calendar: calendar) > 0 {
                carriedMonthsChecked += 1
                // Explicitly *not* the 1st, which is the behavior being kept.
                #expect(key != DateFormatters.dateKey(from: month, calendar: calendar))
            }
        }
        // At most a couple of twelve consecutive months open on a Sunday.
        #expect(carriedMonthsChecked >= 8)

        // The worked example, pinned through the helper `boardAnchorDateKey` delegates to (which
        // does take a `today:`): standing well outside July's block, July 2026 hands back Jul 5.
        #expect(CalendarPageStateSupport.dateKeyForVisibleMonth(
            visibleMonthIdx: todayMonthIdx,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: try Self.day(2026, 7, 1, calendar),
            calendar: calendar,
            today: try Self.day(2026, 12, 1, calendar)
        ) == "2026-07-05")
    }
}
#endif
