import Foundation

enum CadenceSearchMatcher {
    nonisolated static func rank(_ hits: [CadenceSearchHit], query: String) -> [CadenceSearchHit] {
        hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

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
