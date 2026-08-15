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
    @Test func bestStreakUsesDueDaysNotCalendarDaysForScheduledHabits() throws {
        // 2026-04-27 is a Monday. Eight weeks of Mon/Wed/Fri, ending Friday 2026-06-19.
        let habit = makeHabit(frequency: .daysOfWeek, days: [1, 3, 5])
        var keys: [String] = []
        let calendar = Calendar.current
        var cursor = try #require(DateFormatters.date(from: "2026-04-27"))
        for _ in 0..<8 {
            for offset in [0, 2, 4] {
                if let day = calendar.date(byAdding: .day, value: offset, to: cursor) {
                    keys.append(DateFormatters.dateKey(from: day))
                }
            }
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
        }
        complete(habit, keys)

        let asOf = try #require(DateFormatters.date(from: "2026-06-19"))
        let current = habit.currentStreak(asOf: asOf)
        let best = habit.bestStreak(asOf: asOf)

        #expect(current == 24)
        #expect(best == 24)
        #expect(best >= current)
    }

    /// The other half of the old implementation's incoherence: a hard 366-day scan window meant
    /// a longer daily streak reported a "best" *below* its own "current".
    @Test func bestStreakIsNeverLessThanCurrentStreakBeyondAYear() throws {
        let habit = makeHabit(frequency: .daily)
        let calendar = Calendar.current
        let end = try #require(DateFormatters.date(from: "2026-06-19"))
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
    @Test func bestStreakReportsTheLongestHistoricalRunNotTheMostRecent() throws {
        let habit = makeHabit(frequency: .daily)
        complete(habit, [
            "2026-04-01", "2026-04-02", "2026-04-03", "2026-04-04", "2026-04-05",
            // 2026-04-06 missed
            "2026-04-07", "2026-04-08",
        ])

        let asOf = try #require(DateFormatters.date(from: "2026-04-08"))
        #expect(habit.bestStreak(asOf: asOf) == 5)
        #expect(habit.currentStreak(asOf: asOf) == 2)
    }

    /// `.timesPerWeek` streaks are counted in weeks, so "best" has to be too — otherwise the two
    /// tiles report different units under the same pair of labels.
    @Test func bestStreakCountsWeeksForTimesPerWeekHabits() throws {
        let habit = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        // ISO weeks starting Mon 2026-04-27, 2026-05-04, 2026-05-11 — three satisfied weeks.
        complete(habit, [
            "2026-04-27", "2026-04-29", "2026-05-01",
            "2026-05-04", "2026-05-06", "2026-05-08",
            "2026-05-11", "2026-05-13", "2026-05-15",
        ])

        let asOf = try #require(DateFormatters.date(from: "2026-05-15"))
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
    @Test func aVeryOldStrayCompletionDoesNotPushRecentHistoryOutOfTheWindow() throws {
        let habit = makeHabit(frequency: .daily)
        let calendar = Calendar.current
        let today = try #require(DateFormatters.date(from: "2026-06-19"))

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

    // MARK: - The three rendered habit metrics that had no tests at all

    /// `last30DayCompletionRate` is the "30 days" tile on the macOS habit detail, the same tile on
    /// iOS, and the number averaged across every habit on the habits page — and nothing asserted
    /// it. The percentage is over *due* days, not calendar days, which is the whole reason a
    /// Mon/Wed/Fri habit can read 100%.
    @Test func thirtyDayRateIsOverDueDaysNotCalendarDays() throws {
        let calendar = Calendar.current
        let today = try #require(DateFormatters.date(from: "2026-06-19"))

        // Every due day in the window, kept. A calendar-day denominator would read 43%.
        let scheduled = makeHabit(frequency: .daysOfWeek, days: [1, 3, 5])
        var keys: [String] = []
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if scheduled.isDue(on: day, calendar: calendar) {
                keys.append(DateFormatters.dateKey(from: day, calendar: calendar))
            }
        }
        complete(scheduled, keys)
        #expect(keys.count == 13)
        #expect(scheduled.last30DayCompletionRate(asOf: today, calendar: calendar) == 100)

        // Half of a daily habit's window: 15 of 30.
        let daily = makeHabit(frequency: .daily)
        var dailyKeys: [String] = []
        for offset in stride(from: 0, to: 30, by: 2) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                dailyKeys.append(DateFormatters.dateKey(from: day, calendar: calendar))
            }
        }
        complete(daily, dailyKeys)
        #expect(daily.last30DayCompletionRate(asOf: today, calendar: calendar) == 50)

        // Completions outside the window must not count toward it.
        let stale = makeHabit(frequency: .daily)
        if let old = calendar.date(byAdding: .day, value: -45, to: today) {
            complete(stale, [DateFormatters.dateKey(from: old, calendar: calendar)])
        }
        #expect(stale.last30DayCompletionRate(asOf: today, calendar: calendar) == 0)

        // No due days in the window is 0, not a made-up 100 from an empty denominator.
        let never = makeHabit(frequency: .daysOfWeek, days: [])
        #expect(never.last30DayCompletionRate(asOf: today, calendar: calendar) == 0)
    }

    /// A single fixed instant, read in two time zones whose calendar days *differ* for it. Both
    /// habits are kept perfectly in their own zone, so both must read 100%.
    ///
    /// Two zones, not one, is the point. Pinning one zone proves nothing on a host that happens
    /// to agree with it — and every zone agrees with some host — so an implementation that
    /// ignores the injected calendar and reads `Calendar.current` passes half the time depending
    /// on who runs the suite. No host can agree with both of these at once. The Santiago window
    /// additionally spans 2026-09-06, a *midnight* spring-forward, which is the wall-clock-
    /// preserving drift `bestStreakSurvivesAMidnightDSTTransition` exists for.
    @Test func thirtyDayRateReadsTheCalendarItIsGivenAndSurvivesAMidnightDSTTransition() throws {
        // 2026-09-25T12:00Z: 09:00 on the 25th in Santiago (UTC-3), 02:00 on the *26th* in
        // Kiritimati (UTC+14).
        let instant = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(secondsFromGMT: 0),
                    year: 2026, month: 9, day: 25, hour: 12
                )
            )
        )

        func perfectlyKeptRate(inTimeZone identifier: String) throws -> Int {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))

            let habit = makeHabit(frequency: .daily)
            let today = calendar.startOfDay(for: instant)
            var keys: [String] = []
            for offset in 0..<30 {
                if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                    keys.append(DateFormatters.dateKey(from: day, calendar: calendar))
                }
            }
            complete(habit, keys)
            #expect(Set(keys).count == 30, "fixture for \(identifier) is not 30 distinct days")
            return habit.last30DayCompletionRate(asOf: instant, calendar: calendar)
        }

        #expect(try perfectlyKeptRate(inTimeZone: "America/Santiago") == 100)
        #expect(try perfectlyKeptRate(inTimeZone: "Pacific/Kiritimati") == 100)
    }

    /// `last7DayStates` drives the iOS seven-dot strip. It used to `compactMap` the day walk, so a
    /// date that could not be formed silently *shortened* the array — six dots, and every dot
    /// after the gap labelling the wrong day. Seven, always, oldest first with today last.
    ///
    /// Read in two zones for the same reason as the 30-day rate above: one zone cannot tell an
    /// injected calendar apart from `Calendar.current`.
    @Test func sevenDayStatesAreAlwaysSevenOldestFirstWithTodayLast() throws {
        let instant = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(secondsFromGMT: 0),
                    year: 2026, month: 9, day: 7, hour: 12
                )
            )
        )

        func states(inTimeZone identifier: String, doneOn keys: [String]) throws -> [Bool] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))
            let habit = makeHabit(frequency: .daily)
            complete(habit, keys)
            return habit.last7DayStates(asOf: instant, calendar: calendar)
        }

        // Santiago reads the instant as 2026-09-07; today and today-3 are checked in. Its window
        // also spans the 2026-09-06 midnight spring-forward.
        let santiago = try states(inTimeZone: "America/Santiago", doneOn: ["2026-09-07", "2026-09-04"])
        #expect(santiago.count == 7)
        #expect(santiago == [false, false, false, true, false, false, true])

        // Kiritimati reads the same instant as 2026-09-08, one day later, so the same two keys
        // land one slot earlier and the strip's last dot is a day with no check-in.
        let kiritimati = try states(inTimeZone: "Pacific/Kiritimati", doneOn: ["2026-09-07", "2026-09-04"])
        #expect(kiritimati.count == 7)
        #expect(kiritimati == [false, false, true, false, false, true, false])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let empty = makeHabit(frequency: .daily)
        #expect(empty.last7DayStates(asOf: instant, calendar: calendar) == Array(repeating: false, count: 7))
    }

    /// `frequencyShortLabel` is the eyebrow on the iOS habit detail and the label in the habit
    /// widget, and it had no test. The invariant worth pinning is not the string but that the
    /// number in it is the number of days the habit is actually due in a week — the label used to
    /// be free to read `targetCount` (which means something else entirely for `.daysOfWeek`).
    @Test func frequencyShortLabelCountsTheDaysTheHabitIsActuallyDue() throws {
        let calendar = Calendar.current
        let monday = try #require(DateFormatters.date(from: "2026-06-15"))

        func dueDaysInAWeek(_ habit: Habit) -> Int {
            (0..<7).reduce(0) { partial, offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { return partial }
                return partial + (habit.isDue(on: day, calendar: calendar) ? 1 : 0)
            }
        }

        let scheduled = makeHabit(frequency: .daysOfWeek, days: [1, 3, 5], targetCount: 9)
        #expect(scheduled.frequencyShortLabel == "3x/week")
        #expect(dueDaysInAWeek(scheduled) == 3)

        let weekend = makeHabit(frequency: .daysOfWeek, days: [6, 7], targetCount: 9)
        #expect(weekend.frequencyShortLabel == "2x/week")
        #expect(dueDaysInAWeek(weekend) == 2)

        // `.timesPerWeek` is the one where `targetCount` *is* the number in the label.
        #expect(makeHabit(frequency: .timesPerWeek, targetCount: 4).frequencyShortLabel == "4x/week")
        #expect(makeHabit(frequency: .daily, targetCount: 3).frequencyShortLabel == "Daily")
        #expect(makeHabit(frequency: .monthly, days: [12]).frequencyShortLabel == "Monthly")

        // No days selected: never due, and the label says so rather than borrowing `targetCount`.
        let unscheduled = makeHabit(frequency: .daysOfWeek, days: [], targetCount: 5)
        #expect(unscheduled.frequencyShortLabel == "0x/week")
        #expect(dueDaysInAWeek(unscheduled) == 0)
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
    @Test func heatmapGridRunsThroughTodayOnEveryWeekday() throws {
        let calendar = Calendar.current
        // Walk a full week of "todays" so no single weekday can pass by luck.
        for offset in 0..<7 {
            guard let today = calendar.date(
                byAdding: .day,
                value: offset,
                to: try #require(DateFormatters.date(from: "2026-04-27"))
            ) else { continue }

            let keys = HabitHeatmap.HabitHeatmapGrid.cells(weeks: 52, today: today, calendar: calendar).map(\.key)
            let todayKey = DateFormatters.dateKey(from: today, calendar: calendar)

            #expect(keys.contains(todayKey), "heatmap omitted today for weekday offset \(offset)")
            #expect(keys.count == 52 * 7)
        }
    }

    // MARK: - `.timesPerWeek` is due until its week is met, and its streak is counted in weeks

    /// `isDue(on:)` returned `true` unconditionally for `.timesPerWeek`, so `isDueToday` could
    /// never be false: the detail's "Due today" chip, the list row badge and the "N of M done
    /// today" eyebrow all insisted a 3x/week habit was outstanding on a Thursday whose Mon/Tue/Wed
    /// had already met the target — the same week `weeklyStreak` scored as satisfied.
    @Test func aWeeklyTargetHabitStopsBeingDueOnceItsWeekIsMet() throws {
        let calendar = Calendar.current
        let habit = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        // ISO week of Mon 2026-06-15.
        complete(habit, ["2026-06-15", "2026-06-16", "2026-06-17"])

        let thursday = try #require(DateFormatters.date(from: "2026-06-18"))
        let wednesday = try #require(DateFormatters.date(from: "2026-06-17"))
        let nextMonday = try #require(DateFormatters.date(from: "2026-06-22"))

        #expect(habit.isDue(on: thursday, calendar: calendar) == false)
        // The day whose own check-in finished the week still counts as having been due —
        // otherwise the last check-in of every week reads as unnecessary.
        #expect(habit.isDue(on: wednesday, calendar: calendar) == true)
        // A new week starts owing again, and the streak agrees the old one was satisfied.
        #expect(habit.isDue(on: nextMonday, calendar: calendar) == true)
        #expect(habit.currentStreak(asOf: thursday, calendar: calendar) == 1)
    }

    @Test func aWeeklyTargetHabitIsStillDueWhileItsWeekIsShort() throws {
        let calendar = Calendar.current
        let habit = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        complete(habit, ["2026-06-15", "2026-06-16"])

        let thursday = try #require(DateFormatters.date(from: "2026-06-18"))
        #expect(habit.isDue(on: thursday, calendar: calendar) == true)

        // Weeks are the ISO ones the streak uses, so a Sunday closes the week that opened Monday
        // rather than opening a new one.
        let sunday = try #require(DateFormatters.date(from: "2026-06-21"))
        complete(habit, ["2026-06-19"])
        #expect(habit.isDue(on: sunday, calendar: calendar) == false)
    }

    /// The 30-day tile divided by *due* days, and every day was due, so a "Gym, 3x/week" habit
    /// kept perfectly for a month read 43% beside a healthy streak — the exact number the doc
    /// comment on that function holds up as the answer it exists to avoid.
    @Test func thirtyDayRateScoresWeeklyTargetHabitsInWeeks() throws {
        let calendar = Calendar.current
        let today = try #require(DateFormatters.date(from: "2026-06-19"))

        // Four complete ISO weeks before the current one, three check-ins each.
        let perfect = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        complete(perfect, [
            "2026-06-08", "2026-06-10", "2026-06-12",
            "2026-06-01", "2026-06-03", "2026-06-05",
            "2026-05-25", "2026-05-27", "2026-05-29",
            "2026-05-18", "2026-05-20", "2026-05-22",
        ])
        #expect(perfect.last30DayCompletionRate(asOf: today, calendar: calendar) == 100)

        // Two of three, every week: two thirds, not a day-count.
        let short = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        complete(short, [
            "2026-06-08", "2026-06-10",
            "2026-06-01", "2026-06-03",
            "2026-05-25", "2026-05-27",
            "2026-05-18", "2026-05-20",
        ])
        #expect(short.last30DayCompletionRate(asOf: today, calendar: calendar) == 67)

        // An extra check-in cannot lift a week above its own target.
        let over = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        complete(over, [
            "2026-06-08", "2026-06-09", "2026-06-10", "2026-06-11", "2026-06-12",
            "2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05",
            "2026-05-25", "2026-05-26", "2026-05-27", "2026-05-28", "2026-05-29",
            "2026-05-18", "2026-05-19", "2026-05-20", "2026-05-21", "2026-05-22",
        ])
        #expect(over.last30DayCompletionRate(asOf: today, calendar: calendar) == 100)

        #expect(makeHabit(frequency: .timesPerWeek, targetCount: 3).last30DayCompletionRate(asOf: today, calendar: calendar) == 0)
    }

    /// `currentStreak` returns **weeks** for `.timesPerWeek` — the model says so twice — while
    /// every surface appended a hardcoded "d", so eight kept weeks (24+ check-ins) rendered as
    /// "8d streak" and read as weaker than a ten-day daily habit.
    @Test func streakUnitFollowsTheFrequencyRatherThanBeingAssumedInDays() throws {
        #expect(makeHabit(frequency: .timesPerWeek, targetCount: 3).streakUnit == .weeks)
        #expect(makeHabit(frequency: .daily).streakUnit == .days)
        #expect(makeHabit(frequency: .daysOfWeek, days: [1, 3, 5]).streakUnit == .days)
        #expect(makeHabit(frequency: .monthly, days: [1]).streakUnit == .days)

        #expect(HabitStreakUnit.days.shortLabel(8) == "8d")
        #expect(HabitStreakUnit.weeks.shortLabel(8) == "8w")
        #expect(HabitStreakUnit.days.phrase(8) == "8 day streak")
        #expect(HabitStreakUnit.weeks.phrase(8) == "8 week streak")

        // And the unit has to match the number actually produced: eight satisfied weeks of a
        // 3x/week habit is "8w", not "8d".
        let calendar = Calendar.current
        let habit = makeHabit(frequency: .timesPerWeek, targetCount: 3)
        var keys: [String] = []
        var weekStart = try #require(DateFormatters.date(from: "2026-04-27"))
        for _ in 0..<8 {
            for offset in [0, 2, 4] {
                if let day = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                    keys.append(DateFormatters.dateKey(from: day, calendar: calendar))
                }
            }
            weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        }
        complete(habit, keys)

        let asOf = try #require(DateFormatters.date(from: "2026-06-19"))
        #expect(habit.currentStreak(asOf: asOf, calendar: calendar) == 8)
        #expect(habit.streakUnit.shortLabel(habit.currentStreak(asOf: asOf, calendar: calendar)) == "8w")
    }

    /// The grid should end on the week containing today, not run arbitrarily far past it.
    @Test func heatmapGridStopsAtTheEndOfTheCurrentWeek() throws {
        let calendar = Calendar.current
        let today = try #require(DateFormatters.date(from: "2026-04-29"))
        let keys = HabitHeatmap.HabitHeatmapGrid.cells(weeks: 52, today: today, calendar: calendar).map(\.key)

        guard let last = keys.last, let lastDate = DateFormatters.date(from: last, in: calendar) else {
            Issue.record("heatmap produced no cells")
            return
        }

        let daysPastToday = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: lastDate).day ?? -1
        #expect(daysPastToday >= 0)
        #expect(daysPastToday <= 6)
    }

    /// The month ruler deduped on the month *number* over a 364-day grid, so the first and last
    /// columns — almost always the same month — collapsed onto the label emitted a year ago. On
    /// 2026-08-15 the grid opens in Aug 2025, so "Aug" was spent at column 0 and every Aug 2026
    /// column at the right edge went unlabelled: the last label a reader saw was "Jul", and
    /// counting back from it to date a cell landed a month out.
    @Test func heatmapMonthLabelsReachTheCurrentMonthAtTheRightEdge() throws {
        let calendar = Calendar.current
        let today = try #require(DateFormatters.date(from: "2026-08-15"))
        let labels = HabitHeatmap.HabitHeatmapGrid.monthLabels(weeks: 52, today: today, calendar: calendar)

        let last = try #require(labels.last)
        #expect(last.label == DateFormatters.monthAbbrev.string(from: today))
        // Not the column a year ago: the current month's label belongs at the right-hand end.
        #expect(last.weekCol >= 46)
        // Thirteen months are touched by a 52-week window, and each gets exactly one column.
        #expect(labels.count == 13)
        #expect(Set(labels.map(\.weekCol)).count == labels.count)

        // Every label sits on a column whose week really does start in the month it names.
        for label in labels {
            let start = HabitHeatmap.HabitHeatmapGrid.startDate(weeks: 52, today: today, calendar: calendar)
            let weekStart = try #require(calendar.date(byAdding: .day, value: label.weekCol * 7, to: start))
            #expect(DateFormatters.monthAbbrev.string(from: weekStart) == label.label)
        }
    }

    /// The grid hardcoded a Sunday start (`-(weekday - 1)`) while every weekly *computation* goes
    /// through `Habit.isoWeekCalendar`'s fixed Monday week — so a 3x/week habit checked
    /// Sun/Mon/Tue drew one full-looking column that the scoring counted as 2/3 of one week and
    /// 1/3 of the next.
    @Test func heatmapColumnsUseTheSameMondayWeekTheScoringDoes() throws {
        let iso = Habit.isoWeekCalendar(inheritingTimeZoneFrom: Calendar.current)

        // A full week of "todays", so no single weekday can pass by luck.
        let anchor = try #require(DateFormatters.date(from: "2026-08-10"))
        for offset in 0..<7 {
            let today = try #require(Calendar.current.date(byAdding: .day, value: offset, to: anchor))
            let start = HabitHeatmap.HabitHeatmapGrid.startDate(weeks: 52, today: today, calendar: .current)
            // Monday is weekday 2 in every Gregorian/ISO calendar.
            #expect(iso.component(.weekday, from: start) == 2, "column boundary is not Monday for offset \(offset)")

            let cells = HabitHeatmap.HabitHeatmapGrid.cells(weeks: 52, today: today, calendar: .current)
            let firstOfLastColumn = try #require(cells.dropLast(6).last)
            #expect(iso.component(.weekday, from: firstOfLastColumn.date) == 2)
        }
    }

    /// And the boundary must not move with the locale's `firstWeekday`, which is what made the
    /// old grid disagree with the scoring in the first place.
    @Test func heatmapColumnsIgnoreTheLocalesFirstWeekday() throws {
        let today = try #require(DateFormatters.date(from: "2026-08-15"))

        func start(firstWeekday: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            calendar.firstWeekday = firstWeekday
            return HabitHeatmap.HabitHeatmapGrid.startDate(weeks: 52, today: today, calendar: calendar)
        }

        #expect(start(firstWeekday: 1) == start(firstWeekday: 2))
        #expect(start(firstWeekday: 7) == start(firstWeekday: 2))
    }
}
