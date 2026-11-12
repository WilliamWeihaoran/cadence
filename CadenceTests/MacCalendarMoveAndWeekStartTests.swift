// `TimelineEventBlockEditGate` and `CalendarMonthGridSupport` are macOS view types, so the iOS
// test target cannot compile this file.
#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// Hands the day cache a fixed list in a fixed, deliberately unsorted order ([[T-13822]]).
private final class ReversedEventDaySource: CalendarEventDaySource {
    var isAuthorized: Bool = true
    var storeVersion: Int = 0
    var timed: [EKEvent] = []
    var allDay: [EKEvent] = []
    func fetchEvents(for date: Date) -> [EKEvent] { timed }
    func fetchAllDayEvents(for date: Date) -> [EKEvent] { allDay }
}

/// [[T-5354]], [[T-5355]], [[T-5361]]: a macOS timeline move writes only what moved and keeps a
/// single-day event inside its day; the Month grid's headings and tiling share one week start.
///
/// The rules are tested as values. That the block and the grid actually consult them is a
/// view-construction fact, pinned by source scan through `codeOnly` so prose cannot stand in.
@Suite("macOS calendar move clamp and Month week start")
@MainActor
struct MacCalendarMoveAndWeekStartTests {
    // MARK: - T-5354: a click is a click

    @Test("A move that ends on the stored start writes nothing")
    func aMoveBackToTheStoredStartWritesNothing() {
        #expect(!TimelineEventBlockEditGate.commitsMove(to: 600, from: 600))
        #expect(TimelineEventBlockEditGate.commitsMove(to: 605, from: 600))
        #expect(TimelineEventBlockEditGate.commitsMove(to: 595, from: 600))
    }

    /// [[T-17200]]: a block's own top resolves to the block's own minute at every zoom.
    ///
    /// A sideways-slipped click hands the gate `topY == yOffset(for: start)`, and a task drag that
    /// comes back to its origin hands the drop delegate the same Y. `yToMins` truncated
    /// `y / hourHeight * 60`, which in floating point lands a hair under the minute for about one
    /// (hourHeight, minute) pair in seven -- 25 at a 33.33pt hour read as 24.999..., floored to the
    /// previous 5-minute line -- so the "click is a click" gate above saw a move to 20 and wrote it.
    /// The hour heights are the ones `TimelineZoom.hourHeight` produces for a sweep of window
    /// heights, so the count is over real zoom levels, not a contrived figure.
    @Test("A block whose top is exactly at its start resolves to that start at every zoom")
    func aBlocksOwnTopResolvesToItsOwnMinute() {
        var checked = 0
        var drifted = 0
        var example = ""
        for halfPoints in stride(from: 800, through: 2_400, by: 7) {
            for level in TimelineZoom.levels {
                let hourHeight = TimelineZoom.hourHeight(viewportHeight: CGFloat(halfPoints) / 2, level: level)
                let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: hourHeight)
                for start in stride(from: 0, to: 24 * 60 - 60, by: CadenceScheduleSupport.pointerTimeGridMinutes) {
                    checked += 1
                    let top = metrics.yOffset(for: start)
                    let resolved = TimelineEventBlockEditGate.movedStartMinute(
                        topY: top,
                        durationMinutes: 60,
                        isMultiDayTimedEvent: false,
                        metrics: metrics
                    )
                    if resolved != start || TimelineEventBlockEditGate.commitsMove(to: resolved, from: start)
                        || metrics.snappedStart(fromY: top, duration: 60) != start {
                        if drifted == 0 { example = "\(start) at \(hourHeight)pt -> \(resolved)" }
                        drifted += 1
                    }
                }
            }
        }
        #expect(checked > 10_000)
        #expect(drifted == 0, "\(drifted) block tops resolved off their own minute, e.g. \(example)")
    }

    // MARK: - T-5355: a single-day event still ends by midnight

    private static let fullDay = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)

    @Test("A single-day event dropped on the last slot still ends by the end of the day")
    func aSingleDayEventStopsWhereItStillEndsByMidnight() {
        let metrics = Self.fullDay
        for duration in [30, 60, 90] {
            let start = TimelineEventBlockEditGate.movedStartMinute(
                topY: metrics.totalHeight,
                durationMinutes: duration,
                isMultiDayTimedEvent: false,
                metrics: metrics
            )
            #expect(start + duration == metrics.endHour * 60, "a \(duration)-minute event ends at \(start + duration)")
        }
        // Mid-day the clamp is inert: the snapped minute is the answer.
        #expect(
            TimelineEventBlockEditGate.movedStartMinute(
                topY: metrics.yOffset(for: 600),
                durationMinutes: 60,
                isMultiDayTimedEvent: false,
                metrics: metrics
            ) == metrics.snappedMinute(fromY: metrics.yOffset(for: 600))
        )
    }

    @Test("A multi-day segment keeps the start-only clamp")
    func aMultiDaySegmentKeepsTheStartOnlyClamp() {
        let metrics = Self.fullDay
        let start = TimelineEventBlockEditGate.movedStartMinute(
            topY: metrics.totalHeight,
            durationMinutes: 60,
            isMultiDayTimedEvent: true,
            metrics: metrics
        )
        #expect(start == metrics.snappedMinute(fromY: metrics.totalHeight))
        #expect(start > metrics.endHour * 60 - 60)
    }

    @Test("The timeline block moves through the gate and compares against the stored start")
    func theBlockMovesThroughTheGate() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift"))
        #expect(code.count > 1_000)
        #expect(
            CadenceSourceScan.matchCount(#"liveStartMin = TimelineEventBlockEditGate\.movedStartMinute\(\s*topY: value\.location\.y - dragGrabOffset,\s*durationMinutes: item\.durationMinutes,\s*isMultiDayTimedEvent: item\.isMultiDayTimedEvent"#, in: code) == 1,
            "the move gesture no longer clamps with the event's own duration"
        )
        #expect(
            CadenceSourceScan.matchCount(#"if TimelineEventBlockEditGate\.commitsMove\(to: newStart, from: item\.startMin\) \{\s*requestEventMutation\(\.move\(startMin: newStart\)\)"#, in: code) == 1,
            "a move that changed nothing is written again"
        )
        #expect(CadenceSourceScan.matchCount(#"snappedMinute\(fromY:"#, in: code) == 0)
    }

    // MARK: - T-5361: one week start for the headings and the tiling

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test("Every Month block and row opens on the calendar's first weekday, under a matching heading")
    func blocksAndHeadingsShareTheWeekStart() throws {
        let english = Self.calendar(firstWeekday: 1)
        for firstWeekday in [1, 2, 7] {
            let calendar = Self.calendar(firstWeekday: firstWeekday)
            let headings = CadenceScheduleSupport.weekdaySymbols(calendar: calendar, width: .short)
            #expect(headings.count == 7)
            for monthOffset in 0..<12 {
                let month = try #require(calendar.date(from: DateComponents(year: 2026, month: 1 + monthOffset, day: 1)))
                let blockStart = CalendarMonthGridSupport.blockFirstDay(of: month, calendar: calendar)
                #expect(calendar.component(.weekday, from: blockStart) == firstWeekday)
                #expect(calendar.component(.day, from: blockStart) <= 7)
                for row in CalendarMonthGridSupport.weeks(for: month, calendar: calendar) {
                    let first = try #require(row.first ?? nil)
                    #expect(row.count == 7)
                    #expect(calendar.component(.weekday, from: first) == firstWeekday)
                    // The heading over column 0 names the weekday the row actually starts on.
                    let weekday = calendar.component(.weekday, from: first)
                    #expect(headings[0] == english.shortWeekdaySymbols[weekday - 1])
                }
            }
        }
    }

    @Test("A Monday-first September 2026 carries six days back, not five")
    func aMondayFirstMonthCarriesFromMonday() throws {
        let monday = Self.calendar(firstWeekday: 2)
        let september = try #require(monday.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        #expect(CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: september, calendar: monday) == 6)
        let sunday = Self.calendar(firstWeekday: 1)
        #expect(CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: september, calendar: sunday) == 5)
    }

    // MARK: - T-13821: an event that ends at midnight is a one-day event

    private static func timedEvent(_ store: EKEventStore, _ title: String, start: Date, end: Date) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = false
        event.startDate = start
        event.endDate = end
        return event
    }

    @Test("A 10 PM to 12 AM event is one day long, so its move keeps the whole-event clamp")
    func anEventEndingAtMidnightIsNotMultiDay() throws {
        let calendar = Calendar.current
        let store = EKEventStore()
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 22)))
        let midnight = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let event = Self.timedEvent(store, "Late session", start: start, end: midnight)

        let item = try #require(CalendarEventItem(event: event, clippedTo: day, calendar: calendar))
        #expect(!item.isMultiDayTimedEvent)
        #expect(item.durationMinutes == 120)
        #expect(CalendarEventItem.timedSegments(from: [event], for: midnight, calendar: calendar).isEmpty)
        // So the drag the block hands the gate stops where the event still ends by midnight.
        let metrics = Self.fullDay
        let moved = TimelineEventBlockEditGate.movedStartMinute(
            topY: metrics.totalHeight,
            durationMinutes: item.durationMinutes,
            isMultiDayTimedEvent: item.isMultiDayTimedEvent,
            metrics: metrics
        )
        #expect(moved + item.durationMinutes == metrics.endHour * 60)

        // One second past midnight is the next day, and is multi-day.
        let pastMidnight = Self.timedEvent(store, "Later", start: start, end: midnight.addingTimeInterval(60))
        #expect(try #require(CalendarEventItem(event: pastMidnight, clippedTo: day, calendar: calendar)).isMultiDayTimedEvent)
        #expect(CalendarEventChipTimeSupport.isMultiDayTimedEvent(start: start, end: midnight, calendar: calendar) == false)
        #expect(CalendarEventChipTimeSupport.isMultiDayTimedEvent(start: start, end: midnight.addingTimeInterval(1), calendar: calendar))
        // A degenerate zero-length event at midnight stays on its own day.
        #expect(!CalendarEventChipTimeSupport.isMultiDayTimedEvent(start: midnight, end: midnight, calendar: calendar))
    }

    // MARK: - T-13822: one day reads in one order

    @Test("The Mac day cache hands every surface a day's events in the shared start-title-identity order")
    func theDayCacheOrdersEachDay() throws {
        let calendar = Calendar.current
        let store = EKEventStore()
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        func at(_ hour: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: hour)))
        }
        let source = ReversedEventDaySource()
        source.timed = [
            Self.timedEvent(store, "Review", start: try at(16), end: try at(17)),
            Self.timedEvent(store, "Lunch", start: try at(12), end: try at(13)),
            Self.timedEvent(store, "Standup", start: try at(9), end: try at(10)),
            Self.timedEvent(store, "Alpha", start: try at(9), end: try at(10))
        ]
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let holidays = ["Zoo trip", "Anniversary"].map { title -> EKEvent in
            let event = Self.timedEvent(store, title, start: day, end: nextDay)
            event.isAllDay = true
            return event
        }
        source.allDay = holidays
        let cache = CalendarEventDayCache()

        #expect(cache.timedEvents(for: day, calendarManager: source).map(\.title) == ["Alpha", "Standup", "Lunch", "Review"])
        #expect(cache.allDayEvents(for: day, calendarManager: source).map(\.title) == ["Anniversary", "Zoo trip"])
        // The Month cell reads the same order: all-day first, then the timed segments by start.
        #expect(
            CalendarMonthCellEventSupport.items(for: day, eventCache: cache, source: source, calendar: calendar).map(\.title)
                == ["Anniversary", "Zoo trip", "Alpha", "Standup", "Lunch", "Review"]
        )
    }

    // MARK: - T-16522: a transition-day event is drawn at its wall-clock span

    private static func newYork(_ month: Int, _ day: Int, _ hour: Int, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    @Test("On a DST day the Mac draws an event between its wall-clock ends, as iOS does")
    func aTransitionDayEventIsDrawnAtItsWallClockSpan() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let store = EKEventStore()
        // (month, day, start hour, end hour): spring forward, fall back, and an ordinary day.
        for (month, day, startHour, endHour) in [(3, 8, 1, 4), (11, 1, 0, 3), (6, 11, 1, 4)] {
            let start = try Self.newYork(month, day, startHour, calendar)
            let end = try Self.newYork(month, day, endHour, calendar)
            let dayStart = calendar.startOfDay(for: start)
            let event = Self.timedEvent(store, "Overnight", start: start, end: end)
            let item = try #require(CalendarEventItem(event: event, clippedTo: dayStart, calendar: calendar))
            let ios = CadenceScheduleSupport.minuteRange(from: start, to: end, on: dayStart, calendar: calendar)

            #expect(item.startMin == startHour * 60)
            #expect(item.startMin + item.durationMinutes == endHour * 60, "\(month)/\(day) drawn to \(item.startMin + item.durationMinutes)")
            #expect(item.startMin == ios.start && item.startMin + item.durationMinutes == ios.end)
            // The elapsed length is kept separately, and differs exactly on the two transition days.
            let elapsed = Int(end.timeIntervalSince(start) / 60)
            #expect(item.eventDurationMinutes == elapsed)
            #expect((item.durationMinutes == elapsed) == (month == 6))
        }
    }

    @Test("Moving a DST-day event keeps its elapsed length, not its drawn one")
    func movingATransitionDayEventKeepsItsElapsedLength() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let store = EKEventStore()
        let start = try Self.newYork(3, 8, 1, calendar)
        let end = try Self.newYork(3, 8, 4, calendar)
        let event = Self.timedEvent(store, "Overnight", start: start, end: end)
        let item = try #require(CalendarEventItem(event: event, clippedTo: calendar.startOfDay(for: start), calendar: calendar))
        #expect(!item.isMultiDayTimedEvent)

        let moved = try #require(item.eventDateRangeForMovedSegment(startMin: 10 * 60, calendar: calendar))
        #expect(moved.start == (try Self.newYork(3, 8, 10, calendar)))
        #expect(moved.end.timeIntervalSince(moved.start) == end.timeIntervalSince(start))
    }

    // MARK: - T-16578: a resize writes the wall-clock row the user let go on

    @Test("Resizing a DST-day event writes the end at the row it was released on")
    func resizingATransitionDayEventWritesTheWallClockEnd() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let store = EKEventStore()
        // (month, day, start hour, end hour, released-on hour): spring forward, fall back, ordinary.
        for (month, day, startHour, endHour, releasedHour) in [(3, 8, 1, 4, 5), (11, 1, 0, 3, 4), (6, 11, 1, 4, 5)] {
            let start = try Self.newYork(month, day, startHour, calendar)
            let end = try Self.newYork(month, day, endHour, calendar)
            let event = Self.timedEvent(store, "Overnight", start: start, end: end)
            let item = try #require(CalendarEventItem(event: event, clippedTo: calendar.startOfDay(for: start), calendar: calendar))

            // Bottom edge dragged down one row, then back onto the row it started on.
            let grown = try #require(item.eventDateRangeForResizedSegment(
                startMin: item.startMin, endMin: releasedHour * 60, calendar: calendar))
            #expect(grown.start == start)
            #expect(grown.end == (try Self.newYork(month, day, releasedHour, calendar)),
                    "\(month)/\(day): released on \(releasedHour):00, wrote hour \(calendar.component(.hour, from: grown.end))")
            let back = try #require(item.eventDateRangeForResizedSegment(
                startMin: item.startMin, endMin: endHour * 60, calendar: calendar))
            #expect(back.end == end, "\(month)/\(day): released on \(endHour):00, wrote hour \(calendar.component(.hour, from: back.end))")

            // The bottom edge pulled to the foot of the grid is the next midnight.
            let toMidnight = try #require(item.eventDateRangeForResizedSegment(
                startMin: item.startMin, endMin: 24 * 60, calendar: calendar))
            #expect(toMidnight.end == (try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)))))
        }
    }

    @Test("A top-edge resize keeps an end inside the repeated fall-back hour")
    func aTopEdgeResizeKeepsTheEventsOwnEnd() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let store = EKEventStore()
        let start = try Self.newYork(11, 1, 0, calendar)
        // 1:30 EST, the second of the day's two 1:30s: 1:00 EDT plus ninety minutes.
        let end = try Self.newYork(11, 1, 1, calendar).addingTimeInterval(90 * 60)
        let event = Self.timedEvent(store, "Late", start: start, end: end)
        let item = try #require(CalendarEventItem(event: event, clippedTo: start, calendar: calendar))
        #expect(item.startMin + item.durationMinutes == 90)

        let resized = try #require(item.eventDateRangeForResizedSegment(
            startMin: 30, endMin: item.startMin + item.durationMinutes, calendar: calendar))
        #expect(resized.start == start.addingTimeInterval(30 * 60))
        #expect(resized.end == end, "the untouched end was re-read as the earlier 1:30")
    }

    @Test("The timeline block's resize writes its end as a wall-clock row")
    func theBlockResizesThroughTheWallClockRange() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift"))
        #expect(CadenceSourceScan.matchCount(#"requestEventMutation\(\.resize\(startMin: finalStart, endMin: finalStart \+ finalDuration\)\)"#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"item\.eventDateRangeForResizedSegment\(startMin: startMin, endMin: endMin\)"#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"eventDateRangeForEditedSegment"#, in: code) == 0)
    }

    @Test("The Month header reads its headings from the grid's calendar")
    func theHeaderReadsTheGridsCalendar() throws {
        let support = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthGridSupport.swift"))
        let header = try #require(CadenceSourceScan.declarationBody("struct MonthGridWeekdayHeader: View", in: support))
        #expect(CadenceSourceScan.matchCount(#"CadenceScheduleSupport\.weekdaySymbols\(calendar: calendar, width: \.short\)"#, in: header) == 1)
        let page = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageComponents.swift"))
        #expect(CadenceSourceScan.matchCount(#"MonthGridWeekdayHeader\(calendar: cal\)"#, in: page) == 1)
    }
}
#endif
