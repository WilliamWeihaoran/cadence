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
