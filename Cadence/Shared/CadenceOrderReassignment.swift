import Foundation

/// Where an **existing** row's `order` comes from after the user rearranges the list.
///
/// The sibling of `CadenceOrderAllocation`, which answers the same question for a row that is
/// being created. Both exist for the same reason: the rule was being re-typed per call site, and
/// re-typed rules drift.
///
/// **The arithmetic here is one line long and wrong in two ways if you write it from memory.**
///
/// 1. Removing the dragged element shifts everything after it down by one, so inserting "before
///    the target" is `toIndex` when the drag went upwards and `toIndex - 1` when it went
///    downwards. Getting that wrong drops the row one place short of where it was released, but
///    only in one of the two directions — so it looks like an off-by-one that only sometimes
///    happens.
/// 2. A *one-step* move down is not "move me to the next slot". It is **move the row below me
///    above me**, which is the same primitive with the two ids swapped. Written the other way it
///    reads correctly and does nothing, because "insert me immediately before the row that is
///    already immediately after me" is where I already am.
///
/// **The order is reassigned over the whole collection, not over the visible slice.** macOS's
/// contexts pane hands in every context including the archived ones, and it must: `order` is a
/// single sequence across the model, so renumbering only the visible rows hands them indices the
/// hidden rows already hold, and `@Query(sort: \Context.order)` then sorts on ties — which is
/// unstable, and reads as the app losing an arrangement the user made. Callers pass the full
/// collection and use `neighbourStep(moving:by:within:)` to turn a visible-list gesture into a pair
/// of ids that is meaningful in it.
///
/// Nothing here touches a `ModelContext`. Deciding the new order and committing it are separate
/// jobs, and only the second one can fail.
nonisolated enum CadenceOrderReassignment {

    /// `items` with `draggedID` moved to sit immediately before `targetID`.
    ///
    /// `nil` when there is nothing to do — the two ids are the same, or either is not in `items` —
    /// so a caller can skip the renumber and the commit rather than saving an identical array.
    static func moved<Item: Identifiable>(
        _ items: [Item],
        _ draggedID: Item.ID,
        before targetID: Item.ID
    ) -> [Item]? {
        guard draggedID != targetID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedID }),
              let toIndex = items.firstIndex(where: { $0.id == targetID }) else { return nil }

        var ordered = items
        let moved = ordered.remove(at: fromIndex)
        ordered.insert(moved, at: fromIndex < toIndex ? toIndex - 1 : toIndex)
        return ordered
    }

    /// Turns "move this row up/down one place in the list I can see" into the `(dragged, target)`
    /// pair `moved(_:_:before:)` takes.
    ///
    /// `visibleIDs` is the filtered, already-sorted list the user is looking at — the *active*
    /// contexts, not every context — because a step has to move the row past its visible
    /// neighbour, which may be several archived rows away in the full collection.
    ///
    /// `nil` at the ends of the list, and for any offset other than one step, so the caller can
    /// hide or disable the affordance rather than offering a move that does nothing.
    static func neighbourStep<ID: Hashable>(
        moving id: ID,
        by offset: Int,
        within visibleIDs: [ID]
    ) -> (dragged: ID, target: ID)? {
        guard let index = visibleIDs.firstIndex(of: id) else { return nil }

        switch offset {
        case -1:
            guard index > 0 else { return nil }
            return (dragged: id, target: visibleIDs[index - 1])
        case 1:
            guard index + 1 < visibleIDs.count else { return nil }
            // Moving down is the row below being moved above this one. The other spelling —
            // "insert me before the row after me" — is a no-op.
            return (dragged: visibleIDs[index + 1], target: id)
        default:
            return nil
        }
    }
}
