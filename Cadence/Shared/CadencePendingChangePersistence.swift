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
enum CadencePendingChangePersistence {

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
    /// 2. **Its edit undo is not visible until something refreshes the object.** Measured:
    ///    `rollback()` un-*deletes* unconditionally — which is what makes it right for
    ///    `commitDelete`, and what `CadenceListCascadeRollbackTests` pins — but after
    ///    `area.name = "New"; rollback()` the live `Area` still answers `"New"` and only a *fetch*
    ///    brings it back to `"Old"`. The store is correct throughout. So an editor that rolled back
    ///    and then reported `editFailureNotice` would be relying on a fetch nobody scheduled, and
    ///    `EditAreaSheet` binds straight to the model rather than through a `@Query`.
    ///    `CadenceEditorSaveCommitSurfaceTests.rollbackRestoresAnEditOnlyOnceSomethingRefreshesTheObject`
    ///    pins both halves — including the assertion order, because a fetch placed before the read
    ///    hides the whole effect.
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
    /// - Parameter cascade: Runs the delete. Returns `false` if it could not finish.
    static func commitCascade(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        cascade: () -> Bool
    ) throws {
        guard cascade() else {
            modelContext.rollback()
            throw CascadeIncomplete()
        }
        try commitDelete(in: modelContext, commit: commit)
    }

    /// Thrown by `commitCascade(in:commit:cascade:)` when the cascade itself could not finish.
    ///
    /// It carries nothing because there is nothing the surface can do with a detail: the store
    /// could not be read, the delete was rolled back, and the sentence the user reads is the same
    /// one a refused commit produces.
    struct CascadeIncomplete: Error {}
}
