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
/// The four relationships are the to-one sides only, which is the same reach the write had:
/// `TaskContainerResolver.applyContainer` assigns `task.area` / `project` / `context` and lets
/// SwiftData maintain the inverse arrays, so assigning them back is symmetric with it.
///
/// **`bundle` and `bundleOrder` are here because a drop handler started writing them ([[T-1952]]).**
/// The Calendar Board's Unscheduled rail detaches the card from its block before it clears the do
/// date — `SchedulingActions.removeTaskFromBundle` — so a refused commit that restored only the
/// date left the task out of the block it was still drawn in, and
/// `CadencePendingChangePersistence.editFailureNotice`'s "Nothing was changed" would have been a
/// second lie on top of the first. `bundle` is the to-one side, exactly as `area`/`project`/
/// `context` are: assigning it back re-enters the task in `TaskBundle.tasks` through the inverse
/// SwiftData maintains, which is the same route the detach left by.
/// `bundleOrder` **does** need the sibling repair `order` does not: `normalizeBundleOrder`
/// renumbers every remaining member of the block the task left, so the caller passes those members
/// as `alsoRestoring:` and this field is what puts their numbering back.
///
/// **`title` and `order` are here because leaving them out restored half of an edit (T-701).**
/// They are the two scalars a caller writes through this unit without writing anything else that
/// would give the omission away: an inline rename moves `title` and — through the `!` shortcut —
/// `priorityRaw`, and a move between lists moves the relationships and `order`. Restoring one and
/// not the other is a state neither outcome the user could have expected, and it was silent. It
/// cost two callers a hand-written near-copy of this undo before it cost anybody a bug.
/// `order` needs no sibling repair: `CadenceTaskMutationSupport.nextContainerOrder` reads the
/// destination's siblings but writes only the moved task, so putting that one value back is the
/// whole undo.
///
/// **`calendarEventID` is here for the same reason one ticket later ([[T-1980]]).** The Calendar
/// Board's day-column drop moves a *block*, and `SchedulingActions.dropBundle` clears every
/// member's calendar link as part of that move — the block owns the slot now, so a stale link
/// cannot stay. An undo that put back the two schedule fields and not this one would have left a
/// refused block move having silently unlinked its members from their calendar events, under the
/// same "Nothing was changed" sentence. It is the field this doc named as *not* carried until a
/// caller started writing it, which is exactly the sequence the boundary below asks for.
///
/// **The stated boundary.** `restore(to:)` assigns the nineteen properties below and nothing else.
/// A task's `notes`, `actualMinutes`, `createdAt`, the `recurrenceEnd*` and
/// `recurrenceSource*`/`recurrenceOccurrenceIndex` fields, `goal`, and the to-many `subtasks` /
/// `tags` / `focusSessions` are **not** carried — the to-manys because a snapshot of a relationship
/// array cannot restore an insert, and the rest because no caller of
/// `CadenceTaskFieldEditCommit.commit` writes them. A caller that starts to must add the field
/// here in the same change, and `thefieldSnapshotCapturesAndRestoresTheSameNineteenFields` in
/// `CadenceEditorSaveCommitSurfaceTests` pins the covered set exactly, so an addition on one side
/// of the pair cannot be forgotten on the other.
struct CadenceTaskFieldSnapshot {
    let taskID: UUID

    private let title: String
    private let order: Int
    private let statusRaw: String
    private let completedAt: Date?
    private let priorityRaw: String
    private let estimatedMinutes: Int
    private let sectionName: String
    private let scheduledDate: String
    private let scheduledStartMin: Int
    private let calendarEventID: String
    private let dueDate: String
    private let recurrenceRaw: String
    private let recurrenceSeriesIDRaw: String
    private let recurrenceSpawnedTaskIDRaw: String
    private let area: Area?
    private let project: Project?
    private let context: Context?
    private let bundle: TaskBundle?
    private let bundleOrder: Int

    init(_ task: AppTask) {
        taskID = task.id
        title = task.title
        order = task.order
        statusRaw = task.statusRaw
        completedAt = task.completedAt
        priorityRaw = task.priorityRaw
        estimatedMinutes = task.estimatedMinutes
        sectionName = task.sectionName
        scheduledDate = task.scheduledDate
        scheduledStartMin = task.scheduledStartMin
        calendarEventID = task.calendarEventID
        dueDate = task.dueDate
        recurrenceRaw = task.recurrenceRaw
        recurrenceSeriesIDRaw = task.recurrenceSeriesIDRaw
        recurrenceSpawnedTaskIDRaw = task.recurrenceSpawnedTaskIDRaw
        area = task.area
        project = task.project
        context = task.context
        bundle = task.bundle
        bundleOrder = task.bundleOrder
    }

    /// The successor `markDone` / `markCancelled` minted after this snapshot was taken, if they
    /// did. `nil` when the pointer did not change, so a task that already had a successor before
    /// the edit is never mistaken for one that just gained one.
    func spawnedSuccessorID(comparedWith task: AppTask) -> UUID? {
        guard task.recurrenceSpawnedTaskIDRaw != recurrenceSpawnedTaskIDRaw else { return nil }
        return task.recurrenceSpawnedTaskID
    }

    func restore(to task: AppTask) {
        task.title = title
        task.order = order
        task.statusRaw = statusRaw
        task.completedAt = completedAt
        task.priorityRaw = priorityRaw
        task.estimatedMinutes = estimatedMinutes
        task.sectionName = sectionName
        task.scheduledDate = scheduledDate
        task.scheduledStartMin = scheduledStartMin
        task.calendarEventID = calendarEventID
        task.dueDate = dueDate
        task.recurrenceRaw = recurrenceRaw
        task.recurrenceSeriesIDRaw = recurrenceSeriesIDRaw
        task.recurrenceSpawnedTaskIDRaw = recurrenceSpawnedTaskIDRaw
        task.area = area
        task.project = project
        task.context = context
        task.bundle = bundle
        task.bundleOrder = bundleOrder
    }
}

/// The three fields a **block move** writes on the block itself, captured before the write
/// ([[T-1980]]).
///
/// The member tasks' half of the same move is `CadenceTaskFieldSnapshot` above, reused rather than
/// near-copied: `SchedulingActions.dropBundle` writes each member's `scheduledDate`,
/// `scheduledStartMin` and `calendarEventID`, and all three are in that set. This type exists
/// because the block is not an `AppTask` and the move's subject is the block — a block with no
/// members at all still moves, so there is no task to hang the commit on.
///
/// **Deliberately not `CadenceTaskMutationSupport.updateBundle`**, which already undoes a block
/// header plus its members' schedules. That unit writes `title` and clamps against its own
/// literals, and it does **not** clear the members' calendar links, so routing the board's drop
/// through it would have changed what the drop does on the way to fixing what it reports.
///
/// `restore(to:)` is spelled `restore(to bundle:)` so the task snapshot's own `restore` stays the
/// only `func restore(to task: AppTask)` in this file; `thefieldSnapshotCapturesAndRestoresTheSameNineteenFields`
/// reads that declaration by its full prefix for exactly that reason.
struct CadenceTaskBundleSlotSnapshot {
    let bundleID: UUID

    private let dateKey: String
    private let startMin: Int
    private let durationMinutes: Int

    init(_ bundle: TaskBundle) {
        bundleID = bundle.id
        dateKey = bundle.dateKey
        startMin = bundle.startMin
        durationMinutes = bundle.durationMinutes
    }

    func restore(to bundle: TaskBundle) {
        bundle.dateKey = dateKey
        bundle.startMin = startMin
        bundle.durationMinutes = durationMinutes
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

    /// A **block move**, committed, with the board told only if it landed ([[T-1980]]).
    ///
    /// The sibling of `commit(_:alsoRestoring:in:reconciler:commit:apply:)` above, and separate
    /// from it for one reason: the subject is a `TaskBundle`, not an `AppTask`. A block with no
    /// members still moves, so there is no task to pass as the primary, and threading an optional
    /// one through the existing entry point would have made every caller read a parameter that is
    /// meaningful for exactly one of them.
    ///
    /// - Parameter members: The block's member tasks, read **before** `apply` runs. `dropBundle`
    ///   writes each one's `scheduledDate`, `scheduledStartMin` and `calendarEventID`, and does not
    ///   change the membership itself, so the list stays valid across the write.
    /// - Parameter commit: See `commit(_:alsoRestoring:in:reconciler:commit:apply:)`.
    @discardableResult
    static func commitBlockMove(
        _ bundle: TaskBundle,
        members: [AppTask],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        apply: () -> Void
    ) -> Bool {
        let slot = CadenceTaskBundleSlotSnapshot(bundle)
        let memberSnapshots = members.map(CadenceTaskFieldSnapshot.init)

        apply()

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                slot.restore(to: bundle)
                for (snapshot, member) in zip(memberSnapshots, members) {
                    snapshot.restore(to: member)
                }
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
