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

    // MARK: - What a rejected write says (T-324)

    /// The two sentences an iOS event sheet shows when EventKit refuses. Held in one place so the
    /// quick-create sheet could adopt the edit sheet's wording rather than invent a third.
    @Test func theWriteFailureNoticesNameTheOperationAndTheApp() {
        #expect(CadenceCalendarEventEditingSupport.saveFailureNotice == "Couldn't save this event to Apple Calendar.")
        #expect(CadenceCalendarEventEditingSupport.deleteFailureNotice == "Couldn't delete this event from Apple Calendar.")
        #expect(
            CadenceCalendarEventEditingSupport.saveFailureNotice
                != CadenceCalendarEventEditingSupport.deleteFailureNotice
        )
    }

    /// `iOSCalendarQuickCreateSheet.createEvent()` is a private method on a SwiftUI view in an
    /// `#if os(iOS)` file, so this target can neither call it nor compile it. The scan is scoped
    /// to that **function body**.
    ///
    /// What it pins is the shape of the bug rather than a spelling: `createEvent()` used to leave
    /// two paths that returned without a word — an unparseable date key, and the `false` that
    /// missing access, no writable calendar, a bad range and a throwing save all collapse into.
    /// A bare `else { return }` anywhere in this body is that bug back.
    @Test func theQuickCreateSheetHasNoSilentEventFailurePath() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(raw.count > 400, "iOSCalendarQuickCreateSheet.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "createEvent", in: stripped),
            "could not find createEvent()"
        )
        #expect(body.contains("calendarManager.createEvent("), "createEvent() body looks wrong")
        #expect(
            body.contains("actionError = CadenceCalendarEventEditingSupport.saveFailureNotice"),
            "createEvent() no longer reports a rejected write"
        )
        #expect(
            CadenceSourceScan.matchCount(silentReturnPattern, in: body) == 0,
            "createEvent() still has a failure path that returns without saying anything"
        )
    }

    /// Both iOS event sheets read the shared notices, so neither can drift into wording of its own.
    @Test func bothIOSEventSheetsReadTheSharedWriteFailureNotices() throws {
        for relativePath in [
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift"
        ] {
            let stripped = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(relativePath))
            #expect(
                stripped.contains("CadenceCalendarEventEditingSupport.saveFailureNotice"),
                "\(relativePath) does not use the shared save-failure notice"
            )
            #expect(
                CadenceSourceScan.matchCount(#""Couldn.t save this event"#, in: stripped) == 0,
                "\(relativePath) spells the save-failure notice itself"
            )
        }
    }

    /// The needles above match what they hunt and miss what they protect.
    @Test func theSilentReturnNeedleMatchesTheOldSpellingAndNotTheNew() {
        #expect(CadenceSourceScan.matchCount(silentReturnPattern, in: "        ) else { return }") == 1)
        #expect(CadenceSourceScan.matchCount(silentReturnPattern, in: "else {\n            return\n        }") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                silentReturnPattern,
                in: "else {\n    actionError = CadenceCalendarEventEditingSupport.saveFailureNotice\n    return\n}"
            ) == 0
        )
        #expect(CadenceSourceScan.matchCount(#""Couldn.t save this event"#, in: "\"Couldn't save this event to Apple Calendar.\"") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #""Couldn.t save this event"#,
                in: "CadenceCalendarEventEditingSupport.saveFailureNotice"
            ) == 0
        )
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

    // MARK: - The hour ladder both platforms draw (T-619 → T-1129)

    /// **Every third hour is a rung; the other sixteen are texture — and the sixteen are the half
    /// the assertion has to exercise.**
    ///
    /// This is the check the standing failure mode is aimed at. "The rung exists" is true of a
    /// ladder that draws *every* line heavy, of one that emphasises every second hour, and of one
    /// whose two branches hand back the same number — so the population is walked whole, both
    /// halves are named, and the weight each half resolves to is asserted rather than assumed. A
    /// uniformly-heavy ladder has `emphasised.count == 25` here; a flat one 0; a `% 2` cadence 13;
    /// a `% 4` cadence 7.
    ///
    /// The hours walked are the ones a canvas actually rules: `calendarStartHour` through
    /// `calendarEndHour` **inclusive**, because the iOS grid draws a closing line under the last
    /// hour and the Mac's `ForEach` stops one short of it. 24 is a rung either way.
    @Test func theHourLadderEmphasisesEveryThirdHourAndNothingElse() {
        let hours = Array(CadenceScheduleSupport.calendarStartHour...CadenceScheduleSupport.calendarEndHour)
        #expect(hours.count == 25)

        let emphasised = hours.filter { CadenceCalendarHourLadderMetrics.isEmphasised(hour: $0) }
        let ordinary = hours.filter { !CadenceCalendarHourLadderMetrics.isEmphasised(hour: $0) }

        #expect(emphasised == [0, 3, 6, 9, 12, 15, 18, 21, 24])
        #expect(ordinary.count == 16)
        #expect(ordinary.allSatisfy { $0 % 3 != 0 })
        #expect(emphasised.count + ordinary.count == hours.count)

        // Both halves resolve to their own weight. Without this an `isEmphasised` that answered
        // correctly would still pass while every line was drawn at one opacity.
        for hour in emphasised {
            #expect(CadenceCalendarHourLadderMetrics.ruleOpacity(hour: hour) == 0.46)
            #expect(CadenceCalendarHourLadderMetrics.labelOpacity(hour: hour) == 0.9)
        }
        for hour in ordinary {
            #expect(CadenceCalendarHourLadderMetrics.ruleOpacity(hour: hour) == 0.20)
            #expect(CadenceCalendarHourLadderMetrics.labelOpacity(hour: hour) == 0.45)
        }

        // The gap is the effect. A pair collapsed onto one value satisfies every assertion above
        // about *which* hours are rungs and none of these.
        #expect(CadenceCalendarHourLadderMetrics.emphasisedRuleOpacity > CadenceCalendarHourLadderMetrics.ordinaryRuleOpacity)
        #expect(CadenceCalendarHourLadderMetrics.emphasisedLabelOpacity > CadenceCalendarHourLadderMetrics.ordinaryLabelOpacity)
        let ruleStep = CadenceCalendarHourLadderMetrics.emphasisedRuleOpacity
            / CadenceCalendarHourLadderMetrics.ordinaryRuleOpacity
        #expect(abs(ruleStep - 2.3) < 0.0005)
        #expect(CadenceCalendarHourLadderMetrics.emphasisInterval == 3)
    }

    /// **The Mac's canvas draws the rung, and the flat ladder it replaces is unspellable here.**
    ///
    /// [[T-1129]]: the repository owner chose *"bring iOS's every-third-hour rung to the Mac"* over
    /// leaving the Mac flat and over dropping the rung on iOS. Before that the loop discarded its
    /// hour (`ForEach(…) { _ in }`) and every rule was one weight — which is the shape a row has to
    /// have to be flat, because a row that cannot see which hour it is cannot draw a rung. So the
    /// binding of the hour is asserted, and so is the fact that the weight is a *function of it*:
    /// naming either raw weight inside this view would be a call site that had already picked one,
    /// which is a uniformly-heavy ladder by another spelling.
    @Test func theMacsTimedCanvasDrawsARungRatherThanOneWeightAtEveryHour() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDayCanvasSupportViews.swift")
        let mac = CadenceSourceScan.strippingComments(raw)
        #expect(mac != raw)
        #expect(mac.count == raw.count)

        let ladder = try #require(
            CadenceSourceScan.declarationBody("struct TimelineHourGridLines: View", in: mac),
            "could not find TimelineHourGridLines"
        )

        #expect(ladder.contains("ForEach(metrics.startHour..<metrics.endHour, id: \\.self) { hour in"))
        #expect(CadenceSourceScan.matchCount(#"ruleOpacity\(hour: hour\)"#, in: ladder) == 1)
        #expect(CadenceSourceScan.matchCount("emphasisedRuleOpacity", in: ladder) == 0)
        #expect(CadenceSourceScan.matchCount("ordinaryRuleOpacity", in: ladder) == 0)
        #expect(CadenceSourceScan.matchCount("gridRuleOpacity", in: ladder) == 0)

        // The Mac's half-hour tick stays — the decision said so, and it is a different line. Pinned
        // positionally, as it was before: which weight sits with the half-hour offset, behind the
        // `showHalfHourMarks` gate. A count survives a swap that keeps both names in the file.
        let tick = try #require(
            ladder.range(of: "CalendarVisualStyle.halfHourTickOpacity"),
            "the half-hour tick no longer reads its own weight"
        )
        let halfHour = try #require(
            ladder.range(of: "metrics.hourHeight / 2"),
            "the half-hour tick no longer offsets by half an hour"
        )
        #expect(tick.upperBound < halfHour.lowerBound)
        #expect(ladder.contains("if showHalfHourMarks {"))
    }

    /// **A rung is a rule *and* a label, so all four rails step with the canvas beside them.**
    ///
    /// Both Mac rails used to set one weight at every hour — `Theme.dim`, bare — beside a canvas
    /// that was itself flat, which was at least consistent. Half of [[T-1129]] would have left a
    /// heavy rule against a uniform column of labels, which is a worse ladder than either.
    @Test func allFourHourRailsStepTheirLabelsOnTheRungTheirRulesStepOn() throws {
        let rails = [
            ("Cadence/macOS/Views/CalendarPageComponents.swift", "struct CalTimeRailLabel: View"),
            ("Cadence/macOS/Views/SchedulePanelSupportViews.swift", "struct ScheduleTimeRailRow: View")
        ]
        for (relativePath, declaration) in rails {
            let raw = try CadenceSourceScan.sourceFile(relativePath)
            let source = CadenceSourceScan.strippingComments(raw)
            #expect(source != raw)
            #expect(source.count == raw.count)
            let rail = try #require(
                CadenceSourceScan.declarationBody(declaration, in: source),
                "could not find \(declaration)"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"Theme\.dim\.opacity\(\s*CadenceCalendarHourLadderMetrics\.labelOpacity\(hour: hour\)"#,
                    in: rail
                ) == 1,
                "\(declaration) does not weigh its label by the hour"
            )
            #expect(
                CadenceSourceScan.matchCount(#"foregroundStyle\(Theme\.dim\)"#, in: rail) == 0,
                "\(declaration) still sets one weight at every hour"
            )
        }

        // The two iOS rails, which had the cadence first and must not have been left behind by the
        // hoist. Read as text: `Cadence/iOS/` is invisible to this macOS-built target.
        for relativePath in [
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift"
        ] {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(relativePath)
            )
            #expect(source.contains("CadenceCalendarHourLadderMetrics.labelOpacity(hour: hour)"))
            #expect(CadenceSourceScan.matchCount("hourLabelMutedOpacity", in: source) == 0)
        }
    }

    /// **The cadence is spelled in exactly one file in the product tree, and it is the shared one.**
    ///
    /// This is the check [[T-596]] did not have. That defect was not a wrong number: it was the
    /// `% 3` being copied to a second surface while the weights it selects between were not, so the
    /// two surfaces agreed on *when* to shout and disagreed about *what* shouting meant. [[T-1129]]
    /// made the Mac a third such surface, which is why the ticket bound its builder to derive once
    /// in `Cadence/Shared/` rather than copy again.
    ///
    /// Swept over the whole tree rather than over a list of the files known to draw ladders — a
    /// list is what stops matching its population the moment a fifth surface appears. The assertion
    /// is an identity, not an allowlist: the single file that spells the modulo must be the
    /// declaration itself.
    @Test func theHourCadenceIsDerivedOnceAndEveryTimedSurfaceReadsIt() throws {
        let declaration = "Cadence/Shared/CadenceCalendarHourLadderMetrics.swift"
        let spellsItsOwnCadence = try CadenceScanInstrument(
            "hand-spelled hour cadence",
            fires: "hour % iOSCalendarTimelineMetrics.hourEmphasisInterval == 0 ? major : minor",
            andNotOn: "Theme.borderSubtle.opacity(CadenceCalendarHourLadderMetrics.ruleOpacity(hour: hour))",
            by: {
                CadenceSourceScan.matchCount(
                    #"\b(hour|index)\b\s*%[^\n]*==\s*0"#,
                    in: CadenceSourceScan.codeOnly($0)
                ) > 0
            }
        )

        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let offenders = try spellsItsOwnCadence.sweep(
            files,
            atLeast: 500,
            including: declaration,
            read: { try CadenceSourceScan.sourceFile($0) }
        )
        #expect(offenders == [declaration])

        // And the other half of "derive once, both read": every surface that draws an hour ladder
        // reads it. Named because they are what the decision changed, and checked against the
        // sweep above, which is what catches a sixth.
        for relativePath in [
            "Cadence/macOS/Views/TimelineDayCanvasSupportViews.swift",
            "Cadence/macOS/Views/CalendarPageComponents.swift",
            "Cadence/macOS/Views/SchedulePanelSupportViews.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift"
        ] {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(relativePath)
            )
            #expect(
                source.contains("CadenceCalendarHourLadderMetrics."),
                "\(relativePath) no longer reads the shared ladder"
            )
            #expect(
                CadenceSourceScan.matchCount("hourHeight / 2", in: source)
                    == (relativePath.hasSuffix("TimelineDayCanvasSupportViews.swift") ? 1 : 0),
                "\(relativePath) disagrees with the app about who subdivides the hour"
            )
        }
    }

    /// **What the three lines of the Mac's ladder weigh, in ink per line — opacity × line width,
    /// the proxy [[T-619]] filed its measurement in.**
    ///
    /// The ordering is the assertion: rung, then ordinary hour, then half-hour tick. It is not a
    /// preference. A tick heavier than the hour it bisects turns the grid into 30-minute rows with
    /// a light line at the top of each — which is what leaving the tick at its shipped 0.30 would
    /// have done once the ordinary hour came down to the shared weight, and is why
    /// `CalendarVisualStyle.halfHourTickOpacity` is derived from that weight rather than typed.
    ///
    /// The cross-platform figure is here too, because it is the reason the Mac can take iOS's
    /// opacities without going faint: the Mac draws them at 0.95pt against iOS's 0.5pt hairline, so
    /// every line on the Mac's ladder still carries about 1.9× the ink of the iOS line that settled
    /// the number. The widths stay per-platform — [[T-619]] measured them and declined to converge
    /// them, and this ticket did not reopen that.
    @Test func theMacLaddersThreeLinesStayInOrderAndKeepIOSsPairAtTheMacsWidth() {
        let rung = CadenceCalendarHourLadderMetrics.emphasisedRuleOpacity
            * Double(CalendarVisualStyle.hourRuleWidth)
        let hour = CadenceCalendarHourLadderMetrics.ordinaryRuleOpacity
            * Double(CalendarVisualStyle.hourRuleWidth)
        let tick = CalendarVisualStyle.halfHourTickOpacity
            * Double(CalendarVisualStyle.halfHourTickWidth)

        #expect(abs(rung - 0.437) < 0.0005)
        #expect(abs(hour - 0.190) < 0.0005)
        #expect(abs(tick - 0.142) < 0.0005)
        #expect(rung > hour)
        #expect(hour > tick)

        // The tick keeps the ratio to the hour rule it shipped at — 0.30×0.85 against 0.36×0.95.
        #expect(abs(tick / hour - 0.30 * 0.85 / (0.36 * 0.95)) < 0.0005)

        // iOS draws the same two opacities at its own hairline width, unchanged by this ticket.
        let iOSRung = CadenceCalendarHourLadderMetrics.emphasisedRuleOpacity
            * Double(iOSCalendarHairlineMetrics.width)
        let iOSHour = CadenceCalendarHourLadderMetrics.ordinaryRuleOpacity
            * Double(iOSCalendarHairlineMetrics.width)
        #expect(abs(iOSRung - 0.230) < 0.0005)
        #expect(abs(iOSHour - 0.100) < 0.0005)
        #expect(abs(rung / iOSRung - 1.9) < 0.0005)
        #expect(abs(hour / iOSHour - 1.9) < 0.0005)
    }

    /// **All four hour rails name the hour the same way, and it is the user's way ([[T-1130]]).**
    ///
    /// This test used to pin the opposite: the Mac spelled `Text("\(hour)")` — a bare 24-hour
    /// integer — at both of its rails, while both iOS rails asked `TimeFormatters`, so the same
    /// hour of the same day was called `13` on one device and `1 PM` on the other. That was the
    /// only place in the app naming a time without going through the shared formatter. The
    /// repository owner's answer to the filed question was *"Both follow the system clock"*, so the
    /// Mac rails now route through `TimeFormatters.timeString(from:)` too and, since [[T-1135]],
    /// that function reads `Locale.hourCycle` — one clock face across four rails and two platforms,
    /// chosen by the user's *24-Hour Time* setting rather than by which window they are in.
    ///
    /// A positive assertion on all four, not an absence check on two: the failure this has to catch
    /// is a fifth rail, or one of these four going back to spelling its own label, and "no file
    /// contains the old string" would pass on a file that had simply been renamed.
    @Test func everyHourRailInTheAppNamesItsHourThroughTimeFormatters() throws {
        // The two spellings the four rails have been retired from, as regexes, each checked
        // against a string that must match and one that must not before it is trusted over the
        // tree. `bareHourText` is what both Mac rails drew; `bareHourLabel` is the computed
        // property the Schedule panel wrapped its copy in.
        let bareHourText = #"Text\("\\\(hour\)"\)"#
        let bareHourLabel = #"hourLabel: String \{ "\\\(hour\)" \}"#
        #expect(CadenceSourceScan.matchCount(bareHourText, in: ##"Text("\(hour)")"##) == 1)
        #expect(CadenceSourceScan.matchCount(bareHourText, in: #"Text(TimeFormatters.timeString(from: hour * 60))"#) == 0)
        #expect(CadenceSourceScan.matchCount(bareHourLabel, in: ##"private var hourLabel: String { "\(hour)" }"##) == 1)
        #expect(
            CadenceSourceScan.matchCount(
                bareHourLabel,
                in: #"private var hourLabel: String { TimeFormatters.timeString(from: hour * 60) }"#
            ) == 0
        )

        // Each rail's declaring type, so a read that landed on the wrong file — or on a file that
        // no longer holds the rail — fails rather than passing on an absence.
        let rails: [(path: String, declaration: String)] = [
            ("Cadence/macOS/Views/CalendarPageComponents.swift", "struct CalTimeRailLabel: View {"),
            ("Cadence/macOS/Views/SchedulePanelSupportViews.swift", "struct ScheduleTimeRailRow: View {"),
            ("Cadence/iOS/iOSCalendarTimelineViews.swift", "struct iOSCalendarTimeRail: View {"),
            ("Cadence/iOS/iOSTodaySchedulePanel.swift", "struct iOSScheduleHourRow: View {")
        ]

        for rail in rails {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(rail.path)
            )
            #expect(
                source.contains(rail.declaration),
                "\(rail.path) no longer declares \(rail.declaration), so this read proves nothing"
            )
            #expect(
                source.contains("TimeFormatters.timeString(from: hour * 60)"),
                "\(rail.path) names an hour without going through TimeFormatters"
            )
            #expect(
                CadenceSourceScan.matchCount(bareHourText, in: source) == 0,
                "\(rail.path) spells a bare hour integer again"
            )
            #expect(
                CadenceSourceScan.matchCount(bareHourLabel, in: source) == 0,
                "\(rail.path) spells its own hour label again"
            )
        }

        // And the face itself, from the formatter the four of them now share. 13:00 is `1 PM` or
        // `13:00` according to the clock the locale names — the two readings that used to be a
        // difference between two devices and are now a difference between two settings.
        #expect(TimeFormatters.timeString(from: 13 * 60, locale: CadenceTestClocks.twelveHour) == "1 PM")
        #expect(TimeFormatters.timeString(from: 13 * 60, locale: CadenceTestClocks.twentyFourHour) == "13:00")
        #expect(TimeFormatters.timeString(from: 0, locale: CadenceTestClocks.twelveHour) == "12 AM")
        #expect(TimeFormatters.timeString(from: 0, locale: CadenceTestClocks.twentyFourHour) == "00:00")
    }
}

/// `else {` followed by nothing but `return` — a guard that fails and says nothing. Written with
/// `\s*` rather than a fixed shape so both the one-line `) else { return }` and the multi-line
/// form match.
private let silentReturnPattern = #"else\s*\{\s*return\b[^\n]*\s*\}?"#
