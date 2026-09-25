import Foundation
import SwiftData

/// Commit a pending change, and undo the pending change if the commit throws.
///
/// **Why this is its own type (T-319, T-320).** `CadenceSavedLinkPersistence` (T-327) and
/// `CadenceTaskMutationSupport.insertTask` had already written this twice, once each for a
/// `SavedLink` and an `AppTask`. Neither is actually about the model it names: an insert whose
/// commit fails has to un-insert, a delete whose commit fails has to un-delete, and which `@Model`
/// it was makes no difference to either sentence. So the sentence lives here once, generic over
/// `PersistentModel`, and the callers keep only the part that *is* theirs — the user-facing notice
/// and what the screen does next.
///
/// **What it buys.** A pending change that is neither committed nor undone is the state both
/// tickets are about: `try? modelContext.save()` leaves the context holding a task the store never
/// took, or a note the store still has, and the UI then reports success over it. There is no third
/// outcome here. Either the commit lands, or the context is back where it started and the caller
/// gets the error to show.
///
/// **Insert and delete undo differently, deliberately.**
/// - An insert knows exactly which objects it added, so it deletes those and leaves every other
///   pending edit in the context alone.
/// - A delete has no object to hand back — the rows are already marked deleted — so it rolls the
///   context back, which is the only way to make them visible again.
///
/// This is the unit `docs/TODO.md` [[T-322]]'s sweep should be built from, not a second copy of it.
///
/// **`nonisolated` because a commit is not a main-actor question** (T-1295). The app target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would isolate this type to the main actor in
/// the app and leave it nonisolated in `CadenceMCPServer`, whose build does not set it — two
/// isolations for one file. Everything below touches only `ModelContext` and `PersistentModel`,
/// both nonisolated, so the annotation costs nothing and makes the helper reachable from the
/// `nonisolated` writers that need it: `CadenceHabitCompletionStore.toggle` is compiled into the
/// widget extension, and calling a main-actor `commitInsert` from it was four warnings against a
/// zero baseline. Nonisolated members stay callable from every main-actor caller here unchanged.
nonisolated enum CadencePendingChangePersistence {

    /// Commits a pending insert. If the commit throws, the objects are removed from the context
    /// again, so no caller is left showing a row the store does not hold.
    ///
    /// `models` is a list rather than one object because a creation is often a small graph — a task
    /// and its subtasks — and undoing only the root would strand the rest as orphans in the
    /// context. Pass every object the caller inserted.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    static func commitInsert(
        of models: [any PersistentModel],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        do {
            try commit(modelContext)
        } catch {
            for model in models {
                modelContext.delete(model)
            }
            throw error
        }
    }

    /// The one-object spelling of `commitInsert(of:in:commit:)`.
    static func commitInsert(
        of model: some PersistentModel,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try commitInsert(of: [model], in: modelContext, commit: commit)
    }

    /// The sentence a structural editor shows when its save is refused.
    ///
    /// It says "Nothing was changed" for the same reason
    /// `CadenceListDeletionKind.deleteFailureNotice` says "Nothing was removed": it is only true
    /// because `commitEdit(in:commit:undo:)` below guarantees the undo ran before the caller was
    /// told. A caller that reports this sentence without an undo is lying, and the source scans in
    /// `CadenceEditorSaveCommitSurfaceTests` are what keep the two together.
    static let editFailureNotice = "Couldn't save these changes. Nothing was changed."

    /// Commits a pending **in-place edit**, undoing it with `undo` when the commit throws.
    ///
    /// The third case, after insert and delete (T-321, T-366). An edit differs from both: there is
    /// no object to delete and no row to un-hide, only fields that now hold values the store never
    /// took. So the undo is the caller's — it is the only party that knows how far the edit
    /// reached — and it is always the same shape: **capture the fields before the write and put
    /// them back here.** `CadenceAINoteSummary.append` writes it inline for two fields;
    /// `CadenceTaskFieldSnapshot` and `CadenceListEditSnapshot` are it for the two editors that
    /// reach further.
    ///
    /// **`{ modelContext.rollback() }` is not offered, for two reasons in this order.**
    ///
    /// 1. **It discards unrelated pending work.** This is the app's single `ModelContext`. A
    ///    refused rename must not take the note someone is typing behind the popover with it —
    ///    `arefusedListEditLeavesUnrelatedPendingWorkAlone` is that assertion, and it does not
    ///    depend on any SwiftData timing.
    /// 2. **It has a second defect on some toolchains, and neither answer licenses a rollback.**
    ///    `rollback()` un-*deletes* unconditionally — which is what makes it right for
    ///    `commitDelete`, and what `CadenceListCascadeRollbackTests` pins — but through Xcode 26,
    ///    after `area.name = "New"; rollback()` the live `Area` still answered `"New"` and only a
    ///    *fetch* brings it back to `"Old"`, while the store is correct throughout. **Xcode 27
    ///    restores the live reference immediately** (T-1279), and this repository builds on both —
    ///    CI on 26, the owner's Mac on 27 (T-1296). Reason 1 never depended on that timing, so
    ///    `commitEdit` keeps the field snapshot regardless of toolchain.
    ///    `CadenceEditorSaveCommitSurfaceTests.rollbackUndoesAnEditInTheStoreAndTheSingleContextObjectionStillStands`
    ///    pins the behaviour now and records the old one, including why the assertion order is
    ///    still load-bearing.
    ///
    /// - Parameter commit: See `commitInsert(of:in:commit:)`.
    static func commitEdit(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        undo: () -> Void
    ) throws {
        do {
            try commit(modelContext)
        } catch {
            undo()
            throw error
        }
    }

    /// Commits a pending delete. If the commit throws, the delete is rolled back, which puts the
    /// rows back where the user can see them rather than leaving them hidden and undeleted.
    ///
    /// Used for cascades too: `ModelContext.deleteArea` and friends mark a whole tree deleted, and
    /// `rollback()` is what undoes all of it at once.
    ///
    /// - Parameter commit: See `commitInsert(of:in:commit:)`.
    static func commitDelete(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        do {
            try commit(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// A delete whose construction can **throw** part-way through, and then commits.
    ///
    /// The third shape of a delete, after `commitDelete` (fully marked before anyone saves) and
    /// `commitCascade` (a construction that reports failure by answering `false`). The privacy
    /// reset is this one (T-1102): it walks twenty-one model types, and each pass is a *fetch* —
    /// so the failure it can hit mid-way arrives as a thrown error with rows from the earlier
    /// passes already marked deleted in the context. Nothing about that error tells the caller to
    /// undo them, and this app has **one `ModelContext`**, so the pending delete simply waits for
    /// the next unrelated `save()` anywhere in the app to commit it — a refused "delete my data"
    /// that deletes the user's tasks a minute later, from a screen that never mentioned it.
    ///
    /// So the construction is enclosed too, not just the save. `rollback()` is the only undo
    /// available for a delete — the rows are already marked, and there is no object to hand back —
    /// and it costs any *unrelated* pending edit in the shared context, which is the documented
    /// price `commitDelete` already pays and the reason this is not the default shape for an edit.
    ///
    /// The original error is rethrown rather than replaced: unlike `commitCascade`'s `false`, a
    /// throwing construction already says what went wrong, and the surface has to name it.
    ///
    /// - Parameter building: Marks the rows deleted. Commits nothing.
    static func commitDelete(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        building: () throws -> Void
    ) throws {
        do {
            try building()
        } catch {
            modelContext.rollback()
            throw error
        }
        try commitDelete(in: modelContext, commit: commit)
    }

    /// A delete that can fail **while it is still being built**, and then commits.
    ///
    /// `commitDelete` covers the delete that is fully marked by the time anyone tries to save it.
    /// The list cascades are the other case (T-291): `ModelContext.deleteArea` walks tasks, nested
    /// projects, notes, documents and links, and any of those steps can hit a store read it cannot
    /// perform. It says so by returning `false` — but it says so *mid-tree*, with part of the
    /// cascade already marked deleted in the context.
    ///
    /// So `false` here is not advisory. It means the context is holding a half-built delete, and
    /// the only correct next move is `rollback()` — never `save()`, which is what all three call
    /// sites used to do, and never leaving it pending, which the next autosave would commit
    /// anyway. The caller gets a thrown error and shows the same notice a refused commit shows,
    /// because from the user's side the two are the same event: the delete did not happen, and
    /// nothing was removed.
    ///
    /// **It is also the scope a deferred delete's side effects are released from ([[T-1348]],
    /// [[T-1351]]).** A cascade commits nothing — that is the whole of T-291 — so any
    /// *success-only* effect it earns along the way has nothing to sit below.
    /// `CadenceDeferredDeleteEffects` is where those effects wait, this is the only place the scope
    /// is opened, and `release()` below is reachable on exactly one path: the cascade finished
    /// **and** the commit landed. Every other exit throws past it, which is what makes "nothing was
    /// removed" also mean "nothing was cancelled" — and, since T-1351, "nothing was ended", because
    /// the macOS delete wrapper's focus-session teardown waits in the same queue.
    ///
    /// **It is also the scope a deferred delete's *undo* is run from ([[T-1377]]).** The mirror of
    /// the paragraph above, and the same object: a cascade edits rows it is not removing — a
    /// surviving goal's `tasks`, a surviving tag's `tasks`, a surviving predecessor's
    /// `recurrenceSpawnedTaskID` — and has no refusal of its own to hang the undo off, so it hands
    /// the undo to `CadenceDeferredDeleteEffects` and this function runs it on both refusal paths.
    /// **Before the `rollback()`, never after**, which is the whole of [[T-1336]]'s construction
    /// carried up one frame: a restore that lands after the rollback writes into a context the
    /// rollback has just made clean, so on the toolchain that needs the repair it is also a fresh
    /// pending edit and `!modelContext.hasChanges` after a refusal stops holding — a clause every
    /// cascade suite asserts. On the commit path that ordering is bought by nesting `commitEdit`
    /// inside `commitDelete`'s `commit:`, exactly as the three delete helpers do; on the
    /// cascade-could-not-finish path the rollback is right here and the undo goes above it.
    ///
    /// - Parameter cascade: Runs the delete. Returns `false` if it could not finish.
    /// - Parameter effects: The queue the cascade's success-only effects wait in, and since
    ///   [[T-1377]] its refusal-only undos too. It is a
    ///   parameter for the reason `commit` is: a released cancellation is otherwise unobservable
    ///   from a test, because `NotificationManager.cancel` is inert under
    ///   `NotificationManager.isTestEnvironment`, and a side effect no test can see is a side
    ///   effect that cannot be proved absent on the refusal path.
    static func commitCascade(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        effects: CadenceDeferredDeleteEffects = CadenceDeferredDeleteEffects(),
        cascade: () -> Bool
    ) throws {
        try CadenceDeferredDeleteEffects.$current.withValue(effects) {
            guard cascade() else {
                effects.undo()
                modelContext.rollback()
                throw CascadeIncomplete()
            }
            try commitDelete(
                in: modelContext,
                commit: { try commitEdit(in: $0, commit: commit, undo: effects.undo) }
            )
        }
        effects.release()
    }

    /// Thrown by `commitCascade(in:commit:cascade:)` when the cascade itself could not finish.
    ///
    /// It carries nothing because there is nothing the surface can do with a detail: the store
    /// could not be read, the delete was rolled back, and the sentence the user reads is the same
    /// one a refused commit produces.
    struct CascadeIncomplete: Error {}
}

/// The side effects a **deferred** delete has earned and may not perform yet, and the undo for
/// what it wrote on rows it is not removing.
///
/// **Two buckets, one queue, one ambient scope ([[T-1377]]).** `hold(taskIDs:habitIDs:effect:)`
/// holds what is right only if the commit **landed**; `holdUndo(_:)` holds what is right only if it
/// was **refused**. They were nearly two objects, and are one because the argument below for why
/// the scope is ambient rather than a parameter applies identically to both, and a second
/// `@TaskLocal` beside this one would be a second thing every present and future cascade caller has
/// to remember to be inside. `CadencePendingChangePersistence.commitCascade` is still the only
/// place the scope is opened, and it is what releases one bucket or runs the other.
///
/// **It was named for reminders, and it is not only about reminders ([[T-1351]]).** A reminder
/// cancellation was the first effect to need this and is still the one the doc below argues from,
/// but the property that earns the queue is not "reminder": it is *right below a commit that
/// landed, and wrong anywhere else*. macOS's delete wrapper ends the user's running focus session
/// when the delete names its task or its block, which is the same shape one layer up — in-memory
/// rather than scheduled with the OS, and therefore lower severity, but equally not repairable
/// from a refusal alert. `ModelContext.deleteTasks` holds it here too.
///
/// **Why this exists ([[T-1348]]).** A reminder cancellation is a success-only side effect: it is
/// right below a commit that landed, and wrong anywhere else, because a cancelled reminder for a
/// row that is still in the store is silent until the next `scenePhase` reconcile. [[T-1301]]
/// settled that for every delete that commits *itself* — `deleteHabit` cancels below its `try`,
/// `CadenceTaskMutationSupport.deleteTasks` cancels below its gate and returns before it on a
/// refusal. The list cascades are the case that rule could not reach: they commit **nothing**
/// (T-291 — the whole cascade is one pending change and the surface that asked for the delete
/// commits it), so there was no commit to put the cancellation below and both legs ran it
/// unconditionally, above a commit that can still be refused.
///
/// **Why the cascade does not simply take a `commit:` instead.** That is the other candidate fix,
/// and it inverts T-291: `deleteArea` recurses into `deleteProject`, so a cascade that committed
/// itself would commit a nested list while the enclosing one could still abort — the exact
/// half-applied state `commitsImmediately: false` was introduced to remove — and
/// `commitCascade` would then be committing on top of a commit. Deferring keeps the property that
/// nothing inside a cascade writes to the store, and moves only the effect.
///
/// **Why the scope is ambient rather than a parameter.** The cascades answer `Bool`, which is what
/// `SettingsView.report(_:cascade:)` and both `EditListSheet` deletes are typed against, and what
/// `commitCascade` consumes. Threading an accumulator down through `deleteContext` /
/// `deleteArea` / `deleteProject` / `deleteTasks` would make correctness depend on every present
/// and future caller remembering to pass one — a delete that forgets is silently back to the
/// T-1348 behaviour. Binding it to the one function that owns the commit means the deferral
/// arrives with the commit or not at all. `@TaskLocal` rather than a `static var` because the
/// binding is then scoped and concurrency-safe by construction.
///
/// **A deferred cancellation with no scope around it is dropped, deliberately.** That is a delete
/// that does not commit and has no owner waiting to, which the source scan in
/// `CadenceListCascadeRollbackTests.noListDeleteSurfaceSavesOverTheCascadesAnswer` already
/// forbids. Dropping costs a reminder that stays armed until the next reconcile converges;
/// firing costs a reminder cancelled for a row the user can still see, which nothing converges.
/// The two errors are not symmetric, so this one errs toward the recoverable side.
///
/// `@unchecked Sendable` with a lock rather than an actor: every touch is synchronous and inside
/// one `commitCascade` frame, and a `@TaskLocal` value must be `Sendable`.
nonisolated final class CadenceDeferredDeleteEffects: @unchecked Sendable {
    /// The queue in scope, set only by `CadencePendingChangePersistence.commitCascade`.
    @TaskLocal static var current: CadenceDeferredDeleteEffects?

    private struct Held {
        let taskIDs: [UUID]
        let habitIDs: [UUID]
        let effect: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var held: [Held] = []
    private var releasedEffects: [Held] = []
    private var undos: [() -> Void] = []

    /// The ids waiting on a commit that has not landed. Empty after `release()`.
    var pendingTaskIDs: [UUID] { lock.withLock { held.flatMap(\.taskIDs) } }
    /// See `pendingTaskIDs`.
    var pendingHabitIDs: [UUID] { lock.withLock { held.flatMap(\.habitIDs) } }
    /// The ids whose effect actually ran. Empty unless a commit landed.
    var releasedTaskIDs: [UUID] { lock.withLock { releasedEffects.flatMap(\.taskIDs) } }
    /// See `releasedTaskIDs`.
    var releasedHabitIDs: [UUID] { lock.withLock { releasedEffects.flatMap(\.habitIDs) } }

    /// - Parameter effect: What to run once the enclosing commit has landed. The ids beside it are
    ///   the same ids it concerns, recorded so the queue can be read without a second spy.
    func hold(taskIDs: [UUID], habitIDs: [UUID], effect: @escaping @Sendable () -> Void) {
        lock.withLock { held.append(Held(taskIDs: taskIDs, habitIDs: habitIDs, effect: effect)) }
    }

    /// Runs everything held, once. Called only from the one path where the commit succeeded.
    func release() {
        let due = lock.withLock { () -> [Held] in
            let due = held
            held = []
            releasedEffects.append(contentsOf: due)
            return due
        }
        for held in due {
            held.effect()
        }
    }

    /// How many undos are waiting. Non-vacuity for a test asserting that none of them ran.
    var heldUndoCount: Int { lock.withLock { undos.count } }

    /// What a **deferred** delete wrote on rows it is not removing, to be put back if the commit
    /// that owns it is refused ([[T-1377]]).
    ///
    /// The mirror of `hold(taskIDs:habitIDs:effect:)` and deliberately the same object rather than
    /// a second ambient scope beside it. One queue, two buckets, one `@TaskLocal`: a delete that
    /// reaches this one has by construction reached the other, and a second scope would be a second
    /// thing every future cascade caller has to be inside.
    ///
    /// **Not `@Sendable`, unlike `effect`.** An undo closes over the `@Model` rows it is putting
    /// back, which are not `Sendable`, and it does not need to be: it is appended and run inside
    /// one synchronous `commitCascade` frame, which is the same reason the lock here is an
    /// `NSLock` rather than an actor.
    func holdUndo(_ undo: @escaping () -> Void) {
        lock.withLock { undos.append(undo) }
    }

    /// Runs every held undo, once, in the order they were captured, and forgets them.
    ///
    /// Called only from the paths where the commit did **not** land, and on each of those it runs
    /// **before** the `rollback()` — see `CadencePendingChangePersistence.commitCascade` for why
    /// that order is the fix rather than a detail. Draining rather than replaying keeps the
    /// idempotence `release()` has: a second call after a first cannot write a stale value back
    /// over a context somebody else has since changed.
    func undo() {
        let due = lock.withLock { () -> [() -> Void] in
            let due = undos
            undos = []
            return due
        }
        for restoration in due {
            restoration()
        }
    }
}
