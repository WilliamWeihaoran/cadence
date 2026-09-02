import Foundation
import SwiftData

/// Flushing an in-place edit on a surface the user is still looking at.
///
/// **The decision this encodes (T-497, tier 3).** Three iOS surfaces end an editing session the
/// same way: write a field, commit, close. The search sheet's note editor, the task detail sheet
/// and the `[[link]]` note editor all spelled the commit `try? modelContext.save()`, so closing
/// *claimed* the write had landed whether or not it had.
///
/// **Why the obvious repair is the wrong one**, which is what blocked this tier for a week. The
/// edit is **in-place on an object the store already holds**, so there is nothing to un-insert; a
/// `CadencePendingChangePersistence.commitEdit(in:undo:)` here would restore the model out from
/// under a caret the user still has in the field — deleting what they typed in order to tell them
/// it was not saved. Keep the surface open, keep what the user typed, show the failure inline, let
/// them retry. The rule is broken here only because closing **claims** it worked; stop claiming it,
/// and the undo question disappears.
///
/// So this is deliberately **not** a fourth `CadencePendingChangePersistence` case. It commits and
/// answers. It never touches the caller's fields, and it never rolls the context back — the pending
/// edit stays pending precisely because the user is still holding it.
enum CadenceInPlaceEditFlush {

    /// Shown inline on the surface that stayed open.
    ///
    /// It says the changes are still here because they are: the fields still hold them and the
    /// context still holds them pending. That is the whole difference between this sentence and
    /// `CadencePendingChangePersistence.editFailureNotice`, whose "Nothing was changed" is only
    /// true because an undo ran first.
    static let failureNotice = "Couldn't save these changes. They're still here — try again."

    /// Commits whatever the surface has pending, and answers whether the store took it.
    ///
    /// `false` means the store refused: nothing was undone, the edit is still in the context and
    /// still in the field, and the caller must **not** close.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and a
    ///   failure path no test can reach is a failure path no test can prove.
    static func flush(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        do {
            try commit(modelContext)
        } catch {
            return false
        }
        return true
    }
}
