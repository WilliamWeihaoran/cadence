import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The iPhone shell's greeting and its More-row counts. The counts are a restatement of rules that
/// already exist somewhere else in the app — the badge snapshot, habit due-ness — so these tests
/// mostly pin that they still *forward* rather than having quietly grown a second opinion.
@MainActor
struct CadenceCompactShellSupportTests {
    private let todayKey = "2026-08-13"
    private let yesterdayKey = "2026-08-12"
    private let tomorrowKey = "2026-08-14"

    private func task(
        _ title: String,
        due: String = "",
        scheduled: String = "",
        startMin: Int = -1,
        status: TaskStatus = .todo,
        order: Int = 0
    ) -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = due
        task.scheduledDate = scheduled
        task.scheduledStartMin = startMin
        task.status = status
        task.order = order
        return task
    }

    // MARK: - Greeting

    @Test func theGreetingFollowsTheClockAndNeverSaysGoodnightToSomeoneWhoJustOpenedTheApp() {
        #expect(CadenceCompactShellSupport.greeting(forHour: 5) == "Good morning")
        #expect(CadenceCompactShellSupport.greeting(forHour: 11) == "Good morning")
        #expect(CadenceCompactShellSupport.greeting(forHour: 12) == "Good afternoon")
        #expect(CadenceCompactShellSupport.greeting(forHour: 16) == "Good afternoon")
        #expect(CadenceCompactShellSupport.greeting(forHour: 17) == "Good evening")
        #expect(CadenceCompactShellSupport.greeting(forHour: 23) == "Good evening")
        // Small hours: still "evening", not a farewell.
        #expect(CadenceCompactShellSupport.greeting(forHour: 2) == "Good evening")
    }

    // MARK: - Destination counts

    @Test func countsAppearOnlyWhereANumberMeansSomething() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(
            tasks: [task("open"), task("also open", due: todayKey)],
            todayKey: todayKey,
            activeGoalCount: 3,
            habitCount: 5,
            activeListCount: 4
        )
        let progress = CadenceCompactShellSupport.HabitProgress(completed: 2, due: 5)

        func label(_ destination: CadenceFeatureDestination) -> String? {
            CadenceCompactShellSupport.countLabel(for: destination, badges: badges, habitProgress: progress)
        }

        #expect(label(.allTasks) == "2")
        #expect(label(.inbox) == "2")
        #expect(label(.goals) == "3")
        #expect(label(.lists) == "4")
        // Habits read as a fraction, not as a total — the badge snapshot's plain `5` is overridden.
        #expect(label(.habits) == "2/5")
        #expect(label(.calendar) == nil)
        #expect(label(.notes) == nil)
        #expect(label(.focus) == nil)
    }

    @Test func aHabitRowWithNothingDueTodayShowsNoCountAtAll() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(tasks: [], todayKey: todayKey, habitCount: 5)

        #expect(
            CadenceCompactShellSupport.countLabel(for: .habits, badges: badges, habitProgress: nil) == nil
        )
    }

    // MARK: - Habit progress

    @Test func habitProgressCountsOnlyTheHabitsActuallyDueToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-08-13 is a Thursday.
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!
        let todayKey = DateFormatters.dateKey(from: today, calendar: calendar)

        let daily = Habit(title: "Read")
        daily.frequencyType = .daily
        let doneDaily = Habit(title: "Stretch")
        doneDaily.frequencyType = .daily
        doneDaily.completions = [HabitCompletion(date: todayKey, habit: doneDaily)]
        let mondayOnly = Habit(title: "Laundry")
        mondayOnly.frequencyType = .daysOfWeek
        mondayOnly.frequencyDays = [1] // Monday

        let progress = try #require(
            CadenceCompactShellSupport.habitProgress(for: [daily, doneDaily, mondayOnly], on: today, calendar: calendar)
        )

        #expect(progress.due == 2)
        #expect(progress.completed == 1)
        #expect(progress.label == "1/2")

        // Nothing due today is not "0/0" — it is no count.
        #expect(CadenceCompactShellSupport.habitProgress(for: [mondayOnly], on: today, calendar: calendar) == nil)
        #expect(CadenceCompactShellSupport.habitProgress(for: [], on: today, calendar: calendar) == nil)
    }
}
