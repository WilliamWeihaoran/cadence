import Foundation

/// How much of a row drop the app is allowed to write — the decision [[T-1119]] settles, kept in
/// one place because two things ask it: the renumber (`TasksPanelSupport.reorderTask`) and the
/// sentence that reports it (`CadenceReorderVisibility.notice`).
///
/// **The question.** On All Tasks and Inbox, `TasksListView.sections(from:)` groups by date, by
/// priority, or not at all under three of its four modes, so one section is drawn from several
/// lists at once and a row drag inside it can name two tasks in different lists. `AppTask.order` is
/// a **per-list** arrangement — `TaskOrdering.fallbackPrecedes`'s own doc says so and settles
/// cross-list ties with `createdAt` — so "put this row above that one" has no meaning when the two
/// rows are in different lists: there is no single sequence the instruction is about. What the app
/// did until this type existed was renumber the whole visible group from 0, which rewrote *every*
/// list represented in it from one drag.
///
/// **What that cost, measured rather than argued** ([[T-1055]], `CadenceRowReorderSliceSpanTests`):
/// one drag over two rows, made on one screen, moved a row on another screen the drag was not made
/// on and which had never displayed the rows it named.
///
/// **The answer, and it is the repository owner's rather than an agent's.** Asked what a drag
/// across lists should do — leave it, reorder within its own list only, or keep the cross-list
/// renumber and explain it at the drop — they answered, verbatim: *"Reorder within its own list
/// only."* That is what `ownListSiblings(moving:before:in:)` returns.
///
/// **What this is not.** It does not widen a renumber to the whole container: a surface still hands
/// in its own slice, and every caller's slice is still smaller than the sequence its numbering
/// spans — that is T-1055's remaining half, filed as [[T-1175]]. This narrows the write to one
/// list; it does not yet widen it to all of that list.
enum CadenceRowReorderSpan {

    /// The dropped row's **own list's** rows, in the sequence the drop puts them in — or `nil` when
    /// the drop moves it past none of them and there is therefore nothing to write.
    ///
    /// - Parameter scopeTasks: the surface's own rows for this drop: one Today group, one All Tasks
    ///   section, a list's Tasks tab. They are sorted by `order` here and not by the screen's sort,
    ///   which is [[T-884]]'s decision and is about *which sequence* a drag rewrites — `order` is
    ///   the only arrangement in this app a user authors, and renumbering the displayed sequence
    ///   would write a derived order over an authored one. This type is about *how much* of that
    ///   sequence a drop may write, which is the orthogonal question.
    ///
    /// **The `nil` is load-bearing, not an optimisation.** A drop that crosses lists without
    /// passing any sibling — dragging the one row this list has in the section above a row of
    /// another list — leaves a one-element array, and committing that would renumber it to `0` and
    /// silently send it to the top of a list arrangement the user was not editing. That is the same
    /// damage T-1119 is about, one list in. It also answers `nil` for the gesture
    /// `CadenceOrderReassignment` calls a no-op in the other direction — "insert me immediately
    /// before the row already immediately after me" — because that instruction does not move the
    /// row either.
    ///
    /// **Callers must treat `nil` as success with nothing to write, not as a refusal.** Nothing
    /// failed: `CadenceOrderCommit.failureNotice` would be two false sentences, exactly as
    /// `CadenceReorderVisibility` says about the other notice. What such a drop should *say* — it
    /// currently says nothing, and the row springs back — is the half of T-1119 the owner's answer
    /// deliberately did not buy, and is filed as [[T-1174]].
    ///
    /// The container is `CadenceTaskQuerySupport.listGroupKey`, so "its own list" means here what
    /// it means to every by-list grouping in the app, Inbox included.
    static func ownListSiblings(
        moving droppedID: UUID,
        before targetID: UUID,
        in scopeTasks: [AppTask]
    ) -> [AppTask]? {
        let sorted = scopeTasks.sorted { $0.order < $1.order }
        guard let ordered = CadenceOrderReassignment.moved(sorted, droppedID, before: targetID),
              let dropped = ordered.first(where: { $0.id == droppedID }) else { return nil }

        let key = CadenceTaskQuerySupport.listGroupKey(for: dropped)
        let after = ordered.filter { CadenceTaskQuerySupport.listGroupKey(for: $0) == key }
        let before = sorted.filter { CadenceTaskQuerySupport.listGroupKey(for: $0) == key }
        guard before.map(\.id) != after.map(\.id) else { return nil }
        return after
    }
}
