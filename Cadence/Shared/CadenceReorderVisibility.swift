import Foundation

/// Whether the row the user just dropped landed somewhere they can see it, and the one sentence
/// that says so when it did not.
///
/// **The condition is per drop, not per sort (T-1077).** [[T-1054]] proposed refusing the reorder
/// half of a drop whenever the active sort is not `.custom`, on the premise that the dragged row
/// always springs back there. The premise is false, and `CadenceRowReorderSequenceTests` measures
/// it three ways: `TaskOrdering.precedes` falls through to `TaskOrdering.fallbackPrecedes` on a tie
/// under `.date` and `.priority` alike, and `fallbackPrecedes`'s first key is `order` — so **inside
/// a tie band the displayed sequence is the `order` sequence**, and a dragged row lands exactly
/// where it was dropped, exactly as under `.custom`. Tie bands are the common case rather than the
/// edge one: `TaskPriority` has four ranks, and under a date sort every undated task shares one key.
///
/// The invisible drag is a subset of a subset — a non-custom sort **and** a drop across a sort-key
/// boundary — so the honest response is to ask both questions at the moment of the drop.
///
/// **It is a notice, not a refusal.** Refusing the gesture would delete something that works and is
/// visible in the common case, to fix a case the user can already recover from by dragging again
/// under Custom.
///
/// **It is deliberately not `CadenceOrderCommit.failureNotice`.** Nothing failed here. The row
/// moved, the store took it, and `order` now says what the user asked it to say; the only thing
/// wrong is that the sequence on screen is not the sequence they just edited. "Couldn't save this
/// new order. Nothing was moved." would be two false sentences.
///
/// **Switching the sort to `.custom` on drag was considered and rejected** for a reason that is not
/// about taste: the sort field is persisted — `@AppStorage("allTasksSortField")`, the per-list
/// `_sortField` keys, `TasksPanel.sortModeDefaultsKey` — so a drag would overwrite a saved
/// preference the user set on purpose, and nothing would put it back.
enum CadenceReorderVisibility {

    /// What a drop that landed outside the visible sequence says.
    ///
    /// **It names no sort mode, and that is a constraint rather than brevity.** The two surfaces
    /// this is drawn on speak two vocabularies for the same arrangement: `TaskSortField.custom` is
    /// labelled *Custom*, and `CadenceTaskSortMode.listOrder` — which macOS Today has used since
    /// T-606 — is labelled *List Order*. A sentence naming either would be wrong on the other
    /// screen, and a sentence naming both would be advice about a chip rather than a report about a
    /// row.
    ///
    /// It claims the move, because the move happened: the caller only reaches this once
    /// `CadenceOrderCommit.commit` has answered `true`, and since T-1119 `notice(droppedID:
    /// targetID:in:sortKeyOrder:)` also refuses to speak for a drop that had nothing to commit.
    static let offScreenNotice = "Moved, but this sort doesn't show it there."

    /// The notice for one drop, or `nil` when the drop is fully visible — **or when it moved
    /// nothing at all**.
    ///
    /// **The second half is [[T-1119]]'s consequence, and it is what keeps
    /// `offScreenNotice`'s "it claims the move, because the move happened" true.** Since the owner
    /// answered *"Reorder within its own list only"*, a cross-list drop that passes none of the
    /// dropped row's own siblings writes nothing — `CadenceRowReorderSpan.ownListSiblings` answers
    /// `nil` and `TasksPanelSupport.reorderTask` skips the commit — and it still answers `true`,
    /// because nothing failed. A notice drawn off that `true` alone would say *"Moved, but this
    /// sort doesn't show it there"* about a row that did not move: one false sentence replacing the
    /// one this type exists to avoid. So the same span rule is asked here, from the same shared
    /// type, rather than being re-derived per surface.
    ///
    /// What such a drop should say instead — today it says nothing and the row springs back — is
    /// the half of T-1119 the owner's answer deliberately did not buy, and is filed as [[T-1174]].
    ///
    /// **Ask this BEFORE the drop lands, and report it after.** `tasks` are live model rows: once
    /// `TasksPanelSupport.reorderTask` has renumbered them, the arrangement this question is about
    /// is gone, and "insert this row immediately before the one now immediately after it" is the
    /// no-op `CadenceOrderReassignment` names — so the same question asked afterwards answers `nil`
    /// on exactly the drops that really did land off screen. All three row surfaces take it into a
    /// `let` first and assign it on the `reordered` arm;
    /// `CadenceReorderOffScreenNoticeTests.everyRowDropSurfaceReportsAnOffScreenLanding` pins that
    /// order, and it is measured rather than reasoned — it was found by a red test.
    ///
    /// - Parameter tasks: the surface's own rows, only so the two ids can be resolved. An id that
    ///   is not in them answers `nil`: a surface that cannot find the row it just moved has nothing
    ///   it can truthfully say about where that row went.
    /// - Parameter sortKeyOrder: the surface's active comparator, minus its tie-break — either
    ///   `TaskOrdering.sortKeyOrder` or `CadenceTaskQuerySupport.sortKeyOrder`/`todaySortKeyOrder`,
    ///   whichever vocabulary that screen's sort chip speaks. Passed as a closure rather than as a
    ///   `TaskSortField` because there are two vocabularies and Today's leads with a date-bucket
    ///   rank that belongs to neither.
    static func notice(
        droppedID: UUID,
        targetID: UUID,
        in tasks: [AppTask],
        sortKeyOrder: (AppTask, AppTask) -> TaskSortKeyOrder
    ) -> String? {
        guard let dropped = tasks.first(where: { $0.id == droppedID }),
              let target = tasks.first(where: { $0.id == targetID }),
              CadenceRowReorderSpan.ownListSiblings(moving: droppedID, before: targetID, in: tasks) != nil
        else { return nil }
        return sortKeyOrder(dropped, target) == .tie ? nil : offScreenNotice
    }

    /// The same question about a **kanban card** drop (T-1085), which differs from a row drop in
    /// two ways that are about the gesture and not about the rule.
    ///
    /// **A card can be dropped on the column itself, not on another card.** `KanbanBoardSupport`
    /// takes that as `before: nil` and renumbers the card to the end of the column's `order`, so
    /// the thing the user is being shown is *the bottom of this column* — and the row it has to tie
    /// with is the card currently last in that sequence. With no such card there is nothing for the
    /// drop to be invisible relative to, and the answer is `nil` rather than a sentence about an
    /// empty column.
    ///
    /// **A card can arrive from another column**, refiled by the same commit. It is therefore not
    /// in `columnOrder` at all, which is why this takes the `AppTask` rather than an id: an id
    /// lookup against the destination column would answer `nil` on every cross-column drop — the
    /// half of the gesture most likely to land somewhere the sort will not show.
    ///
    /// - Parameter columnOrder: the destination column's cards in `order` sequence — the same array
    ///   the drop hands `KanbanBoardSupport.reorder`, so "last" here means what it means there.
    static func cardDropNotice(
        dropped: AppTask,
        before target: AppTask?,
        inColumnOrder columnOrder: [AppTask],
        sortKeyOrder: (AppTask, AppTask) -> TaskSortKeyOrder
    ) -> String? {
        guard let landingBeside = target ?? columnOrder.last(where: { $0.id != dropped.id }) else { return nil }
        return sortKeyOrder(dropped, landingBeside) == .tie ? nil : offScreenNotice
    }
}
