import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Cadence

/// Covers the habit numbers that are *rendered next to each other* and therefore have to agree.
/// `HabitStreakTests` covers `currentStreak` thoroughly and everything it covers is correct; the
/// gap was that nothing asserted any two habit figures were mutually consistent.
@MainActor
struct HabitInsightsAuditTests {
    private func makeHabit(
        frequency: HabitFrequency,
        days: [Int] = [],
        targetCount: Int = 1
    ) -> Habit {
        let habit = Habit(title: "Test")
        habit.frequencyType = frequency
        habit.frequencyDays = days
        habit.targetCount = targetCount
        return habit
    }

    private func complete(_ habit: Habit, _ keys: [String], count: Int = 1) {
        var rows = habit.completions ?? []
        for key in keys {
            let completion = HabitCompletion(date: key, habit: habit)
            completion.count = count
            rows.append(completion)
        }
        habit.completions = rows
    }

    /// The headline defect: a Mon/Wed/Fri habit kept perfectly reported Current 24d, Best 1d,
    /// because the old `bestStreak` counted consecutive *calendar* days and no two completions
    /// of a Mon/Wed/Fri habit are ever adjacent.
    @Test func bestStreakUsesDueDaysNotCalendarDaysForScheduledHabits() {
        // 2026-04-27 is a Monday. Eight weeks of Mon/Wed/Fri, ending Friday 2026-06-19.
        let habit = makeHabit(frequency: .daysOfWeek, days: [1, 3, 5])
        var keys: [String] = []
        let calendar = Calendar.current
        var cursor = DateFormatters.date(from: "2026-04-27") ?? Date()
        for _ in 0..<8 {
            for offset in [0, 2, 4] {
                if let day = calendar.date(byAdding: .day, value: offset, to: cursor) {
                    keys.append(DateFormatters.dateKey(from: day))
                }
            }
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
        }
        complete(habit, keys)

        let asOf = DateFormatters.date(from: "2026-06-19") ?? Date()
        let current = habit.currentStreak(asOf: asOf)
        let best = habit.bestStreak(asOf: asOf)

        #expect(current == 24)
        #expect(best == 24)
        #expect(best >= current)
    }

    /// The other half of the old implementation's incoherence: a hard 366-day scan window meant
    /// a longer daily streak reported a "best" *below* its own "current".
    @Test func bestStreakIsNeverLessThanCurrentStreakBeyondAYear() {
        let habit = makeHabit(frequency: .daily)
        let calendar = Calendar.current
        let end = DateFormatters.date(from: "2026-06-19") ?? Date()
        var keys: [String] = []
        for offset in 0..<500 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: end) {
                keys.append(DateFormatters.dateKey(from: day))
            }
        }
        complete(habit, keys)

        let current = habit.currentStreak(asOf: end)
        let best = habit.bestStreak(asOf: end)

        #expect(current == 500)
        #expect(best == 500)
    }

    /// A break in the middle must still be found, and the run before it must win when it is longer
    /// than the run since.
    @Test func bestStreakReportsTheLongestHistoricalRunNotTheMostRecent() {
        let habit = makeHabit(frequency: .daily)
        complete(habit, [
            "2026-04-01", "2026-04-02", "2026-04-03", "2026-04-04", "2026-04-05",
            // 2026-04-06 missed
            "2026-04-07", "2026-04-08",
        ])

        let asOf = DateFormatters.date(from: "2026-04-08") ?? Date()
        #expect(habit.bestStreak(asOf: asOf) == 5)
        #expect(habit.currentStreak(asOf: asOf) == 2)
    }

    /// `.timesPerWeek` streaks are counted in weeks, so "best" has to be too — otherwise the two
    /// tiles report different units under the same pair of labels.
    @Test func bestStreakCountsWeeksForTimesPerWeekHabits() {
        let habit = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        // ISO weeks starting Mon 2026-04-27, 2026-05-04, 2026-05-11 — three satisfied weeks.
        complete(habit, [
            "2026-04-27", "2026-04-29", "2026-05-01",
            "2026-05-04", "2026-05-06", "2026-05-08",
            "2026-05-11", "2026-05-13", "2026-05-15",
        ])

        let asOf = DateFormatters.date(from: "2026-05-15") ?? Date()
        #expect(habit.bestStreak(asOf: asOf) == 3)
        #expect(habit.currentStreak(asOf: asOf) == 3)
    }

    @Test func bestStreakIsZeroWithNoCompletions() {
        #expect(makeHabit(frequency: .daily).bestStreak() == 0)
    }

    /// The walk is bounded, and the bound must be anchored at **today** rather than at the first
    /// check-in. Anchoring it at the earliest completion meant one stray backdated or imported row
    /// from years ago pushed all recent history outside the window — an unbroken 100-day streak
    /// reported a "best" of 1, which is worse than the 366-day cap this replaced.
    @Test func aVeryOldStrayCompletionDoesNotPushRecentHistoryOutOfTheWindow() {
        let habit = makeHabit(frequency: .daily)
        let calendar = Calendar.current
        let today = DateFormatters.date(from: "2026-06-19") ?? Date()

        var keys: [String] = []
        for offset in 0..<100 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                keys.append(DateFormatters.dateKey(from: day))
            }
        }
        // One row from fifteen years ago, well outside any sane iteration bound.
        if let ancient = calendar.date(byAdding: .year, value: -15, to: today) {
            keys.append(DateFormatters.dateKey(from: ancient))
        }
        complete(habit, keys)

        #expect(habit.currentStreak(asOf: today) == 100)
        #expect(habit.bestStreak(asOf: today) == 100)
    }

    /// `date(byAdding: .day,)` preserves wall-clock time, so a spring-forward that happens *at
    /// midnight* — Santiago and Havana, not New York — drifts the cursor to 01:00 permanently.
    /// Once drifted, a `startOfDay`-bounded comparison silently drops a day at the boundary, and
    /// the day it dropped was today.
    @Test func bestStreakSurvivesAMidnightDSTTransition() {
        var calendar = Calendar(identifier: .gregorian)
        guard let santiago = TimeZone(identifier: "America/Santiago") else {
            Issue.record("America/Santiago unavailable")
            return
        }
        calendar.timeZone = santiago

        let habit = makeHabit(frequency: .daily)
        // 2026-09-06 is a midnight spring-forward in Santiago; span it in both directions.
        guard let end = DateFormatters.date(from: "2026-09-25", in: calendar) else {
            Issue.record("could not build reference date")
            return
        }
        var keys: [String] = []
        for offset in 0..<50 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: end) {
                keys.append(DateFormatters.dateKey(from: day, calendar: calendar))
            }
        }
        complete(habit, keys)

        let current = habit.currentStreak(asOf: end, calendar: calendar)
        let best = habit.bestStreak(asOf: end, calendar: calendar)

        #expect(current == 50)
        #expect(best == 50)
        #expect(best >= current)
    }

    /// `HabitInsights.bestStreak` is the *property*, and it is the only thing the iOS detail view
    /// reads. Every other test here calls the method, so reverting the property to the old
    /// calendar-day scan left the whole suite green while the shipped tile stayed wrong.
    @Test func theBestStreakPropertyTheUIReadsUsesTheFrequencyAwareWalk() {
        let habit = makeHabit(frequency: .daysOfWeek, days: [1, 3, 5])
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Six weeks of this habit's *own* due days, counted back from today, so the property's
        // built-in `Date()` sees a real streak. No two of these are consecutive calendar days,
        // which is exactly what the old implementation could not count.
        var keys: [String] = []
        var found = 0
        var offset = 0
        while found < 18, offset < 200 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today),
               habit.isDue(on: day, calendar: calendar) {
                keys.append(DateFormatters.dateKey(from: day, calendar: calendar))
                found += 1
            }
            offset += 1
        }
        complete(habit, keys)

        #expect(habit.bestStreak == 18)
        #expect(habit.bestStreak >= habit.currentStreak)
    }

    /// A habit reminder is a standing "every day at this time". Building it as a one-shot trigger
    /// matched on `.year/.month/.day` meant it fired once and was then consumed — only a
    /// `scenePhase` reconcile could re-add it, so leaving the app open ended the reminder
    /// silently. Task reminders are the opposite: they belong to one dated task and must not
    /// repeat.
    @Test func onlyHabitRemindersRepeatAndTheyMatchOnTimeOfDayAlone() {
        #expect(NotificationKind.habitReminder.repeatsDaily == true)
        #expect(NotificationKind.habitReminder.triggerComponents == [.hour, .minute])

        for kind in [NotificationKind.taskStart, .taskDue] {
            #expect(kind.repeatsDaily == false)
            #expect(kind.triggerComponents.contains(.day))
            #expect(kind.triggerComponents.contains(.year))
        }
    }

    /// Asserting the enum alone proved nothing: `NotificationManager` built the trigger inline, so
    /// reverting the adapter to a hardcoded one-shot left this file green while the OS still got a
    /// reminder that fired once. `triggerSpec` is the value the manager actually passes, and
    /// `reconcile` early-returns under test, so this is the only place the two can be tied
    /// together.
    @Test func theTriggerSpecTheManagerSchedulesMatchesTheKindsRepeatRules() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let fireDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 9, minute: 30)) ?? Date()

        let habitSpec = CadenceNotificationRequest(
            identifier: "habit-reminder-x",
            kind: .habitReminder,
            title: "Meditate",
            body: "Time to check in",
            fireDate: fireDate
        ).triggerSpec(calendar: calendar)

        #expect(habitSpec.repeats == true)
        #expect(habitSpec.components.hour == 9)
        #expect(habitSpec.components.minute == 30)
        // A repeating trigger that carries a calendar date matches that date once and never again,
        // which is the exact shape of the original bug.
        #expect(habitSpec.components.day == nil)
        #expect(habitSpec.components.month == nil)
        #expect(habitSpec.components.year == nil)

        let taskSpec = CadenceNotificationRequest(
            identifier: "task-due-x",
            kind: .taskDue,
            title: "Ship it",
            body: "Due today",
            fireDate: fireDate
        ).triggerSpec(calendar: calendar)

        #expect(taskSpec.repeats == false)
        #expect(taskSpec.components.year == 2026)
        #expect(taskSpec.components.month == 6)
        #expect(taskSpec.components.day == 19)
    }

    /// And the trigger the manager actually hands the OS, not just the spec it could have used.
    /// Testing `triggerSpec` alone still allowed the adapter to ignore it — this asserts the
    /// object that gets scheduled.
    @Test func theTriggerTheManagerHandsTheOSRepeatsForHabitsAndNotForTasks() {
        let fireDate = Date()

        let habitTrigger = NotificationManager.makeTrigger(
            for: CadenceNotificationRequest(
                identifier: "habit-reminder-x",
                kind: .habitReminder,
                title: "Meditate",
                body: "Time to check in",
                fireDate: fireDate
            )
        )
        #expect(habitTrigger.repeats == true)
        #expect(habitTrigger.dateComponents.day == nil)
        #expect(habitTrigger.dateComponents.hour != nil)

        let taskTrigger = NotificationManager.makeTrigger(
            for: CadenceNotificationRequest(
                identifier: "task-due-x",
                kind: .taskDue,
                title: "Ship it",
                body: "Due today",
                fireDate: fireDate
            )
        )
        #expect(taskTrigger.repeats == false)
        #expect(taskTrigger.dateComponents.day != nil)
        #expect(taskTrigger.dateComponents.year != nil)
    }

    /// iOS reads a goal's habits through `CadenceGoalGroupSupport`, not through the momentum
    /// resolver, so recursing in one and not the other produced a fresh cross-platform
    /// disagreement: the iPhone goal list said "0 habits" while the Milestone widget on the same
    /// phone said "0/2 habits today".
    @Test func theGoalGroupHabitsIOSReadsIncludeMilestoneHabits() {
        let direction = Goal(title: "Get healthy")
        let milestone = Goal(title: "Run a 10k")
        milestone.parentGoal = direction
        direction.subGoals = [milestone]

        let onDirection = Habit(title: "Sleep 8h", goal: direction)
        onDirection.order = 0
        let onMilestone = Habit(title: "Run", goal: milestone)
        onMilestone.order = 1
        direction.habits = [onDirection]
        milestone.habits = [onMilestone]

        let habits = CadenceGoalGroupSupport.habits(for: direction)

        #expect(habits.map(\.title) == ["Sleep 8h", "Run"])
        #expect(CadenceGoalGroupSupport.summary(for: direction).activeHabitCount == 2)
    }

    /// The 52-week heatmap anchored on `today - 52*7` and then rounded *backwards* to a week
    /// start, so its last cell landed one to seven days before today. Today's check-in was never
    /// drawn, on any day of the week.
    @Test func heatmapGridRunsThroughTodayOnEveryWeekday() {
        let calendar = Calendar.current
        // Walk a full week of "todays" so no single weekday can pass by luck.
        for offset in 0..<7 {
            guard let today = calendar.date(
                byAdding: .day,
                value: offset,
                to: DateFormatters.date(from: "2026-04-27") ?? Date()
            ) else { continue }

            let keys = HabitHeatmap.HabitHeatmapGrid.dateKeys(weeks: 52, today: today, calendar: calendar)
            let todayKey = DateFormatters.dateKey(from: today, calendar: calendar)

            #expect(keys.contains(todayKey), "heatmap omitted today for weekday offset \(offset)")
            #expect(keys.count == 52 * 7)
        }
    }

    /// The grid should end on the week containing today, not run arbitrarily far past it.
    @Test func heatmapGridStopsAtTheEndOfTheCurrentWeek() {
        let calendar = Calendar.current
        let today = DateFormatters.date(from: "2026-04-29") ?? Date()
        let keys = HabitHeatmap.HabitHeatmapGrid.dateKeys(weeks: 52, today: today, calendar: calendar)

        guard let last = keys.last, let lastDate = DateFormatters.date(from: last, in: calendar) else {
            Issue.record("heatmap produced no cells")
            return
        }

        let daysPastToday = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: lastDate).day ?? -1
        #expect(daysPastToday >= 0)
        #expect(daysPastToday <= 6)
    }
}
