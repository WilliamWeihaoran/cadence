import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-1348: a list cascade cancelled its habits' and its tasks' reminders **before** anybody tried
/// to commit it.
///
/// The two legs had one shape. `ModelContext.deleteContext` built `habitIDs` and fired
/// `cancel(habitIDs:)` immediately before `return true`, in a function that makes no commit at all
/// — T-291's whole design is that the cascade is one pending change and the *surface* commits it.
/// `CadenceTaskMutationSupport.deleteTasks` did the same for tasks whenever
/// `commitsImmediately` was `false`, which is exactly and only the list cascades, so it reached
/// `deleteProject` and `deleteArea` too. A refused commit then rolled every row back and left
/// nothing scheduled for any of them, silently, until the next `scenePhase` reconcile.
///
/// **Why the queue is the seam and not a notification-centre read.** `NotificationManager.cancel`
/// returns early under `isTestEnvironment`, so a cancellation that runs is invisible to this
/// target — which is precisely how a side effect on the refusal path survived. The tests below
/// therefore assert on `CadenceDeferredReminderCancellations`, the object
/// `CadencePendingChangePersistence.commitCascade` releases: `releasedHabitIDs` is what actually
/// reached the notification centre, `pendingHabitIDs` is what was earned and correctly withheld.
/// Asserting both is what keeps "no cancellation ran" from passing vacuously on a cascade that
/// never reached the line.
@MainActor
struct CadenceDeferredReminderCancellationTests {

    private struct CommitRefused: Error {}

    /// A store holding one context with a habit and a task under it, already committed.
    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let context: Context
        let habit: Habit
        let task: AppTask
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let habit = Habit(title: "Stretch", context: context)
        habit.reminderMinuteOfDay = 8 * 60
        let task = AppTask(title: "File the return")
        task.context = context
        modelContext.insert(context)
        modelContext.insert(habit)
        modelContext.insert(task)
        try modelContext.save()
        return Fixture(
            container: container,
            modelContext: modelContext,
            context: context,
            habit: habit,
            task: task
        )
    }

    /// A stand-in task sweep that refuses, so the cascade aborts before it deletes anything.
    /// The same shape `CadenceListCascadeRollbackTests` uses, and for the same reason: the real
    /// abort is a store read an in-memory container will not fail.
    private nonisolated static func refusingSweep(_ ids: Set<UUID>) -> Bool { false }

    // MARK: - The refusal path

    /// **The ticket, asserted on the reminder rather than on the row.**
    ///
    /// The row was never the part that broke — `commitDelete`'s `rollback()` has always put the
    /// habit back, and `CadenceListCascadeRollbackTests` already pins that. What a refused commit
    /// could not undo was the `Task { … cancel(habitIDs:) }` the cascade had already spawned. So
    /// the store assertion here is the control and `releasedHabitIDs` is the measurement.
    @Test func arefusedCommitLeavesTheHabitInTheStoreWithItsReminderUncancelled() throws {
        let fixture = try makeFixture()
        let cancellations = CadenceDeferredReminderCancellations()

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: fixture.modelContext,
                commit: { _ in throw CommitRefused() },
                cancellations: cancellations,
                cascade: { fixture.modelContext.deleteContext(fixture.context) }
            )
        }

        #expect(
            cancellations.releasedHabitIDs.isEmpty,
            "the refused delete cancelled the reminder for a habit it just put back"
        )
        // Non-vacuity: the cascade really did reach the cancellation and really did earn it. A
        // cascade that never got there would satisfy the assertion above for the wrong reason.
        #expect(
            cancellations.pendingHabitIDs == [fixture.habit.id],
            "the context cascade no longer hands its habits' reminders to the commit that owns them"
        )

        #expect(!fixture.modelContext.hasChanges, "the refused cascade left a pending change")
        let store = ModelContext(fixture.container)
        #expect(try store.fetch(FetchDescriptor<Habit>()).map(\.title) == ["Stretch"])
        #expect(try store.fetch(FetchDescriptor<Context>()).map(\.name) == ["Work"])
    }

    /// The larger leg, and the one the ticket only suspected: the task sweep every list cascade
    /// runs. `deleteProject` and `deleteArea` never cancelled anything of their own, so this was
    /// their only reminder side effect — and it fired on all three cascades, not just `Context`'s.
    @Test func arefusedAreaDeleteLeavesItsTasksRemindersUncancelled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        let cancellations = CadenceDeferredReminderCancellations()
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                cancellations: cancellations,
                cascade: { modelContext.deleteArea(area) }
            )
        }

        #expect(
            cancellations.releasedTaskIDs.isEmpty,
            "the refused area delete cancelled the reminder for a task it just put back"
        )
        #expect(
            cancellations.pendingTaskIDs == [task.id],
            "the deferred task sweep no longer hands its reminders to the commit that owns them"
        )
        #expect(!modelContext.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// The other refusal: the cascade itself could not finish. Nothing is deleted, so nothing is
    /// earned and nothing is released — the `false` return has to mean "changed nothing" for
    /// reminders exactly as it does for rows.
    @Test func acascadeThatCannotFinishCancelsNothing() throws {
        let fixture = try makeFixture()
        let cancellations = CadenceDeferredReminderCancellations()

        #expect(throws: CadencePendingChangePersistence.CascadeIncomplete.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: fixture.modelContext,
                cancellations: cancellations,
                cascade: {
                    fixture.modelContext.deleteContext(fixture.context, sweepTasks: Self.refusingSweep)
                }
            )
        }

        #expect(cancellations.releasedHabitIDs.isEmpty)
        #expect(cancellations.releasedTaskIDs.isEmpty)
        #expect(
            cancellations.pendingHabitIDs.isEmpty,
            "the cascade aborted at its guard and still queued a cancellation past it"
        )
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<Habit>()).count == 1)
    }

    // MARK: - The success path

    /// Non-vacuity for all three above: the fix defers the cancellation, it does not delete it.
    /// A commit that lands releases both legs, once, with the ids the cascade actually removed.
    @Test func acommittedContextDeleteCancelsItsHabitAndTaskRemindersOnce() throws {
        let fixture = try makeFixture()
        let cancellations = CadenceDeferredReminderCancellations()

        try CadencePendingChangePersistence.commitCascade(
            in: fixture.modelContext,
            cancellations: cancellations,
            cascade: { fixture.modelContext.deleteContext(fixture.context) }
        )

        #expect(cancellations.releasedHabitIDs == [fixture.habit.id])
        #expect(cancellations.releasedTaskIDs == [fixture.task.id])
        #expect(
            cancellations.pendingHabitIDs.isEmpty && cancellations.pendingTaskIDs.isEmpty,
            "the queue still holds work after a commit that landed"
        )

        let store = ModelContext(fixture.container)
        #expect(try store.fetch(FetchDescriptor<Context>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// `release()` runs each held effect once and forgets it, so a second call cannot fire a
    /// cancellation twice. `commitCascade` calls it once, but the queue is the thing that has to
    /// guarantee it rather than the caller.
    @Test func releasingTwiceCancelsOnce() {
        let cancellations = CadenceDeferredReminderCancellations()
        let id = UUID()
        let runs = Counter()
        cancellations.hold(taskIDs: [id], habitIDs: []) { runs.increment() }

        cancellations.release()
        cancellations.release()

        #expect(runs.value == 1)
        #expect(cancellations.releasedTaskIDs == [id])
        #expect(cancellations.pendingTaskIDs.isEmpty)
    }

    // MARK: - The committing half is untouched

    /// The gate, from the other side. A delete that commits itself is T-1301's shape already: its
    /// cancellation is below its own commit and a refusal returns before reaching it, so it must
    /// **not** hand anything to an enclosing queue — a cancellation released a second time by
    /// somebody else's commit is the mirror of the bug being fixed.
    @Test func adeleteThatCommitsItselfDefersNothing() throws {
        let fixture = try makeFixture()
        let cancellations = CadenceDeferredReminderCancellations()

        let deleted = CadenceDeferredReminderCancellations.$current.withValue(cancellations) {
            CadenceTaskMutationSupport.deleteTasks(
                withIDs: [fixture.task.id],
                modelContext: fixture.modelContext,
                commitsImmediately: true
            )
        }

        #expect(deleted)
        #expect(
            cancellations.pendingTaskIDs.isEmpty,
            "a delete that commits itself queued its cancellation behind somebody else's commit"
        )
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// And the refusal on that same committing path still returns before the cancellation, which
    /// is the property T-1301 established and T-1348 must not have disturbed.
    @Test func arefusedDirectTaskDeleteStillCancelsNothing() throws {
        let fixture = try makeFixture()
        let cancellations = CadenceDeferredReminderCancellations()

        let deleted = CadenceDeferredReminderCancellations.$current.withValue(cancellations) {
            CadenceTaskMutationSupport.deleteTasks(
                withIDs: [fixture.task.id],
                modelContext: fixture.modelContext,
                commitsImmediately: true,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(!deleted)
        #expect(cancellations.pendingTaskIDs.isEmpty)
        #expect(cancellations.releasedTaskIDs.isEmpty)
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    // MARK: - The source rule

    /// The cascades may not reach a reminder cancellation any way but the deferred one.
    ///
    /// Behaviour cannot see this: a `Task { await NotificationManager.shared.cancel(…) }` grown
    /// back anywhere in `CadenceListDeleteHelpers` would be inert under
    /// `NotificationManager.isTestEnvironment` and every assertion above would stay green while
    /// the shipped app cancelled reminders above a commit again.
    @Test func theListCascadesCancelOnlyThroughTheDeferredSpelling() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Services/CadenceListDeleteHelpers.swift")
        #expect(raw.count > 400, "the cascade file read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")

        #expect(
            stripped.contains("NotificationManager.deferReminderCancellation(habitIDs: habits.map(\\.id))"),
            "the context cascade no longer defers its habit reminders"
        )
        #expect(
            CadenceSourceScan.matchCount(#"NotificationManager\.shared\.cancel\("#, in: stripped) == 0,
            "a cascade cancels a reminder directly again, above a commit it does not make"
        )
        #expect(
            CadenceSourceScan.matchCount(#"NotificationManager\.cancelReminders\("#, in: stripped) == 0,
            "a cascade cancels a reminder outright again, above a commit it does not make"
        )
    }
}

/// A reference box, because the effects a queue releases are plain `@Sendable` closures and a
/// captured `var` in a `@Test` body is not one.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
