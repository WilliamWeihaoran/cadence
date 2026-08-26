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
}
