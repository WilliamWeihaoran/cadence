import Foundation
import Testing

/// **[[T-4800]]: `declarationBody` searched prose for a declaration.**
///
/// `CadenceSourceScan.declarationBody(_:in:)` took `source.range(of: declaration)` on whatever
/// string it was handed. 323 of the 411 call sites in this target handed it **raw** file text, so
/// any comment that merely *mentioned* a declaration matched before the declaration did, and the
/// body read was whichever `{ … }` followed the prose.
///
/// That is a measured defect, not a worry. [[T-3371]] reddened `main` on `205d13a3`: [[T-3021]]
/// added a doc comment reading "filled by `init()` off …" above `PersistenceController.init`, and
/// `theStartupPreflightBacksUpTheStoreThisLaunchOpened` read a two-line `guard` block as the
/// initialiser's body. One failure out of 6,327, in a commit that changed no behaviour. Four scans
/// had each already worked around it by stripping at their own call site; the fix this suite holds
/// does it once, inside `declarationBody`.
///
/// **The invariant asserted here is a RELATION, not a pinned body text:** reading a declaration out
/// of raw source and out of the same source pre-stripped must give the same answer. That is exactly
/// what was false before, it stays true as the files below are edited, and it cannot be satisfied
/// by a scan that is still comment-blind.
struct CadenceDeclarationBodyCommentBlindnessTests {

    // MARK: - The shape, on a fixture that spells the T-3371 trap out

    /// A comment naming the declaration, *above* the declaration, with a brace block between them —
    /// which is what a `guard` or an `if` after a doc comment looks like to a text search.
    private static let trapFixture = """
    struct Example {
        /// The cache is filled by `init()` off the main actor, so the block below is not it.
        func decoy() {
            let readTheWrongBody = true
            _ = readTheWrongBody
        }

        init() {
            let readTheRightBody = true
            _ = readTheRightBody
        }
    }
    """

    @Test func anAnchorThatAppearsOnlyInACommentDoesNotWinTheSearch() throws {
        let body = try #require(
            CadenceSourceScan.declarationBody("init()", in: Self.trapFixture),
            "the fixture's init() did not read as itself"
        )
        #expect(
            body.contains("readTheRightBody"),
            "declarationBody matched the comment and returned the block after it: \(body)"
        )
        #expect(
            !body.contains("readTheWrongBody"),
            "declarationBody returned decoy()'s body, which is the T-3371 failure exactly"
        )
    }

    /// The fixture is only evidence if the comment is genuinely what the old code would have
    /// matched — so this asserts the trap is armed rather than trusting the string above to stay
    /// written the way the test above needs it.
    @Test func theFixtureStillCarriesTheCommentAheadOfTheDeclaration() throws {
        let fixture = Self.trapFixture
        let commentMention = try #require(fixture.range(of: "`init()`"), "the fixture lost its comment")
        let declaration = try #require(
            fixture.range(of: "\n    init()"),
            "the fixture lost its real initialiser"
        )
        #expect(
            commentMention.lowerBound < declaration.lowerBound,
            "the comment no longer precedes the declaration, so this fixture proves nothing"
        )
    }

    // MARK: - The relation, over the real tree

    /// Real declarations, chosen because each file carries prose near the anchor. Read as a
    /// relation between two readings of the same file, so none of them pins a body's text.
    private static let realDeclarations: [(path: String, anchor: String)] = [
        ("Cadence/Services/PersistenceController.swift", "init()"),
        ("Cadence/Shared/CadenceDefaults.swift", "enum CadenceDefaults"),
        ("Cadence/Services/CadenceTodayWidgetSupport.swift", "nonisolated enum CadenceWidgetGenerationLedger")
    ]

    @Test func readingADeclarationFromRawSourceAgreesWithReadingItPreStripped() throws {
        var checked = 0
        for (path, anchor) in Self.realDeclarations {
            let raw = try CadenceSourceScan.sourceFile(path)
            let stripped = CadenceSourceScan.strippingComments(raw)

            let fromRaw = CadenceSourceScan.declarationBody(anchor, in: raw)
            let fromStripped = CadenceSourceScan.declarationBody(anchor, in: stripped)

            #expect(
                fromRaw != nil,
                "\(anchor) no longer reads out of \(path); re-point this case rather than deleting it"
            )
            #expect(
                fromRaw == fromStripped,
                "\(path) reads \(anchor) differently raw and pre-stripped, so the scan is comment-blind again"
            )
            checked += 1
        }
        #expect(checked == Self.realDeclarations.count, "the sweep read no declarations")
    }

    /// The non-vacuity floor for the case above: at least one of those files must actually *have* a
    /// comment mentioning its own anchor, or the relation is true for an uninteresting reason.
    @Test func atLeastOneRealCaseHasACommentThatNamesItsOwnAnchor() throws {
        var armed: [String] = []
        for (path, anchor) in Self.realDeclarations {
            let raw = try CadenceSourceScan.sourceFile(path)
            let stripped = CadenceSourceScan.strippingComments(raw)
            // Present in the raw text, absent once comments are blanked => it was in a comment.
            let rawHits = raw.components(separatedBy: anchor).count - 1
            let codeHits = stripped.components(separatedBy: anchor).count - 1
            if rawHits > codeHits { armed.append(path) }
        }
        #expect(
            !armed.isEmpty,
            "no listed file mentions its own anchor in prose any more, so this suite has stopped testing the defect"
        )
    }
}
