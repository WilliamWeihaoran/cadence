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
/// **Two questions, and they are orthogonal.** `ownListSiblings` answers **which list** a drop may
/// write — one, the dragged row's — and `wholeSequence` answers **how much of that list** —
/// all of it, and not the handful of rows the screen was showing ([[T-1175]], the other half of
/// [[T-1055]]). Widening the second did not undo the first: a row of another list is not in the
/// sequence either function returns, and `thewholeSequenceTakesOnlyTheListItsKeyNames` measures it.
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

    /// One list's **whole `order` sequence**, with `slice`'s rows resequenced inside it — what a
    /// drop must renumber, rather than the handful of rows the screen happened to be showing
    /// ([[T-1175]], the remaining half of [[T-1055]]).
    ///
    /// **The defect this closes.** `CadenceOrderCommit.commit`'s own doc says `ordered` "must be
    /// the *whole* collection the `order` sequence spans rather than the visible slice", and every
    /// row surface handed it a slice: a list's Tasks tab handed its **open** rows, a Today group
    /// handed the rows that list puts on the day, a kanban column handed the cards that column
    /// draws. Each of those is a strict subset of one list, so a renumber from 0 handed the rows it
    /// could see the orders the rows it could not see were already holding — measured in
    /// `CadenceRowReorderSliceSpanTests`, where one drag on Today moved a row on a Tasks tab the
    /// user was not looking at.
    ///
    /// **The rule: the rows the slice does not hold keep their places, and the slice fills the
    /// places it already occupied.** `held` is the list in its own sequence; each row outside the
    /// slice is re-emitted after the same number of slice rows that preceded it before the drop, so
    /// **a drag among visible rows can never move one of them past a row the screen was not
    /// showing**. What changes is only that the whole list is then numbered `0…n`, which is what
    /// stops a hidden row and a visible one holding the same `order`.
    ///
    /// **It does not decide *which* rows are the list.** `key` is the caller's, because the caller
    /// is the only one that knows: a row drop's list is the dragged row's own
    /// (`CadenceTaskQuerySupport.listGroupKey`), and a kanban card drop's is the **destination
    /// column's** — the card is being refiled into it by the same commit, so its own key is still
    /// the list it is leaving. A row of `slice` that `universe` does not hold is that card, and it
    /// is kept rather than dropped.
    ///
    /// **`held` is sorted by `TaskOrdering.fallbackPrecedes` and not by `order` alone.** Before this
    /// fix the collisions were real, so `order` alone is not a total order over the rows being
    /// repaired, and a `sorted(by:)` over a non-total order is not stable. `fallbackPrecedes` is
    /// both total and the sequence the custom sort actually displays, so the repair canonicalises
    /// the arrangement the user was already looking at.
    static func wholeSequence(
        resequencing slice: [AppTask],
        within universe: [AppTask],
        ofList key: String
    ) -> [AppTask] {
        let sliceIDs = Set(slice.map(\.id))
        let held = universe
            .filter { CadenceTaskQuerySupport.listGroupKey(for: $0) == key }
            .sorted(by: TaskOrdering.fallbackPrecedes)

        var anchors: [(row: AppTask, following: Int)] = []
        var passed = 0
        for row in held {
            if sliceIDs.contains(row.id) {
                passed += 1
            } else {
                anchors.append((row, passed))
            }
        }
        // Nothing outside the slice: the slice already *is* the list's sequence, which is what the
        // four one-container surfaces hand in when their filter happens to hide nothing.
        guard !anchors.isEmpty else { return slice }

        // `placed` counts only the slice rows the list **already held**, which is what keeps a row
        // arriving from another column from displacing the anchors: it is not one of the rows
        // `following` was counted against, so it does not spend one of their places.
        let heldIDs = Set(held.map(\.id))
        var sequence: [AppTask] = []
        var next = 0
        var placed = 0
        for anchor in anchors {
            while next < slice.count, placed < anchor.following {
                let row = slice[next]
                sequence.append(row)
                if heldIDs.contains(row.id) { placed += 1 }
                next += 1
            }
            sequence.append(anchor.row)
        }
        sequence.append(contentsOf: slice[next...])
        return sequence
    }
}
