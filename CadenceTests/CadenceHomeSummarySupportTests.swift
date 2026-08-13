import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The iPhone Home screen's today card and grid counts. Every number on that screen is a
/// restatement of a rule that already exists somewhere else in the app — today's task scope, the
/// overdue predicate, the completed-today scope, habit due-ness — so these tests mostly pin that
/// it still *forwards* rather than having quietly grown a second opinion.
@MainActor
struct CadenceHomeSummarySupportTests {
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
        #expect(CadenceHomeSummarySupport.greeting(forHour: 5) == "Good morning")
        #expect(CadenceHomeSummarySupport.greeting(forHour: 11) == "Good morning")
        #expect(CadenceHomeSummarySupport.greeting(forHour: 12) == "Good afternoon")
        #expect(CadenceHomeSummarySupport.greeting(forHour: 16) == "Good afternoon")
        #expect(CadenceHomeSummarySupport.greeting(forHour: 17) == "Good evening")
        #expect(CadenceHomeSummarySupport.greeting(forHour: 23) == "Good evening")
        // Small hours: still "evening", not a farewell.
        #expect(CadenceHomeSummarySupport.greeting(forHour: 2) == "Good evening")
    }

    @Test func minuteOfDayIsMinutesFromMidnightSoItComparesToAScheduledStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9, minute: 45))!

        #expect(CadenceHomeSummarySupport.minuteOfDay(for: date, calendar: calendar) == 585)
    }

    // MARK: - Today stats

    @Test func todayStatsCountDueOverdueAndDoneAndIgnoreFinishedWorkInTheOpenBuckets() {
        let tasks = [
            task("due today", due: todayKey),
            task("also due today", due: todayKey),
            task("overdue", due: yesterdayKey),
            task("due tomorrow", due: tomorrowKey),
            task("done today", due: todayKey, status: .done),
            task("cancelled", due: todayKey, status: .cancelled)
        ]

        let stats = CadenceHomeSummarySupport.todayStats(from: tasks, todayKey: todayKey)

        #expect(stats.dueTodayCount == 2)
        #expect(stats.overdueCount == 1)
        #expect(stats.completedCount == 1)
        #expect(stats.isQuiet == false)
    }

    /// The three counts have to agree with the predicates the rest of the app uses, or the card
    /// promises a day the Today screen it opens does not show.
    @Test func todayStatsForwardToTheSharedOverdueAndCompletedPredicates() {
        let tasks = [
            task("overdue", due: yesterdayKey),
            task("finished but past due", due: yesterdayKey, status: .done),
            task("done today", scheduled: todayKey, status: .done)
        ]

        let stats = CadenceHomeSummarySupport.todayStats(from: tasks, todayKey: todayKey)

        #expect(stats.overdueCount == tasks.filter { $0.isOverdue(todayKey: todayKey) }.count)
        #expect(
            stats.completedCount
                == CadenceTaskQuerySupport.completedTodayTasks(from: tasks, todayKey: todayKey).count
        )
        // A completed task with a past deadline is not overdue — you did it.
        #expect(stats.overdueCount == 1)
    }

    @Test func anEmptyDayReadsAsQuiet() {
        let stats = CadenceHomeSummarySupport.todayStats(from: [], todayKey: todayKey)

        #expect(stats == CadenceHomeSummarySupport.TodayStats(dueTodayCount: 0, overdueCount: 0, completedCount: 0))
        #expect(stats.isQuiet)
    }

    // MARK: - Next action

    @Test func theNextActionIsTheEarliestTimedSlotThatHasNotFinishedYet() {
        let early = task("standup", scheduled: todayKey, startMin: 9 * 60)
        let later = task("review", scheduled: todayKey, startMin: 14 * 60)
        let tasks = [later, early, task("untimed", scheduled: todayKey)]

        // Before both slots.
        #expect(
            CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey, nowMinute: 8 * 60)?.title
                == "standup"
        )
        // Mid-morning, with the 9am block still running (30-minute default duration).
        #expect(
            CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey, nowMinute: 9 * 60 + 10)?.title
                == "standup"
        )
        // Once it has ended, the afternoon block is next.
        #expect(
            CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey, nowMinute: 11 * 60)?.title
                == "review"
        )
    }

    @Test func whenEveryTimedSlotHasPassedItFallsBackToTheMostUrgentOpenTask() {
        let tasks = [
            task("morning block", scheduled: todayKey, startMin: 8 * 60, order: 2),
            task("overdue thing", due: yesterdayKey, order: 1)
        ]

        // Late in the day: nothing timed is still ahead, so urgency ordering decides — and
        // `activeTodayTasks` ranks past-due first.
        #expect(
            CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey, nowMinute: 22 * 60)?.title
                == "overdue thing"
        )
    }

    @Test func withoutAClockTheEarliestTimedSlotWinsRegardlessOfTheHour() {
        let tasks = [
            task("overdue thing", due: yesterdayKey, order: 1),
            task("morning block", scheduled: todayKey, startMin: 8 * 60, order: 2)
        ]

        #expect(CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey)?.title == "morning block")
    }

    @Test func onlyTodaysOpenWorkCanBeTheNextAction() {
        let tasks = [
            task("tomorrow", scheduled: tomorrowKey, startMin: 9 * 60),
            task("finished", scheduled: todayKey, startMin: 7 * 60, status: .done)
        ]

        #expect(CadenceHomeSummarySupport.nextAction(from: tasks, todayKey: todayKey, nowMinute: 6 * 60) == nil)
        #expect(CadenceHomeSummarySupport.nextAction(from: [], todayKey: todayKey) == nil)
    }

    @Test func tasksSharingAStartMinuteResolveThroughTheSharedTotalTieBreak() {
        let first = task("alpha", scheduled: todayKey, startMin: 9 * 60, order: 1)
        let second = task("beta", scheduled: todayKey, startMin: 9 * 60, order: 0)

        // `order` 0 precedes `order` 1 under `TaskOrdering.fallbackPrecedes`, whichever way the
        // input array happens to be arranged.
        #expect(
            CadenceHomeSummarySupport.nextAction(from: [first, second], todayKey: todayKey, nowMinute: 8 * 60)?.title
                == "beta"
        )
        #expect(
            CadenceHomeSummarySupport.nextAction(from: [second, first], todayKey: todayKey, nowMinute: 8 * 60)?.title
                == "beta"
        )
    }

    // MARK: - Next action detail

    @Test func theDetailChipShowsATimeWhenThereIsOneAndOtherwiseTheList() {
        let timed = task("standup", scheduled: todayKey, startMin: 9 * 60 + 30)
        #expect(
            CadenceHomeSummarySupport.nextActionDetail(for: timed, todayKey: todayKey)
                == .scheduled(TimeFormatters.timeString(from: 9 * 60 + 30))
        )

        let inList = task("draft the brief", due: todayKey)
        inList.area = Area(name: "Website")
        #expect(CadenceHomeSummarySupport.nextActionDetail(for: inList, todayKey: todayKey) == .list("Website"))

        // No list is a real answer, not a blank chip.
        let loose = task("call the bank", due: todayKey)
        #expect(CadenceHomeSummarySupport.nextActionDetail(for: loose, todayKey: todayKey) == .list("Inbox"))

        // A slot on a *different* day is not this task's time.
        let scheduledTomorrow = task("later", scheduled: tomorrowKey, startMin: 9 * 60)
        #expect(
            CadenceHomeSummarySupport.nextActionDetail(for: scheduledTomorrow, todayKey: todayKey) == .list("Inbox")
        )
    }

    // MARK: - Grid

    @Test func theGridOffersEveryDestinationExceptTodayWhichIsTheCard() {
        let grid = CadenceHomeSummarySupport.gridDestinations

        #expect(grid.contains(.today) == false)
        #expect(Set(grid).count == grid.count)
        for destination in CadenceFeatureDestination.allCases
        where destination != .today && !destination.isUtilityNavigation {
            #expect(grid.contains(destination), "\(destination.title) fell out of the home grid")
        }
    }

    @Test func gridCountsAppearOnlyWhereANumberMeansSomething() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(
            tasks: [task("open"), task("also open", due: todayKey)],
            todayKey: todayKey,
            activeGoalCount: 3,
            habitCount: 5,
            activeListCount: 4
        )
        let progress = CadenceHomeSummarySupport.HabitProgress(completed: 2, due: 5)

        func label(_ destination: CadenceFeatureDestination) -> String? {
            CadenceHomeSummarySupport.gridCountLabel(for: destination, badges: badges, habitProgress: progress)
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

    @Test func aHabitCellWithNothingDueTodayShowsNoCountAtAll() {
        let badges = CadenceFeatureBadgeSupport.Snapshot(tasks: [], todayKey: todayKey, habitCount: 5)

        #expect(
            CadenceHomeSummarySupport.gridCountLabel(for: .habits, badges: badges, habitProgress: nil) == nil
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
            CadenceHomeSummarySupport.habitProgress(for: [daily, doneDaily, mondayOnly], on: today, calendar: calendar)
        )

        #expect(progress.due == 2)
        #expect(progress.completed == 1)
        #expect(progress.label == "1/2")

        // Nothing due today is not "0/0" — it is no count.
        #expect(CadenceHomeSummarySupport.habitProgress(for: [mondayOnly], on: today, calendar: calendar) == nil)
        #expect(CadenceHomeSummarySupport.habitProgress(for: [], on: today, calendar: calendar) == nil)
    }
}
