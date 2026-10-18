#if os(macOS)
import EventKit
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// An authorised calendar source answering a fixed number of timed and all-day events per day.
///
/// The test host is not calendar-authorised, so `CalendarManager` answers `[]` from its
/// `isAuthorized` guard and a month cell built on it would draw no all-day event whether or not the
/// cell asked for them. The two halves answer different counts so a drawn item can be attributed to
/// the half it came from.
private final class FixedEventDaySource: CalendarEventDaySource {
    var isAuthorized: Bool = true
    var storeVersion: Int = 0
    var timedEventsPerDay = 3
    var allDayEventsPerDay = 2

    private let store = EKEventStore()

    func fetchEvents(for date: Date) -> [EKEvent] {
        makeEvents(on: date, count: timedEventsPerDay, allDay: false)
    }

    func fetchAllDayEvents(for date: Date) -> [EKEvent] {
        makeEvents(on: date, count: allDayEventsPerDay, allDay: true)
    }

    private func makeEvents(on date: Date, count: Int, allDay: Bool) -> [EKEvent] {
        let dayStart = Calendar.current.startOfDay(for: date)
        return (0..<count).map { index in
            let event = EKEvent(eventStore: store)
            event.title = "\(allDay ? "All-day" : "Timed") \(index)"
            event.isAllDay = allDay
            if allDay {
                event.startDate = dayStart
                event.endDate = dayStart.addingTimeInterval(86_400)
            } else {
                event.startDate = dayStart.addingTimeInterval(TimeInterval((9 + index) * 3600))
                event.endDate = dayStart.addingTimeInterval(TimeInterval((10 + index) * 3600))
            }
            return event
        }
    }
}

/// **T-3163** — an all-day event was drawn on neither the macOS month grid nor the iOS week
/// timeline. **T-3164** — the iOS week timeline dropped a completed timed task that macOS draws.
///
/// Counts and relations only, never a duration or a pinned point figure.
@MainActor
@Suite struct CalendarAllDayAndDoneTaskParityTests {
    private static let day: Date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 6, day: 11)
    ) ?? Date(timeIntervalSince1970: 0)

    // MARK: - T-3163, macOS month cell

    /// The month cell's event list carries both halves of the day, all-day first.
    @Test func theMacMonthCellEventListCarriesTheDaysAllDayEventsAheadOfItsTimedOnes() {
        let source = FixedEventDaySource()
        let items = CalendarMonthCellEventSupport.items(
            for: Self.day,
            eventCache: CalendarEventDayCache(),
            source: source
        )

        let allDayCount = items.filter(\.ekEvent.isAllDay).count
        let timedCount = items.filter { !$0.ekEvent.isAllDay }.count
        #expect(allDayCount == source.allDayEventsPerDay, "the cell drew \(allDayCount) all-day events")
        #expect(timedCount == source.timedEventsPerDay, "the cell drew \(timedCount) timed events")
        #expect(items.count == allDayCount + timedCount)

        // Every all-day item precedes every timed one, so the priority split's "events" rows go to
        // the whole-day items first.
        let lastAllDay = items.lastIndex { $0.ekEvent.isAllDay }
        let firstTimed = items.firstIndex { !$0.ekEvent.isAllDay }
        if let lastAllDay, let firstTimed {
            #expect(lastAllDay < firstTimed)
        } else {
            Issue.record("one half of the day is missing from the list")
        }

        // An all-day chip names no time — the month chip asks the event, not the segment.
        #expect(items.filter(\.ekEvent.isAllDay).allSatisfy { $0.chipTimeLabel() == nil })
        // Control: the timed ones do, so the line above is not vacuous.
        #expect(items.filter { !$0.ekEvent.isAllDay }.allSatisfy { $0.chipTimeLabel() != nil })
    }

    /// The unauthorised control: the same call answers nothing, so the counts above came from the
    /// source rather than from the helper inventing items.
    @Test func anUnauthorisedSourceGivesTheMacMonthCellNoEventsOfEitherKind() {
        let source = FixedEventDaySource()
        source.isAuthorized = false
        let items = CalendarMonthCellEventSupport.items(
            for: Self.day,
            eventCache: CalendarEventDayCache(),
            source: source
        )
        #expect(items.isEmpty)
    }

    /// `MonthDayCell` draws its chips from that helper and no longer asks the timed half alone.
    @Test func theMacMonthCellAsksTheHelperRatherThanTheTimedHalfAlone() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        let body = try #require(CadenceSourceScan.declarationBody("struct MonthDayCell", in: code))
        #expect(CadenceSourceScan.matchCount(#"CalendarMonthCellEventSupport\.items\("#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.timedEvents\(for:"#, in: body) == 0,
                "MonthDayCell asks the timed half on its own again")
    }

    // MARK: - T-1474 (was T-3163), the all-day strip's capped split

    private typealias Band = CadenceCalendarAllDayBandPriority

    /// The owner's caps: 6 chip rows at compact width (iPhone), 8 at regular (iPad), and a task
    /// reserve of `min(tasks, min(cap / 2, 3))` — 3 on both today.
    @Test func theStripCapIsSixOnIPhoneAndEightOnIPadWithAReserveOfThree() {
        #expect(Band.capacity(isRegularWidth: false) == 6)
        #expect(Band.capacity(isRegularWidth: true) == 8)
        #expect(Band.reservedTaskRows(unscheduledTasks: 10, capacity: 6) == 3)
        #expect(Band.reservedTaskRows(unscheduledTasks: 10, capacity: 8) == 3)
        // The formula, not two constants: it keeps working if the cap moves.
        #expect(Band.reservedTaskRows(unscheduledTasks: 10, capacity: 4) == 2)
        #expect(Band.reservedTaskRows(unscheduledTasks: 10, capacity: 2) == 1)
        // `min(taskCount, ...)`: one task reserves one row, not three blank ones.
        #expect(Band.reservedTaskRows(unscheduledTasks: 1, capacity: 6) == 1)
        #expect(Band.reservedTaskRows(unscheduledTasks: 0, capacity: 6) == 0)
    }

    /// No rationing until overflow; on overflow events take every row the reserve leaves, and the
    /// "+N more" count is exactly what was not drawn.
    @Test func theStripRationsOnlyOnOverflowAndThenHoldsTheTaskReserve() {
        // Fits: everything drawn, whatever the mix.
        #expect(Band.split(allDayEvents: 5, unscheduledTasks: 1, capacity: 6)
                == .init(events: 5, tasks: 1, hidden: 0))
        #expect(Band.split(allDayEvents: 1, unscheduledTasks: 5, capacity: 6)
                == .init(events: 1, tasks: 5, hidden: 0))
        // The T-3163 starvation case: a holiday, a birthday and an overdue task all show now.
        #expect(Band.split(allDayEvents: 2, unscheduledTasks: 1, capacity: 6)
                == .init(events: 2, tasks: 1, hidden: 0))
        // Overflow, iPhone: three task rows held, events take the other three.
        #expect(Band.split(allDayEvents: 10, unscheduledTasks: 5, capacity: 6)
                == .init(events: 3, tasks: 3, hidden: 9))
        // Overflow, iPad: still three task rows, events take five.
        #expect(Band.split(allDayEvents: 10, unscheduledTasks: 5, capacity: 8)
                == .init(events: 5, tasks: 3, hidden: 7))
        // A reserve the tasks cannot fill flows back to events.
        #expect(Band.split(allDayEvents: 10, unscheduledTasks: 1, capacity: 6)
                == .init(events: 5, tasks: 1, hidden: 5))
        // Rows the events cannot fill flow back to tasks.
        #expect(Band.split(allDayEvents: 2, unscheduledTasks: 10, capacity: 6)
                == .init(events: 2, tasks: 4, hidden: 6))
        // A day with no loose tasks gives events every row.
        #expect(Band.split(allDayEvents: 9, unscheduledTasks: 0, capacity: 6)
                == .init(events: 6, tasks: 0, hidden: 3))
        // An unbounded capacity (the Mac's scrolling band) hides nothing.
        #expect(Band.split(allDayEvents: 40, unscheduledTasks: 30, capacity: .max)
                == .init(events: 40, tasks: 30, hidden: 0))
    }

    /// The invariants, over every small mix at both caps.
    @Test func theStripSplitHoldsItsInvariantsAtBothCaps() {
        var checked = 0
        for capacity in [Band.capacity(isRegularWidth: false), Band.capacity(isRegularWidth: true)] {
            for events in 0...12 {
                for tasks in 0...12 {
                    let split = Band.split(allDayEvents: events, unscheduledTasks: tasks, capacity: capacity)
                    let total = events + tasks
                    #expect(split.visible <= capacity)
                    #expect(split.visible + split.hidden == total)
                    if total <= capacity {
                        #expect(split.hidden == 0, "rationed below overflow: \(events)e \(tasks)t cap \(capacity)")
                    } else {
                        #expect(split.visible == capacity, "an overflowing strip left a blank row")
                        #expect(split.tasks >= Band.reservedTaskRows(unscheduledTasks: tasks, capacity: capacity))
                    }
                    checked += 1
                }
            }
        }
        #expect(checked == 2 * 13 * 13, "non-vacuity: \(checked) mixes")
    }

    /// The iOS grid hands each header its day's all-day events and this width's capacity, and the
    /// header draws them through the split, as event chips, above the unscheduled tasks.
    /// `Cadence/iOS/` is behind `#if os(iOS)`, so this half can only be read as text.
    @Test func theIOSTimelineHeaderIsHandedAndDrawsTheDaysAllDayEvents() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        #expect(
            CadenceSourceScan.matchCount(
                #"iOSCalendarTimelineDayHeader\(\s*date: date,\s*allDayEvents: allDayEvents\(on: date\),\s*unscheduledTasks: items\(unscheduledTasksByDate, on: date\),\s*capacity: bandCapacity,\s*bandHeight: dayHeaderHeight"#,
                in: code
            ) == 1,
            "the grid no longer hands the header the day's all-day events, its capacity and the shared band height"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarAllDayBandPriority\.capacity\(isRegularWidth: isRegularWidth\)"#, in: code) == 1,
            "the strip's capacity is no longer the shared per-width rule"
        )

        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader", in: code)
        )
        #expect(CadenceSourceScan.matchCount(#"CadenceCalendarAllDayBandPriority\.split\(\s*allDayEvents: allDayEvents\.count,\s*unscheduledTasks: unscheduledTasks\.count,\s*capacity: capacity"#, in: header) == 1)
        let events = try #require(header.range(of: "ForEach(allDayEvents.prefix(split.events)"))
        let tasks = try #require(header.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        #expect(events.lowerBound < tasks.lowerBound, "the band stacks its tasks above its all-day events")
        #expect(CadenceSourceScan.matchCount(#"isEvent: true"#, in: header) == 1,
                "the band's all-day chip does not wear the event (rail) treatment")
        #expect(CadenceSourceScan.matchCount(#"split\.hidden"#, in: header) >= 1)
        // The band is the grid's one height, not the old fixed figure.
        #expect(CadenceSourceScan.matchCount(#"\.frame\(height: bandHeight"#, in: header) == 1)
        #expect(CadenceSourceScan.matchCount(#"iOSCalendarTimelineMetrics\.dayHeaderHeight\b(?!\()"#, in: header) == 0)
        // No second, hand-rolled cap.
        #expect(CadenceSourceScan.matchCount(#"prefix\(\d+\)"#, in: header) == 0)
    }

    // MARK: - T-1474, the span rule

    /// **A timed event is never promoted to the strip, however long it runs.** The fixture runs
    /// Monday 07:30 to Thursday 16:15; on each of its four days the grid's own clamp draws it as a
    /// block — real start, two full days, real end — and on neither neighbouring day at all.
    @Test func aFourDayTimedEventIsABlockOnEachDayAndNeverInTheStrip() throws {
        let calendar = Calendar.current
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        #expect(calendar.component(.weekday, from: monday) == 2, "the anchor is not a Monday")

        let spec = CadenceCalendarFixtureEvents.Fixture.multiDay
        let span = spec.interval(anchoredOn: monday, calendar: calendar)
        func day(_ offset: Int) throws -> Date {
            try #require(calendar.date(byAdding: .day, value: offset, to: monday))
        }
        func range(on offset: Int) throws -> (start: Int, end: Int) {
            CadenceScheduleSupport.minuteRange(from: span.start, to: span.end, on: try day(offset), calendar: calendar)
        }
        func overlaps(_ offset: Int) throws -> Bool {
            let start = calendar.startOfDay(for: try day(offset))
            let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
            return span.start < end && span.end > start
        }

        #expect(try range(on: 0) == (7 * 60 + 30, 24 * 60), "Monday: its real start, to midnight")
        #expect(try range(on: 1) == (0, 24 * 60), "Tuesday: the full column")
        #expect(try range(on: 2) == (0, 24 * 60), "Wednesday: the full column")
        #expect(try range(on: 3) == (0, 16 * 60 + 15), "Thursday: midnight to its real end")
        #expect(try (0...3).allSatisfy(overlaps), "a day of the span would not be fetched for it")
        #expect(try !overlaps(-1) && !overlaps(4), "the span leaks onto a neighbouring day")

        // The strip's door is `isAllDay` and nothing else, on iOS and on the Mac's fetch alike.
        let iOS = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))
        #expect(CadenceSourceScan.matchCount(#"\.filter\(\\\.isAllDay\)"#, in: iOS) == 1,
                "the iOS strip has a second door, or lost its one")
        let helper = try #require(CadenceSourceScan.declarationBody("private func allDayEvents(on date: Date)", in: iOS))
        #expect(helper.contains("filter(\\.isAllDay)"))
        #expect(CadenceSourceScan.matchCount(#"duration|endDate|timeIntervalSince"#, in: helper) == 0,
                "the strip's door started reading an event's length")
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Services/CalendarManager.swift"))
        #expect(CadenceSourceScan.matchCount(#"\.filter \{ \$0\.isAllDay \}"#, in: mac) == 1)
    }

    // MARK: - T-3164, completed timed tasks on the iOS timeline

    private func doneAndCancelledTasks(in context: ModelContext) -> [AppTask] {
        let key = DateFormatters.dateKey(from: Self.day)
        func add(_ title: String, done: Bool = false, cancelled: Bool = false) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = key
            task.scheduledStartMin = 9 * 60
            task.estimatedMinutes = 30
            if done { task.status = .done }
            if cancelled { task.status = .cancelled }
            context.insert(task)
            return task
        }
        return [add("Open"), add("Finished", done: true), add("Dropped", cancelled: true)]
    }

    /// Both iOS grids call the shared query with the argument the macOS Calendar page passes, and
    /// with that argument the done task is on the day and the cancelled one is not.
    @Test func theIOSTimelineKeepsACompletedTimedTaskExactlyAsTheMacCalendarPageDoes() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let tasks = doneAndCancelledTasks(in: context)
        let key = DateFormatters.dateKey(from: Self.day)
        #expect(tasks.filter(\.isDone).count == 1)
        #expect(tasks.filter(\.isCancelled).count == 1)

        let mac = Set((CalendarPageDataSupport.tasksByScheduledDate(tasks)[key] ?? []).map(\.title))
        #expect(mac == ["Open", "Finished"])

        for path in ["Cadence/iOS/iOSCalendarView.swift", "Cadence/iOS/iOSTodaySchedulePanel.swift"] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(code != raw)
            #expect(code.count == raw.count)

            let pattern = try Regex(#"tasksByScheduledDate\(allTasks, includeCompleted: (true|false)\)"#)
            let matches = code.matches(of: pattern)
            #expect(matches.count == 1, "\(path): expected one scheduled-task query, found \(matches.count)")
            let literal = try #require(matches.first?.output[1].substring.map(String.init))
            let includeCompleted = literal == "true"

            let ios = Set(
                (CadenceScheduleSupport.tasksByScheduledDate(tasks, includeCompleted: includeCompleted)[key] ?? [])
                    .map(\.title)
            )
            #expect(ios == mac, "\(path) draws \(ios.sorted()) where macOS draws \(mac.sorted())")
        }
    }
}
#endif
