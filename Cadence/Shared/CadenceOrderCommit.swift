import Foundation
import SwiftData

/// Committing a rearrangement **the user can see** — the third member of the family whose first two
/// are `CadenceOrderAllocation` (where a *new* row's `order` comes from) and
/// `CadenceOrderReassignment` (where an *existing* row's `order` goes after a drag). Those two are
/// pure arithmetic and cannot fail. This is the part that can.
///
/// **Why it exists (T-868, T-869).** T-614 settled the rule these sites inherit: a row that stays
/// where you dropped it is the strongest success claim this app makes, stronger than the dismissed
/// sheet `AGENTS.md`'s half 2 already counts, and a refused reorder is exactly the failure the rule
/// is for — a silent revert at next launch with nothing to retry. It fixed one site,
/// `SettingsView.moveContext`, by hand. The audit that followed found four more `order` renumbers
/// on drag paths: two ending in `try? modelContext.save()` and two reaching no commit at all. Four
/// hand-written copies of "capture every previous order, renumber, commit, put them all back" is
/// how the app ends up restoring three of the four correctly.
///
/// **Every previous order is captured, not just the dragged row's.** A reorder writes `order` on
/// the whole run of rows between the two positions, so an undo that repairs only the row the user
/// dragged leaves the store and the screen disagreeing about the rest. That is the T-701 mistake
/// one field wider.
///
/// **The undo is a snapshot restore, never `modelContext.rollback()`**, for the reason
/// `CadencePendingChangePersistence.commitEdit` states at length: this is the app's single
/// `ModelContext`, and a refused drag must not discard the note somebody is typing in another pane.
///
/// **What this is not.** It does not decide the new arrangement — `CadenceOrderReassignment` and
/// each surface's own sort do that — and it does not know what a failure should *say* on screen.
/// It offers the sentence and returns the answer; naming the refusal where the user is already
/// looking stays the caller's job, because only the caller knows where that is.
///
/// **It does not cover the kanban *column* order (T-870)**, which is a re-serialised
/// `[TaskSectionConfig]` blob on the list with no `order` field at all —
/// `CadenceSectionConfigContainer.reorderSectionConfigs(in:commit:_:)` is that one, built from the
/// same `commitEdit` and reading the same `failureNotice`. Any future sweep written over `\.order`
/// will not see it; that is the stated blind spot, not an oversight.
enum CadenceOrderCommit {

    /// The one sentence every refused rearrangement in the app shows.
    ///
    /// Distinct from `CadencePendingChangePersistence.editFailureNotice` ("Couldn't save these
    /// changes. Nothing was changed.") because a user who just dragged a row did not *change* it,
    /// and the thing they need told is that the position they are looking at is not the one that
    /// will be there next launch. "Nothing was moved" is only true because `commit(_:readOrder:
    /// writeOrder:in:commit:)` below guarantees the restore ran before the caller was told —
    /// the same contract, and the same reason it is stated here rather than at seven call sites.
    static let failureNotice = "Couldn't save this new order. Nothing was moved."

    /// Renumbers `ordered` from 0 upwards, commits, and puts **every** previous order back if the
    /// store refuses.
    ///
    /// `ordered` is the collection in its new arrangement, and it must be the *whole* collection
    /// the `order` sequence spans rather than the visible slice — renumbering only the visible rows
    /// hands them indices the hidden rows already hold, and a `@Query(sort:)` then sorts on ties.
    /// `CadenceOrderReassignment` says the same thing about the array it returns, and for the same
    /// reason.
    ///
    /// - Parameter readOrder: How to read the field being renumbered. A closure rather than a
    ///   `KeyPath` because `SidebarListEntry` is an `enum` over two models and reads its order
    ///   through a `switch`, not through a stored property.
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    /// - Returns: Whether the new order is in the store. `false` means every row is back exactly
    ///   as it was found, so the caller must show `failureNotice` rather than report a move.
    @discardableResult
    static func commit<Item>(
        _ ordered: [Item],
        readOrder: (Item) -> Int,
        writeOrder: (Item, Int) -> Void,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let previousOrders = ordered.map(readOrder)
        for (index, item) in ordered.enumerated() {
            writeOrder(item, index)
        }

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                for (item, order) in zip(ordered, previousOrders) {
                    writeOrder(item, order)
                }
            }
        } catch {
            return false
        }
        return true
    }
}
