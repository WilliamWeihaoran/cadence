import Foundation
import Testing
@testable import Cadence

/// A `.timesPerWeek` habit's target has to be reachable, because `Habit.currentStreak` measures
/// it literally: a week counts only when its summed completions meet `targetCount`.
///
/// Completion is a per-day toggle on both platforms — there is no counter UI — so a week can
/// contribute at most seven. The iOS frequency editor offered `1...14`, which put a permanently
/// unsatisfiable target two taps away: the habit then read "10x/week · no streak" forever, on
/// both platforms. macOS's stepper stopped at 7 but never clamped an existing value down, so
/// opening and saving such a habit wrote 10 straight back.
@MainActor
struct HabitWeeklyTargetTests {
    @Test func theWeeklyTargetRangeCannotExceedTheDaysInAWeek() {
        #expect(HabitFrequency.weeklyTargetRange == 1...7)
    }

    @Test func storedTargetsAreClampedIntoTheSelectableRange() {
        #expect(HabitFrequency.clampedWeeklyTarget(10) == 7)
        #expect(HabitFrequency.clampedWeeklyTarget(14) == 7)
        #expect(HabitFrequency.clampedWeeklyTarget(0) == 1)
        #expect(HabitFrequency.clampedWeeklyTarget(-3) == 1)
        #expect(HabitFrequency.clampedWeeklyTarget(3) == 3)
    }

    /// The reason the cap exists, stated as behaviour: a target above seven can never be met even
    /// by a perfect week, so the streak it reports is a permanent zero.
    @Test func aTargetAboveSevenIsUnreachableEvenWithACompletionEveryDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let today = try #require(DateFormatters.date(from: "2026-08-11"))

        func habit(target: Int) -> Habit {
            let habit = Habit(title: "Move")
            habit.frequencyType = .timesPerWeek
            habit.targetCount = target
            habit.frequencyDays = [target]
            habit.completions = (0..<21).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return HabitCompletion(date: DateFormatters.dateKey(from: day, calendar: calendar), habit: habit)
            }
            return habit
        }

        #expect(habit(target: 10).currentStreak(asOf: today, calendar: calendar) == 0)
        #expect(habit(target: HabitFrequency.clampedWeeklyTarget(10)).currentStreak(asOf: today, calendar: calendar) > 0)
    }
}
