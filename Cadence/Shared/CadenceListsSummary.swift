import Foundation

/// The eyebrow over the Lists page title.
///
/// It read `WORKSPACE` — a word that named the app you were already inside, over a title that
/// already said "Lists". The repo's standing rule is that a page header does not describe the page
/// you are on, and every sibling page already obeys it with a *shape* eyebrow instead: Goals reads
/// "1 direction · 0 milestones", Habits "0 of 2 done today", Focus "6 ready". Lists was the one
/// page still spending that line on a constant.
///
/// Zeros are omitted rather than printed, following `CadenceTodaySummary.line` and
/// `CadenceTodaySummary.line`: a count worth showing appears once, and a page with nothing in it
/// says so in words rather than with a pair of noughts.
nonisolated enum CadenceListsSummary {
    ///
    /// **`hasArchived` is [[T-17786]].** The zero branch said "No lists yet" whatever was archived,
    /// so archiving every list put that sentence -- a claim that nothing has ever been made -- over
    /// the Archived section listing them, on the same screen. With something archived the eyebrow
    /// says what is true, in the empty panel's own words; the caller passes the same predicate
    /// that draws the Archived section (`hasArchivedLists`), as `activeListsSubtitle` asks.
    static func eyebrow(areaCount: Int, projectCount: Int, hasArchived: Bool) -> String {
        // No `max(_, 0)` clamp: the `> 0` guards below already exclude a negative, so a clamp was
        // dead code — a mutation test that deleted it left every assertion passing, which is how it
        // was found. The negative case is still pinned; it is these guards that pin it.
        var parts: [String] = []
        if areaCount > 0 { parts.append("\(areaCount) \(areaCount == 1 ? "area" : "areas")") }
        if projectCount > 0 { parts.append("\(projectCount) \(projectCount == 1 ? "project" : "projects")") }

        guard !parts.isEmpty else {
            return hasArchived
                ? CadenceEmptyStateCopy.activeListsTitle
                : CadenceEmptyStateCopy.listsTitle(isNarrowed: false)
        }
        return parts.joined(separator: " · ")
    }
}
