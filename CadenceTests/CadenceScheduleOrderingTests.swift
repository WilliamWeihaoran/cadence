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
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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

    /// Bundles sharing a start time, which nothing in the model prevents.
    private func tiedBundles(in context: ModelContext) -> [TaskBundle] {
        let specs: [(String, String, Int)] = [
            ("Deep work", dayKey, 540),
            ("Admin block", dayKey, 540),
            ("Evening review", dayKey, 1_080),
            ("Tomorrow prep", otherDayKey, 540),
            ("Morning triage", otherDayKey, 540)
        ]
        return specs.map { title, date, startMin in
            let bundle = TaskBundle(title: title, dateKey: date, startMin: startMin, durationMinutes: 30)
            context.insert(bundle)
            return bundle
        }
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
                .scheduledTasks(on: dayKey, from: input, includeCompleted: true, excludeBundled: false)
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
            .scheduledTasks(on: dayKey, from: twins, includeCompleted: true, excludeBundled: false)
            .map(\.id)
        let backward = CadenceScheduleSupport
            .scheduledTasks(on: dayKey, from: twins.reversed(), includeCompleted: true, excludeBundled: false)
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
            .scheduledTasks(on: dayKey, from: tasks, includeCompleted: true, excludeBundled: true)
            .map(\.id)
        let grouped = CadenceScheduleSupport
            .items(on: dayKey, in: CadenceScheduleSupport.tasksByScheduledDate(tasks, includeCompleted: true))
            .map(\.id)

        #expect(!direct.isEmpty)
        #expect(direct == grouped)
    }

    // MARK: - Bundles

    @Test
    func bundlesOnADaySortTheSameFromEveryInputPermutation() throws {
        let context = ModelContext(try makeContainer())
        let bundles = tiedBundles(in: context)

        // Non-vacuity: two bundles on the day really do share a start minute.
        let onDay = bundles.filter { $0.dateKey == dayKey }
        #expect(onDay.filter { $0.startMin == 540 }.count == 2)

        let results = permutations(bundles).map { input in
            CadenceScheduleSupport.bundles(on: dayKey, from: input, includeCompleted: true)
                .map(\.displayTitle)
        }

        for (index, result) in results.enumerated() {
            #expect(result == ["Admin block", "Deep work", "Evening review"], "permutation \(index) produced \(result)")
        }
    }

    @Test
    func bundlesGroupedByDateSortTheSameFromEveryInputPermutation() throws {
        let context = ModelContext(try makeContainer())
        let bundles = tiedBundles(in: context)

        let results = permutations(bundles).map { input in
            (CadenceScheduleSupport.bundlesByDate(input, includeCompleted: true)[otherDayKey] ?? [])
                .map(\.displayTitle)
        }

        for (index, result) in results.enumerated() {
            #expect(result == ["Morning triage", "Tomorrow prep"], "permutation \(index) produced \(result)")
        }
    }

    /// The direct day lookup and the grouped lookup are one rule, spelled once.
    @Test
    func theDayLookupAndTheGroupedLookupAgreeOnBundleOrder() throws {
        let context = ModelContext(try makeContainer())
        let bundles = tiedBundles(in: context)

        for key in [dayKey, otherDayKey] {
            let direct = CadenceScheduleSupport.bundles(on: key, from: bundles, includeCompleted: true).map(\.id)
            let grouped = CadenceScheduleSupport
                .items(on: key, in: CadenceScheduleSupport.bundlesByDate(bundles, includeCompleted: true))
                .map(\.id)
            #expect(!direct.isEmpty)
            #expect(direct == grouped, "the two lookups disagreed on \(key)")
        }
    }

    @Test
    func bundlesTiedOnDayStartAndTitleStillOrderTheSameWay() throws {
        let context = ModelContext(try makeContainer())
        let twins = (0..<2).map { _ -> TaskBundle in
            let bundle = TaskBundle(title: "Standup", dateKey: dayKey, startMin: 540, durationMinutes: 30)
            context.insert(bundle)
            return bundle
        }

        let forward = CadenceScheduleSupport.bundles(on: dayKey, from: twins, includeCompleted: true).map(\.id)
        let backward = CadenceScheduleSupport
            .bundles(on: dayKey, from: twins.reversed(), includeCompleted: true)
            .map(\.id)

        #expect(forward.count == 2)
        #expect(forward == backward)
        #expect(forward.first == twins.min(by: { $0.id.uuidString < $1.id.uuidString })?.id)
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

    @Test
    func everyDistinctPairOfBundlesOrdersInExactlyOneDirection() throws {
        let context = ModelContext(try makeContainer())
        let bundles = tiedBundles(in: context)

        for lhs in bundles {
            #expect(!CadenceScheduleSupport.bundlePrecedes(lhs, lhs))
            for rhs in bundles where lhs.id != rhs.id {
                #expect(
                    CadenceScheduleSupport.bundlePrecedes(lhs, rhs)
                        != CadenceScheduleSupport.bundlePrecedes(rhs, lhs),
                    "'\(lhs.displayTitle)' ties with '\(rhs.displayTitle)'"
                )
            }
        }
    }
}
