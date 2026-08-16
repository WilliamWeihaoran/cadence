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
    /// true range. With the column painting the whole day, an event anywhere in it is drawn where
    /// it happens — nothing is trimmed except a range that leaves the day altogether.
    @Test func theDrawnRangeStaysInsideTheHoursTheColumnPaints() {
        let lateNight = CadenceScheduleSupport.timelineVisibleRange(start: 23 * 60, end: 24 * 60)
        #expect(lateNight == (23 * 60, 24 * 60))

        let earlyMorning = CadenceScheduleSupport.timelineVisibleRange(start: 0, end: 5 * 60)
        #expect(earlyMorning == (0, 5 * 60))

        let midday = CadenceScheduleSupport.timelineVisibleRange(start: 9 * 60, end: 10 * 60)
        #expect(midday == (9 * 60, 10 * 60))

        // Only a range that runs off the end of the day is trimmed.
        let overrun = CadenceScheduleSupport.timelineVisibleRange(start: 23 * 60 + 30, end: 25 * 60)
        #expect(overrun.end == CadenceScheduleSupport.calendarEndHour * 60)
    }

    // MARK: - The hours every timeline draws

    /// The complaint: Today's timeline showed 06:00–22:59, so a third of the day did not exist on
    /// it. Every day canvas in the app draws all 24 hours, and there is exactly one place that
    /// says so — macOS's two globals are aliases of it. Three independent spellings is how the
    /// iOS one drifted to `6..<23` while macOS stayed on the whole day.
    @Test func everyTimelineOnEveryPlatformDrawsTheSameHours() {
        #expect(CadenceScheduleSupport.calendarStartHour == 0)
        #expect(CadenceScheduleSupport.calendarEndHour == 24)
        #expect(CadenceScheduleSupport.calendarHourCount == 24)
        #expect(Array(CadenceScheduleSupport.calendarHours) == Array(0...23))

        #expect(schedStartHour == CadenceScheduleSupport.calendarStartHour)
        #expect(schedEndHour == CadenceScheduleSupport.calendarEndHour)
        #expect(calStartHour == CadenceScheduleSupport.calendarStartHour)
        #expect(calEndHour == CadenceScheduleSupport.calendarEndHour)
    }

    // MARK: - Hour rows on iPad Today

    /// The two times the window used to swallow. 05:00 was clamped up into the 06:00 row and 23:30
    /// down into the 22:00 row, each printing a time its row contradicted; before the clamp existed
    /// they matched no row at all and vanished, since "Ready to Schedule" needs
    /// `scheduledStartMin == -1`. Both now land on their own hour.
    @Test func aTaskAtFiveAMOrHalfPastElevenLandsInItsOwnRow() {
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 5 * 60) == 5)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 23 * 60 + 30) == 23)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 0) == 0)
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
        let rows = CadenceScheduleSupport.calendarHours.map {
            CadenceScheduleSupport.tasks(inHourRow: $0, from: all)
        }

        // Every timed task lands in exactly one row, and the untimed one lands in none.
        #expect(rows.flatMap { $0 }.count == 3)
        #expect(rows[5].map(\.title) == ["Dawn run"])
        #expect(rows[23].map(\.title) == ["Wind down"])
        #expect(rows[13].map(\.title) == ["Standup"])
        #expect(rows[6].isEmpty)
        #expect(rows[22].isEmpty)
        #expect(rows.contains { $0.contains { $0.title == "Someday" } } == false)
    }

    @Test func bundlesTakeTheirOwnHourTheSameWay() {
        let early = TaskBundle(title: "Morning block", dateKey: "2026-06-19", startMin: 5 * 60, durationMinutes: 60)
        let normal = TaskBundle(title: "Deep work", dateKey: "2026-06-19", startMin: 10 * 60, durationMinutes: 60)

        #expect(CadenceScheduleSupport.bundles(inHourRow: 5, from: [early, normal]).map(\.title) == ["Morning block"])
        #expect(CadenceScheduleSupport.bundles(inHourRow: 10, from: [early, normal]).map(\.title) == ["Deep work"])
        #expect(CadenceScheduleSupport.bundles(inHourRow: 0, from: [early, normal]).isEmpty)
    }

    /// The clamp inside `timelineHourRow` no longer has a *range* to defend — every minute of the
    /// day has a row. It is kept for the other job: `startMin` is a plain stored `Int`, and a value
    /// from outside `0..<1440` must still be shown somewhere rather than dropped silently, which is
    /// the failure the function was written for.
    @Test func aGarbageMinuteIsStillShownRatherThanDropped() {
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: -600) == 0)
        #expect(CadenceScheduleSupport.timelineHourRow(forMinute: 40 * 60) == 23)

        let corrupt = TaskBundle(title: "Impossible", dateKey: "2026-06-19", startMin: 99 * 60, durationMinutes: 60)
        let rows = CadenceScheduleSupport.calendarHours.map {
            CadenceScheduleSupport.bundles(inHourRow: $0, from: [corrupt])
        }
        #expect(rows.flatMap { $0 }.count == 1)
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

    /// The canvas starts at `calendarStartHour` and a scroll view opens at the top of its content,
    /// so a timeline left to itself opens at its first hour whatever the time of day. That was 6 AM
    /// and is now midnight, which is strictly worse — this rule is what keeps a 24-hour grid from
    /// being a regression.
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

    /// Early morning used to be clamped up to 06:00 because the canvas did not draw it. It does
    /// now, so 3 AM opens at 2 AM — the same "one hour of context" every other time of day gets.
    /// Only midnight itself has no hour above it to show.
    @Test func earlyMorningOpensWhereItActuallyIs() throws {
        let threeAM = try date("2026-08-15", hour: 3)
        let midnight = try date("2026-08-15", hour: 0)
        let elevenPM = try date("2026-08-15", hour: 23)

        #expect(CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: threeAM, calendar: calendar) == 2)
        #expect(
            CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: midnight, calendar: calendar)
                == CadenceScheduleSupport.calendarStartHour
        )
        #expect(CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: elevenPM, calendar: calendar) == 22)
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

    /// A work day starting at 04:00 is a row the canvas draws now, so it is honoured rather than
    /// pushed forward to whatever the canvas happened to begin at. The clamp is still the guard
    /// against a nonsense stored value.
    @Test func anEarlyWorkHoursStartIsHonouredNotPushedForward() throws {
        let twoPM = try date("2026-08-15", hour: 14)

        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: false,
                now: twoPM,
                workHoursStartMinute: 4 * 60,
                calendar: calendar
            ) == 4
        )
        #expect(
            CadenceScheduleSupport.initialTimelineHour(
                showsToday: false,
                now: twoPM,
                workHoursStartMinute: -90,
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
        #expect(offset == CGFloat(101 + 13 * 58))
        #expect(
            CadenceScheduleSupport.timelineScrollOffset(forHour: 0, hourHeight: 58, topInset: 101)
                == CGFloat(101)
        )
    }

    @Test func theScrollOffsetNeverGoesNegative() {
        #expect(CadenceScheduleSupport.timelineScrollOffset(forHour: 0, hourHeight: 58) == CGFloat(0))
    }
}
