import Foundation

/// Where a newly created row's `order` comes from.
///
/// The rule is **max-plus-one**, never `count`. Those two agree only while nothing has ever been
/// deleted: delete the middle of three and the survivors hold `[0, 2]`, so `count` hands the new
/// row `2` — an order that already exists — while max-plus-one hands it `3`.
///
/// A duplicate `order` is not a cosmetic tie. Every list here sorts on `order` alone, and a sort
/// with equal keys is unstable, so two rows can swap places between launches with nothing edited.
/// That reads as the app losing track of an arrangement the user made, not as a sorting detail.
///
/// This lives in `Shared/` and is spelled once because the divergence it fixes (T-329) came from
/// the rule being re-typed per call site: macOS's *list* creation already allocated max-plus-one
/// while the context and saved-link sheets beside it still counted.
nonisolated enum CadenceOrderAllocation {
    /// The next free order for a collection whose current orders are `existingOrders`.
    ///
    /// Empty means `0`, so the first row of an empty list is numbered from zero rather than from
    /// one. Negative stored orders are honoured: a collection holding `[-3]` allocates `-2`, not
    /// `0`, because a hand-reordered or migrated row that sorted first must stay first.
    static func nextOrder(after existingOrders: some Sequence<Int>) -> Int {
        (existingOrders.max() ?? -1) + 1
    }

    /// The next free order for `items`, reading each item's order through `order`.
    static func nextOrder<Item>(after items: some Sequence<Item>, order: (Item) -> Int) -> Int {
        nextOrder(after: items.map(order))
    }
}
