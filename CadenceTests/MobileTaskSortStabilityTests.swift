import Foundation
import SwiftData
import Testing
@testable import Cadence

/// iOS's task comparator has to be a **total** order, for the same reason macOS's is.
///
/// `order` is assigned per container, so any cross-container surface — All Tasks is the one that
/// matters, and `.listOrder` is its default — routinely compares two tasks with the same `order`.
/// A comparator that stops there lets `sort` return either arrangement, so the rendered sequence
/// is whatever SwiftData's row order happened to be. These tests sort the *same* set from two
/// different starting permutations and require identical output.
@MainActor
struct MobileTaskSortStabilityTests {
    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// Every task shares `order == 0`, which is what two containers' worth of tasks look like.
    private func tieHeavyTasks(in context: ModelContext) -> [AppTask] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let specs: [(String, Int)] = [
            ("Write the brief", 0),
            ("Archive last quarter", 0),
            ("Book the venue", 0),
            ("Call the supplier", 0),
        ]

        return specs.enumerated().map { index, spec in
            let task = AppTask(title: spec.0)
            task.order = spec.1
            // Identical createdAt for two of them, so the tie-break has to reach title and id.
            task.createdAt = index < 2 ? base : base.addingTimeInterval(60)
            context.insert(task)
            return task
        }
    }

    private func sorted(_ tasks: [AppTask], mode: CadenceTaskSortMode) -> [String] {
        tasks
            .sorted { CadenceTaskQuerySupport.sortTasks($0, $1, sortMode: mode) }
            .map(\.title)
    }

    @Test
    func everyModeSortsATieHeavySetIdenticallyFromAnyStartingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)

        for mode in CadenceTaskSortMode.allCases {
            let forward = sorted(tasks, mode: mode)
            let reversed = sorted(tasks.reversed(), mode: mode)
            let shuffled = sorted([tasks[2], tasks[0], tasks[3], tasks[1]], mode: mode)

            #expect(forward == reversed, "\(mode) disagreed with itself on a reversed input")
            #expect(forward == shuffled, "\(mode) disagreed with itself on a shuffled input")
        }
    }

    @Test
    func tasksSharingOrderAndCreationStillGetAStableSequence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)

        // The first two share `order` *and* `createdAt`, so only title/id can separate them.
        let result = sorted(tasks, mode: .listOrder)
        #expect(Set(result).count == tasks.count)
        #expect(result == sorted(tasks.reversed(), mode: .listOrder))
    }

    @Test
    func aRealOrderingIsStillRespected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let first = AppTask(title: "First")
        first.order = 0
        let second = AppTask(title: "Second")
        second.order = 1
        context.insert(first)
        context.insert(second)

        // The tie-break must not override a genuine `order` difference.
        #expect(CadenceTaskQuerySupport.sortTasks(first, second, sortMode: .listOrder))
        #expect(!CadenceTaskQuerySupport.sortTasks(second, first, sortMode: .listOrder))
    }

    // MARK: - T-669: `.doDate` and `.priority` are `TaskOrdering.precedes` under other names

    /// A set built so that every branch of `.date` + `.ascending` and of `.priority` +
    /// `.descending` is reached: two dated days and the undated sentinel, timed against untimed on
    /// one day, two different start minutes on that day, all four priorities, and one pair that is
    /// identical down to `order` and `createdAt` so the comparison has to reach `title`.
    private func comparatorProbeTasks(in context: ModelContext) -> [AppTask] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let specs: [(String, String, Int, TaskPriority, Int)] = [
            // `order` descends as the do-date ascends, so the bare fallback disagrees with both
            // modes rather than happening to reproduce one of them.
            ("Alpha timed early", "2026-05-11", 540, .high, 7),
            ("Bravo timed early", "2026-05-11", 540, .medium, 6),
            ("Charlie timed late", "2026-05-11", 600, .low, 5),
            ("Delta untimed", "2026-05-11", -1, .none, 4),
            ("Echo next day", "2026-05-12", -1, .high, 3),
            ("Foxtrot undated", "", -1, .low, 1),
            ("Golf undated", "", -1, .low, 1),
            ("Hotel timed early", "2026-05-11", 540, .high, 7),
        ]

        return specs.map { spec in
            let task = AppTask(title: spec.0)
            task.scheduledDate = spec.1
            task.scheduledStartMin = spec.2
            task.priority = spec.3
            task.order = spec.4
            // Two pairs share `order`; one of those also shares `createdAt`.
            task.createdAt = spec.0.hasPrefix("Golf") ? base : base.addingTimeInterval(60)
            context.insert(task)
            return task
        }
    }

    /// The equivalence T-669 leans on, **measured** over every ordered pair rather than read off
    /// the shape of the two functions.
    ///
    /// `.doDate` used to be fourteen lines restating `.date` + `.ascending`, and `.priority` the
    /// same shape against `.priority` + `.descending`. Converging a comparator is only safe if the
    /// equivalence holds everywhere, including the case the two spellings phrased differently:
    /// `.priority`'s guard asked `lhs.priority != rhs.priority` where `TaskOrdering` compares the
    /// ranks. Those agree exactly because `TaskPriority.rank` is injective, which
    /// `TrackingDeleteHelpersTests.priorityRankIsOneOrderingSharedByEveryCaller` asserts.
    @Test
    func doDateAndPriorityAgreeWithTaskOrderingOnEveryOrderedPair() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = comparatorProbeTasks(in: context)

        for lhs in tasks {
            for rhs in tasks {
                #expect(
                    CadenceTaskQuerySupport.sortTasks(lhs, rhs, sortMode: .doDate)
                        == TaskOrdering.precedes(lhs, rhs, field: .date, direction: .ascending),
                    "doDate disagreed on \(lhs.title) vs \(rhs.title)"
                )
                #expect(
                    CadenceTaskQuerySupport.sortTasks(lhs, rhs, sortMode: .priority)
                        == TaskOrdering.precedes(lhs, rhs, field: .priority, direction: .descending),
                    "priority disagreed on \(lhs.title) vs \(rhs.title)"
                )
            }
        }

        // Agreement alone stops arguing the moment the two spellings become one function: mutate
        // `TaskOrdering.precedes` now and both sides of the comparison move together. So the two
        // sequences are pinned *absolutely* as well — this is the iOS surface's own statement of
        // what its two shared modes order by, and it goes red for a change to the shared
        // comparator that the equivalence sweep above cannot see.
        let byDoDate = sorted(tasks, mode: .doDate)
        let byPriority = sorted(tasks, mode: .priority)

        #expect(byDoDate == [
            "Bravo timed early",    // 05-11, 09:00, lowest `order` of the three at that minute
            "Alpha timed early",    // same day and minute as Hotel; separated on title
            "Hotel timed early",
            "Charlie timed late",   // same day, later start minute
            "Delta untimed",        // same day, untimed sorts under timed
            "Echo next day",
            "Golf undated",         // the no-date sentinel sorts last; `createdAt` splits the pair
            "Foxtrot undated",
        ])

        #expect(byPriority == [
            "Echo next day",        // high, and the lowest `order` of the three high tasks
            "Alpha timed early",    // high
            "Hotel timed early",    // high
            "Bravo timed early",    // medium
            "Golf undated",         // low
            "Foxtrot undated",      // low
            "Charlie timed late",   // low, highest `order` of the three
            "Delta untimed",        // none
        ])

        // Non-vacuity: the probe set is not degenerate. Each mode reorders it away from the bare
        // tie-break and away from the other, so the two sequences are the comparators' doing.
        let byFallback = tasks.sorted(by: TaskOrdering.fallbackPrecedes).map(\.title)
        #expect(byDoDate != byFallback)
        #expect(byPriority != byFallback)
        #expect(byDoDate != byPriority)
        #expect(Set(byDoDate).count == tasks.count)
    }

    // MARK: - T-3260: what `sortKeyOrder` answers, held by effect rather than by its text

    /// **The delegation, as an answer rather than a spelling (T-3260).** This used to be read off
    /// `sortKeyOrder`'s body: two `contains` needles requiring the `.doDate` and `.priority` arms
    /// to spell `TaskOrdering.sortKeyOrder(…)` with the right field and direction. That pin passed
    /// on any body holding those two strings and failed on any reflow of them.
    ///
    /// The pair sweep above cannot replace it, because it compares the *composed* comparator — and
    /// a restated arm that broke every tie with its own `order` comparison instead of answering
    /// `.tie` would agree with `TaskOrdering.precedes` on every pair while lying to
    /// `CadenceReorderVisibility` about which drops land where they were dropped. So this compares
    /// the KEY, `.tie` included, over every ordered pair of the same probe set.
    @Test
    func theDoDateAndPriorityModesAnswerTaskOrderingsOwnKeyOnEveryPair() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = comparatorProbeTasks(in: context)
        var ties = 0
        var ordered = 0

        for lhs in tasks {
            for rhs in tasks {
                let doDate = CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .doDate)
                let priority = CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .priority)
                #expect(
                    doDate == TaskOrdering.sortKeyOrder(lhs, rhs, field: .date, direction: .ascending),
                    "doDate's key disagreed on \(lhs.title) vs \(rhs.title)"
                )
                #expect(
                    priority == TaskOrdering.sortKeyOrder(lhs, rhs, field: .priority, direction: .descending),
                    "priority's key disagreed on \(lhs.title) vs \(rhs.title)"
                )
                for key in [doDate, priority] {
                    if key == .tie { ties += 1 } else { ordered += 1 }
                }
            }
        }

        // Non-vacuity: the probe set reaches both answers, so `.tie` is compared and not assumed.
        #expect(ties > tasks.count * 2, "only the diagonal tied: \(ties) ties")
        #expect(ordered > 0)
    }

    /// **`.listOrder` sorts by the list, and by nothing the other modes read (T-3260).** Replaces
    /// the negative needles that required no `scheduledStartMin` and no priority comparison inside
    /// the mode switch, in the one place where they were a statement about the ORDER a list comes
    /// back in: without section names every pair is a tie — so `sortTasks` hands it to the shared
    /// `order`-first fallback — and with them the only thing that separates two rows is which
    /// column they sit in, ranked case-insensitively, unlisted last.
    @Test
    func listOrderIsATieOnEverythingButTheColumn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = comparatorProbeTasks(in: context)

        for lhs in tasks {
            for rhs in tasks {
                #expect(
                    CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .listOrder) == .tie,
                    "listOrder separated \(lhs.title) from \(rhs.title) on something other than the list"
                )
            }
        }
        #expect(sorted(tasks, mode: .listOrder) == tasks.sorted(by: TaskOrdering.fallbackPrecedes).map(\.title))

        // Same day and priority everywhere, so the column is the only key left to read.
        let names = ["Doing", "Backlog"]
        let doing = AppTask(title: "Doing row")
        doing.sectionName = "doing"
        doing.order = 9
        let backlog = AppTask(title: "Backlog row")
        backlog.sectionName = "Backlog"
        backlog.order = 0
        let unlisted = AppTask(title: "Unlisted row")
        unlisted.sectionName = "Shipped"
        unlisted.order = 0
        let backlogTwin = AppTask(title: "Backlog twin")
        backlogTwin.sectionName = "Backlog"
        backlogTwin.priority = .high
        backlogTwin.order = 5
        for task in [doing, backlog, unlisted, backlogTwin] { context.insert(task) }

        let key = { (lhs: AppTask, rhs: AppTask) in
            CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .listOrder, sectionNames: names)
        }
        #expect(key(doing, backlog) == .before, "the first column, matched ignoring case, leads")
        #expect(key(backlog, doing) == .after)
        #expect(key(backlog, unlisted) == .before, "a column the list does not name sorts last")
        #expect(key(unlisted, doing) == .after)
        #expect(key(backlog, backlogTwin) == .tie, "one column is one tie, whatever the priority")

        let arranged = [unlisted, backlogTwin, backlog, doing]
            .sorted { CadenceTaskQuerySupport.sortTasks($0, $1, sortMode: .listOrder, sectionNames: names) }
            .map(\.title)
        #expect(arranged == ["Doing row", "Backlog row", "Backlog twin", "Unlisted row"])
    }

    /// **`.dueDate` and `.newest` read their own key and nothing else (T-3260).** The other half of
    /// what the negative needles stood for: no arm of the switch reaches a start minute or a
    /// priority it was not asked about. Each pair below differs on every key EXCEPT the mode's,
    /// so an arm that consulted a second key would separate it.
    @Test
    func dueDateAndNewestReadOnlyTheirOwnKey() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        func task(_ title: String, due: String, created: TimeInterval, start: Int, priority: TaskPriority, order: Int) -> AppTask {
            let task = AppTask(title: title)
            task.dueDate = due
            task.createdAt = base.addingTimeInterval(created)
            task.scheduledDate = "2026-05-11"
            task.scheduledStartMin = start
            task.priority = priority
            task.order = order
            context.insert(task)
            return task
        }

        let early = task("Due early", due: "2026-05-10", created: 0, start: 600, priority: .low, order: 3)
        let earlyTwin = task("Due early twin", due: "2026-05-10", created: 0, start: 540, priority: .high, order: 1)
        let late = task("Due late", due: "2026-05-20", created: 60, start: -1, priority: .none, order: 0)
        let undue = task("No due date", due: "", created: 120, start: 540, priority: .high, order: 2)

        let due = { (lhs: AppTask, rhs: AppTask) in
            CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .dueDate)
        }
        #expect(due(early, late) == .before)
        #expect(due(late, early) == .after)
        #expect(due(late, undue) == .before, "a dated task leads an undated one")
        #expect(due(undue, early) == .after)
        #expect(due(early, earlyTwin) == .tie, "same due day: start minute and priority are not this mode's")
        #expect(due(earlyTwin, early) == .tie)

        let newest = { (lhs: AppTask, rhs: AppTask) in
            CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: .newest)
        }
        #expect(newest(undue, late) == .before, "the later creation leads")
        #expect(newest(early, late) == .after)
        #expect(newest(early, earlyTwin) == .tie, "same creation instant: nothing else is this mode's")

        let all = [undue, late, earlyTwin, early]
        #expect(sorted(all, mode: .dueDate) == ["Due early twin", "Due early", "Due late", "No due date"])
        #expect(sorted(all, mode: .newest) == ["No due date", "Due late", "Due early twin", "Due early"])
    }

    /// **What is left here is the structural half, and it stays a source scan on purpose.** T-669's
    /// rule is that the ordering is spelled ONCE: a restated arm that happened to agree would pass
    /// every behavioural test in this file forever, which is the case a text rule exists for.
    ///
    /// **T-3260 moved the behavioural needles out.** This used to also require the two delegating
    /// calls and the `sortTasks` tie-break by text. Those are now held by effect —
    /// `theDoDateAndPriorityModesAnswerTaskOrderingsOwnKeyOnEveryPair` for the delegation, and
    /// `CadenceReorderOffScreenNoticeTests.theModeKeyRecomposesIntoItsComparatorExactly`, which
    /// recomposes `sortTasks` from `sortKeyOrder` plus `fallbackPrecedes` over every mode and pair,
    /// for the tie-break — so what remains is only what behaviour cannot see.
    @Test
    func theDoDateAndPriorityBranchesDelegateRatherThanRestate() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskQuerySupport.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "sortKeyOrder", in: source))

        // Non-vacuity: this is the real switch, not a truncated read of it, so the negatives below
        // are read over all five arms.
        #expect(body.contains("case .listOrder:"))
        #expect(body.contains("case .newest:"))

        // The restatement is gone rather than merely joined: no branch here reads a start minute
        // or spells a priority comparison of its own.
        #expect(!body.contains("scheduledStartMin"))
        #expect(!body.contains("priorityRank("))
        #expect(!body.contains(".priority !="))

        // And the mode switch is not spelled a second time in the frame it moved out of.
        let sortTasks = try #require(CadenceSourceScan.functionBody(named: "sortTasks", in: source))
        #expect(!sortTasks.contains("case .listOrder:"), "the mode switch is spelled twice")
    }
}
