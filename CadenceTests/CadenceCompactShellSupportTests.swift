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

    /// **The fraction arm went with T-2076, not the rule.** `countLabel` used to take a
    /// `habitProgress` and answer `2/5` for the Habits row alone; Habits is no longer a row, so
    /// every destination the More list draws is one the badge snapshot can answer and the whole
    /// label is a tally again. What is still asserted is the original claim — a number appears
    /// only where it means something — over the rows that remain, with Calendar, Notes and Focus
    /// as the unobliged controls that prove the `nil` arm is doing work.
    @Test func countsAppearOnlyWhereANumberMeansSomething() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(
            tasks: [task("open"), task("also open", due: todayKey)],
            todayKey: todayKey,
            activeListCount: 4
        )

        func label(_ destination: CadenceFeatureDestination) -> String? {
            CadenceCompactShellSupport.countLabel(for: destination, badges: badges)
        }

        #expect(label(.allTasks) == "2")
        #expect(label(.inbox) == "2")
        #expect(label(.lists) == "4")
        #expect(label(.calendar) == nil)
        #expect(label(.notes) == nil)
        #expect(label(.focus) == nil)
    }

    /// A tally of zero draws nothing: the absence of a badge *is* the zero state, which is the
    /// half of the rule the row with no lists and no open tasks exercises.
    @Test func aRowWithNothingToCountShowsNoCountAtAll() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(tasks: [], todayKey: todayKey)

        #expect(CadenceCompactShellSupport.countLabel(for: .lists, badges: badges) == nil)
        #expect(CadenceCompactShellSupport.countLabel(for: .allTasks, badges: badges) == nil)
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
