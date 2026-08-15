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
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
}
