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

    /// The equivalence above is what makes it safe to delete the copy; this is what keeps it
    /// deleted. A restated branch that happens to still agree would pass the pair sweep forever
    /// — the point of T-669 is that the ordering is spelled once.
    @Test
    func theDoDateAndPriorityBranchesDelegateRatherThanRestate() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskQuerySupport.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "sortTasks", in: source))

        // Non-vacuity: this is the real switch, not a truncated read of it.
        #expect(body.contains("case .listOrder:"))
        #expect(body.contains("case .newest:"))

        #expect(body.contains("TaskOrdering.precedes(lhs, rhs, field: .date, direction: .ascending)"))
        #expect(body.contains("TaskOrdering.precedes(lhs, rhs, field: .priority, direction: .descending)"))

        // The restatement is gone rather than merely joined: no branch here reads a start minute
        // or spells a priority comparison of its own.
        #expect(!body.contains("scheduledStartMin"))
        #expect(!body.contains("priorityRank("))
        #expect(!body.contains(".priority !="))
    }
}
