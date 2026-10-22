#if os(macOS)
import EventKit
import Foundation
import SwiftData
import SwiftUI
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
        // T-1364 put the shared rule behind `iOSCalendarTypographyMetrics.bandCapacity`, which
        // spends the same per-width budget on fewer rows as the labels grow. The grid reads the
        // wrapper and the wrapper is still required to derive from the shared rule, so the
        // invariant is checked across both halves rather than relaxed to whichever one is left.
        #expect(
            CadenceSourceScan.matchCount(
                #"iOSCalendarTypographyMetrics\.bandCapacity\(isRegularWidth: isRegularWidth, at: dynamicTypeSize, scaling: scaling\)"#,
                in: code
            ) == 1,
            "the strip's capacity is no longer read through the shared per-width rule's wrapper"
        )
        let metrics = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMetrics.swift")
        )
        let capacityBody = try #require(
            CadenceSourceScan.functionBody(named: "bandCapacity", in: metrics),
            "iOSCalendarTypographyMetrics.bandCapacity was not found"
        )
        #expect(
            capacityBody.contains("CadenceCalendarAllDayBandPriority.capacity(isRegularWidth: isRegularWidth)"),
            "the strip's capacity is no longer derived from the shared per-width rule"
        )

        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader", in: code)
        )
        #expect(CadenceSourceScan.matchCount(#"CadenceCalendarAllDayBandPriority\.split\(\s*allDayEvents: allDayEvents\.count,\s*unscheduledTasks: unscheduledTasks\.count,\s*capacity: capacity"#, in: header) == 1)
        // The chips themselves moved into `iOSCalendarAllDayBandChips` when the single-day pane
        // gained a strip of its own (T-3163, the Today half) — ONE construction with two callers,
        // so this reads the stack the header hands its split to rather than relaxing to whichever
        // half stayed behind. The header still has to be the thing that hands it over.
        #expect(CadenceSourceScan.matchCount(#"iOSCalendarAllDayBandChips\(\s*allDayEvents: allDayEvents,\s*unscheduledTasks: unscheduledTasks,\s*split: split"#, in: header) == 1,
                "the week header no longer hands the shared chip stack its day's items and split")
        let chips = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarAllDayBandChips", in: code)
        )
        let events = try #require(chips.range(of: "ForEach(allDayEvents.prefix(split.events)"))
        let tasks = try #require(chips.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        #expect(events.lowerBound < tasks.lowerBound, "the band stacks its tasks above its all-day events")
        #expect(CadenceSourceScan.matchCount(#"isEvent: true"#, in: chips) == 1,
                "the band's all-day chip does not wear the event (rail) treatment")
        #expect(CadenceSourceScan.matchCount(#"split\.hidden"#, in: chips) >= 1)
        // The band is the grid's one height, not the old fixed figure.
        #expect(CadenceSourceScan.matchCount(#"\.frame\(height: bandHeight"#, in: header) == 1)
        #expect(CadenceSourceScan.matchCount(#"iOSCalendarTimelineMetrics\.dayHeaderHeight\b(?!\()"#, in: header) == 0)
        // No second, hand-rolled cap.
        #expect(CadenceSourceScan.matchCount(#"prefix\(\d+\)"#, in: header) == 0)
    }

    /// The Mac band (`CalDayHeaderView.allDayBannerContent`) orders its chips by the same shared
    /// rule as iOS — events first — at an unbounded capacity, because its fixed-height band scrolls
    /// and so hides nothing. It used to hand-roll tasks first. T-1474, macOS half.
    @Test func theMacDayHeaderBandOrdersItsChipsByTheSharedRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        let header = try #require(CadenceSourceScan.declarationBody("struct CalDayHeaderView", in: code))
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceCalendarAllDayBandPriority\.split\(\s*allDayEvents: allDayEventItems\.count,\s*unscheduledTasks: unscheduledTasks\.count,\s*capacity: Self\.bandCapacity"#,
                in: header
            ) == 1,
            "the Mac band no longer asks the shared all-day rule"
        )
        #expect(CadenceSourceScan.matchCount(#"static let bandCapacity = Int\.max\b"#, in: header) == 1,
                "the Mac band's scrolling strip gained a cap")
        let events = try #require(header.range(of: "ForEach(allDayEventItems.prefix(split.events))"))
        let tasks = try #require(header.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        #expect(events.lowerBound < tasks.lowerBound, "the Mac band stacks its tasks above its all-day events")
        // No second, unsplit pass over either list.
        #expect(CadenceSourceScan.matchCount(#"ForEach\(unscheduledTasks\)"#, in: header) == 0)
        #expect(CadenceSourceScan.matchCount(#"ForEach\(allDayEventItems\)"#, in: header) == 0)
        // The band keeps its fixed scrolling frame: the order changed, not the geometry.
        #expect(CadenceSourceScan.matchCount(#"\.frame\(height: calAllDayBannerHeight"#, in: header) == 1)
        #expect(CadenceSourceScan.matchCount(#"ScrollView\(\.vertical"#, in: header) == 1)
    }

    // MARK: - T-1474, the span rule

    /// **A timed event is never promoted to the strip, however long it runs.** The fixture runs
    /// Monday 07:30 to Thursday 16:15; on each of its four days the grid's own clamp draws it as a
    /// block — real start, two full days, real end — and on neither neighbouring day at all.
    @Test func aFourDayTimedEventIsABlockOnEachDayAndNeverInTheStrip() throws {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
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

    // MARK: - The single-day pane's all-day strip (T-3163, the Today half)

    /// **The strip costs nothing on a day with nothing all-day on it, and grows with the chips it
    /// draws.** That zero is the whole reason `allDayStripHeight` is a second function rather than
    /// a flag on `bandHeight`: the week grid's figure always pays for a date block and a
    /// `previewMinHeight` floor, because every column of a week has a weekday and a day number over
    /// it, and charging a Today pane 105pt for a day with no holiday would push its hour ladder
    /// down for nothing.
    @Test func aSingleDayStripCostsNothingUntilThereIsAnAllDayEventAndThenGrowsWithThem() {
        typealias Band = CadenceCalendarAllDayBandPriority
        let metrics = iOSCalendarTypographyMetrics.self

        let empty = Band.split(allDayEvents: 0, unscheduledTasks: 0, capacity: 6)
        #expect(empty.visible == 0 && empty.hidden == 0, "non-vacuity: the empty split really is empty")
        #expect(metrics.allDayStripHeight(for: empty, at: .large, scaling: .enabled) == 0,
                "a day with nothing all-day on it must not move the hour ladder")

        // Strictly monotonic over the rows it can actually draw, so a second holiday is never
        // drawn into the first one's space.
        var previous: CGFloat = 0
        for count in 1...6 {
            let split = Band.split(allDayEvents: count, unscheduledTasks: 0, capacity: 6)
            #expect(split.events == count, "non-vacuity: the split really drew \(count) rows")
            let height = metrics.allDayStripHeight(for: split, at: .large, scaling: .enabled)
            #expect(height > previous, "\(count) all-day events did not buy more strip than \(count - 1)")
            previous = height
        }

        // The "+N more" line is a row too: at capacity, one more event buys the overflow line.
        let full = Band.split(allDayEvents: 6, unscheduledTasks: 0, capacity: 6)
        let over = Band.split(allDayEvents: 7, unscheduledTasks: 0, capacity: 6)
        #expect(full.hidden == 0 && over.hidden == 1, "non-vacuity: the capacity really overflowed")
        // A whole LINE taller, not just one more inter-line gap: the "+N more" sentence has to
        // have been paid for, or it is drawn in the strip's padding.
        let overflowGain = metrics.allDayStripHeight(for: over, at: .large, scaling: .enabled)
            - metrics.allDayStripHeight(for: full, at: .large, scaling: .enabled)
        #expect(overflowGain > iOSCalendarTimelineMetrics.bandLineSpacing,
                "the hidden count is announced in a line the strip bought only the spacing for")

        // The relation that says the two figures are not the same figure: for every split, the
        // week header's band is the taller one, because it carries a date block this strip does
        // not draw. A strip that quietly started answering `bandHeight` would fail here.
        for count in 0...8 {
            let split = Band.split(allDayEvents: count, unscheduledTasks: 2, capacity: 6)
            #expect(metrics.allDayStripHeight(for: split, at: .large, scaling: .enabled)
                    < metrics.bandHeight(for: [split], at: .large, scaling: .enabled),
                    "the single-day strip is no longer cheaper than a week column's header at \(count)")
        }
    }

    /// The strip announces the events it drew and nothing else. No date — a pane showing one day
    /// has already said which day — and no unscheduled count, because the strip carries all-day
    /// events only. The count phrase is the one `timelineDayLabel` uses, so the week header and the
    /// Today strip cannot drift into two ways of announcing the same two holidays.
    @Test func theSingleDayStripAnnouncesItsAllDayEventsAndNoDate() {
        typealias Say = CadenceCalendarDayAccessibility
        #expect(Say.allDayStripLabel(allDayEventCount: 1) == "1 all-day event")
        #expect(Say.allDayStripLabel(allDayEventCount: 2) == "2 all-day events")
        #expect(Say.allDayStripLabel(allDayEventCount: 0) == "0 all-day events")

        let week = Say.timelineDayLabel(date: Date(), allDayEventCount: 2, unscheduledCount: 3)
        #expect(week.contains(Say.allDayStripLabel(allDayEventCount: 2)),
                "the week header and the Today strip count all-day events in two different sentences")
        #expect(!Say.allDayStripLabel(allDayEventCount: 2).contains("unscheduled"))
    }

    /// **The single-day grid draws that strip, above the hour ladder, from the same chip stack the
    /// week header uses.** `Cadence/iOS/` is behind `#if os(iOS)`, so this wiring can only be read
    /// as text; the arithmetic it reaches is pinned behaviourally above.
    ///
    /// Until this landed, `dayHeaderHeight` answered a flat `0` on a single-day grid and
    /// `singleDayCanvas` was a scroll view and nothing else, so an all-day event was on no part of
    /// the iOS Today pane: the column drops it (`timedEvents` filters `!isAllDay`) and there was
    /// nothing above the column to carry it.
    @Test func theSingleDayTimelineDrawsItsAllDayEventsAboveTheHourLadder() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        let height = try #require(
            CadenceSourceScan.declarationBody("private var dayHeaderHeight: CGFloat", in: code),
            "iOSCalendarTimelineGrid.dayHeaderHeight was not found"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"allDayStripHeight\(\s*for: singleDaySplit"#, in: height
            ) == 1,
            "the single-day branch no longer sizes itself from the all-day strip"
        )
        #expect(CadenceSourceScan.matchCount(#"guard !isSingleDay else \{ return 0 \}"#, in: height) == 0,
                "the single-day grid is back to reserving no strip at all")

        // The rule, not a reading of the caller's dictionary: the strip carries events only.
        let split = try #require(
            CadenceSourceScan.declarationBody("private var singleDaySplit:", in: code),
            "iOSCalendarTimelineGrid.singleDaySplit was not found"
        )
        #expect(split.contains("allDayEvents: allDayEvents(on: leadingDate).count"))
        #expect(CadenceSourceScan.matchCount(#"unscheduledTasks: 0"#, in: split) == 1,
                "the single-day strip has started repeating the task column's untimed tasks")

        let canvas = try #require(
            CadenceSourceScan.functionBody(named: "singleDayCanvas", in: code),
            "iOSCalendarTimelineGrid.singleDayCanvas was not found"
        )
        let guardIndex = try #require(canvas.range(of: "if dayHeaderHeight > 0 {"))
        let stripIndex = try #require(canvas.range(of: "iOSCalendarTimelineAllDayStrip("))
        let columnIndex = try #require(canvas.range(of: "dayColumn(for: leadingDate"))
        #expect(guardIndex.lowerBound < stripIndex.lowerBound,
                "the strip is drawn on a day that reserved no height for it")
        #expect(stripIndex.lowerBound < columnIndex.lowerBound,
                "the all-day strip is drawn below the hour ladder rather than above it")

        // One construction, two callers — the lesson `dayColumn` records about itself.
        #expect(CadenceSourceScan.matchCount(#"iOSCalendarAllDayBandChips\("#, in: code) == 2,
                "the band's chip stack is no longer one declaration with two callers")
        #expect(CadenceSourceScan.matchCount(#"private struct iOSCalendarAllDayBandChips"#, in: code) == 1)
        let strip = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineAllDayStrip", in: code)
        )
        #expect(CadenceSourceScan.matchCount(#"unscheduledTasks: \[\]"#, in: strip) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceCalendarDayAccessibility\.allDayStripLabel"#, in: strip) == 1,
                "the strip announces itself with some other sentence")
        // No date block on this one: that is the page's own title.
        #expect(CadenceSourceScan.matchCount(#"DateFormatters\.day"#, in: strip) == 0)
    }

}
#endif
