import Foundation
import SwiftData

/// Every field a task-field editor writes, captured before the write.
///
/// **Why raw strings rather than the enums.** `statusRaw`, `priorityRaw` and `recurrenceRaw` are
/// the stored properties; the computed `status` / `priority` / `recurrenceRule` in front of them
/// coerce an unrecognised value to a default on read. Snapshotting the computed side would put
/// that default back as if the user had chosen it — a restore that quietly rewrites a row it was
/// meant to leave alone. Restoring the raw is the only spelling that is a no-op when the commit
/// lands and an exact undo when it does not.
///
/// The three relationships are the to-one sides only, which is the same reach the write had:
/// `TaskContainerResolver.applyContainer` assigns `task.area` / `project` / `context` and lets
/// SwiftData maintain the inverse arrays, so assigning them back is symmetric with it.
struct CadenceTaskFieldSnapshot {
    let taskID: UUID

    private let statusRaw: String
    private let completedAt: Date?
    private let priorityRaw: String
    private let estimatedMinutes: Int
    private let sectionName: String
    private let scheduledDate: String
    private let scheduledStartMin: Int
    private let dueDate: String
    private let recurrenceRaw: String
    private let recurrenceSeriesIDRaw: String
    private let recurrenceSpawnedTaskIDRaw: String
    private let area: Area?
    private let project: Project?
    private let context: Context?

    init(_ task: AppTask) {
        taskID = task.id
        statusRaw = task.statusRaw
        completedAt = task.completedAt
        priorityRaw = task.priorityRaw
        estimatedMinutes = task.estimatedMinutes
        sectionName = task.sectionName
        scheduledDate = task.scheduledDate
        scheduledStartMin = task.scheduledStartMin
        dueDate = task.dueDate
        recurrenceRaw = task.recurrenceRaw
        recurrenceSeriesIDRaw = task.recurrenceSeriesIDRaw
        recurrenceSpawnedTaskIDRaw = task.recurrenceSpawnedTaskIDRaw
        area = task.area
        project = task.project
        context = task.context
    }

    /// The successor `markDone` / `markCancelled` minted after this snapshot was taken, if they
    /// did. `nil` when the pointer did not change, so a task that already had a successor before
    /// the edit is never mistaken for one that just gained one.
    func spawnedSuccessorID(comparedWith task: AppTask) -> UUID? {
        guard task.recurrenceSpawnedTaskIDRaw != recurrenceSpawnedTaskIDRaw else { return nil }
        return task.recurrenceSpawnedTaskID
    }

    func restore(to task: AppTask) {
        task.statusRaw = statusRaw
        task.completedAt = completedAt
        task.priorityRaw = priorityRaw
        task.estimatedMinutes = estimatedMinutes
        task.sectionName = sectionName
        task.scheduledDate = scheduledDate
        task.scheduledStartMin = scheduledStartMin
        task.dueDate = dueDate
        task.recurrenceRaw = recurrenceRaw
        task.recurrenceSeriesIDRaw = recurrenceSeriesIDRaw
        task.recurrenceSpawnedTaskIDRaw = recurrenceSpawnedTaskIDRaw
        task.area = area
        task.project = project
        task.context = context
    }
}

/// One field edit made from a task **embed card**, committed, with the card told only if it landed.
///
/// **What it fixes (T-366).** `TaskEmbedFieldEditorPopover` mutated the live `AppTask`, ran
/// `try? modelContext.save()`, and then called `onChanged()` — unconditionally. `onChanged()` is
/// what makes the note editor re-render the embedded task card, so a refused save repainted the
/// card with a priority, a date or a container the store does not hold, and nothing on screen said
/// otherwise. The card was the *only* report of success, which is what made it a lie.
///
/// **The undo is a field snapshot, not `modelContext.rollback()`**, and that is the whole reason
/// this exists rather than a second call to `CadencePendingChangePersistence.commitDelete`. This
/// popover opens over a note editor that shares the same `ModelContext` and holds the user's
/// in-flight note text as a pending change. Rolling back to undo a refused priority edit would
/// throw that text away — a fix strictly worse than the bug. Same shape, same reason, as
/// `CadenceAINoteSummary.append`.
///
/// **Two writes reach past the task's own fields, and both are handled rather than ignored.**
/// - `markDone` / `markCancelled` mint the next occurrence of a recurring task and insert it. A
///   snapshot cannot restore an insert, so the successor is deleted — identified by the pointer
///   the spawn wrote, not by guessing.
/// - `applyRecurrenceRule(scope: .thisAndFuture)` writes the rule to every later occurrence in the
///   series. Those are `alsoRestoring:`; the caller already computes the same list to perform the
///   edit, so it passes it rather than this type re-deriving it differently.
///
/// **The reconcile on the failure path is not belt-and-braces.** The date edits go through
/// `CadenceTaskDateEditing`, which reconciles OS notifications as part of the mutation — before
/// anyone knows whether the commit will be accepted. So a refused date edit has already retired
/// the old reminder and armed a new one for a day the store never took. Reconciling again after
/// the restore is what puts the notifications back in step with the task; leaving it to the next
/// `scenePhase` transition is exactly the latency T-362 closed. It is a parameter for the reason
/// `CadenceWindDownReconciler` is one everywhere else: `.default` is inert in a test host, so a
/// test that wants to watch it injects its own recorder.
@MainActor
enum CadenceTaskFieldEditCommit {

    /// Shown inside the still-open popover. Singular, because one popover edits one field — the
    /// list editors' plural sentence (`CadencePendingChangePersistence.editFailureNotice`) would
    /// be describing something the user did not do.
    static let saveFailureNotice = "Couldn't save this change."

    /// Applies `apply`, commits it, and returns whether the change is in the store.
    ///
    /// `false` means the task — and every task in `alsoRestoring` — is back exactly as it was
    /// found, so the caller must not report success: no card refresh, no dismissal.
    ///
    /// - Parameter alsoRestoring: Other tasks `apply` writes to. Snapshotted with `task`.
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    @discardableResult
    static func commit(
        _ task: AppTask,
        alsoRestoring others: [AppTask] = [],
        in modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        apply: () -> Void
    ) -> Bool {
        var targets = [task]
        for other in others where !targets.contains(where: { $0.id == other.id }) {
            targets.append(other)
        }
        let snapshots = targets.map(CadenceTaskFieldSnapshot.init)

        apply()

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                undo(snapshots, on: targets, in: modelContext, reconciler: reconciler)
            }
        } catch {
            return false
        }
        return true
    }

    /// Successors first, then fields: reading which successor was minted needs the pointer the
    /// spawn wrote, and restoring the fields is what overwrites it.
    private static func undo(
        _ snapshots: [CadenceTaskFieldSnapshot],
        on targets: [AppTask],
        in modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler?
    ) {
        for (snapshot, target) in zip(snapshots, targets) {
            if let successorID = snapshot.spawnedSuccessorID(comparedWith: target),
               let successor = pendingInsertedTask(withID: successorID, in: modelContext) {
                modelContext.delete(successor)
            }
        }
        for (snapshot, target) in zip(snapshots, targets) {
            snapshot.restore(to: target)
        }
        (reconciler ?? .default).run(in: modelContext)
    }

    /// Deliberately looks **only** among the context's pending inserts, not through a fetch.
    ///
    /// The successor this is hunting was minted by `apply` moments ago and has not been committed
    /// — the commit is what just failed — so a pending insert is the only place it can be. Narrowing
    /// the search that way is also what makes the deletion safe: a pointer that came to name a task
    /// the store already held could never be matched here, so no undo can delete a row it did not
    /// create.
    private static func pendingInsertedTask(withID id: UUID, in modelContext: ModelContext) -> AppTask? {
        modelContext.insertedModelsArray
            .compactMap { $0 as? AppTask }
            .first { $0.id == id }
    }
}
