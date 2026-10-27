import Foundation
import SwiftData
import Testing
@testable import Cadence

/// `CadenceScheduleSupport`'s day orderings have to be **total**, for the same reason
/// `TaskOrdering.fallbackPrecedes` exists.
///
/// Both task comparators here used to end at a bare `$0.order < $1.order`, and `order` is
/// assigned **per container** (`CadenceTaskQuerySupport.nextTaskOrder(in:)` maxes over one
/// list), so every surface these functions feed — iPad Today, the iOS calendar, the macOS
/// calendar page and schedule panel — routinely compares two same-time tasks that carry the
/// same `order` because they came from different lists. Bundles were worse: they sorted on
/// `startMin` alone with nothing at all beneath it.
///
/// A comparator that leaves two rows comparing equal both ways gives an unstable sort, so the
/// rendered sequence is whatever the input order happened to be. Every test below therefore
/// sorts the *same* fixture from several different input permutations and requires identical
/// output; a single-permutation assertion would pass against a comparator that merely got
/// lucky.
@MainActor
struct CadenceScheduleOrderingTests {
    private let dayKey = "2026-05-11"
    private let otherDayKey = "2026-05-12"

    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    // MARK: - Fixtures

    /// Two lists' worth of tasks on one day, numbered the way the app numbers them: `order`
    /// comes from `nextTaskOrder(in:)` over **that container's** tasks, so the first task in
    /// each area is `order == 0` and the collision is genuine rather than typed in.
    ///
    /// The pairs that collide also share `createdAt`, so the tie-break has to reach title.
    private func crossContainerTasks(in context: ModelContext) -> [AppTask] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let work = Area(name: "Work")
        let home = Area(name: "Home")
        context.insert(work)
        context.insert(home)

        var workTasks: [AppTask] = []
        var homeTasks: [AppTask] = []

        func add(_ title: String, to area: Area, startMin: Int, createdAt: Date) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = dayKey
            task.scheduledStartMin = startMin
            task.createdAt = createdAt
            task.area = area
            let siblings = area === work ? workTasks : homeTasks
            task.order = CadenceTaskQuerySupport.nextTaskOrder(in: siblings)
            context.insert(task)
            if area === work { workTasks.append(task) } else { homeTasks.append(task) }
            return task
        }

        // Work: orders 0, 1, 2.
        let draft = add("Draft the deck", to: work, startMin: 540, createdAt: base)
        let sync = add("Sync with design", to: work, startMin: 600, createdAt: base.addingTimeInterval(60))
        let zip = add("Zip the archive", to: work, startMin: 540, createdAt: base)
        // Home: orders 0, 1, 2 again — the same three numbers, in a different container.
        let water = add("Water the plants", to: home, startMin: 540, createdAt: base)
        let pay = add("Pay the bill", to: home, startMin: 600, createdAt: base.addingTimeInterval(60))
        let archive = add("Archive receipts", to: home, startMin: 540, createdAt: base)

        return [draft, sync, zip, water, pay, archive]
    }

    /// The sequence the fixture has to produce: start minute, then `order`, then `createdAt`,
    /// then title. Every adjacent pair below is decided by a different rung.
    private var expectedTaskTitles: [String] {
        [
            "Draft the deck",     // 09:00, order 0
            "Water the plants",   // 09:00, order 0 — same createdAt, later title
            "Archive receipts",   // 09:00, order 2
            "Zip the archive",    // 09:00, order 2 — same createdAt, later title
            "Pay the bill",       // 10:00, order 1
            "Sync with design"    // 10:00, order 1 — same createdAt, later title
        ]
    }

    // MARK: - Helpers

    private func permutations<T>(_ items: [T]) -> [[T]] {
        [
            items,
            items.reversed(),
            Array(items.dropFirst() + items.prefix(1)),
            Array(items.suffix(2) + items.dropLast(2))
        ]
    }

    // MARK: - Tasks: the direct day lookup

    @Test
    func scheduledTasksOnADaySortTheSameFromEveryInputPermutation() throws {
        let context = ModelContext(try makeContainer())
        let tasks = crossContainerTasks(in: context)

        // Non-vacuity: the fixture really does collide on `order` at one start minute.
        let nineAM = tasks.filter { $0.scheduledStartMin == 540 }
        #expect(nineAM.count == 4)
        #expect(Set(nineAM.map(\.order)).count < nineAM.count)

        let results = permutations(tasks).map { input in
            CadenceScheduleSupport
                .scheduledTasks(on: dayKey, from: input, includeCompleted: true)
                .map(\.title)
        }

        for (index, result) in results.enumerated() {
            #expect(result == expectedTaskTitles, "permutation \(index) produced \(result)")
        }
    }

    @Test
    func scheduledTasksTiedOnEveryFieldButIdentityStillOrderTheSameWay() throws {
        let context = ModelContext(try makeContainer())
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let twins = (0..<2).map { _ -> AppTask in
            let task = AppTask(title: "Standup")
            task.scheduledDate = dayKey
            task.scheduledStartMin = 540
            task.order = 0
            task.createdAt = base
            context.insert(task)
            return task
        }

        let forward = CadenceScheduleSupport
            .scheduledTasks(on: dayKey, from: twins, includeCompleted: true)
            .map(\.id)
        let backward = CadenceScheduleSupport
            .scheduledTasks(on: dayKey, from: twins.reversed(), includeCompleted: true)
            .map(\.id)

        #expect(forward.count == 2)
        #expect(forward == backward)
        #expect(forward.first == twins.min(by: { $0.id.uuidString < $1.id.uuidString })?.id)
    }

    // MARK: - Tasks: the grouped-by-date lookup

    @Test
    func tasksGroupedByScheduledDateSortTheSameFromEveryInputPermutation() throws {
        let context = ModelContext(try makeContainer())
        let tasks = crossContainerTasks(in: context)

        let results = permutations(tasks).map { input in
            (CadenceScheduleSupport.tasksByScheduledDate(input, includeCompleted: true)[dayKey] ?? [])
                .map(\.title)
        }

        for (index, result) in results.enumerated() {
            #expect(result == expectedTaskTitles, "permutation \(index) produced \(result)")
        }
    }

    /// The two lookups are two spellings of one rule, so they must not disagree.
    @Test
    func theDayLookupAndTheGroupedLookupAgreeOnTaskOrder() throws {
        let context = ModelContext(try makeContainer())
        let tasks = crossContainerTasks(in: context)

        let direct = CadenceScheduleSupport
            .scheduledTasks(on: dayKey, from: tasks, includeCompleted: true)
            .map(\.id)
        let grouped = CadenceScheduleSupport
            .items(on: dayKey, in: CadenceScheduleSupport.tasksByScheduledDate(tasks, includeCompleted: true))
            .map(\.id)

        #expect(!direct.isEmpty)
        #expect(direct == grouped)
    }

    // MARK: - [[T-3213]] a task inside a block is not hidden

    /// The four lookups used to drop every member of a `TaskBundle`, because a block's card drew
    /// them. Nothing draws a block any more, so the filter only hid the task; the owner ruled the
    /// bundles out of the app on 2026-10-26. A member is listed like any other task.
    @Test
    func aTaskInsideABlockIsListedByEveryDayLookup() throws {
        let context = ModelContext(try makeContainer())
        let block = TaskBundle(title: "Old block", dateKey: dayKey, startMin: 540, durationMinutes: 60)
        context.insert(block)
        let timed = AppTask(title: "Timed member")
        timed.scheduledDate = dayKey
        timed.scheduledStartMin = 600
        let untimed = AppTask(title: "Untimed member")
        untimed.scheduledDate = dayKey
        untimed.scheduledStartMin = -1
        for task in [timed, untimed] {
            context.insert(task)
            CadenceTestBundleFixture.place(task, in: block)
        }
        // The fixture writes the block-era `-1`; one member has since been given its own time.
        timed.scheduledStartMin = 600
        // Non-vacuity: both really are members.
        #expect(timed.bundle?.id == block.id && untimed.bundle?.id == block.id)

        let tasks = [timed, untimed]
        #expect(CadenceScheduleSupport.scheduledTasks(on: dayKey, from: tasks, includeCompleted: true).map(\.id) == [timed.id])
        #expect(CadenceScheduleSupport.tasksByScheduledDate(tasks, includeCompleted: true)[dayKey]?.map(\.id) == [timed.id])
        #expect(CadenceScheduleSupport.unscheduledTasksByDate(tasks)[dayKey]?.map(\.id) == [untimed.id])
        #expect(Set(CadenceScheduleSupport.monthTasksByDate(tasks)[dayKey]?.map(\.id) ?? []) == [timed.id, untimed.id])
        #expect(Set(CalendarBoardPlannerSupport.tasksByBoardDate(from: tasks)[dayKey]?.map(\.id) ?? []) == [timed.id, untimed.id])
    }

    // MARK: - The comparators themselves

    /// The structural statement behind every permutation test above: for each distinct pair,
    /// exactly one direction is true. A missing tie-break makes both false.
    @Test
    func everyDistinctPairOfScheduledTasksOrdersInExactlyOneDirection() throws {
        let context = ModelContext(try makeContainer())
        let tasks = crossContainerTasks(in: context)

        for lhs in tasks {
            #expect(!CadenceScheduleSupport.scheduledTaskPrecedes(lhs, lhs))
            for rhs in tasks where lhs.id != rhs.id {
                #expect(
                    CadenceScheduleSupport.scheduledTaskPrecedes(lhs, rhs)
                        != CadenceScheduleSupport.scheduledTaskPrecedes(rhs, lhs),
                    "'\(lhs.title)' ties with '\(rhs.title)'"
                )
            }
        }
    }


}
