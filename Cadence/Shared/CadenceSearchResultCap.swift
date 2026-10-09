import Foundation

/// How many of a search section's matches it lists, and what it says about the ones it is not
/// listing yet.
///
/// **The cap stays; what changes is that it stops being silent (T-3089).** Both search surfaces
/// truncate — mobile at 24 matches per section while a query is live, the Mac at 14 — and until
/// this type existed neither of them said so. A query matching 62 tasks drew 24 rows, ended at an
/// ordinary row edge, and looked exactly like a query matching 24: the user's own data told them
/// the search was complete when it was not. That is worse than a long list, because a wrong
/// answer with no seam in it is indistinguishable from a right one.
///
/// **The affordance is a count row at the end of the list that expands in place**, not a second
/// screen and not a "see all" push. The owner's decision, and the reason it is the right shape
/// here: the rows above it are already the answer, so the user's question is "is that all?" — and
/// a row that both answers it and resolves it on the spot costs one tap and loses no context. A
/// push would make the cheapest case (two more results) cost a screen transition and a way back.
///
/// **Why its own type rather than another `prefix` at the call site.** The three numbers — rows
/// drawn, rows withheld, and the sentence naming the second — have to be derived from one list in
/// one place or they drift, which is the exact failure `CadenceTaskSurfaceOptions.overflowCaption`
/// records for the completed sections ("N rows under a count of M"). It lives in `Shared/` because
/// the Mac's global search needs the same three numbers; its own cap lives inside
/// `GlobalSearchIndexSupport`, which is why only the mobile surface could adopt this first.
enum CadenceSearchResultCap {
    /// How many rows a section draws, given everything it matched.
    ///
    /// Expanding reveals **all** of the remainder rather than another capful. The count row has
    /// already told the user the exact number they are asking for, so a second "14 more results"
    /// after tapping "38 more results" would be the affordance contradicting itself.
    static func visibleCount(total: Int, cap: Int, isExpanded: Bool) -> Int {
        let matched = max(0, total)
        guard !isExpanded else { return matched }
        return min(matched, max(0, cap))
    }

    /// How many matches the section is withholding, or `nil` when it is listing all of them.
    ///
    /// `nil` rather than `0` for the same reason `hiddenCompletedCount` uses it: there is no
    /// "0 more results" row, and an optional makes the no-row case unspellable at the call site
    /// instead of merely unlikely.
    static func hiddenCount(total: Int, cap: Int, isExpanded: Bool) -> Int? {
        let hidden = max(0, total) - visibleCount(total: total, cap: cap, isExpanded: isExpanded)
        return hidden > 0 ? hidden : nil
    }

    /// What the continuation row reads.
    ///
    /// **It names the remainder, not both numbers**, which is the opposite of
    /// `CadenceTaskSurfaceOptions.overflowCaption`'s "Showing 24 of 62" — and the difference is
    /// the same one that file already draws between its two lines. "Showing 24 of 62" is a
    /// *statement*, for a list where nothing can be done about it. This row is a *control*: it is
    /// tapped, and what it promises is what arrives, so it is phrased as the thing you get.
    ///
    /// It is deliberately not `CadenceTaskSurfaceOptions.moreLabel(hidden:)`'s "+38 more" either.
    /// That line sits beside a strip of chips in a calendar cell with no room for a word; this one
    /// is a full-width row in a list of search results, where "38 more" alone would leave the
    /// reader to infer the noun from context — and the contexts it appears in are a Tasks section,
    /// a Notes section and a Calendar Events section, three different nouns.
    static func continuationLabel(hidden: Int) -> String? {
        guard hidden > 0 else { return nil }
        return hidden == 1 ? "1 more result" : "\(hidden) more results"
    }
}
