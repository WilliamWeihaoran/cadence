import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-3170]]: the Block feature leaves, and no member task loses its place in the day.**
///
/// The hazard this suite exists for is one line of the feature it is retiring:
/// CadenceTaskMutationSupport.assignTask writes `task.scheduledStartMin = -1` on every task that
/// joins a block, because the block carries the slot. `-1` is the unscheduled sentinel the
/// timeline's layout filters on. Delete the blocks and stop there and every member is on its date
/// with no time — drawn nowhere, with nothing on screen to say it happened.
///
/// So every test below ends on the same two questions: is any member still `-1`, and is every
/// member still inside the span its block occupied. The store is read back through a second
/// `ModelContext` on the same container wherever the answer is about what was *committed*, which
/// is the reading `TaskBundleTests` established for this area and the only one a live object does
/// not flatter.
/// The suite is deliberately **not** `@MainActor`: the pass it tests is not, and a suite that
/// acquired the isolation anyway could not have caught the day this type needed it.
struct CadenceTaskBundleRetirementTests {

    private struct CommitRefused: Error {}

    private static let day = "2026-05-01"

    private static func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceTestStore.container()
        return (container, ModelContext(container))
    }

    /// Builds a block with `count` members, each estimated at `estimate` minutes, in order.
    @discardableResult
    private static func makeBlock(
        in context: ModelContext,
        title: String,
        startMin: Int,
        durationMinutes: Int,
        memberCount: Int,
        estimate: Int = 30,
        dateKey: String = day
    ) -> (bundle: TaskBundle, members: [AppTask]) {
        let bundle = TaskBundle(
            title: title,
            dateKey: dateKey,
            startMin: startMin,
            durationMinutes: durationMinutes
        )
        context.insert(bundle)
        var members: [AppTask] = []
        for index in 0..<memberCount {
            let task = AppTask(title: "\(title) member \(index)")
            task.estimatedMinutes = estimate
            context.insert(task)
            task.bundle = bundle
            task.bundleOrder = index
            task.scheduledDate = dateKey
            // The state the feature really leaves a member in. Spelled here rather than reached
            // through `assignTask` so the fixture cannot be quietly repaired by a change to the
            // code under test.
            task.scheduledStartMin = -1
            bundle.tasks = (bundle.tasks ?? []) + [task]
            members.append(task)
        }
        return (bundle, members)
    }

    // MARK: - The arithmetic, asserted where it can be read

    /// The fitting branch: members laid end to end from the block's start, at their own lengths.
    @Test func membersThatFitTheirBlockAreLaidOutEndToEndFromItsStart() {
        let starts = TaskBundleRetirement.memberStartMinutes(
            lengths: [10, 20, 15],
            blockStart: 600,
            blockDuration: 60
        )
        #expect(starts == [600, 610, 630])
    }

    /// The non-fitting branch: equal slices of the block's own span, never past its end.
    ///
    /// 4 members, 30 minutes: slices of 7 and a bit, spread across the span rather than bunched at
    /// the top — which is what `span * index / count` buys over `index * (span / count)`, whose
    /// answer here would be `[600, 607, 614, 621]` and would leave nine of the thirty minutes
    /// unused at the bottom.
    @Test func membersThatDoNotFitShareTheBlocksOwnSpanAndNeverPassItsEnd() {
        let starts = TaskBundleRetirement.memberStartMinutes(
            lengths: [30, 30, 30, 30],
            blockStart: 600,
            blockDuration: 30
        )
        #expect(starts == [600, 607, 615, 622])
        #expect(starts.allSatisfy { $0 >= 600 && $0 < 630 }, "a member was laid out past the block's end")
        #expect(starts == starts.sorted(), "the block's order was not preserved")
    }

    /// No members, no starts — and, below, no block either.
    @Test func aBlockWithNoMembersHasNothingToLayOut() {
        #expect(TaskBundleRetirement.memberStartMinutes(lengths: [], blockStart: 600, blockDuration: 30).isEmpty)
    }

    /// More members than the block has minutes: the slices collapse, which is the one case where
    /// `bundleOrder` stops deciding the on-screen order. It is asserted rather than left implicit
    /// because the pass's own note makes that promise and no other — the starts must still be
    /// non-decreasing, real, and inside the block.
    @Test func moreMembersThanMinutesStillLandsEveryoneInsideTheBlock() {
        let starts = TaskBundleRetirement.memberStartMinutes(
            lengths: Array(repeating: 5, count: 40),
            blockStart: 600,
            blockDuration: 10
        )
        #expect(starts.count == 40)
        #expect(starts.allSatisfy { $0 >= 600 && $0 < 610 })
        #expect(starts == starts.sorted())
        #expect(starts.allSatisfy { $0 != -1 })
    }

    // MARK: - The store walk

    /// **The headline, over blocks of 1, 3 and many members including one that cannot fit its
    /// own.** Every member comes out with a real start minute inside the span its block held, the
    /// blocks are gone, and no task is left holding the sentinel.
    @Test func everyMemberOfEveryBlockKeepsARealTimeInsideTheBlockItWasIn() throws {
        let (container, context) = try Self.makeContext()

        // One member, a 30-minute block at 09:00.
        let single = Self.makeBlock(
            in: context, title: "Solo", startMin: 540, durationMinutes: 30, memberCount: 1, estimate: 30
        )
        // Three members that fit: 3 x 15 in a 60-minute block at 10:00.
        let trio = Self.makeBlock(
            in: context, title: "Trio", startMin: 600, durationMinutes: 60, memberCount: 3, estimate: 15
        )
        // Nine members that cannot fit: 9 x 30 in a 45-minute block at 14:00.
        let crowd = Self.makeBlock(
            in: context, title: "Crowd", startMin: 840, durationMinutes: 45, memberCount: 9, estimate: 30
        )
        // An empty block, which has nothing to preserve.
        let empty = Self.makeBlock(
            in: context, title: "Empty", startMin: 1_080, durationMinutes: 30, memberCount: 0
        )
        let emptyID = empty.bundle.id
        try context.save()

        let outcome = TaskBundleRetirement.runIfNeeded(modelContext: context)
        #expect(outcome == .changed)

        let stored = ModelContext(container)
        #expect(try stored.fetch(FetchDescriptor<TaskBundle>()).isEmpty, "a block survived the retirement")
        #expect(
            try stored.fetch(FetchDescriptor<TaskBundle>()).allSatisfy { $0.id != emptyID },
            "the empty block survived"
        )

        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 13, "the retirement took tasks with it: \(tasks.count) of 13 left")
        #expect(
            tasks.allSatisfy { $0.scheduledStartMin != -1 },
            "a member came out of its block unscheduled, which is the whole of T-3170"
        )
        #expect(tasks.allSatisfy { $0.bundle == nil }, "a task is still attached to a block")
        #expect(tasks.allSatisfy { $0.scheduledDate == Self.day }, "a member left its block's day")

        func starts(ofTitlesPrefixed prefix: String) -> [Int] {
            tasks.filter { $0.title.hasPrefix(prefix) }
                .sorted { $0.title < $1.title }
                .map(\.scheduledStartMin)
        }

        #expect(starts(ofTitlesPrefixed: "Solo") == [540], "the one member did not take the block's own start")
        #expect(starts(ofTitlesPrefixed: "Trio") == [600, 615, 630], "three fitting members were not laid end to end")

        let crowdStarts = starts(ofTitlesPrefixed: "Crowd")
        #expect(crowdStarts.count == 9)
        #expect(
            crowdStarts.allSatisfy { $0 >= 840 && $0 < 885 },
            "an overcommitted block spilled a member outside itself: \(crowdStarts)"
        )
        #expect(crowdStarts == crowdStarts.sorted(), "the overcommitted block lost its member order")

        // Non-vacuity for the fixture: these really were the shapes the ticket names.
        #expect(single.members.count == 1 && trio.members.count == 3 && crowd.members.count == 9)
    }

    /// A member that is cancelled is laid out too. It is hidden from the timeline today, so its
    /// start minute is invisible — which is exactly why it would be the one left holding `-1`, to
    /// surface as a timeless task the first time the user un-cancels it.
    @Test func aCancelledMemberIsGivenATimeToo() throws {
        let (container, context) = try Self.makeContext()
        let block = Self.makeBlock(
            in: context, title: "Mixed", startMin: 600, durationMinutes: 60, memberCount: 2, estimate: 15
        )
        block.members[1].status = .cancelled
        try context.save()

        _ = TaskBundleRetirement.runIfNeeded(modelContext: context)

        let stored = ModelContext(container)
        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.scheduledStartMin != -1 }, "the cancelled member kept the sentinel")
    }

    /// A task that was never in a block is not touched — including one legitimately sitting on a
    /// day with no time, which is a state `removeTaskFromBundle(_:keepOnBundleDate:)` has always
    /// been able to produce and which this pass must not mistake for work.
    @Test func aTaskThatWasNeverInABlockIsLeftExactlyAsItWas() throws {
        let (container, context) = try Self.makeContext()
        let loose = AppTask(title: "On the day, no time")
        loose.scheduledDate = Self.day
        loose.scheduledStartMin = -1
        context.insert(loose)
        Self.makeBlock(in: context, title: "Block", startMin: 600, durationMinutes: 30, memberCount: 1)
        try context.save()

        _ = TaskBundleRetirement.runIfNeeded(modelContext: context)

        let stored = ModelContext(container)
        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        let untouched = try #require(tasks.first { $0.title == "On the day, no time" })
        #expect(untouched.scheduledStartMin == -1, "the pass rescheduled a task that was never in a block")
        let member = try #require(tasks.first { $0.title.hasPrefix("Block member") })
        #expect(member.scheduledStartMin == 600)
    }

    /// Idempotent, and cheap on the launch after the first: with no blocks left the pass answers
    /// `nothingToDo` rather than re-walking the task table.
    @Test func aSecondRunHasNothingToDo() throws {
        let (_, context) = try Self.makeContext()
        Self.makeBlock(in: context, title: "Once", startMin: 600, durationMinutes: 30, memberCount: 2)
        try context.save()

        #expect(TaskBundleRetirement.runIfNeeded(modelContext: context) == .changed)
        #expect(TaskBundleRetirement.runIfNeeded(modelContext: context) == .nothingToDo)
    }

    /// An empty store is a result, not a failure — the distinction T-1402 drew for the other
    /// startup passes, and the reason this one answers `CadenceMaintenancePassOutcome`.
    @Test func anEmptyStoreIsNothingToDoAndNotAFailedRead() throws {
        let (_, context) = try Self.makeContext()
        #expect(TaskBundleRetirement.runIfNeeded(modelContext: context) == .nothingToDo)
    }

    /// A refused commit leaves the store exactly where it was: the blocks are still there and
    /// their members are still in them. The pass reports the refusal rather than swallowing it, so
    /// `performStartupMaintenance`'s instrument records a `refused` stage instead of a clean one.
    @Test func aRefusedCommitLeavesEveryBlockAndEveryMembershipAlone() throws {
        let (container, context) = try Self.makeContext()
        Self.makeBlock(in: context, title: "Kept", startMin: 600, durationMinutes: 30, memberCount: 2)
        try context.save()

        let outcome = TaskBundleRetirement.runIfNeeded(modelContext: context) { _ in
            throw CommitRefused()
        }
        #expect(outcome == .couldNotRead, "a refused commit was reported as a clean pass")

        let stored = ModelContext(container)
        let bundles = try stored.fetch(FetchDescriptor<TaskBundle>())
        #expect(bundles.count == 1, "the block was removed by a refused commit")
        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.bundle != nil }, "a membership was dropped by a refused commit")
        #expect(tasks.allSatisfy { $0.scheduledStartMin == -1 }, "a start minute was written by a refused commit")
    }

    /// An estimate is user data. The pass moves a task's start; it does not decide how long the
    /// user thinks the task takes, in either branch.
    @Test func noMembersEstimateIsRewritten() throws {
        let (container, context) = try Self.makeContext()
        Self.makeBlock(in: context, title: "Fits", startMin: 600, durationMinutes: 120, memberCount: 2, estimate: 20)
        Self.makeBlock(in: context, title: "Spills", startMin: 900, durationMinutes: 20, memberCount: 3, estimate: 45)
        try context.save()

        _ = TaskBundleRetirement.runIfNeeded(modelContext: context)

        let stored = ModelContext(container)
        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.filter { $0.title.hasPrefix("Fits") }.allSatisfy { $0.estimatedMinutes == 20 })
        #expect(tasks.filter { $0.title.hasPrefix("Spills") }.allSatisfy { $0.estimatedMinutes == 45 })
    }

    /// The two constants this pass spells for itself really are the ones that sized the blocks it
    /// is taking apart. They are re-spelled rather than read because
    /// `CadenceTaskMutationSupport`'s copies are `MainActor`-isolated and the archive import that
    /// shares this arithmetic is not — the same arrangement, and the same failure mode, as
    /// `bundleClampsMatchTheTimelineDayRange` between that type and `TimelineDayRange`.
    @Test func theClampsMatchTheOnesThatSizedTheBlocks() {
        #expect(TaskBundleRetirement.minimumSlotMinutes == CadenceTaskMutationSupport.bundleMinimumDuration)
        #expect(TaskBundleRetirement.dayEndMin == CadenceTaskMutationSupport.bundleDayEndMin)
        for startMin in [-10, 0, 1, 600, 1_435, 1_436, 2_000] {
            #expect(
                TaskBundleRetirement.clampedStart(startMin)
                    == CadenceTaskMutationSupport.clampedBundleStart(startMin),
                "the two clamps disagree at \(startMin)"
            )
        }
    }
}
