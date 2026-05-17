#if os(macOS)
import Foundation
import Testing
@testable import Cadence

@MainActor
struct TaskSortHelperTests {
    @Test func dateSortAscendingOrdersScheduledTasksBeforeUndatedOnes() {
        let sameDayLater = task(title: "same-day-later", scheduledDate: "2026-05-11", order: 20)
        let undated = task(title: "undated", scheduledDate: "", order: 1)
        let nextDay = task(title: "next-day", scheduledDate: "2026-05-12", order: 5)
        let sameDayEarlier = task(title: "same-day-earlier", scheduledDate: "2026-05-11", order: 10)

        let sorted = [sameDayLater, undated, nextDay, sameDayEarlier]
            .taskSorted(by: .date, direction: .ascending)

        #expect(sorted.map(\.title) == [
            "same-day-earlier",
            "same-day-later",
            "next-day",
            "undated",
        ])
    }

    @Test func dateSortDescendingUsesLatestDateFirstAndStableFallbackForTies() {
        let earlier = task(title: "earlier", scheduledDate: "2026-05-11", order: 1)
        let later = task(title: "later", scheduledDate: "2026-05-12", order: 99)
        let sameLatestHigherOrder = task(title: "same-latest-higher-order", scheduledDate: "2026-05-12", order: 50)
        let sameLatestLowerOrder = task(title: "same-latest-lower-order", scheduledDate: "2026-05-12", order: 10)

        let sorted = [earlier, later, sameLatestHigherOrder, sameLatestLowerOrder]
            .taskSorted(by: .date, direction: .descending)

        #expect(sorted.map(\.title) == [
            "same-latest-lower-order",
            "same-latest-higher-order",
            "later",
            "earlier",
        ])
    }

    @Test func prioritySortDescendingKeepsHigherPriorityFirstAndFallsBackByOrder() {
        let medium = task(title: "medium", priority: .medium, order: 1)
        let highLater = task(title: "high-later", priority: .high, order: 30)
        let none = task(title: "none", priority: .none, order: 0)
        let highEarlier = task(title: "high-earlier", priority: .high, order: 10)

        let sorted = [medium, highLater, none, highEarlier]
            .taskSorted(by: .priority, direction: .descending)

        #expect(sorted.map(\.title) == [
            "high-earlier",
            "high-later",
            "medium",
            "none",
        ])
    }

    @Test func classifyTasksByDatePrioritizesDueBucketsOverScheduledToday() {
        let todayKey = "2026-05-11"

        let overdueAndScheduled = task(
            title: "overdue-and-scheduled",
            dueDate: "2026-05-10",
            scheduledDate: todayKey,
            order: 0
        )
        let dueTodayAndScheduled = task(
            title: "due-today-and-scheduled",
            dueDate: todayKey,
            scheduledDate: todayKey,
            order: 1
        )
        let scheduledOnly = task(
            title: "scheduled-only",
            dueDate: "",
            scheduledDate: todayKey,
            order: 2
        )
        let future = task(
            title: "future",
            dueDate: "2026-05-12",
            scheduledDate: "",
            order: 3
        )

        let buckets = classifyTasksByDate(
            [overdueAndScheduled, dueTodayAndScheduled, scheduledOnly, future],
            todayKey: todayKey
        )

        #expect(buckets.overdueIDs == Set([overdueAndScheduled.id]))
        #expect(buckets.dueTodayIDs == Set([dueTodayAndScheduled.id]))
        #expect(buckets.doTodayIDs == Set([scheduledOnly.id]))
        #expect(buckets.contains(overdueAndScheduled))
        #expect(buckets.contains(dueTodayAndScheduled))
        #expect(buckets.contains(scheduledOnly))
        #expect(!buckets.contains(future))
    }

    private func task(
        title: String,
        dueDate: String = "",
        scheduledDate: String = "",
        priority: TaskPriority = .none,
        order: Int
    ) -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = dueDate
        task.scheduledDate = scheduledDate
        task.priority = priority
        task.order = order
        return task
    }
}
#endif
