import Foundation
import Testing
@testable import Cadence

/// Covers the two pinned rails the Calendar Board absorbed from the retired Planning page:
/// which tasks land in them, what a drop on each one writes, and the summary line above them.
@MainActor
struct CalendarBoardRailTests {
    private let todayKey = "2026-06-15"

    private func task(
        _ title: String,
        doDate: String = "",
        dueDate: String = "",
        startMin: Int = -1
    ) -> AppTask {
        let task = AppTask(title: title)
        task.scheduledDate = doDate
        task.dueDate = dueDate
        task.scheduledStartMin = startMin
        return task
    }

    // MARK: - Bucketing

    @Test func pastDoDateLandsInOverdue() {
        let overdue = task("Overdue", doDate: "2026-06-14")

        #expect(CalendarBoardPlannerSupport.rail(for: overdue, todayKey: todayKey) == .overdue)
    }

    @Test func missingDoDateLandsInUnscheduled() {
        let backlog = task("Backlog")

        #expect(CalendarBoardPlannerSupport.rail(for: backlog, todayKey: todayKey) == .unscheduled)
    }

    /// A task whose only date is a *due* date has no do date, so it belongs in the Unscheduled
    /// rail — not in its due day's column. If it were bucketed by the due date, dragging it to
    /// Unscheduled would clear a do date it never had and the card would not move.
    @Test func dueOnlyTaskLandsInUnscheduledRatherThanItsDueDay() {
        let dueOnly = task("Due only", dueDate: "2026-06-20")

        #expect(CalendarBoardPlannerSupport.rail(for: dueOnly, todayKey: todayKey) == .unscheduled)
        #expect(CalendarBoardPlannerSupport.tasksByBoardDate(from: [dueOnly])["2026-06-20"] == nil)
    }

    @Test func todayAndFutureDoDatesBelongToDayColumnsNotRails() {
        let today = task("Today", doDate: todayKey)
        let later = task("Later", doDate: "2026-07-01")

        #expect(CalendarBoardPlannerSupport.rail(for: today, todayKey: todayKey) == nil)
        #expect(CalendarBoardPlannerSupport.rail(for: later, todayKey: todayKey) == nil)
    }

    /// The rails and the *rendered* day columns must partition the board's open work exactly once:
    /// every open task is in one rail or one day column, and never in both. The board renders day
    /// columns from today forward, so only those keys count — past keys still exist in the
    /// bucketing but have no column to appear in, which is exactly what the Overdue rail covers.
    @Test func railsAndRenderedDayColumnsPartitionOpenWorkExactlyOnce() {
        let overdue = task("Overdue", doDate: "2026-06-01")
        let today = task("Today", doDate: todayKey)
        let backlog = task("Backlog")
        let dueOnly = task("Due only", dueDate: "2026-06-20")
        let all = [overdue, today, backlog, dueOnly]

        let rails = CalendarBoardPlannerSupport.railTasks(from: all, todayKey: todayKey)
        let renderedDayColumns = CalendarBoardPlannerSupport.tasksByBoardDate(from: all).filter { $0.key >= todayKey }
        let dayColumnIDs = Set(renderedDayColumns.values.flatMap { $0 }.map(\.id))
        let railIDs = Set(rails.values.flatMap { $0 }.map(\.id))

        #expect(railIDs.isDisjoint(with: dayColumnIDs))
        #expect(railIDs.union(dayColumnIDs) == Set(all.map(\.id)))
    }

    @Test func railsExcludeCompletedAndCancelledWork() {
        let done = task("Done", doDate: "2026-06-01")
        done.status = .done
        let cancelled = task("Cancelled")
        cancelled.status = .cancelled

        let rails = CalendarBoardPlannerSupport.railTasks(from: [done, cancelled], todayKey: todayKey)

        #expect(rails.isEmpty)
    }

    // MARK: - Drop target → attribute

    @Test func droppingFromUnscheduledOntoADaySetsTheDoDate() {
        let backlog = task("Backlog")
        let action = CalendarBoardPlannerSupport.dropAction(for: .day("2026-06-18"))

        #expect(action == .setDoDate("2026-06-18"))
        CalendarBoardPlannerSupport.apply(action!, to: backlog)

        #expect(backlog.scheduledDate == "2026-06-18")
        #expect(CalendarBoardPlannerSupport.rail(for: backlog, todayKey: todayKey) == nil)
    }

    /// The regression this whole drop path exists to avoid: bucketing on the do date but clearing
    /// only *one* of the two scheduling fields leaves the card stranded on the timeline.
    @Test func droppingFromADayOntoUnscheduledClearsBothDoDateAndStartMinute() {
        let scheduled = task("Scheduled", doDate: "2026-06-18", startMin: 9 * 60)
        let action = CalendarBoardPlannerSupport.dropAction(for: .rail(.unscheduled))

        #expect(action == .clearDoDate)
        CalendarBoardPlannerSupport.apply(action!, to: scheduled)

        #expect(scheduled.scheduledDate.isEmpty)
        #expect(scheduled.scheduledStartMin == -1)
        #expect(CalendarBoardPlannerSupport.rail(for: scheduled, todayKey: todayKey) == .unscheduled)
    }

    @Test func droppingOntoUnscheduledLeavesTheDueDateAlone() {
        let scheduled = task("Scheduled", doDate: "2026-06-18", dueDate: "2026-06-20", startMin: 9 * 60)

        CalendarBoardPlannerSupport.apply(.clearDoDate, to: scheduled)

        #expect(scheduled.dueDate == "2026-06-20")
    }

    @Test func overdueRailRefusesDropsInsteadOfNoOping() {
        #expect(CalendarBoardPlannerSupport.dropAction(for: .rail(.overdue)) == nil)
        #expect(!CalendarBoardRail.overdue.acceptsDrops)
        #expect(CalendarBoardRail.unscheduled.acceptsDrops)
    }

    @Test func aDayTargetWithNoDateKeyRefusesTheDrop() {
        #expect(CalendarBoardPlannerSupport.dropAction(for: .day("")) == nil)
    }

    // MARK: - Summary

    @Test func summaryCountsMatchTheRails() {
        let all = [
            task("Overdue 1", doDate: "2026-06-01"),
            task("Overdue 2", doDate: "2026-06-14"),
            task("Backlog 1"),
            task("Backlog 2", dueDate: "2026-06-20"),
            task("Backlog 3"),
            task("Today", doDate: todayKey)
        ]

        let rails = CalendarBoardPlannerSupport.railTasks(from: all, todayKey: todayKey)

        #expect(rails[.overdue]?.count == 2)
        #expect(rails[.unscheduled]?.count == 3)
        #expect(CalendarBoardPlannerSupport.railSummaryLine(rails) == "3 unscheduled · 2 overdue")
    }

    @Test func summaryReadsZeroWhenBothRailsAreEmpty() {
        let rails = CalendarBoardPlannerSupport.railTasks(from: [task("Today", doDate: todayKey)], todayKey: todayKey)

        #expect(CalendarBoardPlannerSupport.railSummaryLine(rails) == "0 unscheduled · 0 overdue")
    }

    // MARK: - Ordering

    @Test func railCardsOrderByDateAnchorThenTimeThenPriority() {
        let laterAnchor = task("Later anchor", dueDate: "2026-07-01")
        let earlyTimed = task("Early timed", dueDate: "2026-06-20", startMin: 9 * 60)
        let earlyUntimedHigh = task("Early untimed high", dueDate: "2026-06-20")
        earlyUntimedHigh.priority = .high
        let earlyUntimedLow = task("Early untimed low", dueDate: "2026-06-20")
        earlyUntimedLow.priority = .low

        let rails = CalendarBoardPlannerSupport.railTasks(
            from: [laterAnchor, earlyUntimedLow, earlyUntimedHigh, earlyTimed],
            todayKey: todayKey
        )

        #expect(rails[.unscheduled]?.map(\.title) == [
            "Early timed",
            "Early untimed high",
            "Early untimed low",
            "Later anchor"
        ])
    }

    @Test func undatedRailCardsSortAfterDatedOnes() {
        let undated = task("Undated")
        let dated = task("Dated", dueDate: "2026-06-20")

        let rails = CalendarBoardPlannerSupport.railTasks(from: [undated, dated], todayKey: todayKey)

        #expect(rails[.unscheduled]?.map(\.title) == ["Dated", "Undated"])
    }

    // MARK: - Day-column window

    @Test func dayColumnWindowNeverOpensBeforeToday() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let pastAnchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let start = CalendarBoardPlannerSupport.plannerWindowStart(
            for: pastAnchor,
            notBefore: today,
            calendar: calendar
        )

        #expect(start == today)
    }

    @Test func aFarFutureAnchorStillGetsLeadingBufferDays() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let anchor = calendar.date(byAdding: .day, value: 400, to: today)!

        let start = CalendarBoardPlannerSupport.plannerWindowStart(
            for: anchor,
            notBefore: today,
            calendar: calendar
        )

        #expect(
            CalendarBoardPlannerSupport.dayIndex(
                for: anchor,
                bufferStart: start,
                calendar: calendar,
                renderDays: CalendarBoardPlannerSupport.plannerRenderDayCount
            ) == CalendarBoardPlannerSupport.plannerLeadingDayCount
        )
    }

    @Test func boardDatesClampForwardToToday() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let past = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let future = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        #expect(CalendarBoardPlannerSupport.clampedBoardDate(past, notBefore: today, calendar: calendar) == today)
        #expect(CalendarBoardPlannerSupport.clampedBoardDate(future, notBefore: today, calendar: calendar) == future)
    }

    /// The floor belongs to the board that has rails to compensate for it. A caller that does not
    /// ask for one — the iOS board, which has no Overdue rail — keeps the full leading buffer and
    /// stays scrollable into the past.
    @Test func theTodayForwardFloorIsOptInNotDefaultedOn() {
        let calendar = Calendar(identifier: .gregorian)
        let pastAnchor = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let expected = calendar.date(
            byAdding: .day,
            value: -CalendarBoardPlannerSupport.plannerLeadingDayCount,
            to: pastAnchor
        )!

        #expect(CalendarBoardPlannerSupport.plannerWindowStart(for: pastAnchor, calendar: calendar) == expected)
    }

    // MARK: - Recentering

    /// A floored window *rests* at day index 0, permanently inside `shouldRecenter`'s leading band
    /// for the first six weeks. Recentering there would rebuild the window to the same start and
    /// re-scroll the board mid-gesture on nearly every column crossing — so it must not fire.
    @Test func aFlooredWindowDoesNotRecenterAtItsLeadingEdge() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let windowStart = CalendarBoardPlannerSupport.plannerWindowStart(
            for: today,
            notBefore: today,
            calendar: calendar
        )
        #expect(windowStart == today)

        for dayIndex in [0, 3, CalendarBoardPlannerSupport.plannerRecenterThreshold] {
            let visibleDate = CalendarBoardPlannerSupport.date(
                at: dayIndex,
                bufferStart: windowStart,
                calendar: calendar
            )
            // Proximity alone says yes; the window has nowhere to move, so the answer is no.
            #expect(CalendarBoardPlannerSupport.shouldRecenter(dayIndex: dayIndex))
            #expect(CalendarBoardPlannerSupport.recenteredWindowStart(
                visibleDayIndex: dayIndex,
                visibleDate: visibleDate,
                currentWindowStart: windowStart,
                notBefore: today,
                calendar: calendar
            ) == nil)
        }
    }

    @Test func aFlooredWindowStillRecentersAtItsTrailingEdge() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let renderDays = CalendarBoardPlannerSupport.plannerRenderDayCount
        let windowStart = CalendarBoardPlannerSupport.plannerWindowStart(
            for: today,
            notBefore: today,
            calendar: calendar
        )
        let dayIndex = renderDays - 1
        let visibleDate = CalendarBoardPlannerSupport.date(
            at: dayIndex,
            bufferStart: windowStart,
            calendar: calendar
        )

        let recentered = CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: windowStart,
            notBefore: today,
            calendar: calendar
        )

        #expect(recentered == calendar.date(
            byAdding: .day,
            value: -CalendarBoardPlannerSupport.plannerLeadingDayCount,
            to: visibleDate
        ))
    }

    /// An unfloored window (the iOS board) rests in the *middle* of its render range, so reaching
    /// its leading edge really does mean there is more past to render.
    @Test func anUnflooredWindowStillRecentersAtItsLeadingEdge() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let windowStart = CalendarBoardPlannerSupport.plannerWindowStart(for: anchor, calendar: calendar)
        let dayIndex = 5
        let visibleDate = CalendarBoardPlannerSupport.date(
            at: dayIndex,
            bufferStart: windowStart,
            calendar: calendar
        )

        let recentered = CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: windowStart,
            calendar: calendar
        )

        #expect(recentered == calendar.date(
            byAdding: .day,
            value: -CalendarBoardPlannerSupport.plannerLeadingDayCount,
            to: visibleDate
        ))
    }

    @Test func aWindowAwayFromBothEdgesIsLeftAlone() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let dayIndex = CalendarBoardPlannerSupport.plannerLeadingDayCount
        let visibleDate = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: today, calendar: calendar)

        #expect(CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: today,
            notBefore: today,
            calendar: calendar
        ) == nil)
    }

    // MARK: - Remembered timeline day

    /// The remembered day belongs to the timeline, which browses freely into the past. Opening the
    /// Board clamps it forward to today; writing that clamp back would erase the remembered day
    /// just for having glanced at the Board.
    @Test func sittingOnTheClampedRememberedDayWritesNothingBack() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(CalendarBoardPlannerSupport.rememberedDateKeyWriteBack(
            boardDate: today,
            rememberedKey: "2026-05-01",
            notBefore: today,
            calendar: calendar
        ) == nil)
    }

    @Test func movingTheBoardOffItsOpeningColumnPersistsTheNewDay() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let moved = calendar.date(byAdding: .day, value: 7, to: today)!

        #expect(CalendarBoardPlannerSupport.rememberedDateKeyWriteBack(
            boardDate: moved,
            rememberedKey: "2026-05-01",
            notBefore: today,
            calendar: calendar
        ) == "2026-06-22")
    }

    @Test func anUnsetRememberedDayTakesTheBoardsPositionDirectly() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(CalendarBoardPlannerSupport.rememberedDateKeyWriteBack(
            boardDate: today,
            rememberedKey: "",
            notBefore: today,
            calendar: calendar
        ) == "2026-06-15")
    }

    // MARK: - Window navigation

    /// With the columns floored at today, stepping back from the first week clamps straight back to
    /// where it started, so the arrow that would do it is disabled rather than dead.
    @Test func theWindowCannotStepBackOutOfTheFirstWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(!CalendarBoardPlannerSupport.canMoveWindow(from: today, by: -1, notBefore: today, calendar: calendar))
        #expect(CalendarBoardPlannerSupport.canMoveWindow(from: today, by: 1, notBefore: today, calendar: calendar))
    }

    @Test func theWindowCanStepBackFromALaterWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let laterWeek = calendar.date(byAdding: .day, value: 14, to: today)!

        #expect(CalendarBoardPlannerSupport.canMoveWindow(from: laterWeek, by: -1, notBefore: today, calendar: calendar))
    }

    // MARK: - Adding

    /// A day column supplies the do date, so it can insert a card inline. The Unscheduled rail
    /// cannot — an inline insert there leaves an untitled, unplaced card in the backlog — so it
    /// opens the create sheet, as the Planning page's add row did.
    @Test func theUnscheduledRailAddOpensTheCreateSheetRatherThanInsertingACard() {
        #expect(CalendarBoardPlannerSupport.addAction(for: .rail(.unscheduled)) == .presentCreateSheet)
    }

    @Test func aDayColumnAddInsertsInlineOnItsOwnDate() {
        #expect(CalendarBoardPlannerSupport.addAction(for: .day("2026-06-18")) == .insertInline(dateKey: "2026-06-18"))
        #expect(CalendarBoardPlannerSupport.addAction(for: .day("")) == nil)
    }

    @Test func theOverdueRailHasNoAddAffordance() {
        #expect(CalendarBoardPlannerSupport.addAction(for: .rail(.overdue)) == nil)
    }
}
