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
    /// `CadenceOrderCommit.commit` has answered `true`.
    static let offScreenNotice = "Moved, but this sort doesn't show it there."

    /// The notice for one drop, or `nil` when the drop is fully visible.
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
        return sortKeyOrder(dropped, target) == .tie ? nil : offScreenNotice
    }
}
