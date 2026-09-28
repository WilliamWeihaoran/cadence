import Foundation
import Testing
@testable import Cadence

/// **[[T-1444]]: `MarkdownOutlineParser.items` compiled its heading pattern once per line, and the
/// two things that had to be true for hoisting it to be safe.**
///
/// The defect was structural and the fix is the one [[T-1366]] proved four declarations away in the
/// same file: a `try? NSRegularExpression(pattern:)` expression sitting *inside* the `for line in`
/// loop, rebuilt from a string literal that never varies, now a stored `nonisolated private static
/// let` spelled the way `nonProseRegex`, `inlineTagRegex` and `headingPrefixRegex` are spelled.
///
/// **This one was measured before it was changed**, because [[T-1366]]'s sweep deliberately did not
/// cover it — the outline is not on the launch path. Apple M3 Pro / Mac15,6, 11 cores, 18 GB,
/// `swiftc -O`, medians of 101 calls per point, the shipping file compiled standalone against a
/// synthetic note that is one `## Section` heading every twelfth line:
///
/// ```
///   lines      before (median)     after (median)     per line before/after
///       3            10.2µs              2.5µs           3.39 / 0.83µs
///      50           157.4µs             33.5µs           3.15 / 0.67µs
///     100           312.7µs             66.2µs           3.13 / 0.66µs
///     400         1,275.9µs            263.8µs           3.19 / 0.66µs
///   1,000         3,175.1µs            665.5µs           3.18 / 0.67µs
/// ```
///
/// Tight spread: p10/p90 at 400 lines are 1,258/1,355µs before and 259/273µs after. The cost is
/// linear in lines in both, which is what makes the per-line figure meaningful, and the ~2.5µs a
/// line that goes away is **four-fifths of the pass**.
///
/// **Said honestly: that is not a compile.** [[T-1366]] measured ~100µs for one
/// `NSRegularExpression` construction; 2.5µs is nowhere near it, because `NSRegularExpression`
/// caches compiled patterns internally, so every line after the first was paying a cache lookup
/// rather than a parse. The duplication is the defect either way, and the saving is real — this
/// pass runs on the **main actor** 150ms after the user stops typing
/// (`MarkdownEditorSyncTiming.derivedStateRefreshDelay`), once per keystroke burst, from both
/// `NoteEditorPane.refreshDerivedState` and `ListNotesSupportViews.refreshDerivedState`.
///
/// **What is asserted here is a count and an output, never a duration** ([[T-1279]]/[[T-1296]]):
/// the table above is prose, and 3.15µs is this machine's number and some other number on CI's.
/// `theOutlineParserCompilesNoRegularExpressionPerLine` counts the construction sites the parse
/// reaches — **1 before, 0 after** — and
/// `theSharedOutlinePatternOutlinesWhatThePerLineOneOutlined` is the equivalence oracle whose
/// expectations were *recorded by running the corpus against the pre-change parser*, not reasoned
/// about, because `level` is `marker.count` and `title` is capture 2: a character lost while moving
/// the literal changes which lines become rows and what those rows are called.
@Suite
struct CadenceOutlineParserRegexTests {
    // MARK: - The bound: a count of construction sites

    /// **Zero regular expressions compiled per line, where it was one.**
    ///
    /// Structural for the same reason [[T-1366]]'s twin is: `Foundation` exposes no compile counter
    /// and nothing on this path can observe an `NSRegularExpression` being built, so what is counted
    /// is the construction sites in the declaration the parse runs through.
    @Test func theOutlineParserCompilesNoRegularExpressionPerLine() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownMetadataSupport.swift")
        )
        let parser = try #require(
            CadenceSourceScan.declarationBody("nonisolated enum MarkdownOutlineParser", in: source),
            "MarkdownOutlineParser is gone or its braces do not balance, so this reads nothing"
        )
        #expect(parser.count > 500, "the stripped outline parser body is too small to be the real one")

        let (stored, inBody) = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: parser)
        #expect(
            inBody == 0,
            "the outline parser compiles \(inBody) pattern(s) inside a function body, so outlining an N-line note rebuilds them N times"
        )
        // Non-vacuity, and the count itself: `inBody == 0` is not an outline parser that lost its
        // pattern, it is one that holds it once.
        #expect(stored == 1, "the outline parser holds \(stored) stored patterns, not the expected 1")

        // The one body the measurement named, by name. `MarkdownOutlineParser` has exactly one
        // function today; naming it means a second one that reintroduces an in-body compile is
        // caught by the count above *and* says which function it was.
        let items = try #require(CadenceSourceScan.functionBody(named: "items", in: parser), "items(in:) is gone")
        #expect(!items.contains("NSRegularExpression("), "items(in:) compiles its pattern per line again")
        #expect(items.contains("outlineHeadingRegex"), "items(in:) no longer reads the stored pattern")

        // And the counter can see an in-body construction at all — over a snippet, so this leg
        // cannot be turned vacuous by somebody fixing a neighbouring type.
        let regressed = """
            nonisolated enum Sample {
                nonisolated private static let kept = try? NSRegularExpression(pattern: #"a"#)
                nonisolated static func items(_ line: String) -> Bool {
                    guard let regex = try? NSRegularExpression(pattern: #"b"#) else { return false }
                    return regex.firstMatch(in: line, range: NSRange(location: 0, length: 1)) != nil
                }
            }
            """
        let control = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: regressed)
        #expect(control.stored == 1)
        #expect(control.inBody == 1, "the counter cannot see an in-body compile, so the zero above means nothing")
    }

    /// **The literal itself, byte for byte.**
    ///
    /// The oracle below covers what the pattern *does*; this covers what it *is*, so a hoist that
    /// silently normalised `\s` to a space or dropped the `?` from `(.+?)` fails on the character
    /// rather than on whichever corpus row happened to notice. The expected string is the one that
    /// stood inside the loop at `8609aa30`: 25 bytes, sha256 `5824bcf2…`.
    @Test func theHoistedPatternLiteralIsTheOneThatStoodInsideTheLoop() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownMetadataSupport.swift")
        let expected = ##"#"^(#{1,6})\s+(.+?)\s*$"#"##
        #expect(expected.utf8.count == 25, "the expectation itself was retyped wrong")
        #expect(
            source.components(separatedBy: expected).count - 1 == 1,
            "the outline heading literal is not in the file exactly once, byte-identical to the pre-hoist one"
        )
    }

    // MARK: - The oracle: recorded from the pre-change implementation

    /// **The stored pattern outlines exactly what the per-line one outlined.**
    ///
    /// Every expectation in `outlineOracle` is output, not intent: the corpus was run against the
    /// unhoisted `items(in:)` and what it printed was pasted in. Rows that look wrong are therefore
    /// *recorded* behaviour and not this ticket's to change — the outline has no code-fence
    /// awareness, so `# heading` inside a fence is a row; a heading indented by two spaces is not;
    /// a CRLF file's titles come back with the `\r` trimmed by the `\s*$` tail.
    @Test func theSharedOutlinePatternOutlinesWhatThePerLineOneOutlined() {
        for (content, expected) in Self.outlineOracle {
            let produced = MarkdownOutlineParser.items(in: content).map {
                OutlineRow(id: $0.id, level: $0.level, title: $0.title, location: $0.location)
            }
            #expect(produced == expected, "the hoisted pattern changed the outline of \(content.debugDescription)")
        }
        // Non-vacuity: the corpus answers are neither all empty nor all non-empty, it exercises the
        // whole `#{1,6}` range, and the total row count is fixed so a silently shortened corpus
        // fails here rather than passing over four entries.
        #expect(Self.outlineOracle.contains { !$0.expected.isEmpty })
        #expect(Self.outlineOracle.contains { $0.expected.isEmpty })
        #expect(Self.outlineOracle.reduce(0) { $0 + $1.expected.count } == 23)
        let levels = Set(Self.outlineOracle.flatMap { $0.expected.map(\.level) })
        #expect(levels.min() == 1 && levels.max() == 6, "the corpus no longer spans the whole # ramp")
    }

    struct OutlineRow: Equatable {
        let id: Int
        let level: Int
        let title: String
        let location: Int
    }

    /// Corpus and the output the pre-[[T-1444]] parser produced for it. See the test above.
    nonisolated static let outlineOracle: [(content: String, expected: [OutlineRow])] = [
        ("# Alpha\n\nbody\n\n## Beta\n\nmore", [
            OutlineRow(id: 0, level: 1, title: "Alpha", location: 0),
            OutlineRow(id: 15, level: 2, title: "Beta", location: 15),
        ]),
        ("###### deep\n####### seven hashes\n#nospace\n#\n#   \n", [
            OutlineRow(id: 0, level: 6, title: "deep", location: 0),
        ]),
        ("#   Trailing spaces   \n## Tabs\tafter\n", [
            OutlineRow(id: 0, level: 1, title: "Trailing spaces", location: 0),
            OutlineRow(id: 23, level: 2, title: "Tabs\tafter", location: 23),
        ]),
        ("no headings here\njust prose\n", []),
        ("", []),
        ("# Only heading", [OutlineRow(id: 0, level: 1, title: "Only heading", location: 0)]),
        ("# A\r\n## B\r\n", [
            OutlineRow(id: 0, level: 1, title: "A", location: 0),
            OutlineRow(id: 5, level: 2, title: "B", location: 5),
        ]),
        ("```\n# fenced looks like a heading\n```\n# real", [
            OutlineRow(id: 4, level: 1, title: "fenced looks like a heading", location: 4),
            OutlineRow(id: 38, level: 1, title: "real", location: 38),
        ]),
        ("  # indented two spaces\n# flush", [OutlineRow(id: 24, level: 1, title: "flush", location: 24)]),
        ("# café — unicode ünïcode 日本語\n", [
            OutlineRow(id: 0, level: 1, title: "café — unicode ünïcode 日本語", location: 0),
        ]),
        ("#### four #### trailing hashes ####\n", [
            OutlineRow(id: 0, level: 4, title: "four #### trailing hashes ####", location: 0),
        ]),
        ("# one\n# one\n", [
            OutlineRow(id: 0, level: 1, title: "one", location: 0),
            OutlineRow(id: 6, level: 1, title: "one", location: 6),
        ]),
        ("---\ntitle: front\n---\n# after frontmatter\n", [
            OutlineRow(id: 21, level: 1, title: "after frontmatter", location: 21),
        ]),
        ("# a\n\n\n### c\n## b\n", [
            OutlineRow(id: 0, level: 1, title: "a", location: 0),
            OutlineRow(id: 6, level: 3, title: "c", location: 6),
            OutlineRow(id: 12, level: 2, title: "b", location: 12),
        ]),
        ("#\tTabAfterHash\n", [OutlineRow(id: 0, level: 1, title: "TabAfterHash", location: 0)]),
        ("# ends with hash #\n", [OutlineRow(id: 0, level: 1, title: "ends with hash #", location: 0)]),
        ("text\n# mid\ntext\n###### six\n", [
            OutlineRow(id: 5, level: 1, title: "mid", location: 5),
            OutlineRow(id: 16, level: 6, title: "six", location: 16),
        ]),
    ]
}
