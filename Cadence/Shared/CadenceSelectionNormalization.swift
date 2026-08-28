import Foundation

/// T-345, T-346. **A selection that names a model the store no longer has.**
///
/// `CadenceDetailPanelPresentation` is the *model-side* half of this defect class: a host holding a
/// `PersistentModel` asks it whether the thing it is holding is still real, reading `isDeleted` and
/// a nil `modelContext`. This is the *id-side* half. A sidebar selection and a goals list selection
/// hold a `UUID`, not the model, so neither of those two signals exists — the only evidence
/// available is that the id no longer names anything in the live query.
///
/// **The value here is that it splits two questions a page is forever conflating.** "Does this
/// subject still exist?" and "is it hidden by the filter the user has typed?" are different facts
/// with different answers, and T-346 is what happens when one condition answers both: macOS Goals
/// read `visibleGoals.contains(selected) || trimmedQuery.isEmpty`, so a *deleted* goal stayed
/// selected whenever the search box was empty. The guard worked while you were searching and failed
/// when you were not, which is precisely backwards — an empty search box is the state a stale
/// selection is most likely to be sitting in, because it is the state the page spends its life in.
///
/// So existence is checked against the **whole** collection and always retargets; the filter is a
/// separate, optional question a page may answer however its product behaviour requires. A page
/// that does not filter (the macOS sidebar) passes the same set twice and `filterIsActive: false`,
/// and gets existence alone.
///
/// Lives in `Shared/` rather than beside either caller because both callers are platform surfaces
/// and the decision is the half worth pinning — the same reason `CadenceDetailPanelPresentation` is
/// there.
nonisolated enum CadenceSelectionNormalization {

    /// **Whether a held id still names something.** `nil` is not stale: a page with nothing selected
    /// has nothing to retarget, and seeding an empty selection is a separate decision the page owns.
    ///
    /// Deliberately not spelled `existingIDs.contains(selected) == false` at each call site: the
    /// mistake this type exists to prevent is a call site widening the question with an `||`.
    static func isStale<ID: Hashable>(_ selected: ID?, existingIDs: Set<ID>) -> Bool {
        guard let selected else { return false }
        return !existingIDs.contains(selected)
    }

    /// The whole rule, with both questions stated so neither can absorb the other.
    ///
    /// - `existingIDs` is every id the store still has, *unfiltered*. Missing from it means gone,
    ///   and gone always retargets — no filter state can excuse it. That is the T-346 half.
    /// - `visibleIDs` is the page's filtered view. It is consulted **only** when `filterIsActive`,
    ///   which keeps the existing product behaviour: with no search typed, a selection the page
    ///   cannot currently see but which still exists is kept.
    ///
    /// Returns the selection to hold: `selected` when it is still good, `fallback` when it is not.
    static func normalized<ID: Hashable>(
        _ selected: ID?,
        existingIDs: Set<ID>,
        visibleIDs: Set<ID>,
        filterIsActive: Bool,
        fallback: ID?
    ) -> ID? {
        guard let selected else { return nil }
        if isStale(selected, existingIDs: existingIDs) { return fallback }
        if filterIsActive, !visibleIDs.contains(selected) { return fallback }
        return selected
    }

    /// The spelling an unfiltered page calls. Existence is the only question it has.
    static func normalized<ID: Hashable>(
        _ selected: ID?,
        existingIDs: Set<ID>,
        fallback: ID?
    ) -> ID? {
        normalized(
            selected,
            existingIDs: existingIDs,
            visibleIDs: existingIDs,
            filterIsActive: false,
            fallback: fallback
        )
    }
}
