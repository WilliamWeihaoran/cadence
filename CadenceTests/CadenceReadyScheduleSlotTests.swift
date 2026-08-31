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

/// **T-585.** The chips checked 30 minutes of free time and then inserted a task of any length.
///
/// `iOSSchedulePanel` called `readyScheduleSlots` with no `durationMinutes:`, so the collision
/// check ran against the 30-minute default for every row. Tapping a chip calls
/// `CadenceTaskDateEditing.setScheduledSlot`, which writes the *start* only — the block that lands
/// is `AppTask.timelineDurationMinutes` tall. A task whose own subtitle in that row reads
/// "90 min estimate" was therefore offered a slot cleared for 30 and drew through the block below.
///
/// The pane still resolves the *day* once — `CadenceScheduleSupport.ReadyScheduleContext` — and
/// each row derives its own start times from it. "Every row offers the same times" could not be
/// kept: with different lengths, one answer for every row is the wrong answer for all but one of
/// them. What is kept is that every row reads one clock, one work window and one set of busy
/// ranges, which is the half that makes a filled slot leave every row at once.
struct CadenceReadyScheduleDurationTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func time(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = hour
        components.minute = minute
        return Self.calendar.date(from: components)!
    }

    private func context(
        at hour: Int,
        _ minute: Int = 0,
        workStart: Int = 9 * 60,
        workEnd: Int = 17 * 60,
        busy: [Range<Int>] = []
    ) -> CadenceScheduleSupport.ReadyScheduleContext {
        CadenceScheduleSupport.ReadyScheduleContext(
            now: Self.time(hour, minute),
            workStartMinute: workStart,
            workEndMinute: workEnd,
            busyRanges: busy,
            calendar: Self.calendar
        )
    }

    /// The reported defect, as arithmetic. 10:30–11:00 is booked; 10:00 clears a 30-minute block
    /// exactly and cannot hold a 90-minute one. The old pane offered 10:00 to both.
    @Test func aLongTaskIsNotOfferedAStartThatOnlyAThirtyMinuteBlockFitsInto() {
        let day = context(at: 8, busy: [10 * 60 + 30..<11 * 60])
        // `count` past the size of the pool so `spread` returns it whole and membership is the
        // property under test rather than which three were picked out of it.
        let short = day.slots(forDurationMinutes: 30, count: 40)
        let long = day.slots(forDurationMinutes: 90, count: 40)

        #expect(short.contains(10 * 60), "a 30-minute block ends exactly as the booking begins")
        #expect(!long.contains(10 * 60), "10:00 + 90 minutes runs through the 10:30 booking")
        #expect(long.contains(9 * 60), "9:00 + 90 minutes ends exactly as the booking begins")
        #expect(long.allSatisfy { start in
            !(start < 11 * 60 && 10 * 60 + 30 < start + 90)
        })
    }

    /// The length the chip is checked against is the length the chip writes — the row's own task,
    /// not a constant. `timelineDurationMinutes`, because that is what `scheduledEndMin` and the
    /// timeline block both read.
    @Test func theCheckedLengthIsTheBlockTheChipActuallyWrites() {
        let task = AppTask(title: "Draft the deck")
        task.estimatedMinutes = 90
        #expect(task.timelineDurationMinutes == 90)

        let day = context(at: 8, busy: [10 * 60 + 30..<11 * 60])
        for start in day.slots(forDurationMinutes: task.timelineDurationMinutes, count: 40) {
            let end = start + task.timelineDurationMinutes
            #expect(!day.busyRanges.contains { $0.lowerBound < end && start < $0.upperBound })
        }
    }

    /// An estimate-less task is still a 30-minute block, so it keeps exactly the answer the pane
    /// used to give everybody. The fix is invisible except where it mattered.
    @Test func anEstimatelessTaskGetsTheSameSlotsTheOldSharedAnswerGave() {
        let task = AppTask(title: "Something")
        // Zero is the only value that means "unset" — see `AppTask.timelineDurationMinutes`. The
        // initialiser's own default is 30, so an estimate-less task has to be spelled.
        task.estimatedMinutes = 0
        #expect(task.timelineDurationMinutes == AppTask.defaultTimelineDurationMinutes)
        #expect(task.timelineDurationMinutes == 30)

        let day = context(at: 8, busy: [10 * 60 + 30..<11 * 60])
        #expect(
            day.slots(forDurationMinutes: task.timelineDurationMinutes)
                == CadenceScheduleSupport.readyScheduleSlots(
                    now: Self.time(8),
                    workStartMinute: 9 * 60,
                    workEndMinute: 17 * 60,
                    busyRanges: [10 * 60 + 30..<11 * 60],
                    calendar: Self.calendar
                )
        )
    }

    /// A long block is not offered a start it cannot finish inside the day. The 23:30 chip that is
    /// the honest last answer for a 30-minute task is a 1 AM finish for a 90-minute one.
    @Test func aLongTaskIsNeverOfferedAStartThatRunsPastMidnight() {
        for minutes in [30, 45, 90, 120, 240] {
            let offered = context(at: 22).slots(forDurationMinutes: minutes, count: 40)
            #expect(!offered.isEmpty)
            #expect(offered.allSatisfy { $0 + minutes <= 24 * 60 }, "\(minutes) minutes overran the day")
        }
        #expect(context(at: 22).slots(forDurationMinutes: 30, count: 40).last == 23 * 60 + 30)
        #expect(context(at: 22).slots(forDurationMinutes: 90, count: 40).last == 22 * 60 + 30)
    }

    /// The half of "once per pane" that survived: one day drives every length, so a slot that has
    /// just been filled leaves the short task's chips and the long task's chips together.
    @Test func fillingASlotRemovesItFromEveryLengthAtOnce() {
        let before = context(at: 8)
        let landed = AppTask(title: "Standup")
        landed.scheduledStartMin = 11 * 60
        landed.estimatedMinutes = 60
        let after = context(
            at: 8,
            busy: CadenceScheduleSupport.busyMinuteRanges(tasks: [landed], bundles: [])
        )

        for minutes in [30, 90] {
            #expect(before.slots(forDurationMinutes: minutes, count: 40).contains(11 * 60))
            #expect(!after.slots(forDurationMinutes: minutes, count: 40).contains(11 * 60))
        }
    }

    /// A whole day of bookings still offers something, at every length — the never-empty rule the
    /// 30-minute answer already had. The chips are the row's only actions.
    @Test func aFullDayStillOffersSomethingAtEveryLength() {
        for hour in 0...23 {
            for minutes in [30, 90, 180] {
                #expect(!context(at: hour, busy: [0..<24 * 60]).slots(forDurationMinutes: minutes).isEmpty)
            }
        }
    }

    // MARK: - The pane

    /// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the pane cannot
    /// be compiled here — this is the source shape that hands the arithmetic above its input.
    @Test func theReadyStackDerivesEachRowsChipsFromThatRowsTaskLength() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        #expect(raw.count > 400, "iOSTodaySchedulePanel.swift read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")

        #expect(
            CadenceSourceScan.matchCount(#"readyScheduleSlots\("#, in: source) == 0,
            "the pane calls readyScheduleSlots directly again — the call it used to make passed no length"
        )
        #expect(
            source.contains("context.slots(forDurationMinutes: task.timelineDurationMinutes)"),
            "the row no longer derives its chips from its own task's length"
        )
        #expect(
            CadenceSourceScan.matchCount(#"ReadyScheduleContext\("#, in: source) == 1,
            "the day should be resolved once for the pane, not per row"
        )
    }

    /// The needles above match what they hunt and miss what they protect.
    @Test func theReadyStackNeedlesMatchTheOldSpellingOnly() {
        #expect(CadenceSourceScan.matchCount(
            #"readyScheduleSlots\("#,
            in: "CadenceScheduleSupport.readyScheduleSlots(\n workStartMinute: a,"
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"readyScheduleSlots\("#,
            in: "context.slots(forDurationMinutes: task.timelineDurationMinutes)"
        ) == 0)
        #expect(CadenceSourceScan.matchCount(
            #"ReadyScheduleContext\("#,
            in: "CadenceScheduleSupport.ReadyScheduleContext(\n workStartMinute: a,"
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"ReadyScheduleContext\("#,
            in: "let context: CadenceScheduleSupport.ReadyScheduleContext"
        ) == 0)
    }
}
