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

    // MARK: - T-3163, iOS timeline band

    /// The band's two rows go to all-day events before unscheduled tasks, and the "+N more" line
    /// counts exactly what was not drawn.
    @Test func theTimelineBandSpendsItsRowsOnAllDayEventsBeforeUnscheduledTasks() {
        let crowded = CadenceCalendarAllDayBandPriority.split(allDayEvents: 3, unscheduledTasks: 2)
        #expect(crowded.events == CadenceCalendarAllDayBandPriority.capacity)
        #expect(crowded.tasks == 0)
        #expect(crowded.visible + crowded.hidden == 5)

        let mixed = CadenceCalendarAllDayBandPriority.split(allDayEvents: 1, unscheduledTasks: 4)
        #expect(mixed.events == 1)
        #expect(mixed.tasks == CadenceCalendarAllDayBandPriority.capacity - 1)
        #expect(mixed.visible + mixed.hidden == 5)

        // A band with no all-day events keeps the task rows it always had.
        let tasksOnly = CadenceCalendarAllDayBandPriority.split(allDayEvents: 0, unscheduledTasks: 4)
        #expect(tasksOnly.tasks == CadenceCalendarAllDayBandPriority.capacity)
        #expect(tasksOnly.events == 0)

        for events in 0...4 {
            for tasks in 0...4 {
                let split = CadenceCalendarAllDayBandPriority.split(allDayEvents: events, unscheduledTasks: tasks)
                #expect(split.visible <= CadenceCalendarAllDayBandPriority.capacity)
                #expect(split.visible + split.hidden == events + tasks)
            }
        }
    }

    /// The iOS grid hands each header its day's all-day events, and the header draws them through
    /// the split, as event chips, above the unscheduled tasks. `Cadence/iOS/` is behind
    /// `#if os(iOS)`, so this half can only be read as text.
    @Test func theIOSTimelineHeaderIsHandedAndDrawsTheDaysAllDayEvents() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        #expect(
            CadenceSourceScan.matchCount(
                #"iOSCalendarTimelineDayHeader\(\s*date: date,\s*allDayEvents: items\(eventsByDate, on: date\)\.filter\(\\\.isAllDay\),"#,
                in: code
            ) == 1,
            "the grid no longer hands the header the day's all-day events"
        )

        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader", in: code)
        )
        #expect(header.contains("CadenceCalendarAllDayBandPriority.split("))
        let events = try #require(header.range(of: "ForEach(allDayEvents.prefix(split.events)"))
        let tasks = try #require(header.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        #expect(events.lowerBound < tasks.lowerBound, "the band stacks its tasks above its all-day events")
        #expect(CadenceSourceScan.matchCount(#"isEvent: true"#, in: header) == 1,
                "the band's all-day chip does not wear the event (rail) treatment")
        #expect(CadenceSourceScan.matchCount(#"split\.hidden"#, in: header) >= 1)
        // The old fixed cap is gone: one rule, not a second count.
        #expect(CadenceSourceScan.matchCount(#"prefix\(2\)"#, in: header) == 0)
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
