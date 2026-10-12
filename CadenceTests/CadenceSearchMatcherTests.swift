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

    // MARK: - Score buckets
    //
    // These pin the magic numbers themselves. The matcher was forked once because two surfaces
    // needed the same ranking; the numbers are the behaviour, so they get asserted exactly.

    @Test func exactTitleMatchScoresTheFullTitleBonusPlusPositionalTokenBonuses() throws {
        // 1000 (title == query) + 260 (word 0) + 246 (word 1) + 232 (word 2)
        let score = try #require(
            CadenceSearchMatcher.matchScore(query: "deep work block", fields: ["Deep Work Block"])
        )

        #expect(score == 1_738)
    }

    @Test func titlePrefixScoresBelowExactTitleAndAboveBodyContainment() throws {
        let exact = try #require(CadenceSearchMatcher.matchScore(query: "deep", fields: ["Deep"]))
        let prefix = try #require(CadenceSearchMatcher.matchScore(query: "deep", fields: ["Deep Work"]))
        let bodyContains = try #require(
            CadenceSearchMatcher.matchScore(query: "deep work", fields: ["Focus", "a deep work slot"])
        )

        #expect(exact == 1_000 + 260)
        #expect(prefix == 800 + 260)
        // 320 (body contains the whole query) + 158 (word 2 of the body) + 152 (word 3)
        #expect(bodyContains == 320 + 158 + 152)
    }

    @Test func titleWordBonusDecaysWithPositionAndFloorsAt180() throws {
        func score(titleWords: [String]) throws -> Int {
            try #require(CadenceSearchMatcher.matchScore(query: "target", fields: [titleWords.joined(separator: " ")]))
        }

        let atIndex5 = try score(titleWords: ["a", "b", "c", "d", "e", "target", "x", "y"])
        let atIndex6 = try score(titleWords: ["a", "b", "c", "d", "e", "f", "target", "x"])
        let atIndex7 = try score(titleWords: ["a", "b", "c", "d", "e", "f", "g", "target"])

        // 320 for the body containing the query, then max(260 - index * 14, 180).
        #expect(atIndex5 == 320 + 190)
        #expect(atIndex6 == 320 + 180)
        #expect(atIndex7 == 320 + 180, "the positional bonus floors at 180 rather than decaying away")
    }

    @Test func nonTitleWordBonusDecaysMoreSlowlyAndFloorsAt90() throws {
        func score(bodyWordCountBeforeTarget count: Int) throws -> Int {
            let filler = (0..<count).map { "w\($0)" }.joined(separator: " ")
            return try #require(
                CadenceSearchMatcher.matchScore(query: "target", fields: ["Zebra", "\(filler) target"])
            )
        }

        // allWords index = 1 (the title word) + filler count.
        #expect(try score(bodyWordCountBeforeTarget: 3) == 320 + 146)   // max(170 - 4 * 6, 90)
        #expect(try score(bodyWordCountBeforeTarget: 13) == 320 + 90)   // max(170 - 14 * 6, 90) -> floor
        #expect(try score(bodyWordCountBeforeTarget: 30) == 320 + 90)
    }

    @Test func substringFallbacksRankTitleAboveBody() throws {
        // "board" is inside "keyboard" but is not a word prefix, so neither word-prefix branch fires.
        let inTitle = try #require(CadenceSearchMatcher.matchScore(query: "board", fields: ["Keyboard"]))
        let inBody = try #require(
            CadenceSearchMatcher.matchScore(query: "board", fields: ["Alpha", "Keyboard shortcuts"])
        )

        #expect(inTitle == 320 + 85)
        #expect(inBody == 320 + 35)
        #expect(inTitle > inBody)
    }

    // MARK: - Degenerate input
    //
    // The macOS command palette leans on these: it calls the matcher on every keystroke,
    // including the empty field it opens with.

    @Test func emptyOrWhitespaceOnlyQueryMatchesEverythingFlatly() {
        #expect(CadenceSearchMatcher.matchScore(query: "", fields: ["Anything"]) == 1)
        #expect(CadenceSearchMatcher.matchScore(query: "   \t\n ", fields: ["Anything"]) == 1)
        // An empty query does not even need fields to match against.
        #expect(CadenceSearchMatcher.matchScore(query: "", fields: []) == 1)
    }

    /// T-3099: a query the user actually typed that normalizes to no tokens is not the idle field.
    /// It used to score every row 1, so the palette showed arbitrary results ordered by title and
    /// looked as if search had worked.
    @Test func punctuationOrSymbolOnlyQueryMatchesNothing() {
        #expect(CadenceSearchMatcher.PreparedQuery("!!! ---").tokens.isEmpty)
        #expect(CadenceSearchMatcher.matchScore(query: "!!! ---", fields: ["Anything"]) == nil)
        #expect(CadenceSearchMatcher.matchScore(query: "\u{1F389}", fields: ["Party \u{1F389}"]) == nil)
        #expect(CadenceSearchMatcher.matchScore(query: "!!!", fields: []) == nil)

        struct Row { let title: String }
        let rows = [Row(title: "Alpha"), Row(title: "Beta")]
        let ranked = CadenceSearchMatcher.rank(
            rows, query: "???", title: { $0.title }, fields: { [$0.title] }, identity: { $0.title }
        )
        let scores = rows.map { CadenceSearchMatcher.matchScore(query: "???", fields: [$0.title]) }
        #expect(ranked.count == rows.count, "rank still sinks rather than drops")
        #expect(scores.allSatisfy { $0 == nil })
    }

    @Test func nonEmptyQueryAgainstNoUsableFieldsDoesNotMatch() {
        #expect(CadenceSearchMatcher.matchScore(query: "plan", fields: []) == nil)
        #expect(CadenceSearchMatcher.matchScore(query: "plan", fields: ["", "   "]) == nil)
    }

    @Test func normalizeFoldsCaseDiacriticsAndCollapsesPunctuationToSingleSpaces() {
        #expect(CadenceSearchMatcher.normalize("  Café--Plan!! 2026  ") == "cafe plan 2026")
        #expect(CadenceSearchMatcher.normalize("!!!") == "")
    }

    // MARK: - T-3099: letters and digits of every script survive normalization

    @Test func normalizeKeepsLettersAndDigitsOfEveryScript() {
        // Han, with a full-width colon as the separator.
        #expect(CadenceSearchMatcher.normalize("\u{4F1A}\u{8BAE}\u{8BB0}\u{5F55}\u{FF1A}\u{5468}\u{4E00}")
            == "\u{4F1A}\u{8BAE}\u{8BB0}\u{5F55} \u{5468}\u{4E00}")
        // Cyrillic: case folds, punctuation collapses.
        #expect(CadenceSearchMatcher.normalize("\u{041F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442}, \u{041C}\u{0438}\u{0440}!")
            == "\u{043F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442} \u{043C}\u{0438}\u{0440}")
        // Greek tonos folds like a Latin accent.
        #expect(CadenceSearchMatcher.normalize("\u{0395}\u{03BB}\u{03BB}\u{03B7}\u{03BD}\u{03B9}\u{03BA}\u{03AC}")
            == "\u{03B5}\u{03BB}\u{03BB}\u{03B7}\u{03BD}\u{03B9}\u{03BA}\u{03B1}")
        // Hebrew, Arabic, Thai and Devanagari are kept whole -- none of them may vanish.
        for word in [
            "\u{05E9}\u{05DC}\u{05D5}\u{05DD}",
            "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}",
            "\u{0E20}\u{0E32}\u{0E29}\u{0E32}\u{0E44}\u{0E17}\u{0E22}",
            "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}",
        ] {
            #expect(!CadenceSearchMatcher.normalize(word).isEmpty, "\(word) normalized away")
            #expect(!CadenceSearchMatcher.normalize(word).contains(" "), "\(word) was split")
        }
        // Arabic-Indic digits are digits.
        #expect(CadenceSearchMatcher.normalize("\u{0662}\u{0660}\u{0662}\u{0666}") == "\u{0662}\u{0660}\u{0662}\u{0666}")
    }

    /// Han has no word breaks, so a title is one normalized "word" and the matcher finds a query
    /// inside it by substring containment: a query that starts the title is a prefix hit, one in
    /// the middle falls to the containment buckets, and an absent one does not match.
    @Test func cjkTitleIsFindableByPrefixAndBySubstring() throws {
        let title = "\u{4F1A}\u{8BAE}\u{8BB0}\u{5F55}"          // meeting minutes
        let atStart = try #require(CadenceSearchMatcher.matchScore(query: "\u{4F1A}\u{8BAE}", fields: [title]))
        let inside = try #require(CadenceSearchMatcher.matchScore(query: "\u{8BB0}\u{5F55}", fields: [title]))
        let exact = try #require(CadenceSearchMatcher.matchScore(query: title, fields: [title]))

        #expect(exact == 1_000 + 260)
        #expect(atStart == 800 + 260)
        #expect(inside == 320 + 85)
        #expect(exact > atStart && atStart > inside)
        #expect(CadenceSearchMatcher.matchScore(query: "\u{65E5}\u{5386}", fields: [title]) == nil)
    }

    /// The other half of the ticket: a non-Latin query used to normalize to zero tokens and score
    /// every row 1. It must now discriminate -- one row matches, the Latin and the other-script
    /// rows do not.
    @Test func nonLatinQueryMatchesOnlyRowsThatContainIt() throws {
        struct Row { let title: String; let notes: String }
        let rows = [
            Row(title: "Weekly review", notes: "plan"),
            Row(title: "\u{041F}\u{043B}\u{0430}\u{043D} \u{043D}\u{0435}\u{0434}\u{0435}\u{043B}\u{0438}", notes: ""),
            Row(title: "\u{4F1A}\u{8BAE}", notes: "\u{9879}\u{76EE}\u{8BA1}\u{5212}"),
        ]
        func matches(_ query: String) -> [String] {
            rows.filter { CadenceSearchMatcher.matchScore(query: query, fields: [$0.title, $0.notes]) != nil }.map(\.title)
        }

        // Cyrillic, typed in a different case from the stored title.
        #expect(matches("\u{041F}\u{041B}\u{0410}\u{041D}") == [rows[1].title])
        // Han, found in the notes body rather than the title.
        #expect(matches("\u{8BA1}\u{5212}") == [rows[2].title])
        // And Latin still behaves as it did.
        #expect(matches("plan") == [rows[0].title])

        let ranked = CadenceSearchMatcher.rank(
            rows, query: "\u{043F}\u{043B}\u{0430}\u{043D}", title: { $0.title },
            fields: { [$0.title, $0.notes] }, identity: { $0.title }
        )
        #expect(ranked.first?.title == rows[1].title)
    }

    // MARK: - Ranking

    @Test func rankByPrecomputedScoreUsesAlphabeticalTitleAsTieBreaker() {
        let hits = [
            CadenceSearchHit(entityType: "task", entityId: "2", title: "Beta", subtitle: "", excerpt: "", score: 100),
            CadenceSearchHit(entityType: "task", entityId: "3", title: "Gamma", subtitle: "", excerpt: "", score: 80),
            CadenceSearchHit(entityType: "task", entityId: "1", title: "Alpha", subtitle: "", excerpt: "", score: 100),
        ]

        let ranked = CadenceSearchMatcher.rank(
            hits,
            score: { $0.score },
            title: { $0.title },
            identity: { $0.entityId }
        )

        #expect(ranked.map(\.title) == ["Alpha", "Beta", "Gamma"])
    }

    // MARK: - T-372a: the three tiers, and that each one is load-bearing

    /// Pins **score, then title, then identity** as an ordered sequence of tiers rather than as a
    /// set of three rules.
    ///
    /// The fixture is built so that every pair in it disagrees on exactly one tier while the tiers
    /// *below* that one point the other way. That is what makes the expectation discriminating:
    /// the previous tie-break test above ranked `Alpha/100`, `Beta/100`, `Gamma/80`, where score
    /// order and title order happen to agree — so sorting by title first and score second produces
    /// the same three names and the test cannot see the difference. Here every adjacent swap of two
    /// tiers, and every reversal of one tier's direction, reorders the answer.
    ///
    /// Read the expectation as `title/identity` pairs:
    /// - `Admin/a` before `Admin/b` — same score, same title, identity decides.
    /// - `Admin/*` before `Zulu/a1` — same score, title decides, and it decides *against* identity
    ///   (`a1` sorts before `b`).
    /// - all of them before `AAA/a0`, whose title and identity both sort first and whose score
    ///   does not.
    @Test func rankPutsScoreAheadOfTitleAndTitleAheadOfIdentity() {
        let hits = [
            CadenceSearchHit(entityType: "task", entityId: "b", title: "Admin", subtitle: "", excerpt: "", score: 100),
            CadenceSearchHit(entityType: "task", entityId: "a1", title: "Zulu", subtitle: "", excerpt: "", score: 100),
            CadenceSearchHit(entityType: "task", entityId: "a0", title: "AAA", subtitle: "", excerpt: "", score: 50),
            CadenceSearchHit(entityType: "task", entityId: "a", title: "Admin", subtitle: "", excerpt: "", score: 100),
        ]

        let ranked = CadenceSearchMatcher.rank(
            hits,
            score: { $0.score },
            title: { $0.title },
            identity: { $0.entityId }
        )

        #expect(ranked.map { "\($0.title)/\($0.entityId)" } == ["Admin/a", "Admin/b", "Zulu/a1", "AAA/a0"])
    }

    /// The property the identity tier exists for: ranking is a function of the *set* of hits, not
    /// of the order the store happened to hand them over in.
    ///
    /// Twenty-four rows sharing a score and a title is the shape the ticket names — the same task
    /// title under several lists, a saved link added twice. Without the identity leg the comparator
    /// answers "neither" for every pair, and the sort can only echo its input, so the two calls
    /// below disagree. This is the assertion the tier test above cannot make: a dropped tie-break
    /// is invisible to a fixture whose ties are already in the expected order.
    @Test func rankIsIndependentOfTheOrderTheStoreHandedTheHitsOver() {
        let hits = (0..<24).map { index in
            CadenceSearchHit(
                entityType: "task",
                entityId: String(format: "id-%02d", index),
                title: "Admin",
                subtitle: "",
                excerpt: "",
                score: 100
            )
        }

        func ranked(_ input: [CadenceSearchHit]) -> [String] {
            CadenceSearchMatcher.rank(
                input,
                score: { $0.score },
                title: { $0.title },
                identity: { $0.entityId }
            )
            .map(\.entityId)
        }

        #expect(ranked(hits) == ranked(hits.reversed()))
        #expect(ranked(hits.reversed()) == hits.map(\.entityId))
    }

    @Test func rankByQueryScoresFieldsAndSinksNonMatchesToTheBottom() {
        struct Row { let title: String; let subtitle: String }
        let rows = [
            Row(title: "Unrelated", subtitle: "nothing here"),
            Row(title: "Deep dive", subtitle: "notes"),
            Row(title: "Deep Work Block", subtitle: "protect focus"),
            Row(title: "Weekly review", subtitle: "a deep work retro"),
        ]

        let ranked = CadenceSearchMatcher.rank(
            rows,
            query: "deep work",
            title: { $0.title },
            fields: { [$0.title, $0.subtitle] },
            identity: { $0.title }
        )

        #expect(ranked.map(\.title) == ["Deep Work Block", "Weekly review", "Deep dive", "Unrelated"])
    }

    @Test func rankByQueryFallsBackToAlphabeticalWhenEveryItemScoresTheSame() {
        struct Row { let title: String }
        let rows = [Row(title: "Gamma"), Row(title: "alpha"), Row(title: "Beta")]

        let ranked = CadenceSearchMatcher.rank(
            rows,
            query: "",
            title: { $0.title },
            fields: { [$0.title] },
            identity: { $0.title }
        )

        #expect(ranked.map(\.title) == ["alpha", "Beta", "Gamma"])
    }
}
