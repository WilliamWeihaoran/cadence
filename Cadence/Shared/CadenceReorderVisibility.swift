import Foundation

/// Whether the row the user just dropped landed somewhere they can see it, and the sentence that
/// says so when it did not — or when it did not land at all ([[T-1174]]).
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
    /// targetID:in:sortKeyOrder:)` refuses to speak *this* sentence for a drop that had nothing to
    /// commit — that drop gets `acrossListsNotice`, which claims nothing.
    static let offScreenNotice = "Moved, but this sort doesn't show it there."

    /// What a drop that crossed lists and therefore moved nothing says ([[T-1174]]).
    ///
    /// **This is the sentence [[T-1119]]'s answer needs, not the option that answer declined.** The
    /// repository owner was given three choices and picked *"Reorder within its own list only"*.
    /// That ticket's own text records what picking it costs: the option "would be [[T-614]]'s rule
    /// inverted and would need a sentence of its own to be honest", because a drag that crosses
    /// lists now visibly does nothing. Option 3 was a different thing — *keep* the cross-list
    /// renumber and explain the move at the drop — and nothing here revives it: the drop still
    /// writes nothing, and this reports that rather than softening it.
    ///
    /// **It leads with the outcome and then gives the rule**, in that order, because the first
    /// thing the user needs is that the spring-back was not a failure — T-614's rule is that a
    /// visible rearrangement is the success report, so its absence reads as a refusal unless
    /// something says otherwise. `CadenceOrderCommit.failureNotice` is what a refusal says, and it
    /// is deliberately not this: nothing failed, so it is drawn in
    /// `CadenceInlineNotice(tone: .informational)` beside the other landing sentence.
    ///
    /// **It names a list rather than a sort**, which is the one thing that makes it safe to draw on
    /// all three row surfaces: `offScreenNotice` may not name a sort mode because the surfaces
    /// speak two vocabularies for it (*Custom* and *List Order*), and "its own list" has one
    /// spelling everywhere — it is `CadenceTaskQuerySupport.listGroupKey`, the same grouping the
    /// sidebar, Today's headers and All Tasks' By List mode all use, Inbox included.
    ///
    /// **It teaches nothing about `order`.** A sentence explaining that each list carries its own
    /// hand-made sequence would be a paragraph about a data model at the moment the user is trying
    /// to move a row; this states the rule as a rule, which is all that is needed to aim the next
    /// drag — drop it on a row of its own list and it moves.
    static let acrossListsNotice = "Nothing moved — rows only reorder within their own list."

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
    /// **What such a drop says instead is `acrossListsNotice` ([[T-1174]])**, and only when it
    /// really did ask for something: `CadenceRowReorderSpan.movesTheSlice` separates a drop that was
    /// declined because it crossed lists from one that asked for no change at all, and the second
    /// stays silent. So this answers one of three things, and the three arms are the three
    /// different events a drop can be — moved and shown, moved and not shown, not moved and told
    /// why.
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
              let target = tasks.first(where: { $0.id == targetID }) else { return nil }
        guard CadenceRowReorderSpan.ownListSiblings(moving: droppedID, before: targetID, in: tasks) != nil else {
            // The drop wrote nothing. Which of the two reasons it was decides whether there is
            // anything to say: a gesture that asked for no change needs no sentence, and one that
            // asked for a change across lists and was declined is the one that springs back
            // unexplained (T-1174).
            return CadenceRowReorderSpan.movesTheSlice(moving: droppedID, before: targetID, in: tasks)
                ? acrossListsNotice
                : nil
        }
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
