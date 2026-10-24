import Foundation
import Testing
@testable import Cadence

/// **[[T-5012]] (a) — a habit's "done today" and "due today" are answered against a day KEY.**
///
/// Both platforms' Habits pages computed `todayKey` from the clock in a body whose inputs are the
/// same on both sides of midnight, so a page left open overnight kept "Done today" on yesterday's
/// tick. T-5012 gave each page one `CadenceObservedDay` and handed its key down.
///
/// **[[T-5002]] deleted both pages**, with `HabitListFilter` and every view that read it, so the
/// three wire tests this suite carried — `theMacPageFiltersAndRendersAgainstItsObservedDay`,
/// `theIOSPageHandsItsObservedDayToItsRows` and `rowsAndDetailsAskTheObservedDayWhetherTheHabitIsDue`
/// — now have no subject; their absence is pinned by
/// `CadenceCodexTrackingUIRetirementTests.codexRetiredTrackingViewsAreGoneFromTheTree`.
///
/// What survives is the half the pages were only ever a caller of, and it still has live readers:
/// `CadenceHabitWidgetSupport`, `CadenceFocusPlanningSupport` and `CadenceCompactShellSupport` all
/// ask `Habit.isDone(on:)` / `Habit.isDue(onDayKey:)` with a key someone handed them. So these two
/// tests are re-pointed at the model methods the deleted filter was a wrapper over, rather than
/// deleted with it: the rollover claim is the claim, and it was never the view's.
@MainActor
struct CadenceHabitsObservedDayTests {

    @Test func aHabitTickedYesterdayIsNotDoneOnceTheDayTurns() {
        let habit = Habit(title: "Stretch")
        habit.frequencyType = .daily
        habit.completions = [HabitCompletion(date: "2026-10-21", habit: habit)]

        #expect(habit.isDone(on: "2026-10-21"))
        #expect(!habit.isDone(on: "2026-10-22"))
    }

    @Test func dueTodayFollowsTheObservedDaysWeekday() {
        let habit = Habit(title: "Laundry")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = [4] // Thursday; 2026-10-22 is a Thursday.

        #expect(habit.isDue(onDayKey: "2026-10-22"))
        #expect(!habit.isDue(onDayKey: "2026-10-23"))
    }

    /// Non-vacuity for the pair above, and the one asymmetry between the two methods, stated
    /// rather than discovered later: a completion is a SET MEMBERSHIP, so a key nothing can parse
    /// is simply not in it — while `isDue(onDayKey:)` documents a deliberate fall back to the
    /// clock, so an unreadable key answers for *today* instead of answering "no". Asserted as a
    /// relation against `isDueToday` rather than as a fixed value, because the right answer here
    /// moves with the day the test runs on.
    @Test func anUnreadableKeyIsNotDoneAndFallsBackToTheClockForDue() {
        let habit = Habit(title: "Stretch")
        habit.frequencyType = .daily
        habit.completions = [HabitCompletion(date: "2026-10-21", habit: habit)]

        #expect(!habit.isDone(on: "not a day"))
        #expect(habit.isDue(onDayKey: "not a day") == habit.isDueToday)
    }
}
