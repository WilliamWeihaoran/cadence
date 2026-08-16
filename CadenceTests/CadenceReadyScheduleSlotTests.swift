import Foundation
import Testing
@testable import Cadence

/// The one-tap start times "Ready to Schedule" offers.
///
/// They were three literals — 9 AM, 1 PM, 4 PM — that knew nothing about the clock, the user's
/// work-hours window, or what was already booked. These pin that all three now feed the answer.
struct CadenceReadyScheduleSlotTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func time(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func slots(
        at hour: Int,
        _ minute: Int = 0,
        workStart: Int = 9 * 60,
        workEnd: Int = 17 * 60,
        busy: [Range<Int>] = [],
        count: Int = 3
    ) -> [Int] {
        CadenceScheduleSupport.readyScheduleSlots(
            now: Self.time(hour, minute),
            workStartMinute: workStart,
            workEndMinute: workEnd,
            busyRanges: busy,
            count: count,
            calendar: Self.calendar
        )
    }

    @Test func anEmptyWorkdayIsSpreadAcrossTheWorkHoursWindowRatherThanBunchedAtItsStart() {
        // 9–5, asked at 8 AM: first offer is the start of the window, last is the last half hour a
        // 30-minute task still fits inside it, and the third sits between them. Three adjacent half
        // hours would be one choice presented three times.
        let result = slots(at: 8)
        #expect(result.count == 3)
        #expect(result.first == 9 * 60)
        #expect(result.last == 16 * 60 + 30)
        #expect(result == result.sorted())
        #expect(Set(result).count == 3)
    }

    @Test func noSlotIsEverInThePast() {
        // The old chips offered 9 AM at 3 in the afternoon. Every slot starts at or after the next
        // half hour.
        for hour in 0...23 {
            for minute in [0, 1, 29, 30, 31, 59] {
                let earliest = ((hour * 60 + minute) + 29) / 30 * 30
                for slot in slots(at: hour, minute) {
                    #expect(slot >= min(earliest, 23 * 60 + 30))
                }
            }
        }
    }

    @Test func theSearchWidensPastTheWorkWindowWhenTheWorkdayIsOver() {
        // 8 PM against a 9–5 window: there is nothing left of the work day, so the rest of the
        // evening is offered instead of three dead chips at hours that have already been.
        let result = slots(at: 20)
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0 >= 20 * 60 })
        #expect(result.last == 23 * 60 + 30)
    }

    @Test func aBookedHourIsNotOffered() {
        // 9–5 with 9:00–13:00 solid: nothing before 1 PM can be suggested.
        let result = slots(at: 8, busy: [9 * 60..<13 * 60])
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0 >= 13 * 60 })
    }

    @Test func aBlockRulesOutEverySlotItOverlapsAndNoMore() {
        // 11:00–12:00 booked. 11:00 and 11:30 are out; 10:30 is not — a 30-minute probe there ends
        // exactly as the block begins, which is the point of half-open ranges.
        let result = slots(at: 10, 15, busy: [11 * 60..<12 * 60], count: 8)
        #expect(!result.contains(11 * 60))
        #expect(!result.contains(11 * 60 + 30))
        #expect(result.contains(10 * 60 + 30))
        #expect(result.contains(12 * 60))
    }

    @Test func awholeDayOfBookingsStillOffersSomethingRatherThanAnEmptyRow() {
        // The chips are the row's only actions; a row of no controls is worse than a slot that
        // overlaps. Never empty, at any minute of any day.
        let solid = [0..<24 * 60]
        for hour in 0...23 {
            #expect(!slots(at: hour, busy: solid).isEmpty)
        }
    }

    @Test func lateAtNightTheHonestAnswerIsOneChip() {
        // 23:50 leaves exactly one half-hour mark that still starts today.
        let result = slots(at: 23, 50)
        #expect(result == [23 * 60 + 30])
    }

    @Test func aCustomWorkWindowMovesTheSlotsWithIt() {
        // An early riser's 6 AM–2 PM window, asked at 5 AM.
        let result = slots(at: 5, workStart: 6 * 60, workEnd: 14 * 60)
        #expect(result.first == 6 * 60)
        #expect(result.last == 13 * 60 + 30)
    }

    @Test func everySlotIsAHalfHourMarkInsideTheDay() {
        for hour in 0...23 {
            for slot in slots(at: hour) {
                #expect(slot % CadenceScheduleSupport.scheduleSlotStep == 0)
                #expect((0..<24 * 60).contains(slot))
            }
        }
    }

    @Test func busyRangesAreBuiltFromBothTasksAndBundles() {
        let task = AppTask(title: "Standup")
        task.scheduledStartMin = 9 * 60
        task.estimatedMinutes = 45

        let bundle = TaskBundle(
            title: "Errands",
            dateKey: "2026-08-17",
            startMin: 14 * 60,
            durationMinutes: 60
        )

        let ranges = CadenceScheduleSupport.busyMinuteRanges(tasks: [task], bundles: [bundle])
        #expect(ranges.contains(9 * 60..<(9 * 60 + 45)))
        #expect(ranges.contains(14 * 60..<15 * 60))
    }

    @Test func anUnscheduledTaskContributesNoBusyRange() {
        let task = AppTask(title: "Someday")
        task.scheduledStartMin = -1
        #expect(CadenceScheduleSupport.busyMinuteRanges(tasks: [task], bundles: []).isEmpty)
    }
}
