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
    /// Rank pre-scored items: score descending, then title case-insensitive ascending.
    ///
    /// Decorate–sort–undecorate. `matchScore` folds and regex-strips every field on each call, so
    /// scoring inside the comparator would cost O(n log n) normalizations of the same strings;
    /// scoring once up front makes it O(n) for an identical ordering.
    nonisolated static func rank<Item>(
        _ items: [Item],
        score: (Item) -> Int,
        title: (Item) -> String
    ) -> [Item] {
        items
            .map { (item: $0, score: score($0), title: title($0)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map(\.item)
    }

    /// Rank items by scoring `fields` against `query`. Items that do not match at all sink to the
    /// bottom (`Int.min`) rather than being dropped — filtering is the caller's decision.
    nonisolated static func rank<Item>(
        _ items: [Item],
        query: String,
        title: (Item) -> String,
        fields: (Item) -> [String]
    ) -> [Item] {
        rank(
            items,
            score: { matchScore(query: query, fields: fields($0)) ?? Int.min },
            title: title
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
