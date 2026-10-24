import Foundation
import Testing

/// **[[T-4801]]: the same comment-blindness class [[T-4800]] retired in `declarationBody`, audited
/// across `CadenceSaveCommitRule`'s three parsing helpers.**
///
/// `declarationExtents(in:)` runs the `declarationHead` regex straight over whatever string it is
/// handed, `typeExtents(in:)` does the same with `typeDeclaration`, and `declarations(in:)` is
/// `declarationExtents` with the offsets dropped. None of the three blanks comments first. Today
/// every real-tree caller happens to pass `CadenceSourceScan.codeOnly(…)` or
/// `CadenceCommitSurfaceScan.scanned(…)`, so the convention holds by discipline — but it is written
/// down in exactly one place (`StoredLaunchReportSuiteRule.writerReach`'s doc comment) and nothing
/// enforces it. A sweep added tomorrow that reads a file plainly re-opens [[T-3371]]'s failure in a
/// new suite.
///
/// What these tests assert is the helper's own robustness, as a RELATION between two readings of
/// the same source. That is caller-independent: it stays true however the ~100 call sites evolve,
/// and it cannot be satisfied by a parser that still reads prose.
struct CadenceSaveCommitScanCommentBlindnessTests {

    // MARK: - The shape

    /// A doc comment that *writes about* a declaration, above a different one. This is the ordinary
    /// register of this repository's comments, which is what makes the class dangerous here.
    private static let trapFixture = """
    struct Example {
        /// Mirrors `func commitThing(` so the reader knows where the save lives.
        var marker: Int { 0 }

        func commitThing(context: ModelContext) {
            context.insert(AppTask(title: "x"))
        }
    }
    """

    @Test func aDeclarationNamedOnlyInACommentIsNotParsedAsOne() throws {
        let fromRaw = CadenceSaveCommitRule.declarations(in: Self.trapFixture).map(\.name)
        let fromCode = CadenceSaveCommitRule.declarations(
            in: CadenceSourceScan.strippingComments(Self.trapFixture)
        ).map(\.name)
        #expect(
            fromRaw == fromCode,
            "the comment changed what parsed as a declaration: raw \(fromRaw) vs code \(fromCode)"
        )
    }

    /// The arming guard: the fixture only proves something while its comment really does spell a
    /// declaration head the regex would match.
    @Test func theFixtureStillCarriesADeclarationHeadInsideItsComment() throws {
        let fixture = Self.trapFixture
        let mention = try #require(fixture.range(of: "`func commitThing("), "the fixture lost its comment")
        let declaration = try #require(
            fixture.range(of: "\n    func commitThing("),
            "the fixture lost its real declaration"
        )
        #expect(
            mention.lowerBound < declaration.lowerBound,
            "the comment no longer precedes the declaration, so this fixture proves nothing"
        )
    }

    // MARK: - The relation, over the real tree

    /// Read as a relation, so nothing here pins a declaration list that ordinary edits would move.
    private static func disagreements(
        reading: (String) -> [String]
    ) throws -> [String] {
        var differing: [String] = []
        var filesRead = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let raw = try CadenceSourceScan.sourceFile(path)
            filesRead += 1
            if reading(raw) != reading(CadenceSourceScan.strippingComments(raw)) {
                differing.append(path)
            }
        }
        #expect(filesRead > 400, "the sweep read \(filesRead) files; that is not the app source tree")
        return differing
    }

    @Test func declarationsReadTheSameFromRawSourceAndFromCommentStrippedSource() throws {
        let differing = try Self.disagreements {
            CadenceSaveCommitRule.declarations(in: $0).map(\.name)
        }
        #expect(
            differing.isEmpty,
            "\(differing.count) file(s) parse different declarations with comments in: \(differing.prefix(8))"
        )
    }

    @Test func declarationTypesReadTheSameFromRawSourceAndFromCommentStrippedSource() throws {
        let differing = try Self.disagreements {
            CadenceSaveCommitRule.declarationTypes(in: $0).map { "\($0.type).\($0.name)" }
        }
        #expect(
            differing.isEmpty,
            "\(differing.count) file(s) attribute declarations differently with comments in: \(differing.prefix(8))"
        )
    }
}
