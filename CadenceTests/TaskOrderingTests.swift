import Foundation
import Testing
@testable import Cadence

/// `TaskOrdering` is the app's one task comparator. These tests are about the property the
/// comparator has to have and used not to: a **total** order.
///
/// A comparator that lets two distinct tasks compare equal both ways gives an unstable sort.
/// Swift's `sorted(by:)` is not documented as stable, so equal-comparing rows are free to swap
/// between renders, between launches, and between a Mac and a widget looking at the same store —
/// motion the user cannot explain and cannot stop. Every assertion below fails if the final
/// tie-break is weakened.
@MainActor
struct TaskOrderingTests {

    // MARK: - The pinning test

    /// Sorts a deliberately tie-heavy set from two different starting permutations and requires
    /// byte-identical output. If any tie-break is removed, the two permutations disagree.
    @Test func sortingATieHeavySetTwiceProducesTheSameOrder() {
        let tasks = tieHeavySet()

        for field in TaskSortField.allCases {
            for direction in TaskSortDirection.allCases {
                let forward = tasks.taskSorted(by: field, direction: direction).map(\.id)
                let fromReversed = Array(tasks.reversed())
                    .taskSorted(by: field, direction: direction).map(\.id)
                let fromRotated = Array(tasks.dropFirst() + tasks.prefix(1))
                    .taskSorted(by: field, direction: direction).map(\.id)

                #expect(
                    forward == fromReversed,
                    "\(field.rawValue)/\(direction.rawValue) is not a total order"
                )
                #expect(
                    forward == fromRotated,
                    "\(field.rawValue)/\(direction.rawValue) is not a total order"
                )
            }
        }
    }

    /// Same requirement for the completed / logbook ordering, where the ties are timestamps.
    @Test func completionSortingATieHeavySetTwiceProducesTheSameOrder() {
        let tasks = completionTieSet()

        #expect(
            tasks.taskCompletionSorted().map(\.id)
                == Array(tasks.reversed()).taskCompletionSorted().map(\.id)
        )
        #expect(
            tasks.taskCompletionSorted().map(\.id)
                == Array(tasks.dropFirst() + tasks.prefix(1)).taskCompletionSorted().map(\.id)
        )
    }

    /// The structural statement behind the two tests above: for every distinct pair, exactly one
    /// of `precedes(a, b)` / `precedes(b, a)` is true. A missing tie-break makes both false.
    @Test func everyDistinctPairIsOrderedInExactlyOneDirection() {
        let tasks = tieHeavySet()

        for field in TaskSortField.allCases {
            for direction in TaskSortDirection.allCases {
                for lhs in tasks {
                    for rhs in tasks where lhs.id != rhs.id {
                        let forward = TaskOrdering.precedes(lhs, rhs, field: field, direction: direction)
                        let backward = TaskOrdering.precedes(rhs, lhs, field: field, direction: direction)
                        #expect(
                            forward != backward,
                            "\(field.rawValue)/\(direction.rawValue) ties '\(lhs.title)' with '\(rhs.title)'"
                        )
                    }
                }
            }
        }

        for lhs in tasks {
            #expect(!TaskOrdering.precedes(lhs, lhs, field: .custom, direction: .ascending))
        }
    }

    // MARK: - The tie-break's own rungs

    /// Each rung has to be reachable, or the ones below it are dead. Two tasks that differ only
    /// at rung N must order by rung N.
    /// Each rung has to be *reachable*, or the rungs below it silently take over. Every case
    /// below is built so that deleting the rung under test hands the decision to the next one
    /// and gets a different answer — otherwise the assertion would be decided by a random UUID
    /// and pass roughly half the time.
    @Test func theTieBreakFallsThroughOrderThenCreatedAtThenTitleThenID() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // `order` beats everything below it: the low-`order` task is the newest and last
        // alphabetically, so any lower rung would put it second.
        let lowOrder = task(title: "zulu", order: 1, createdAt: base.addingTimeInterval(600))
        let highOrder = task(title: "alpha", order: 2, createdAt: base)
        #expect(TaskOrdering.fallbackPrecedes(lowOrder, highOrder))
        #expect(!TaskOrdering.fallbackPrecedes(highOrder, lowOrder))

        // `createdAt` beats `title`: titles run backwards against creation time, so dropping the
        // `createdAt` rung reverses the whole list rather than perturbing it.
        let byCreation = (0..<8).map { index in
            task(
                title: String(UnicodeScalar(UInt8(122 - index))),  // "z", "y", "x", …
                order: 4,
                createdAt: base.addingTimeInterval(Double(index) * 60)
            )
        }
        #expect(byCreation.shuffled().taskSorted(by: .custom, direction: .ascending).map(\.title)
            == byCreation.map(\.title))

        // `title` beats `id`: eight tasks identical but for their titles. If the title rung were
        // gone this would be UUID order, which matches alphabetical order 1 time in 8!.
        let byTitle = ["alpha", "Bravo", "charlie", "Delta", "echo", "Foxtrot", "golf", "Hotel"]
            .map { task(title: $0, order: 4, createdAt: base) }
        #expect(byTitle.shuffled().taskSorted(by: .custom, direction: .ascending).map(\.title)
            == ["alpha", "Bravo", "charlie", "Delta", "echo", "Foxtrot", "golf", "Hotel"])

        // `id` is the floor: two tasks that are equal at every other rung still order, and order
        // the same way whichever side they arrive on.
        let twinA = task(title: "identical", order: 5, createdAt: base)
        let twinB = task(title: "identical", order: 5, createdAt: base)
        let expectedFirst = twinA.id.uuidString < twinB.id.uuidString ? twinA : twinB
        #expect([twinA, twinB].taskSorted(by: .custom, direction: .ascending).first?.id == expectedFirst.id)
        #expect([twinB, twinA].taskSorted(by: .custom, direction: .ascending).first?.id == expectedFirst.id)
    }

    // MARK: - The macOS ordering this consolidation preserved

    /// `.date` ascending: dated before undated, timed before untimed within a day.
    @Test func dateSortKeepsUndatedWorkLastAndTimedWorkFirstWithinADay() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let undated = task(title: "undated", order: 0, createdAt: base)
        let untimedToday = task(title: "untimed-today", scheduledDate: "2026-05-11", order: 1, createdAt: base)
        let timedToday = task(title: "timed-today", scheduledDate: "2026-05-11", startMin: 540, order: 2, createdAt: base)
        let tomorrow = task(title: "tomorrow", scheduledDate: "2026-05-12", order: 3, createdAt: base)

        let ascending = [undated, untimedToday, timedToday, tomorrow]
            .taskSorted(by: .date, direction: .ascending)
        #expect(ascending.map(\.title) == ["timed-today", "untimed-today", "tomorrow", "undated"])

        // Descending flips the *dates*, not the timed-before-untimed rule: "sometime today" above
        // "9am today" would read as a bug rather than as a direction.
        let descending = [undated, untimedToday, timedToday, tomorrow]
            .taskSorted(by: .date, direction: .descending)
        #expect(descending.map(\.title) == ["undated", "tomorrow", "timed-today", "untimed-today"])
    }

    /// Direction is orthogonal to the field, and `.ascending` genuinely means low priority first.
    /// This is the macOS behaviour the shared/iOS comparator does not have.
    @Test func prioritySortHonoursDirectionInBothDirections() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let high = task(title: "high", priority: .high, order: 0, createdAt: base)
        let low = task(title: "low", priority: .low, order: 1, createdAt: base)
        let unset = task(title: "unset", priority: .none, order: 2, createdAt: base)

        #expect([low, unset, high].taskSorted(by: .priority, direction: .descending).map(\.title)
            == ["high", "low", "unset"])
        #expect([low, unset, high].taskSorted(by: .priority, direction: .ascending).map(\.title)
            == ["unset", "low", "high"])
    }

    /// The one "no date" sentinel. It has to sort after every real `yyyy-MM-dd` key, and it has
    /// to be the *same* string everywhere — the repo carried `"9999-99-99"` and `"9999-12-31"`,
    /// and `"9999-99-99" > "9999-12-31"`, so a comparator mixing them would split undated work.
    @Test func theNoDateSentinelSortsAfterEveryRealDateKey() {
        #expect(TaskOrdering.dateSortKey("") == TaskOrdering.noDateSortKey)
        #expect(TaskOrdering.dateSortKey("2026-05-11") == "2026-05-11")
        #expect(TaskOrdering.noDateSortKey > "9999-12-31")
        #expect(TaskOrdering.noDateSortKey > "2999-12-31")
        // Not a parseable date, deliberately: it is a sort key, never data.
        #expect(DateFormatters.date(from: TaskOrdering.noDateSortKey) == nil)
    }

    /// Completed sections read most-recent-first, then fall through the shared tie-break.
    @Test func completionOrderingIsNewestFirstThenTheSharedTieBreak() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = task(title: "recent", order: 9, createdAt: base)
        recent.completedAt = base.addingTimeInterval(600)
        let older = task(title: "older", order: 0, createdAt: base)
        older.completedAt = base.addingTimeInterval(60)
        // No `completedAt` (a cancelled task): falls back to `createdAt`.
        let cancelled = task(title: "cancelled", order: 5, createdAt: base.addingTimeInterval(300))

        #expect([older, cancelled, recent].taskCompletionSorted().map(\.title)
            == ["recent", "cancelled", "older"])

        let tiedEarly = task(title: "tied-a", order: 1, createdAt: base)
        tiedEarly.completedAt = base.addingTimeInterval(900)
        let tiedLate = task(title: "tied-b", order: 2, createdAt: base)
        tiedLate.completedAt = base.addingTimeInterval(900)
        #expect([tiedLate, tiedEarly].taskCompletionSorted().map(\.title) == ["tied-a", "tied-b"])
    }

    // MARK: - The two surfaces that adopted the shared tie-break

    /// The Today widget renders the first few rows of this list. It used to end on a bare
    /// `order`, which is per-container, so a widget showing work from two lists could reshuffle
    /// its rows on any timeline refresh without a single task changing.
    @Test func todayWidgetOrderingDoesNotDependOnInputOrder() {
        let todayKey = "2026-05-11"
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let tasks = (0..<6).map { index in
            task(
                title: "widget-\(index % 2)",
                scheduledDate: todayKey,
                priority: .medium,
                order: index % 2,
                createdAt: base
            )
        }

        let forward = CadenceTodayWidgetSupport.todayTasks(from: tasks, todayKey: todayKey).map(\.id)
        #expect(forward.count == tasks.count)
        #expect(CadenceTodayWidgetSupport.todayTasks(from: tasks.reversed(), todayKey: todayKey).map(\.id) == forward)
        #expect(
            CadenceTodayWidgetSupport
                .todayTasks(from: Array(tasks.dropFirst() + tasks.prefix(1)), todayKey: todayKey)
                .map(\.id) == forward
        )
    }

    /// A goal card names one "next action". That comes off `.first` of a sort, so an incomplete
    /// tie-break does not reorder a list the user can scan — it changes which task the card
    /// tells them to go and do.
    @Test func goalNextActionDoesNotDependOnInputOrder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Tied on priority, both dates, `order` and `createdAt`; distinct only by title and id.
        let tied = (0..<5).map { index in
            task(title: "tied-\(index)", priority: .high, order: 4, createdAt: base)
        }

        let goal = Goal(title: "Direction")
        goal.tasks = tied
        let forward = GoalContributionResolver.summary(for: goal, now: base).nextActionTitle
        #expect(forward != nil)

        goal.tasks = tied.reversed()
        #expect(GoalContributionResolver.summary(for: goal, now: base).nextActionTitle == forward)

        goal.tasks = Array(tied.dropFirst() + tied.prefix(1))
        #expect(GoalContributionResolver.summary(for: goal, now: base).nextActionTitle == forward)
    }

    // MARK: - Fixtures

    /// Deliberate ties at every rung: duplicate dates, duplicate start minutes, duplicate
    /// priorities, duplicate `order`, duplicate `createdAt`, and one duplicated title.
    private func tieHeavySet() -> [AppTask] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            task(title: "alpha", scheduledDate: "2026-05-11", startMin: 540, priority: .high, order: 3, createdAt: base),
            task(title: "beta", scheduledDate: "2026-05-11", startMin: 540, priority: .high, order: 3, createdAt: base),
            task(title: "gamma", scheduledDate: "2026-05-11", priority: .high, order: 3, createdAt: base),
            task(title: "delta", scheduledDate: "", priority: .none, order: 3, createdAt: base),
            task(title: "delta", scheduledDate: "", priority: .none, order: 3, createdAt: base),
            task(title: "epsilon", scheduledDate: "2026-05-12", priority: .low, order: 3, createdAt: base),
            task(title: "zeta", scheduledDate: "2026-05-12", priority: .low, order: 3, createdAt: base.addingTimeInterval(30))
        ]
    }

    private func completionTieSet() -> [AppTask] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<6).map { index in
            let item = task(title: "done-\(index % 2)", order: index % 2, createdAt: base)
            item.completedAt = base.addingTimeInterval(300)
            return item
        }
    }

    private func task(
        title: String,
        scheduledDate: String = "",
        startMin: Int = -1,
        priority: TaskPriority = .none,
        order: Int,
        createdAt: Date
    ) -> AppTask {
        let task = AppTask(title: title)
        task.scheduledDate = scheduledDate
        task.scheduledStartMin = startMin
        task.priority = priority
        task.order = order
        task.createdAt = createdAt
        return task
    }
}
