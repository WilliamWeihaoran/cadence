import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The day-column arithmetic behind the iOS calendar timeline and the iPad Today schedule, plus
/// the rules that decide whether an Apple Calendar event can be edited at all. All three were
/// written inline in `#if os(iOS)` views, where nothing could assert them.
@MainActor
struct CalendarTimelineRangeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func date(_ key: String, hour: Int, minute: Int = 0) throws -> Date {
        let day = try #require(DateFormatters.date(from: key, in: calendar))
        return try #require(calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day))
    }

    // MARK: - Events that cross midnight

    /// The timeline read only the hour/minute of each end, so a 23:00 → 00:00 event produced
    /// `end < start` and fell through to the 15-minute floor. An hour-long event drew as a
    /// quarter-hour sliver.
    @Test func anEventEndingAtMidnightKeepsItsDuration() throws {
        let start = try date("2026-06-19", hour: 23)
        let end = try date("2026-06-20", hour: 0)
        let day = try #require(DateFormatters.date(from: "2026-06-19", in: calendar))

        let range = CadenceScheduleSupport.minuteRange(from: start, to: end, on: day, calendar: calendar)

        #expect(range.start == 23 * 60)
        #expect(range.end == 24 * 60)
        #expect(range.end - range.start == 60)
    }

    /// Every column of a multi-day timed event drew the same sliver. Each column now shows the
    /// part of the event that belongs to it, and a day fully inside the event spans it.
    @Test func aMultiDayEventFillsTheColumnsItCovers() throws {
        let start = try date("2026-06-18", hour: 22)
        let end = try date("2026-06-20", hour: 10)

        let day1 = try #require(DateFormatters.date(from: "2026-06-18", in: calendar))
        let day2 = try #require(DateFormatters.date(from: "2026-06-19", in: calendar))
        let day3 = try #require(DateFormatters.date(from: "2026-06-20", in: calendar))

        let first = CadenceScheduleSupport.minuteRange(from: start, to: end, on: day1, calendar: calendar)
        let middle = CadenceScheduleSupport.minuteRange(from: start, to: end, on: day2, calendar: calendar)
        let last = CadenceScheduleSupport.minuteRange(from: start, to: end, on: day3, calendar: calendar)

        #expect(first == (22 * 60, 24 * 60))
        #expect(middle == (0, 24 * 60))
        #expect(last == (0, 10 * 60))
    }

    @Test func anOrdinaryEventIsUnchangedAndNeverShorterThanTheFloor() throws {
        let day = try #require(DateFormatters.date(from: "2026-06-19", in: calendar))

        let ordinary = CadenceScheduleSupport.minuteRange(
            from: try date("2026-06-19", hour: 9, minute: 30),
            to: try date("2026-06-19", hour: 10, minute: 45),
            on: day,
            calendar: calendar
        )
        #expect(ordinary == (9 * 60 + 30, 10 * 60 + 45))

        // A zero-length event still gets a drawable block.
        let instant = try date("2026-06-19", hour: 14)
        let zero = CadenceScheduleSupport.minuteRange(from: instant, to: instant, on: day, calendar: calendar)
        #expect(zero == (14 * 60, 14 * 60 + 15))
    }

    /// The drawn geometry is clamped to the hours the column actually paints; the label keeps the
    /// true range.
    @Test func theDrawnRangeStaysInsideTheHoursTheColumnPaints() {
        let lateNight = CadenceScheduleSupport.timelineVisibleRange(start: 23 * 60, end: 24 * 60)
        #expect(lateNight.start <= CadenceScheduleSupport.calendarEndHour * 60 - 15)
        #expect(lateNight.end <= CadenceScheduleSupport.calendarEndHour * 60)

        let earlyMorning = CadenceScheduleSupport.timelineVisibleRange(start: 0, end: 5 * 60)
        #expect(earlyMorning.start == CadenceScheduleSupport.calendarStartHour * 60)
        #expect(earlyMorning.end > earlyMorning.start)

        let midday = CadenceScheduleSupport.timelineVisibleRange(start: 9 * 60, end: 10 * 60)
        #expect(midday == (9 * 60, 10 * 60))
    }

    // MARK: - Hour rows on iPad Today

    /// The Timeline pane draws `06:00..<23:00` and matched `startMin / 60 == hour`, so a task set
    /// to 05:00 — which the task detail's picker happily offers — appeared in no hour row, and it
    /// is not in "Ready to Schedule" either (that list needs `scheduledStartMin == -1`). It
    /// vanished from the pane.
    @Test func aTaskTimedOutsideTheDrawnHoursStillLandsInARow() {
        let startHour = CadenceScheduleSupport.calendarStartHour
        let endHour = CadenceScheduleSupport.calendarEndHour

        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 5 * 60) == startHour)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 0) == startHour)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 23 * 60 + 30) == endHour - 1)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 13 * 60 + 45) == 13)

        let dawn = AppTask(title: "Dawn run")
        dawn.scheduledStartMin = 5 * 60
        let midnight = AppTask(title: "Wind down")
        midnight.scheduledStartMin = 23 * 60 + 30
        let midday = AppTask(title: "Standup")
        midday.scheduledStartMin = 13 * 60
        let untimed = AppTask(title: "Someday")
        untimed.scheduledStartMin = -1

        let all = [dawn, midnight, midday, untimed]
        let rows = (startHour..<endHour).map { CadenceScheduleSupport.tasks(inHourRow: $0, from: all) }

        // Every timed task lands in exactly one row, and the untimed one lands in none.
        #expect(rows.flatMap { $0 }.count == 3)
        #expect(rows.first?.map(\.title) == ["Dawn run"])
        #expect(rows.last?.map(\.title) == ["Wind down"])
        #expect(rows[13 - startHour].map(\.title) == ["Standup"])
        #expect(rows.contains { $0.contains { $0.title == "Someday" } } == false)
    }

    @Test func bundlesClampIntoTheDrawnRowsTheSameWay() {
        let early = TaskBundle(title: "Morning block", dateKey: "2026-06-19", startMin: 5 * 60, durationMinutes: 60)
        let normal = TaskBundle(title: "Deep work", dateKey: "2026-06-19", startMin: 10 * 60, durationMinutes: 60)

        let firstRow = CadenceScheduleSupport.bundles(inHourRow: CadenceScheduleSupport.calendarStartHour, from: [early, normal])
        #expect(firstRow.map(\.title) == ["Morning block"])
        #expect(CadenceScheduleSupport.bundles(inHourRow: 10, from: [early, normal]).map(\.title) == ["Deep work"])
    }

    // MARK: - Read-only calendars

    /// The editor rewrote its calendar selection to the first *writable* calendar on appear, so a
    /// Birthdays event claimed to live in "Personal" — and then offered a Save that EventKit
    /// refused.
    @Test func aReadOnlyEventKeepsItsOwnCalendarInTheSheet() {
        let writable = ["personal", "work"]

        #expect(
            CadenceCalendarEventEditingSupport.resolvedCalendarID(
                eventCalendarID: "birthdays",
                isEventEditable: false,
                writableCalendarIDs: writable
            ) == "birthdays"
        )

        // A writable event keeps its own calendar when it is selectable...
        #expect(
            CadenceCalendarEventEditingSupport.resolvedCalendarID(
                eventCalendarID: "work",
                isEventEditable: true,
                writableCalendarIDs: writable
            ) == "work"
        )
        // ...and falls back only when it is not, so the picker is never empty.
        #expect(
            CadenceCalendarEventEditingSupport.resolvedCalendarID(
                eventCalendarID: "hidden",
                isEventEditable: true,
                writableCalendarIDs: writable
            ) == "personal"
        )
        #expect(
            CadenceCalendarEventEditingSupport.resolvedCalendarID(
                eventCalendarID: "hidden",
                isEventEditable: true,
                writableCalendarIDs: []
            ) == ""
        )
    }

    /// Save was enabled on an event that could not be saved: tapping it threw inside EventKit,
    /// returned false, and left the sheet open with nothing said.
    @Test func saveIsImpossibleOnAReadOnlyEventHoweverCompleteTheFormIs() {
        let writable = ["personal"]

        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "Someone's birthday",
                isEventEditable: false,
                selectedCalendarID: "personal",
                writableCalendarIDs: writable
            ) == false
        )
        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "Team sync",
                isEventEditable: true,
                selectedCalendarID: "personal",
                writableCalendarIDs: writable
            ) == true
        )
        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "   ",
                isEventEditable: true,
                selectedCalendarID: "personal",
                writableCalendarIDs: writable
            ) == false
        )
        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "Team sync",
                isEventEditable: true,
                selectedCalendarID: "birthdays",
                writableCalendarIDs: writable
            ) == false
        )
    }

    @Test func theReadOnlyNoticeNamesTheCalendarWhenItCan() {
        #expect(CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: "Birthdays").hasPrefix("Birthdays"))
        #expect(CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: "  ").contains("read-only calendar"))
    }

    // MARK: - Where a timeline opens

    /// The complaint: Week opened at 6 AM whatever the time of day, because the canvas starts at
    /// `calendarStartHour` and a scroll view opens at the top of its content. Open it at 2pm and the
    /// hours you came for are below the fold.
    @Test func aSpanContainingTodayOpensNearTheCurrentHour() throws {
        let twoPM = try date("2026-08-15", hour: 14)

        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: true,
                now: twoPM,
                calendar: calendar
            ) == 13
        )
    }

    /// The hour just gone stays on screen, so the timeline opens with context above "now" rather
    /// than with it pinned to the very top edge.
    @Test func todayKeepsTheHourJustGoneInView() throws {
        let nineAM = try date("2026-08-15", hour: 9)
        let hour = CadenceScheduleSupport.initialTimelineHour(
            showsToday: true,
            now: nineAM,
            calendar: calendar
        )

        #expect(hour == 8)
        #expect(hour < 9)
    }

    /// Early morning and late night both fall outside the drawn window; clamping keeps the
    /// placement inside the canvas instead of asking for an offset that does not exist.
    @Test func todayClampsToTheHoursTheCanvasDraws() throws {
        let threeAM = try date("2026-08-15", hour: 3)
        let elevenPM = try date("2026-08-15", hour: 23)

        #expect(
            CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: threeAM, calendar: calendar)
                == CadenceScheduleSupport.calendarStartHour
        )
        #expect(
            CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: elevenPM, calendar: calendar)
                == CadenceScheduleSupport.calendarEndHour - 1
        )
    }

    /// A week that is not this week has no "now" to honour. The sensible default is the user's own
    /// work-hours start — the window the amber band on each column is already drawn from — rather
    /// than a second hardcoded hour.
    @Test func aSpanWithoutTodayOpensAtTheWorkHoursStart() throws {
        let twoPM = try date("2026-08-15", hour: 14)

        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: false,
                now: twoPM,
                workHoursStartMinute: 10 * 60 + 30,
                calendar: calendar
            ) == 10
        )
        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: false,
                now: twoPM,
                calendar: calendar
            ) == CalendarWorkHoursPreferences.defaultStartMinute / 60
        )
    }

    /// A work day starting before the canvas does still has to land on a row the canvas draws.
    @Test func anEarlyWorkHoursStartClampsToTheFirstDrawnHour() throws {
        let twoPM = try date("2026-08-15", hour: 14)

        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: false,
                now: twoPM,
                workHoursStartMinute: 4 * 60,
                calendar: calendar
            ) == CadenceScheduleSupport.calendarStartHour
        )
    }

    /// The offset has to clear the day-header band the canvas scrolls past before its first hour
    /// line, or every hour lands one header too high and the rule reads as being an hour out.
    @Test func theScrollOffsetClearsTheDayHeaderBand() {
        let offset = CadenceScheduleSupport.timelineScrollOffset(
            forHour: 13,
            hourHeight: 58,
            topInset: 101
        )

        // Spelled as a `CGFloat`: `#expect` records the untyped literal expression as an `Int`, so
        // an integer right-hand side compares unequal to a `CGFloat` of the same value.
        #expect(offset == CGFloat(101 + 7 * 58))
        #expect(
            CadenceScheduleSupport.timelineScrollOffset(forHour: 6, hourHeight: 58, topInset: 101)
                == CGFloat(101)
        )
    }

    @Test func theScrollOffsetNeverGoesNegative() {
        #expect(CadenceScheduleSupport.timelineScrollOffset(forHour: 0, hourHeight: 58) == CGFloat(0))
    }
}
