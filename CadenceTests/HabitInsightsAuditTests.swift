import Foundation
import SwiftData
import Testing
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
