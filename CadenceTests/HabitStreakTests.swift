//
//  HabitStreakTests.swift
//  CadenceTests
//
//  Regression coverage for Habit model computation logic: currentStreak (daily / daysOfWeek /
//  timesPerWeek / monthly), frequencyDays JSON round-tripping, reminderMinuteOfDay validation,
//  and HabitCompletion.count vs targetCount day-satisfaction. Several rows for one day
//  collapse to the largest rather than adding (T-359); the argument is in
//  CadenceHabitCompletionDuplicateTests.
//

import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct HabitStreakTests {

    // MARK: - Helpers

    private static func gregorian(timeZoneIdentifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .init(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    @discardableResult
    private static func complete(_ habit: Habit, on key: String, count: Int = 1, context: ModelContext) -> HabitCompletion {
        let completion = HabitCompletion(date: key, habit: habit)
        completion.count = count
        context.insert(completion)
        habit.completions = (habit.completions ?? []) + [completion]
        return completion
    }

    // MARK: - 1. Daily streak: "today pending" semantics

    @Test func dailyStreakCountsTodayWhenTodayIsCompleted() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()
        let today = Self.date(2026, 3, 10, calendar: cal)

        let habit = Habit(title: "Meditate")
        habit.frequencyType = .daily
        context.insert(habit)
        for day in 6...10 {
            Self.complete(habit, on: Self.key(2026, 3, day), context: context)
        }
        try context.save()

        #expect(habit.currentStreak(asOf: today, calendar: cal) == 5)
    }

    @Test func dailyStreakForgivesUnfinishedTodayButStillCountsThroughYesterday() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()
        let today = Self.date(2026, 3, 10, calendar: cal)

        let habit = Habit(title: "Meditate")
        habit.frequencyType = .daily
        context.insert(habit)
        for day in 6...9 {
            Self.complete(habit, on: Self.key(2026, 3, day), context: context)
        }
        // Today (Mar 10) intentionally left incomplete.
        try context.save()

        #expect(habit.currentStreak(asOf: today, calendar: cal) == 4)
    }

    @Test func dailyStreakIsZeroWhenBothTodayAndYesterdayAreIncomplete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()
        let today = Self.date(2026, 3, 10, calendar: cal)

        let habit = Habit(title: "Meditate")
        habit.frequencyType = .daily
        context.insert(habit)
        // A real streak exists further back, but it's already dead since both today and
        // yesterday are missing — only a single day of grace ("today") is ever forgiven.
        for day in 1...7 {
            Self.complete(habit, on: Self.key(2026, 3, day), context: context)
        }
        try context.save()

        #expect(habit.currentStreak(asOf: today, calendar: cal) == 0)
    }

    // MARK: - 2. daysOfWeek: skips non-scheduled days, across week and month boundaries

    @Test func daysOfWeekStreakSkipsNonScheduledDaysAcrossWeekAndMonthBoundary() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        // Jan 1, 2024 is a Monday. Schedule Mon/Wed/Fri (weekdayIndex 1/3/5) and complete every
        // due day from Jan 1 through Feb 2 (a Friday), crossing both a Sun->Mon week boundary
        // and the Jan->Feb month boundary along the way.
        let habit = Habit(title: "Gym")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = [1, 3, 5]
        context.insert(habit)

        let dueDays: [(Int, Int, Int)] = [
            (2024, 1, 1), (2024, 1, 3), (2024, 1, 5),
            (2024, 1, 8), (2024, 1, 10), (2024, 1, 12),
            (2024, 1, 15), (2024, 1, 17), (2024, 1, 19),
            (2024, 1, 22), (2024, 1, 24), (2024, 1, 26),
            (2024, 1, 29), (2024, 1, 31),
            (2024, 2, 2)
        ]
        for (y, m, d) in dueDays {
            Self.complete(habit, on: Self.key(y, m, d), context: context)
        }
        try context.save()

        let today = Self.date(2024, 2, 2, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == dueDays.count)

        // Evaluating on a non-scheduled day (Saturday Feb 3) should still find Friday Feb 2 as
        // the most recent due day and report the same streak length.
        let saturday = Self.date(2024, 2, 3, calendar: cal)
        #expect(habit.currentStreak(asOf: saturday, calendar: cal) == dueDays.count)
    }

    @Test func daysOfWeekStreakBreaksOnlyOnMissedScheduledDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Gym")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = [1, 3, 5]
        context.insert(habit)

        // Jan 17 (a due Wednesday) is skipped — the streak should reset there, then rebuild
        // through Feb 2 without being derailed by the intervening non-scheduled days.
        let dueDaysAfterGap: [(Int, Int, Int)] = [
            (2024, 1, 19), (2024, 1, 22), (2024, 1, 24), (2024, 1, 26),
            (2024, 1, 29), (2024, 1, 31), (2024, 2, 2)
        ]
        Self.complete(habit, on: Self.key(2024, 1, 1), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 3), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 5), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 8), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 10), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 12), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 15), context: context)
        // Jan 17 deliberately NOT completed.
        for (y, m, d) in dueDaysAfterGap {
            Self.complete(habit, on: Self.key(y, m, d), context: context)
        }
        try context.save()

        let today = Self.date(2024, 2, 2, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == dueDaysAfterGap.count)
    }

    @Test func daysOfWeekStreakIsZeroWhenNoDaysAreScheduled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Nothing scheduled")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = []
        context.insert(habit)
        Self.complete(habit, on: Self.key(2026, 3, 10), context: context)
        try context.save()

        let today = Self.date(2026, 3, 10, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 0)
    }

    // MARK: - 3. timesPerWeek: Monday-start week definition, no off-by-one at boundaries

    @Test func timesPerWeekStreakCountsConsecutiveSatisfiedWeeksAndForgivesInProgressWeek() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Run twice a week")
        habit.frequencyType = .timesPerWeek
        habit.targetCount = 2
        context.insert(habit)

        // Week 1 (Jan 1-7, 2024): satisfied. Week 2 (Jan 8-14): satisfied.
        // Week 3 (Jan 15-21): only 1 completion so far — but "today" (Jan 20) is still inside
        // this in-progress week, so it should be forgiven rather than counted as a break.
        Self.complete(habit, on: Self.key(2024, 1, 2), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 4), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 9), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 11), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 16), context: context)
        try context.save()

        let today = Self.date(2024, 1, 20, calendar: cal) // Saturday, inside week 3
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 2)
    }

    @Test func timesPerWeekStreakDoesNotCombineCompletionsAcrossTheWeekBoundary() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Run twice a week")
        habit.frequencyType = .timesPerWeek
        habit.targetCount = 2
        context.insert(habit)

        // One completion on the last day of week 1 (Sunday Jan 7) and one on the first day of
        // week 2 (Monday Jan 8). Neither week individually reaches the target of 2, so these
        // must NOT be summed together across the Sun/Mon boundary.
        Self.complete(habit, on: Self.key(2024, 1, 7), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 8), context: context)
        try context.save()

        let today = Self.date(2024, 1, 8, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 0)
    }

    @Test func timesPerWeekStreakSatisfiedByCountAnywhereInTheWeek() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Run twice a week")
        habit.frequencyType = .timesPerWeek
        habit.targetCount = 2
        context.insert(habit)

        // Both completions land back-to-back near the end of the (already-elapsed) week —
        // still satisfies that week regardless of which days within it were used.
        Self.complete(habit, on: Self.key(2024, 1, 6), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 7), context: context)
        try context.save()

        let today = Self.date(2024, 1, 10, calendar: cal) // Wednesday of the following week
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 1)
    }

    // MARK: - 4. Monthly: variable month lengths and year boundary

    @Test func monthlyStreakClampsToShorterMonthsAndCrossesYearBoundary() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Pay rent")
        habit.frequencyType = .monthly
        habit.frequencyDays = [31] // clamps to each month's actual last day
        context.insert(habit)

        // Nov 2023 (30 days) -> clamps to Nov 30. Dec 2023 (31 days) -> Dec 31 (year boundary
        // immediately follows). Jan 2024 (31 days) -> Jan 31. Feb 2024 (leap, 29 days) -> Feb 29.
        Self.complete(habit, on: Self.key(2023, 11, 30), context: context)
        Self.complete(habit, on: Self.key(2023, 12, 31), context: context)
        Self.complete(habit, on: Self.key(2024, 1, 31), context: context)
        Self.complete(habit, on: Self.key(2024, 2, 29), context: context)
        try context.save()

        let today = Self.date(2024, 2, 29, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 4)
    }

    @Test func monthlyStreakClampsToNonLeapFebruary() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Pay rent")
        habit.frequencyType = .monthly
        habit.frequencyDays = [31]
        context.insert(habit)

        Self.complete(habit, on: Self.key(2023, 1, 31), context: context)
        Self.complete(habit, on: Self.key(2023, 2, 28), context: context) // clamped, non-leap
        Self.complete(habit, on: Self.key(2023, 3, 31), context: context)
        try context.save()

        let today = Self.date(2023, 3, 31, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 3)
    }

    // MARK: - 5. DST transitions (America/New_York)

    @Test func dailyStreakSurvivesSpringForwardDSTTransition() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let nyCal = Self.gregorian(timeZoneIdentifier: "America/New_York")

        let habit = Habit(title: "Journal")
        habit.frequencyType = .daily
        context.insert(habit)

        // 2023-03-12 is the US spring-forward date (2:00 AM -> 3:00 AM does not exist).
        for (y, m, d) in [(2023, 3, 10), (2023, 3, 11), (2023, 3, 12), (2023, 3, 13)] {
            Self.complete(habit, on: Self.key(y, m, d), context: context)
        }
        try context.save()

        let today = Self.date(2023, 3, 13, calendar: nyCal)
        #expect(habit.currentStreak(asOf: today, calendar: nyCal) == 4)
    }

    @Test func dailyStreakSurvivesFallBackDSTTransition() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let nyCal = Self.gregorian(timeZoneIdentifier: "America/New_York")

        let habit = Habit(title: "Journal")
        habit.frequencyType = .daily
        context.insert(habit)

        // 2023-11-05 is the US fall-back date (1:00-2:00 AM occurs twice).
        for (y, m, d) in [(2023, 11, 4), (2023, 11, 5), (2023, 11, 6)] {
            Self.complete(habit, on: Self.key(y, m, d), context: context)
        }
        try context.save()

        let today = Self.date(2023, 11, 6, calendar: nyCal)
        #expect(habit.currentStreak(asOf: today, calendar: nyCal) == 3)
    }

    // MARK: - 6. frequencyDays JSON round-tripping

    @Test func frequencyDaysRoundTripsEmptyAndFullWeekSelections() throws {
        let habit = Habit(title: "Test")
        habit.frequencyDays = []
        #expect(habit.frequencyDays == [])
        #expect(habit.frequencyDaysRaw == "[]")

        habit.frequencyDays = [1, 2, 3, 4, 5, 6, 7]
        #expect(habit.frequencyDays == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func frequencyDaysRoundTripsOutOfRangeValuesWithoutCrashing() throws {
        let habit = Habit(title: "Test")
        habit.frequencyDays = [0, 8, -1, 100]
        #expect(habit.frequencyDays == [0, 8, -1, 100])
    }

    @Test func frequencyDaysDegradesGracefullyOnCorruptRawJSON() throws {
        let habit = Habit(title: "Test")
        habit.frequencyDaysRaw = "not valid json at all"
        #expect(habit.frequencyDays == [])

        habit.frequencyDaysRaw = "{\"not\": \"an array\"}"
        #expect(habit.frequencyDays == [])

        habit.frequencyDaysRaw = "[\"one\", \"two\"]" // wrong element type
        #expect(habit.frequencyDays == [])
    }

    // MARK: - 7. reminderMinuteOfDay validation

    @Test func reminderMinuteOfDayNilMeansNoReminderAndIsNotConfusedWithMidnight() throws {
        let habit = Habit(title: "Test")
        #expect(habit.reminderMinuteOfDay == nil)

        habit.reminderMinuteOfDay = 0
        #expect(habit.reminderMinuteOfDay == 0)
        #expect(habit.reminderMinuteOfDay != nil)

        habit.reminderMinuteOfDay = nil
        #expect(habit.reminderMinuteOfDay == nil)
    }

    /// Audit finding (documented, not silently "fixed"): `reminderMinuteOfDay` has no range
    /// validation at the model layer today. `@Model`'s macro-generated accessors silently
    /// ignore a plain Swift `didSet` on a stored property (verified empirically — adding one
    /// compiles cleanly but never fires), so enforcing 0...1439 here would require switching to
    /// the same raw-storage + computed-property pattern `frequencyDays` already uses, which
    /// renames the persisted attribute. With no `SchemaMigrationPlan` in `CadenceSchema.swift`,
    /// that rename would silently drop any reminder time already stored in existing user data —
    /// out of proportion for this pass. This test locks in the current (unclamped) behavior so
    /// a future migration-aware fix has a regression test to update rather than leaving this
    /// gap silently undocumented.
    ///
    /// The gap is still at the **model** layer, and only there. Two later passes put the check
    /// where the value is used instead: `HabitNotificationPlanner.reminderMinuteRange` (T-363),
    /// which refuses to schedule an out-of-range minute, and `CadenceHabitReminderEditing`
    /// (T-410), which opens both habit editors on "unset" rather than a fabricated time. So a
    /// corrupt value still round-trips through `Habit` exactly as asserted below; what changed is
    /// that nothing downstream pretends it is a time.
    @Test func reminderMinuteOfDayHasNoRangeValidationTodayByDesignGap() throws {
        let habit = Habit(title: "Test")

        habit.reminderMinuteOfDay = -15
        #expect(habit.reminderMinuteOfDay == -15)

        habit.reminderMinuteOfDay = 1440
        #expect(habit.reminderMinuteOfDay == 1440)

        habit.reminderMinuteOfDay = 540 // 9:00 AM — a normal in-range value round-trips fine
        #expect(habit.reminderMinuteOfDay == 540)
    }

    // MARK: - 8. HabitCompletion.count vs targetCount day-satisfaction

    @Test func dailyStreakRequiresCompletionCountToMeetTargetCount() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Drink water 3x")
        habit.frequencyType = .daily
        habit.targetCount = 3
        context.insert(habit)

        // Mar 8 & 9 fully met (count 3); Mar 10 only has a single check-in (count 1) — should
        // NOT satisfy the day even though a completion record exists for it.
        Self.complete(habit, on: Self.key(2026, 3, 8), count: 3, context: context)
        Self.complete(habit, on: Self.key(2026, 3, 9), count: 3, context: context)
        Self.complete(habit, on: Self.key(2026, 3, 10), count: 1, context: context)
        try context.save()

        let today = Self.date(2026, 3, 10, calendar: cal)
        // Today (Mar 10) is unsatisfied but is "today", so it's forgiven; the streak should
        // reflect Mar 8-9 only.
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 2)
    }

    /// This test used to assert the opposite — that two rows for one day **add**, so `count 2` plus
    /// `count 1` met a `targetCount` of 3. T-359 reversed it: several rows for one habit-day are
    /// what two devices checking in produce, not a quantity the user split, and adding them let one
    /// check-in satisfy a target. The day is now worth its largest row.
    ///
    /// The value that the old spelling protected is not lost, because nothing writes it: no path in
    /// the app increments an existing row, so a day genuinely worth 3 is one row of 3, and `max`
    /// reads that unchanged. `CadenceHabitCompletionDuplicateTests` carries the full argument.
    @Test func dailyStreakCollapsesMultipleRecordsForOneDayToTheLargest() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Drink water 3x")
        habit.frequencyType = .daily
        habit.targetCount = 3
        context.insert(habit)

        Self.complete(habit, on: Self.key(2026, 3, 9), count: 2, context: context)
        Self.complete(habit, on: Self.key(2026, 3, 9), count: 1, context: context)
        try context.save()

        // Mar 9 is worth 2, not 3, so it never met the target and there is no streak to carry.
        #expect(habit.completionCountsByDate()[Self.key(2026, 3, 9)] == 2)
        let today = Self.date(2026, 3, 10, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 0)
    }

    @Test func daysOfWeekTargetCountRepresentsSelectedDayCountNotPerDayQuantity() throws {
        // For .daysOfWeek, targetCount mirrors the number of selected days per week — it must
        // NOT be treated as a per-day completion quantity requirement.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let cal = Self.gregorian()

        let habit = Habit(title: "Gym 3x/week")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = [1, 3, 5] // Mon/Wed/Fri
        habit.targetCount = 3 // number of selected days, not a per-day quantity

        context.insert(habit)
        // A single check-in (count 1) per scheduled day should be enough.
        Self.complete(habit, on: Self.key(2024, 1, 1), count: 1, context: context)
        Self.complete(habit, on: Self.key(2024, 1, 3), count: 1, context: context)
        Self.complete(habit, on: Self.key(2024, 1, 5), count: 1, context: context)
        try context.save()

        let today = Self.date(2024, 1, 5, calendar: cal)
        #expect(habit.currentStreak(asOf: today, calendar: cal) == 3)
    }
}
