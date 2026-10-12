import Foundation

/// The one search scorer. macOS's command palette (`Cmd+K`), the iOS search surface, and the
/// MCP read service all rank through this.
///
/// It used to live in `Services/MCPReadOnly/`, which every guide tells agents not to touch, so
/// when macOS needed a matcher a second one -- `GlobalSearchMatcher` -- was written beside it with
/// the same algorithm and the same magic numbers, and only this one had tests. The fork was
/// verified identical before being removed. Keeping the file here, in `Shared/`, is what stops
/// the next surface from forking it again.
///
/// Pure and `nonisolated`: safe to call from widget timeline providers and the MCP server, both
/// of which run off the main actor.
nonisolated enum CadenceSearchMatcher {
    nonisolated struct PreparedQuery: Sendable {
        let normalized: String
        let tokens: [String]
        /// The user typed nothing but whitespace. Only this is "match everything" (T-3099): a query
        /// that had characters and normalized to no tokens -- `"!!!"`, an emoji -- is a real query
        /// with nothing searchable in it, and answering it with every row looked like search worked.
        let isBlank: Bool

        init(_ query: String) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            isBlank = trimmed.isEmpty
            normalized = normalize(trimmed)
            tokens = normalized.split(separator: " ").map(String.init)
        }
    }

    /// Rank pre-scored items: score descending, then title case-insensitive ascending, then
    /// `identity` ascending.
    ///
    /// **T-372a.** All three legs are required, and that is the whole point: with `identity` this
    /// is a **total** order, so the same set of hits ranks to the same sequence on every call.
    /// Stopping at title leaves two hits that share a score and a title — two tasks called "Admin"
    /// in two contexts, a saved link added twice — in whatever order the store handed them over,
    /// which is a property of the store rather than of this code.
    ///
    /// Identity is required at every caller, including MCP and both app search surfaces (T-372a).
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
        identity: (Item) -> String
    ) -> [Item] {
        items
            .map { (item: $0, score: score($0), title: title($0), identity: identity($0)) }
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
        identity: (Item) -> String
    ) -> [Item] {
        rank(items, query: PreparedQuery(query), title: title, fields: fields, identity: identity)
    }

    nonisolated static func rank<Item>(
        _ items: [Item],
        query: PreparedQuery,
        title: (Item) -> String,
        fields: (Item) -> [String],
        identity: (Item) -> String
    ) -> [Item] {
        rank(
            items,
            score: { matchScore(query: query, fields: fields($0)) ?? Int.min },
            title: title,
            identity: identity
        )
    }

    /// `nil` means "no match". An empty or whitespace-only query matches everything with a flat
    /// score of 1; a non-blank query that normalizes to no tokens (all punctuation or symbols)
    /// matches nothing (T-3099). The first field is treated as the title and weighted highest.
    nonisolated static func matchScore(query: String, fields: [String]) -> Int? {
        matchScore(query: PreparedQuery(query), fields: fields)
    }

    nonisolated static func matchScore(query: PreparedQuery, fields: [String]) -> Int? {
        guard !query.tokens.isEmpty else { return query.isBlank ? 1 : nil }

        let normalizedFields = fields
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedFields.isEmpty else { return nil }

        let title = normalizedFields.first ?? ""
        let body = normalizedFields.joined(separator: " ")
        let titleWords = title.split(separator: " ").map(String.init)
        let allWords = body.split(separator: " ").map(String.init)

        var score = 0
        if title == query.normalized {
            score += 1_000
        } else if title.hasPrefix(query.normalized) {
            score += 800
        } else if body.contains(query.normalized) {
            score += 320
        }

        for token in query.tokens {
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

    /// Case- and diacritic-folded, with every run of characters that is not a letter, combining
    /// mark or digit **of any script** collapsed to one space.
    ///
    /// **T-3099.** The class used to be `[^A-Za-z0-9]`, which stripped every CJK, Cyrillic, Greek,
    /// Arabic, Hebrew and Thai character: such a title normalized to `""` and could never be found,
    /// and such a query normalized to no tokens and matched everything. `\p{M}` is kept so Indic
    /// and Thai vowel signs do not split a word into fragments.
    ///
    /// **Scripts without word breaks (CJK, Thai) are not segmented.** A run of them is one "word",
    /// and a query inside it is found by the containment fallbacks in `matchScore`
    /// (`title.contains` / `body.contains`), which score below a word-prefix hit -- so a CJK query
    /// that starts a title still ranks as a prefix, and one in the middle still matches. That is
    /// substring search on the normalized field, chosen over a locale tokenizer so the scorer
    /// stays pure, locale-independent and identical on every caller.
    nonisolated static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{M}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
