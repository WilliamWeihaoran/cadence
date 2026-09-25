import Foundation
import Testing

/// **T-1338. One blanking rule, two implementations, and they used to index text differently.**
///
/// `CadenceSourceScan.codeOnly` walks `Array(source)` — Swift `Character` grapheme clusters — and
/// the `blank()` inside `scripts/test-suite-index.sh` walks code points. The script is what tells
/// an agent which suite to scope a run to, and the Swift pass is what every offset-carrying reader
/// in this target is built on (`declarationBody`, `declarationExtents`, `typeExtents`), so a
/// divergence between them is a trap rather than a cosmetic difference: the shell reports
/// `<file scope>` and `xcb.sh` refuses the suite as `UNKNOWN-SUITE` for a file the Swift guard
/// calls clean.
///
/// [[T-1328]] is the entry that establishes that. This suite is the fixture that ticket asked for
/// and the guard that keeps the repair in place. **Both divergences were real and both were
/// measured**, on 2026-09-25, by compiling each implementation out of this repository and running
/// them over one fixture:
///
/// - **Width.** A literal holding a combining acute, a ZWJ pair, an emoji with U+FE0F and a
///   regional-indicator flag blanked to **26** characters on the Swift side and **31** on the
///   Python one, so every column offset after it on that line differed by five.
/// - **Line terminators.** A lone `\r` ends a `//` comment in Swift's grammar. The Swift pass
///   stopped there; the Python pass ran to the next `\n`, so `let b = 2` after the CR read as
///   **comment** on one side and as **code** on the other — a worse shape than the ticket
///   predicted, which only expected a `\r` inside a literal to blank differently.
///
/// The repair is one change on each side: `CadenceSourceScan.blankedSpansAsSpaces` spells a
/// blanked cluster as one space *per unicode scalar*, and the script's `blank()` ends a line on
/// any of Swift's seven line terminators rather than on `\n` alone. Re-measured after it, over all
/// 938 `.swift` files in `Cadence/`, `CadenceTests/`, `CadenceWidgets/` and `CadenceMCPServer/`:
/// the two passes agree on every one, and the Swift pass's output is byte-identical to what it
/// produced before the change, because the exposure was zero.
///
/// **Behavioural on the Swift side, source-level on the shell side**, for the reason
/// `CadenceGuardScriptSelftestTests` gives: this test host cannot run the `/usr/bin/python3` shim
/// ([[T-719]]), so the alternative to reading the script's source is asserting nothing about it.
///
/// It lives in its own file rather than beside
/// `theTwoBlankingPassesOfOneRuleStillHandleInterpolatedCode` in `CadenceGuardScriptSelftestTests`
/// only because that file was owned by a concurrent agent when this landed; [[T-1353]] is the
/// note to fold it back in.
@MainActor
struct CadenceBlankingPassParityTests {

    /// Swift's own grammar — and `Character.isNewline` — ends a line on any of these. `\r\n` is one
    /// `Character` and two scalars; both of its scalars are here.
    private static let lineTerminators: Set<Unicode.Scalar> = [
        "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{85}", "\u{2028}", "\u{2029}",
    ]

    /// A scalar that attaches itself to whatever precedes it, which is the whole class the two
    /// passes count differently: combining marks and variation selectors (Grapheme_Extend), the
    /// zero-width joiner, and regional indicators.
    private static func joinsWhatPrecedesIt(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isGraphemeExtend
            || scalar == "\u{200D}"
            || (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    // MARK: - Width

    /// A combining acute, a ZWJ pair, an emoji with a variation selector and a flag — inside a
    /// literal and inside a comment, which are the two spans that get blanked.
    private static let multiScalarFixture = """
    struct Combining {
        func caption() -> String {
            "cafe\u{301} \u{1F469}\u{200D}\u{1F4BB} \u{2764}\u{FE0F} \u{1F1EF}\u{1F1F5}"
        }
        // a comment holding cafe\u{301} and \u{1F469}\u{200D}\u{1F4BB} too
        func brace() -> Int { 1 }
    }
    """

    /// **The fixture that made the two passes disagree, and the property that makes them agree.**
    ///
    /// A code-point walk and a grapheme-cluster walk can only produce the same text if a blanked
    /// span comes back the same number of *scalars* wide — one space per scalar, not one per
    /// cluster. Asserted as the scalar count rather than by re-running the Python pass, because
    /// this host cannot run it; the equality over all 938 real files was measured out of band and
    /// is recorded in the suite comment above.
    @Test func blankingAMultiScalarClusterKeepsTheScalarWidthTheShellPassCounts() {
        let fixture = Self.multiScalarFixture
        // Non-vacuity: this really is a fixture the two walks index differently. A pure-ASCII one
        // would satisfy everything below while proving nothing.
        #expect(
            fixture.count != fixture.unicodeScalars.count,
            "the fixture holds no multi-scalar grapheme cluster, so it cannot separate the two walks"
        )

        let code = CadenceSourceScan.codeOnly(fixture)
        #expect(
            code.unicodeScalars.count == fixture.unicodeScalars.count,
            """
            codeOnly returned \(code.unicodeScalars.count) scalars for a \
            \(fixture.unicodeScalars.count)-scalar fixture, so every column offset after the \
            first multi-scalar cluster on that line disagrees with scripts/test-suite-index.sh
            """
        )

        // Non-vacuity for the blanking itself: the literal and the comment are gone, the code is not.
        #expect(!code.contains("cafe"), "the literal and the comment were not blanked")
        #expect(code.contains("struct Combining"))
        #expect(code.contains("func brace() -> Int { 1 }"))
        #expect(
            code.filter { $0 == "{" }.count == code.filter { $0 == "}" }.count,
            "brace depth desynchronised over a multi-scalar cluster"
        )
    }

    // MARK: - Line terminators

    /// A lone `\r` and a `\r\n` ending a `//` comment, and a line separator (U+2028) ending
    /// another. Swift's grammar ends a line on all three; the shell pass used to end one only on
    /// `\n`.
    private static let lineTerminatorFixture =
        "let a = 1 // alpha\rlet b = 2\r\nlet c = 3 // beta\u{2028}let d = 4\n"

    @Test func aCommentEndsOnEverySpellingOfALineSwiftEndsOneOn() {
        let fixture = Self.lineTerminatorFixture
        let code = CadenceSourceScan.codeOnly(fixture)

        #expect(code.unicodeScalars.count == fixture.unicodeScalars.count)

        // The terminators are in the same places, and no blanking invented or removed one. This is
        // what keeps line indices aligned between the two passes.
        let before = Array(fixture.unicodeScalars)
        let after = Array(code.unicodeScalars)
        #expect(before.count == after.count)
        for position in before.indices where position < after.count {
            #expect(
                Self.lineTerminators.contains(before[position])
                    == Self.lineTerminators.contains(after[position]),
                "scalar \(position) changed its line-terminator status"
            )
        }

        // The claim the shell pass used to get wrong: the comment stops at the terminator, so the
        // code after it on the next line is code.
        #expect(!code.contains("alpha"), "the CR-terminated comment survived")
        #expect(!code.contains("beta"), "the U+2028-terminated comment survived")
        #expect(code.contains("let b = 2"), "code after a lone CR was blanked as comment")
        #expect(code.contains("let d = 4"), "code after a U+2028 was blanked as comment")
        #expect(code.contains("let a = 1"))
        #expect(code.contains("let c = 3"))
    }

    // MARK: - The shell half

    /// The script cannot be executed from this host, so it is read. Each marker is a half of the
    /// T-1338 repair that would be silently lost by a rewrite of that `blank()`.
    @Test func theShellBlankingPassStillEndsALineTheWaySwiftDoes() throws {
        let script = try String(
            contentsOf: CadenceSourceScan.repositoryRoot()
                .appendingPathComponent("scripts/test-suite-index.sh"),
            encoding: .utf8
        )
        for marker in [
            "NEWLINES = ",
            "def line_end(",
            "if out[k] not in NEWLINES:",
            "if not multiline and src[pos] in NEWLINES:",
            "j = line_end(i)",
            "T-1338",
        ] {
            #expect(
                script.contains(marker),
                """
                scripts/test-suite-index.sh's blank() no longer carries \(marker), so it has \
                diverged from CadenceSourceScan.codeOnly again — see T-1338
                """
            )
        }
        // …and the spelling the repair replaced is gone, so a partial revert is visible too.
        #expect(
            !script.contains("j = src.find('\\n', i)"),
            "the shell pass ends a // comment on \\n again, so a lone CR reads as comment there and as code in Swift"
        )
    }

    // MARK: - The residual, pinned rather than fixed

    /// **What the repair does not close, held at zero so the next agent is told rather than
    /// surprised.**
    ///
    /// The two passes still *index* text differently — one cluster here is several code points
    /// there — so a joining scalar written **directly onto a syntactic character** (a quote, a
    /// `#`, a slash, a backslash, a parenthesis or a brace) would still be read as one unit by the
    /// Swift scanner and as two by the Python one, and the widths would come apart again. Nothing
    /// in this tree does that and nothing plausibly would; closing it properly means giving the
    /// shell pass a grapheme segmenter, which is not proportionate to a class with zero members.
    ///
    /// Measured 2026-09-25: zero offenders across all `.swift` files in the four source roots.
    /// This is a *pinned divergence*, in T-1338's own words: it fails the day such a file enters
    /// the tree.
    @Test func noSourceFileWritesAJoiningScalarOntoASyntacticCharacter() throws {
        let syntactic: Set<Unicode.Scalar> = ["\"", "#", "/", "\\", "(", ")", "{", "}", "*"]
        var scanned = 0
        var offenders: [String] = []

        for root in ["Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                scanned += 1
                let scalars = Array(try CadenceSourceScan.sourceFile(path).unicodeScalars)
                for index in scalars.indices.dropFirst()
                where Self.joinsWhatPrecedesIt(scalars[index]) && syntactic.contains(scalars[index - 1]) {
                    offenders.append("\(path): U+\(String(scalars[index].value, radix: 16, uppercase: true))")
                    break
                }
            }
        }

        #expect(scanned > 900, "the walk read \(scanned) files; an empty walk would pass vacuously")
        #expect(
            offenders == [],
            """
            a joining scalar sits on a syntactic character, which is the one text shape \
            CadenceSourceScan.codeOnly and the blank() in scripts/test-suite-index.sh still index \
            differently (T-1338): \(offenders)
            """
        )
    }

    /// Non-vacuity for the sweep above: the detector fires on the shape it is hunting and not on
    /// an ordinary multi-scalar cluster, which is now harmless.
    @Test func theJoiningScalarDetectorSeparatesTheHarmfulShapeFromTheHarmlessOne() {
        let harmful = Array("let s = \"\u{301}x\"".unicodeScalars)
        let harmless = Array("let s = \"cafe\u{301}\"".unicodeScalars)
        let syntactic: Set<Unicode.Scalar> = ["\""]

        #expect(
            harmful.indices.dropFirst().contains {
                Self.joinsWhatPrecedesIt(harmful[$0]) && syntactic.contains(harmful[$0 - 1])
            },
            "the detector cannot see a combining mark written onto a quote"
        )
        #expect(
            !harmless.indices.dropFirst().contains {
                Self.joinsWhatPrecedesIt(harmless[$0]) && syntactic.contains(harmless[$0 - 1])
            },
            "the detector fires on an ordinary accented letter, which the repair already handles"
        )
    }
}
