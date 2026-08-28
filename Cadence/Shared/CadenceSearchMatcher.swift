import Foundation

/// The one search scorer. macOS's command palette (`Cmd+K`), the iOS search surface, and the
/// MCP read service all rank through this.
///
/// It used to live in `Services/MCPReadOnly/`, which every guide tells agents not to touch, so
/// when macOS needed a matcher a second one — `GlobalSearchMatcher` — was written beside it with
/// the same algorithm and the same magic numbers, and only this one had tests. The fork was
/// verified identical before being removed. Keeping the file here, in `Shared/`, is what stops
/// the next surface from forking it again.
///
/// Pure and `nonisolated`: safe to call from widget timeline providers and the MCP server, both
/// of which run off the main actor.
nonisolated enum CadenceSearchMatcher {
    /// Rank pre-scored items: score descending, then title case-insensitive ascending, then
    /// `identity` ascending.
    ///
    /// **T-372a.** With an `identity` this is a **total** order and the same set of hits ranks to
    /// the same sequence on every call. Without one it stops at title, and two hits sharing a score
    /// and a title — two tasks called "Admin" in two contexts, a saved link added twice — come back
    /// in whatever order the store handed them over, which is a property of the store rather than
    /// of this code. Pass one. The parameter is optional only because `rank` is called from files
    /// this change was not allowed to touch; see the T-372a entry in `docs/TODO.md` for the two
    /// that still need threading.
    ///
    /// Deliberately a closure rather than an `Item: Identifiable` constraint. `CadenceSearchHit` —
    /// the MCP `search()` row, and the case the ticket is about — is not `Identifiable`, and a
    /// constrained overload would have silently selected the partial order for exactly the caller
    /// that needed the total one.
    ///
    /// Decorate–sort–undecorate. `matchScore` folds and regex-strips every field on each call, so
    /// scoring inside the comparator would cost O(n log n) normalizations of the same strings;
    /// scoring once up front makes it O(n) for an identical ordering. `identity` is evaluated once
    /// per item for the same reason.
    nonisolated static func rank<Item>(
        _ items: [Item],
        score: (Item) -> Int,
        title: (Item) -> String,
        identity: ((Item) -> String)? = nil
    ) -> [Item] {
        items
            .map { (item: $0, score: score($0), title: title($0), identity: identity?($0) ?? "") }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let titles = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titles != .orderedSame { return titles == .orderedAscending }
                return lhs.identity < rhs.identity
            }
            .map(\.item)
    }

    /// Rank items by scoring `fields` against `query`. Items that do not match at all sink to the
    /// bottom (`Int.min`) rather than being dropped — filtering is the caller's decision.
    ///
    /// `identity` carries through to the comparator above; the note there applies here too.
    nonisolated static func rank<Item>(
        _ items: [Item],
        query: String,
        title: (Item) -> String,
        fields: (Item) -> [String],
        identity: ((Item) -> String)? = nil
    ) -> [Item] {
        rank(
            items,
            score: { matchScore(query: query, fields: fields($0)) ?? Int.min },
            title: title,
            identity: identity
        )
    }

    /// `nil` means "no match". An empty query matches everything with a flat score of 1.
    /// The first field is treated as the title and weighted highest.
    nonisolated static func matchScore(query: String, fields: [String]) -> Int? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty { return 1 }

        let normalizedQuery = normalize(trimmedQuery)
        let queryTokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !queryTokens.isEmpty else { return 1 }

        let normalizedFields = fields
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedFields.isEmpty else { return nil }

        let title = normalizedFields.first ?? ""
        let body = normalizedFields.joined(separator: " ")
        let titleWords = title.split(separator: " ").map(String.init)
        let allWords = body.split(separator: " ").map(String.init)

        var score = 0
        if title == normalizedQuery {
            score += 1_000
        } else if title.hasPrefix(normalizedQuery) {
            score += 800
        } else if body.contains(normalizedQuery) {
            score += 320
        }

        for token in queryTokens {
            if let index = titleWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(260 - (index * 14), 180)
            } else if let index = allWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(170 - (index * 6), 90)
            } else if title.contains(token) {
                score += 85
            } else if body.contains(token) {
                score += 35
            } else {
                return nil
            }
        }

        return score
    }

    nonisolated static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
