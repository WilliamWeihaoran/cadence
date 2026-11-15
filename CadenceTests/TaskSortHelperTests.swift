#if os(macOS)
import Foundation
import SwiftUI
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

    @Test func dateBucketsPrioritizeDueBucketsOverScheduledToday() {
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

        let tasks = [overdueAndScheduled, dueTodayAndScheduled, scheduledOnly, future]
        let buckets = CadenceTaskQuerySupport.dateBuckets(for: tasks, todayKey: todayKey)

        #expect(buckets.overdueIDs == Set([overdueAndScheduled.id]))
        #expect(buckets.dueTodayIDs == Set([dueTodayAndScheduled.id]))
        #expect(buckets.doTodayIDs == Set([scheduledOnly.id]))
        #expect(buckets.contains(overdueAndScheduled))
        #expect(buckets.contains(dueTodayAndScheduled))
        #expect(buckets.contains(scheduledOnly))
        #expect(!buckets.contains(future))

        // Assert through the surface the app actually renders, so a change to the bucketing rule
        // shows up as a wrong group rather than only as a wrong intermediate value.
        let groups = CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey)
        #expect(groups.first { $0.id == "overdue" }?.tasks.map(\.id) == [overdueAndScheduled.id])
        #expect(groups.first { $0.id == "due-today" }?.tasks.map(\.id) == [dueTodayAndScheduled.id])
        #expect(groups.first { $0.id == "do-today" }?.tasks.map(\.id) == [scheduledOnly.id])
        #expect(groups.first { $0.id == "unscheduled" }?.tasks.map(\.id) == [future.id])
    }

    /// [[T-12323]]: a do date that has already gone by is "Leftover", never "Scheduled" — the
    /// heading that also holds work planned for weeks ahead. Seen on screen as three rows planned
    /// for yesterday under one SCHEDULED heading with a row planned two weeks out.
    @Test func aDoDateAlreadyGoneByIsLeftoverNotScheduled() {
        let todayKey = "2026-05-11"
        let plannedYesterday = task(title: "planned-yesterday", scheduledDate: "2026-05-10", order: 0)
        let plannedAhead = task(title: "planned-ahead", scheduledDate: "2026-05-25", order: 1)
        // A due date outranks a do date (`AppTask.todayStanding`), so this one is due-today.
        let dueTodayPlannedYesterday = task(
            title: "due-today-planned-yesterday", dueDate: todayKey, scheduledDate: "2026-05-10", order: 2
        )
        let tasks = [plannedAhead, plannedYesterday, dueTodayPlannedYesterday]

        let groups = CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey)
        #expect(groups.map(\.id) == ["past-do", "due-today", "scheduled"],
                "Leftover ranks where the past-do standing sorts: after Overdue, before Due Today")
        #expect(groups.first { $0.id == "past-do" }?.tasks.map(\.id) == [plannedYesterday.id])
        #expect(groups.first { $0.id == "past-do" }?.title == "Leftover")
        #expect(groups.first { $0.id == "scheduled" }?.tasks.map(\.id) == [plannedAhead.id],
                "Scheduled holds only a do date still to come")
        #expect(groups.first { $0.id == "due-today" }?.tasks.map(\.id) == [dueTodayPlannedYesterday.id])
        #expect(TasksListView.dateDropKey(forGroupID: "past-do") == nil,
                "a header defined by a day gone by takes no drop")
    }

    /// [[T-12371]]: no two By Date headings share an accent. Leftover (a day gone by) and
    /// Unscheduled (no day at all) both drew `Theme.amber`, so the eyebrow tint said the same
    /// thing twice about opposite situations. A RELATION over all six groups, not a pinned token,
    /// so a later retint of any one heading still has to stay distinct from the other five.
    @Test func everyByDateHeadingDrawsItsOwnAccent() {
        let todayKey = "2026-05-11"
        let tasks = [
            task(title: "overdue", dueDate: "2026-05-01", order: 0),
            task(title: "leftover", scheduledDate: "2026-05-10", order: 1),
            task(title: "due-today", dueDate: todayKey, order: 2),
            task(title: "do-today", scheduledDate: todayKey, order: 3),
            task(title: "scheduled", scheduledDate: "2026-05-25", order: 4),
            task(title: "unscheduled", order: 5),
        ]

        let groups = CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey)
        #expect(groups.map(\.id) == ["overdue", "past-do", "due-today", "do-today", "scheduled", "unscheduled"],
                "non-vacuity: every By Date heading is drawn")
        for (index, group) in groups.enumerated() {
            for other in groups[(index + 1)...] {
                #expect(group.accent != other.accent, "\(group.title) and \(other.title) share an accent")
            }
        }
    }

    /// [[T-18056]]: only Overdue is red. Due Today drew `Theme.red.opacity(0.8)`, which passes the
    /// pairwise check above (a different alpha is a different `Color`) yet reads on screen as a
    /// second Overdue. So the relation compares the resolved RGB with the alpha thrown away: no
    /// heading but `overdue` may be any opacity of Overdue's red.
    @Test func onlyTheOverdueHeadingIsRed() {
        let todayKey = "2026-05-11"
        let tasks = [
            task(title: "overdue", dueDate: "2026-05-01", order: 0),
            task(title: "leftover", scheduledDate: "2026-05-10", order: 1),
            task(title: "due-today", dueDate: todayKey, order: 2),
            task(title: "do-today", scheduledDate: todayKey, order: 3),
            task(title: "scheduled", scheduledDate: "2026-05-25", order: 4),
            task(title: "unscheduled", order: 5),
        ]
        let groups = CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey)
        #expect(groups.count == 6, "non-vacuity: every By Date heading is drawn")

        let environment = EnvironmentValues()
        func rgb(_ color: Color) -> [Float] {
            let resolved = color.resolve(in: environment)
            return [resolved.red, resolved.green, resolved.blue]
        }
        let red = rgb(Theme.red)
        for group in groups {
            let isRed = zip(rgb(group.accent), red).allSatisfy { abs($0 - $1) < 0.01 }
            #expect(isRed == (group.id == "overdue"), "\(group.title) red: \(isRed)")
        }
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
