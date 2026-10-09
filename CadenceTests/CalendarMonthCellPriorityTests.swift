import Foundation
import Testing

@testable import Cadence

/// T-3088: on an overfull month-grid day, the calendar **events** take the chip slots and the
/// **tasks** overflow into "+N more".
///
/// Every assertion here is about the *partition*, not about the remainder. A test that only
/// checks that the cell says "+9 more" is green for the ordering that drops nine events and keeps
/// nine tasks, which is the state this ticket was filed about.
@Suite struct CalendarMonthCellPriorityTests {
    /// The owner's rule, at the one size where it is visible: more of both kinds than fit.
    @Test func anOverfullMonthDayDrawsItsEventsAndOverflowsItsTasks() {
        // Four slots, three events and six tasks. Events-first fills three slots with events and
        // the last one with a task; tasks-first would draw four tasks and hide every event.
        let split = CadenceCalendarMonthCellPriority.split(bundles: 0, events: 3, tasks: 6, capacity: 4)

        #expect(split.events == 3)
        #expect(split.tasks == 1)
        #expect(split.bundles == 0)
        #expect(split.visible == 4)
        #expect(split.hidden == 5)

        // Not a single event may be the thing that gets cut while a task is drawn.
        #expect(split.events == 3)
        #expect(split.tasks < 6)
    }

    /// The case the ranking is actually load-bearing in: events alone exceed the cell.
    @Test func whenEventsAloneOverflowTheCellNoTaskTakesASlotFromThem() {
        let split = CadenceCalendarMonthCellPriority.split(bundles: 0, events: 9, tasks: 4, capacity: 3)

        #expect(split.events == 3)
        #expect(split.tasks == 0)
        #expect(split.visible == 3)
        // Six events and all four tasks.
        #expect(split.hidden == 10)
    }

    /// Bundles keep the rank both platforms already gave them, and the owner's argument did not
    /// touch: they are the shape of the day, not one of its items.
    @Test func bundlesOutrankBothAndEventsStillOutrankTasksBelowThem() {
        let split = CadenceCalendarMonthCellPriority.split(bundles: 2, events: 4, tasks: 4, capacity: 5)

        #expect(split.bundles == 2)
        #expect(split.events == 3)
        #expect(split.tasks == 0)
        #expect(split.hidden == 5)
    }

    /// A day that fits draws everything, in every mix, and claims nothing is hidden.
    @Test func aDayThatFitsHidesNothingAndKeepsEveryKind() {
        let split = CadenceCalendarMonthCellPriority.split(bundles: 1, events: 2, tasks: 2, capacity: 6)

        #expect(split.bundles == 1)
        #expect(split.events == 2)
        #expect(split.tasks == 2)
        #expect(split.visible == 5)
        #expect(split.hidden == 0)
    }

    /// A row too short for even one chip reports every item hidden rather than going negative —
    /// macOS's `chipCapacity` really does return 0 on a 20pt row.
    @Test func aZeroCapacityMonthCellDrawsNothingAndHidesEverything() {
        let split = CadenceCalendarMonthCellPriority.split(bundles: 1, events: 2, tasks: 3, capacity: 0)

        #expect(split.visible == 0)
        #expect(split.hidden == 6)

        // A negative capacity is clamped, not trusted.
        let negative = CadenceCalendarMonthCellPriority.split(bundles: 0, events: 1, tasks: 1, capacity: -4)
        #expect(negative.visible == 0)
        #expect(negative.hidden == 2)
    }

    /// `hidden` is always the complement of what was drawn, so the "+N more" line and the chips
    /// above it can never describe two different days.
    @Test func theHiddenCountAlwaysCompletesTheDrawnChips() {
        for bundles in 0...3 {
            for events in 0...4 {
                for tasks in 0...4 {
                    for capacity in 0...6 {
                        let split = CadenceCalendarMonthCellPriority.split(
                            bundles: bundles,
                            events: events,
                            tasks: tasks,
                            capacity: capacity
                        )
                        #expect(split.visible + split.hidden == bundles + events + tasks)
                        #expect(split.visible <= capacity)
                        #expect(split.bundles <= bundles)
                        #expect(split.events <= events)
                        #expect(split.tasks <= tasks)
                    }
                }
            }
        }
    }

    /// Both month cells ask the shared helper, and neither one re-derives a partition of its own.
    ///
    /// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds on macOS, so the iOS half can
    /// only be read as text — and the macOS half is read the same way so that one of them going
    /// its own way again is caught by the same assertion rather than by two different ones.
    @Test func bothMonthDayCellsPartitionThroughTheSharedPriorityHelper() throws {
        let cells = [
            ("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift", "struct MonthDayCell"),
            ("Cadence/iOS/iOSCalendarMonthViews.swift", "private struct iOSCalendarMonthDayCell")
        ]

        for (path, declaration) in cells {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            // Non-vacuity, both halves: the file was really read, and the stripper really ran
            // without shortening it (the comments here are not optional — both cells carry one).
            #expect(code != raw, "\(path): nothing was stripped, so the scan read raw text")
            #expect(code.count == raw.count, "\(path): the stripper changed the source's length")

            let body = try #require(
                CadenceSourceScan.declarationBody(declaration, in: code),
                "\(path): could not read the body of \(declaration)"
            )
            #expect(body.contains("CadenceCalendarMonthCellPriority.split("), "\(path) does not route through the shared split")
            #expect(body.contains("bundles: bundles.count"), "\(path) does not hand the helper its own bundle count")
            #expect(body.contains("events: events.count"), "\(path) does not hand the helper its own event count")
            #expect(body.contains("tasks: tasks.count"), "\(path) does not hand the helper its own task count")

            // The shapes each cell used to spell its own ordering with. A cell that grows a second
            // partition grows one of these back.
            #expect(CadenceSourceScan.matchCount(#"prefix\(max\(0,"#, in: body) == 0, "\(path) still derives a per-kind cap of its own")
            #expect(CadenceSourceScan.matchCount(#"prefix\([0-9]+\)"#, in: body) == 0, "\(path) still hardcodes a per-kind chip cap")
        }
    }

    /// The macOS cell draws what it ranked, in the order it ranked it — which is also the order
    /// the iOS cell has always drawn. A cell that ranks events above tasks and then draws the task
    /// chips above the event chips is telling the reader the opposite of what it decided.
    @Test func theMacMonthCellDrawsEventChipsAboveTaskChips() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        let body = try #require(CadenceSourceScan.declarationBody("struct MonthDayCell", in: code))
        let events = try #require(body.range(of: "ForEach(eventChips)"))
        let tasks = try #require(body.range(of: "ForEach(taskChips)"))
        #expect(events.lowerBound < tasks.lowerBound, "macOS draws its task chips above its event chips")
    }
}
