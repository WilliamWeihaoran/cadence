import Foundation
import Testing
@testable import Cadence

struct CadenceSearchMatcherTests {
    @Test func matchScoreNormalizesCaseDiacriticsAndPunctuation() throws {
        let score = try #require(
            CadenceSearchMatcher.matchScore(
                query: "cafe plan",
                fields: ["Café-Plan", "Weekly planning note"]
            )
        )

        #expect(score > 1_000)
    }

    @Test func matchScoreRequiresEveryQueryTokenToAppearSomewhere() {
        let score = CadenceSearchMatcher.matchScore(
            query: "focus missing",
            fields: ["Focus Session", "Build a deep work habit"]
        )

        #expect(score == nil)
    }

    @Test func matchScorePrefersTitlePrefixMatchesOverBodyOnlyMatches() throws {
        let prefixScore = try #require(
            CadenceSearchMatcher.matchScore(
                query: "deep",
                fields: ["Deep Work Block", "Protect focus time"]
            )
        )
        let bodyScore = try #require(
            CadenceSearchMatcher.matchScore(
                query: "deep",
                fields: ["Focus Block", "Protect deep work time"]
            )
        )

        #expect(prefixScore > bodyScore)
    }

    @Test func rankUsesAlphabeticalTitleAsTieBreakerAfterScore() {
        let hits = [
            CadenceSearchHit(entityType: "task", entityId: "2", title: "Beta", subtitle: "", excerpt: "", score: 100),
            CadenceSearchHit(entityType: "task", entityId: "3", title: "Gamma", subtitle: "", excerpt: "", score: 80),
            CadenceSearchHit(entityType: "task", entityId: "1", title: "Alpha", subtitle: "", excerpt: "", score: 100),
        ]

        let ranked = CadenceSearchMatcher.rank(hits, query: "anything")

        #expect(ranked.map(\.title) == ["Alpha", "Beta", "Gamma"])
    }
}
