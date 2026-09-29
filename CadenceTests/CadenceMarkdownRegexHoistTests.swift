import Foundation
import Testing
@testable import Cadence

/// **[[T-1484]]: ten constant regex literals the markdown services rebuilt on every call, two of
/// them once per line of every rendered note — and what that was actually worth.**
///
/// The same defect [[T-1366]] and [[T-1444]] closed in `MarkdownMetadataSupport.swift`, spread
/// across five more files: `try? NSRegularExpression(pattern:)` expressions built from string
/// literals that never vary, sitting inside the functions that use them.
///
/// **Measured before anything was changed, because nobody had ever timed a preview render.**
/// `MarkdownPreviewParser.blocks` reaches two of these per line — `MarkdownBlockSupport`'s heading
/// pattern and `MarkdownTaskEmbedParser`'s standalone-embed pattern. Apple M3 Pro / Mac15,6, 11
/// cores, 18 GB, macOS 27.0; the shipping preview path compiled standalone with `swiftc -O`
/// against a synthetic note whose twelve-line cycle is a heading, prose, a bullet, a checklist, a
/// quote, an ordered item, a fenced code block, a table, a task embed and a rule, so the loop
/// reaches every branch; medians of 101 `blocks(in:)` calls per point after 5 discarded warm-ups,
/// before and after built from the same driver and run interleaved:
///
/// ```
///   lines      before (median)     after (median)     per line before/after
///     200         1,363.9µs           567.0µs            6.82 / 2.84µs
///     400         2,750.2µs         1,142.7µs            6.88 / 2.86µs
///     800         5,487.4µs         2,271.5µs            6.86 / 2.84µs
/// ```
///
/// Flat per line across that range in both, which is what makes a per-line figure mean anything;
/// p10/p90 at 400 lines are 2,709/2,882µs before and 1,128/1,177µs after. Block counts are
/// identical either side (122 / 245 / 490).
///
/// **So the saving is ~4µs a line, and that is the whole of it.** It is two sites at ~2µs each,
/// which is [[T-1444]]'s ~2.5µs and **not** the ~100µs a cold `NSRegularExpression` construction
/// costs, because `NSRegularExpression` caches compiled patterns internally. A 400-line note's
/// preview parse goes 2.75ms -> 1.14ms. `blocks(in:)` is not on a keystroke path: its callers are
/// `iOSMarkdownPreview` and `CadenceMarkdownPresentationSupport.plainPreviewText`, which draws the
/// excerpt under each iOS search result and note row, so it is paid per row per list build.
///
/// **The honest justification for this change is therefore the duplication, not the speed.** Ten
/// copies of a pattern are ten places heading syntax can be edited apart — and one of them,
/// `MarkdownFormatCommandSupport`'s `#"^#{1,6}\s+"#`, was byte-for-byte a literal
/// `MarkdownMetadataParser` already held as a stored property four files away. That copy is gone
/// rather than stored twice.
///
/// **What is asserted here is a count, a literal and an output — never a duration**
/// ([[T-1279]]/[[T-1296]]). The table above is prose; 6.86µs is this machine's number and some
/// other number on CI's.
@Suite
struct CadenceMarkdownRegexHoistTests {
    // MARK: - The bound: counts of construction sites

    /// **Zero constant patterns compiled inside a function body, across the five declarations.**
    ///
    /// Structural for [[T-1366]]'s reason: `Foundation` exposes no compile counter and nothing on
    /// these paths can observe an `NSRegularExpression` being built, so what is counted is the
    /// construction sites in the declarations the calls run through.
    ///
    /// `MarkdownTaskEmbedParser` is the one entry whose expected in-body count is **1** and not 0,
    /// and that is deliberate: `referenceTitleRanges(of:in:)` interpolates an escaped UUID into its
    /// pattern, so it varies per call and cannot be hoisted to a stored `let` without a cache.
    /// [[T-1484]] put that shape out of scope by name; asserting 1 rather than 0 records it instead
    /// of letting a future hoist of it go unnoticed.
    @Test func theMarkdownServicesCompileNoConstantPatternPerCall() throws {
        for expectation in Self.constructionCounts {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(expectation.path)
            )
            let body = try #require(
                CadenceSourceScan.declarationBody(expectation.declaration, in: source),
                "\(expectation.declaration) is gone or its braces do not balance, so this reads nothing"
            )
            #expect(body.count > 400, "the stripped body of \(expectation.declaration) is too small to be the real one")

            let (stored, inBody) = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: body)
            #expect(
                inBody == expectation.inBody,
                "\(expectation.declaration) compiles \(inBody) pattern(s) inside a function body, expected \(expectation.inBody)"
            )
            // Non-vacuity: `inBody == 0` must be a declaration that holds its patterns once, not
            // one that lost them.
            #expect(
                stored == expectation.stored,
                "\(expectation.declaration) holds \(stored) stored patterns, not the expected \(expectation.stored)"
            )

            // And the named bodies read the stored property rather than building their own, so a
            // half-hoist that left one copy behind still fails and says which function it was.
            for function in expectation.functions {
                let functionBody = try #require(
                    CadenceSourceScan.functionBody(named: function.name, in: body),
                    "\(expectation.declaration).\(function.name) is gone"
                )
                #expect(
                    !functionBody.contains("NSRegularExpression("),
                    "\(function.name) compiles its pattern per call again"
                )
                #expect(
                    functionBody.contains(function.reads),
                    "\(function.name) no longer reads \(function.reads)"
                )
            }
        }

        // The counter can see an in-body construction at all — over a snippet, so this leg cannot
        // be turned vacuous by somebody fixing a neighbouring type.
        let regressed = """
            nonisolated enum Sample {
                nonisolated private static let kept = try? NSRegularExpression(pattern: #"a"#)
                nonisolated static func scan(_ line: String) -> Bool {
                    guard let regex = try? NSRegularExpression(pattern: #"b"#) else { return false }
                    return regex.firstMatch(in: line, range: NSRange(location: 0, length: 1)) != nil
                }
            }
            """
        let control = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: regressed)
        #expect(control.stored == 1)
        #expect(control.inBody == 1, "the counter cannot see an in-body compile, so the zeroes above mean nothing")
    }

    struct HoistedFunction {
        let name: String
        let reads: String
    }

    struct ConstructionCount {
        let path: String
        let declaration: String
        let stored: Int
        let inBody: Int
        let functions: [HoistedFunction]
    }

    nonisolated static let constructionCounts: [ConstructionCount] = [
        ConstructionCount(
            path: "Cadence/Services/MarkdownBlockSupport.swift",
            declaration: "nonisolated enum MarkdownBlockSupport",
            stored: 1,
            inBody: 0,
            functions: [HoistedFunction(name: "headingLineInfo", reads: "headingLineRegex")]
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownTaskEmbedSupport.swift",
            declaration: "nonisolated enum MarkdownTaskEmbedParser",
            stored: 4,
            inBody: 1,
            functions: [
                HoistedFunction(name: "draftTitle", reads: "draftTitleRegex"),
                HoistedFunction(name: "isUntitledDraftLine", reads: "untitledDraftRegex"),
                HoistedFunction(name: "standaloneTaskReference", reads: "standaloneTaskReferenceRegex"),
                HoistedFunction(name: "referenceTitleRange", reads: "referenceTitleRangeRegex"),
            ]
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownReferenceDisplaySupport.swift",
            declaration: "nonisolated enum MarkdownReferenceDisplaySupport",
            stored: 2,
            inBody: 0,
            functions: [
                HoistedFunction(name: "referenceRanges", reads: "wikiReferenceRegex"),
                HoistedFunction(name: "inlineSegments", reads: "wikiReferenceRegex"),
                HoistedFunction(name: "referencePrefixLength", reads: "referencePrefixRegex"),
            ]
        ),
        ConstructionCount(
            path: "Cadence/Services/NoteReferenceSupport.swift",
            declaration: "nonisolated enum NoteReferenceParser",
            stored: 2,
            inBody: 0,
            functions: [
                HoistedFunction(name: "noteReferences", reads: "wikiReferenceRegex"),
                HoistedFunction(name: "taskReferences", reads: "taskReferenceRegex"),
            ]
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownFormatCommandSupport.swift",
            declaration: "nonisolated enum MarkdownFormatCommandSupport",
            stored: 0,
            inBody: 0,
            functions: [
                HoistedFunction(name: "headingPrefix", reads: "MarkdownMetadataParser.headingPrefixRegex"),
            ]
        ),
    ]

    // MARK: - The literals, byte for byte

    /// **Each hoisted pattern is the string that stood inside the function, character for
    /// character.**
    ///
    /// The oracle below covers what the patterns *do*; this covers what they *are*, so a hoist
    /// that normalised a `\s` to a space or dropped a `?` fails on the character rather than on
    /// whichever corpus row happened to notice. Every expectation is the literal as `git show
    /// HEAD:` printed it before the change, with its byte length beside it.
    ///
    /// The counts matter as much as the bytes. `\[\[([^\[\]]+?)\]\]` must appear **once** in
    /// `MarkdownReferenceDisplaySupport.swift`, where it was written twice, and **once** in
    /// `NoteReferenceSupport.swift`, where the second copy has to stay: `CadenceMCPServer`
    /// compiles `NoteReferenceSupport.swift` and not the other, so the two files cannot share a
    /// constant without moving a file between targets. And `#"^#{1,6}\s+"#` must now appear
    /// **zero** times in `MarkdownFormatCommandSupport.swift` and once in
    /// `MarkdownMetadataSupport.swift` — the dedup this ticket was really about.
    @Test func theHoistedPatternLiteralsAreTheOnesTheyReplaced() throws {
        for expectation in Self.literalExpectations {
            // `literal` carries the `#"` / `"#` delimiters, four bytes the pattern itself does
            // not have; `bytes` is the pattern's own length, as `git show HEAD:` measured it.
            #expect(
                expectation.literal.utf8.count == expectation.bytes + 4,
                "the expectation \(expectation.literal) was retyped wrong: \(expectation.literal.utf8.count - 4) pattern bytes, not \(expectation.bytes)"
            )
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(expectation.path)
            )
            let occurrences = source.components(separatedBy: expectation.literal).count - 1
            #expect(
                occurrences == expectation.occurrences,
                "\(expectation.path) spells \(expectation.literal) \(occurrences) time(s), expected \(expectation.occurrences)"
            )
        }
        // Non-vacuity: the table asserts presences as well as absences, so a scan that silently
        // read nothing cannot pass it.
        #expect(Self.literalExpectations.contains { $0.occurrences == 0 })
        #expect(Self.literalExpectations.filter { $0.occurrences > 0 }.count >= 8)
    }

    struct LiteralExpectation {
        let path: String
        /// The pattern literal exactly as it is written in Swift source, delimiters included.
        let literal: String
        /// The UTF-8 length of the pattern itself, without the `#"` / `"#` delimiters.
        let bytes: Int
        let occurrences: Int
    }

    nonisolated static let literalExpectations: [LiteralExpectation] = [
        LiteralExpectation(
            path: "Cadence/Services/MarkdownBlockSupport.swift",
            literal: ##"#"^(#{1,6})\s+(.+)$"#"##, bytes: 17, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownTaskEmbedSupport.swift",
            literal: ##"#"^\s*\(\s*\)\s+(.+)$"#"##, bytes: 19, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownTaskEmbedSupport.swift",
            literal: ##"#"^\s*\(\s*\)\s*$"#"##, bytes: 15, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownTaskEmbedSupport.swift",
            literal: ##"#"^\s*\[\[task:([0-9A-Fa-f-]{36})\|([^\]\n]+)\]\]\s*$"#"##, bytes: 51, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownTaskEmbedSupport.swift",
            literal: ##"#"^\s*\[\[task:[0-9A-Fa-f-]{36}\|([^\]\n]+)\]\]\s*$"#"##, bytes: 49, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownReferenceDisplaySupport.swift",
            literal: ##"#"\[\[([^\[\]]+?)\]\]"#"##, bytes: 19, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownReferenceDisplaySupport.swift",
            literal: ##"#"^\s*(?:task|note):(?:[^\|\]]*\|)?"#"##, bytes: 33, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/NoteReferenceSupport.swift",
            literal: ##"#"\[\[([^\[\]]+?)\]\]"#"##, bytes: 19, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/NoteReferenceSupport.swift",
            literal: ##"#"(?i)\[\[task:(.+?)\]\]"#"##, bytes: 22, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownMetadataSupport.swift",
            literal: ##"#"^#{1,6}\s+"#"##, bytes: 10, occurrences: 1
        ),
        // The dedup, as an absence.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownFormatCommandSupport.swift",
            literal: ##"#"^#{1,6}\s+"#"##, bytes: 10, occurrences: 0
        ),
    ]

    // MARK: - The oracle: recorded from the pre-change implementation

    /// **The stored patterns answer exactly what the per-call ones answered.**
    ///
    /// `recordedAnswers` below is not a guess about what these patterns *should* match. It is the
    /// output of the pre-change implementations, captured by compiling the unmodified shipping
    /// files standalone with `swiftc -O` and dumping this corpus through them before a single
    /// literal moved. Rows that look surprising are therefore *recorded* behaviour and not this
    /// ticket's to change:
    ///
    /// - `#\tTab heading` is a heading, because the pattern says `\s+` and a tab is whitespace;
    /// - a keycap `#` (`#` + U+FE0F + U+20E3) is not a heading, and neither is `  ## Indented`,
///   because no leading whitespace is allowed;
    /// - `### CRLF\r` yields the content `CRLF`, because `$` matches before the trailing `\r`;
    /// - `[[nested [[inner]] ]]` produces one reference, `inner`, because the label class excludes
    ///   brackets and the quantifier is lazy;
    /// - `[[]]` produces none but `[[ ]]` produces one whose label is a single space;
    /// - `[[multi\nline]]` *does* match, because nothing in the `[[…]]` pattern excludes newlines;
    /// - toggling a heading onto `   ## Indented` produces `## ## Indented`, because
    ///   `headingPrefix` does not see through the leading spaces either.
    ///
    /// A character lost while moving one of these literals is a rendering change — which line of a
    /// note becomes a heading, which run becomes a link — so it fails here on the recorded answer
    /// rather than silently on screen.
    @Test func theSharedPatternsAnswerWhatThePerCallOnesAnswered() {
        let produced = Self.producedAnswers().components(separatedBy: "\n")
        let recorded = Self.recordedAnswers.components(separatedBy: "\n")
        #expect(produced.count == recorded.count, "the dump is \(produced.count) lines, recorded is \(recorded.count)")
        for (index, expected) in recorded.enumerated() where index < produced.count {
            #expect(
                produced[index] == expected,
                "line \(index + 1) of the dump changed:\n  recorded: \(expected)\n  produced: \(produced[index])"
            )
        }

        // Non-vacuity: the dump is the real recording, not an empty string or a wall of nils, and
        // it is the length it was when it was captured.
        #expect(recorded.count == 112, "the recorded dump was shortened")
        #expect(produced.contains("\"# Title\"\t1\t0,2\t2,5\t\"Title\""))
        #expect(Self.producedAnswers().components(separatedBy: "\tnil").count - 1 > 10)
        #expect(!recorded.contains { $0.isEmpty })
    }

    // MARK: - The dump

    nonisolated static func quoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                // Everything outside printable ASCII is escaped rather than drawn. T-1338: a
                // joining scalar written straight onto a syntactic character — `#` + U+FE0F +
                // U+20E3 is the keycap this corpus deliberately tests — indexes as one grapheme
                // to `CadenceSourceScan.codeOnly` and as three code points to the Python `blank()`
                // in `scripts/test-suite-index.sh`, and the two readers' columns then disagree.
                // `CadenceGuardScriptSelftestTests.noSourceFileWritesAJoiningScalarOntoASyntacticCharacter`
                // keeps that shape out of the tree, so the recording below is escaped too.
                if scalar.value < 0x20 || scalar.value > 0x7e {
                    out += String(format: "\\u{%04x}", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    nonisolated static func ranged(_ range: NSRange) -> String { "\(range.location),\(range.length)" }

    nonisolated static let headingCorpus = [
        "# Title", "## Section", "###### Deep", "####### Too deep", "#NoSpace", "#  double space",
        "#\tTab heading", "## ", "##", "  ## Indented", "### Trailing spaces   ", "### CRLF\r",
        "---", "Plain prose", "## Heading with # inside", "#\u{fe0f}\u{20e3} emoji", "## caf\u{e9} \u{2014} em dash",
    ]

    nonisolated static let embedCorpus = [
        "( ) Buy milk", "()Buy milk", "() Buy milk", "   ( )   Buy milk  ", "( )", "()", "(  )", "( ) ",
        "( x ) Buy milk", "[[task:11111111-2222-3333-4444-555555555555|A title]]",
        "  [[task:11111111-2222-3333-4444-555555555555|A title]]  ",
        "[[task:11111111-2222-3333-4444-555555555555|A title]] trailing",
        "[[task:not-a-uuid|A title]]", "[[task:11111111-2222-3333-4444-555555555555|]]",
        "[[note:11111111-2222-3333-4444-555555555555|A title]]",
        "[[TASK:11111111-2222-3333-4444-555555555555|A title]]",
    ]

    nonisolated static let wikiCorpus = [
        "See [[Other Note]] here", "[[task:11111111-2222-3333-4444-555555555555|A title]]",
        "[[note:Alpha]] and [[Beta]]", "[[]]", "[[ ]]", "[[a]][[b]]", "no references at all",
        "[[nested [[inner]] ]]", "[[Task:Upper]]", "[[note:11111111-2222-3333-4444-555555555555|Deep]]",
        "trailing [[unclosed", "[[multi\nline]]",
    ]

    nonisolated static let labelCorpus = [
        "Other Note", "task:1111|A", "note:Alpha", " TASK: 1111 | A ", "note:", "task:", "plain", "NOTE:x|y",
    ]

    nonisolated static let formatCorpus = [
        "# Title", "## Section", "plain line", "#NoSpace", "   ## Indented", "###### Deep",
        "####### Seven", "- bullet", "> quote",
    ]

    /// Runs the corpora through the shipping types in exactly the order and format the pre-change
    /// dump used. Kept as one string rather than as per-row expectations so the comparison is the
    /// whole recorded output, not a subset somebody can shorten without noticing.
    nonisolated static func producedAnswers() -> String {
        var lines: [String] = []

        lines.append("--- headingLineInfo")
        for line in headingCorpus {
            if let heading = MarkdownBlockSupport.headingLineInfo(in: line) {
                lines.append("\(quoted(line))\t\(heading.level)\t\(ranged(heading.markerRange))\t\(ranged(heading.contentRange))\t\(quoted(heading.content))")
            } else {
                lines.append("\(quoted(line))\tnil")
            }
        }

        lines.append("--- draftTitle / isUntitledDraftLine / standaloneTaskReference / referenceTitleRange")
        for line in embedCorpus {
            let draft = MarkdownTaskEmbedParser.draftTitle(in: line).map(quoted) ?? "nil"
            let untitled = MarkdownTaskEmbedParser.isUntitledDraftLine(line)
            let standalone = MarkdownTaskEmbedParser.standaloneTaskReference(in: line)
                .map { "\($0.id.uuidString)|\(quoted($0.title))|\(ranged($0.range))" } ?? "nil"
            let titleRange = MarkdownTaskEmbedParser.referenceTitleRange(in: line).map(ranged) ?? "nil"
            lines.append("\(quoted(line))\t\(draft)\t\(untitled)\t\(standalone)\t\(titleRange)")
        }

        lines.append("--- referenceRanges")
        for text in wikiCorpus {
            let parts = MarkdownReferenceDisplaySupport.referenceRanges(in: text).map {
                "\(ranged($0.fullRange))/\(ranged($0.displayRange))/\($0.display.kind.rawValue)/\(quoted($0.display.displayText))"
            }
            lines.append("\(quoted(text))\t[\(parts.joined(separator: " "))]")
        }

        lines.append("--- inlineSegments")
        for text in wikiCorpus {
            let parts = MarkdownReferenceDisplaySupport.inlineSegments(in: text).map {
                "\(quoted($0.text))/\($0.target.map { "\($0.kind.rawValue):\($0.title)" } ?? "nil")"
            }
            lines.append("\(quoted(text))\t[\(parts.joined(separator: " "))]")
        }

        lines.append("--- display(forWikiLabel:)")
        for label in labelCorpus {
            let display = MarkdownReferenceDisplaySupport.display(forWikiLabel: label)
            lines.append("\(quoted(label))\t\(display.kind.rawValue)\t\(quoted(display.displayText))\t\(display.hiddenPrefixUTF16Length)")
        }

        lines.append("--- noteReferences / taskReferences")
        for text in wikiCorpus {
            let notes = NoteReferenceParser.noteReferences(in: text).map {
                "\(quoted($0.rawValue))/\($0.noteID?.uuidString ?? "nil")/\(quoted($0.fallbackTitle))"
            }
            let tasks = NoteReferenceParser.taskReferences(in: text).map {
                "\(quoted($0.rawValue))/\($0.taskID?.uuidString ?? "nil")/\(quoted($0.title))"
            }
            lines.append("\(quoted(text))\t[\(notes.joined(separator: " "))]\t[\(tasks.joined(separator: " "))]")
        }

        lines.append("--- formatCommand heading/paragraph")
        for line in formatCorpus {
            for command in [MarkdownFormatCommand.heading(2), .paragraph, .heading(1)] {
                let mutation = MarkdownFormatCommandSupport.apply(
                    command,
                    text: line,
                    selection: NSRange(location: 0, length: 0)
                )
                lines.append("\(quoted(line))\t\(command)\t\(quoted(mutation.text))\t\(ranged(mutation.selection))")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// The dump above, as the **pre-change** implementations printed it. See the test.
    nonisolated static let recordedAnswers = #"""
        --- headingLineInfo
        "# Title"	1	0,2	2,5	"Title"
        "## Section"	2	0,3	3,7	"Section"
        "###### Deep"	6	0,7	7,4	"Deep"
        "####### Too deep"	nil
        "#NoSpace"	nil
        "#  double space"	1	0,2	3,12	"double space"
        "#\tTab heading"	1	0,2	2,11	"Tab heading"
        "## "	nil
        "##"	nil
        "  ## Indented"	nil
        "### Trailing spaces   "	3	0,4	4,18	"Trailing spaces   "
        "### CRLF\r"	3	0,4	4,4	"CRLF"
        "---"	nil
        "Plain prose"	nil
        "## Heading with # inside"	2	0,3	3,21	"Heading with # inside"
        "#\u{fe0f}\u{20e3} emoji"	nil
        "## caf\u{00e9} \u{2014} em dash"	2	0,3	3,14	"caf\u{00e9} \u{2014} em dash"
        --- draftTitle / isUntitledDraftLine / standaloneTaskReference / referenceTitleRange
        "( ) Buy milk"	"Buy milk"	false	nil	nil
        "()Buy milk"	nil	false	nil	nil
        "() Buy milk"	"Buy milk"	false	nil	nil
        "   ( )   Buy milk  "	"Buy milk"	false	nil	nil
        "( )"	nil	true	nil	nil
        "()"	nil	true	nil	nil
        "(  )"	nil	true	nil	nil
        "( ) "	nil	true	nil	nil
        "( x ) Buy milk"	nil	false	nil	nil
        "[[task:11111111-2222-3333-4444-555555555555|A title]]"	nil	false	11111111-2222-3333-4444-555555555555|"A title"|0,53	44,7
        "  [[task:11111111-2222-3333-4444-555555555555|A title]]  "	nil	false	11111111-2222-3333-4444-555555555555|"A title"|0,57	46,7
        "[[task:11111111-2222-3333-4444-555555555555|A title]] trailing"	nil	false	nil	nil
        "[[task:not-a-uuid|A title]]"	nil	false	nil	nil
        "[[task:11111111-2222-3333-4444-555555555555|]]"	nil	false	nil	nil
        "[[note:11111111-2222-3333-4444-555555555555|A title]]"	nil	false	nil	nil
        "[[TASK:11111111-2222-3333-4444-555555555555|A title]]"	nil	false	nil	nil
        --- referenceRanges
        "See [[Other Note]] here"	[4,14/6,10/note/"Other Note"]
        "[[task:11111111-2222-3333-4444-555555555555|A title]]"	[0,53/44,7/task/"A title"]
        "[[note:Alpha]] and [[Beta]]"	[0,14/7,5/note/"Alpha" 19,8/21,4/note/"Beta"]
        "[[]]"	[]
        "[[ ]]"	[0,5/2,1/note/" "]
        "[[a]][[b]]"	[0,5/2,1/note/"a" 5,5/7,1/note/"b"]
        "no references at all"	[]
        "[[nested [[inner]] ]]"	[9,9/11,5/note/"inner"]
        "[[Task:Upper]]"	[0,14/7,5/task/"Upper"]
        "[[note:11111111-2222-3333-4444-555555555555|Deep]]"	[0,50/44,4/note/"Deep"]
        "trailing [[unclosed"	[]
        "[[multi\nline]]"	[0,14/2,10/note/"multi\nline"]
        --- inlineSegments
        "See [[Other Note]] here"	["See "/nil "Other Note"/note:Other Note " here"/nil]
        "[[task:11111111-2222-3333-4444-555555555555|A title]]"	["A title"/task:A title]
        "[[note:Alpha]] and [[Beta]]"	["Alpha"/note:Alpha " and "/nil "Beta"/note:Beta]
        "[[]]"	["[[]]"/nil]
        "[[ ]]"	[" "/note:]
        "[[a]][[b]]"	["a"/note:a "b"/note:b]
        "no references at all"	["no references at all"/nil]
        "[[nested [[inner]] ]]"	["[[nested "/nil "inner"/note:inner " ]]"/nil]
        "[[Task:Upper]]"	["Upper"/task:Upper]
        "[[note:11111111-2222-3333-4444-555555555555|Deep]]"	["Deep"/note:Deep]
        "trailing [[unclosed"	["trailing [[unclosed"/nil]
        "[[multi\nline]]"	["multi\nline"/note:multi
        line]
        --- display(forWikiLabel:)
        "Other Note"	note	"Other Note"	0
        "task:1111|A"	task	"A"	10
        "note:Alpha"	note	"Alpha"	5
        " TASK: 1111 | A "	task	" A "	13
        "note:"	note	"note:"	0
        "task:"	task	"task:"	0
        "plain"	note	"plain"	0
        "NOTE:x|y"	note	"y"	7
        --- noteReferences / taskReferences
        "See [[Other Note]] here"	["Other Note"/nil/"Other Note"]	[]
        "[[task:11111111-2222-3333-4444-555555555555|A title]]"	[]	["11111111-2222-3333-4444-555555555555|A title"/11111111-2222-3333-4444-555555555555/"A title"]
        "[[note:Alpha]] and [[Beta]]"	["note:Alpha"/nil/"Alpha" "Beta"/nil/"Beta"]	[]
        "[[]]"	[]	[]
        "[[ ]]"	[]	[]
        "[[a]][[b]]"	["a"/nil/"a" "b"/nil/"b"]	[]
        "no references at all"	[]	[]
        "[[nested [[inner]] ]]"	["inner"/nil/"inner"]	[]
        "[[Task:Upper]]"	[]	["Upper"/nil/"Upper"]
        "[[note:11111111-2222-3333-4444-555555555555|Deep]]"	["note:11111111-2222-3333-4444-555555555555|Deep"/11111111-2222-3333-4444-555555555555/"Deep"]	[]
        "trailing [[unclosed"	[]	[]
        "[[multi\nline]]"	["multi\nline"/nil/"multi\nline"]	[]
        --- formatCommand heading/paragraph
        "# Title"	heading(2)	"## Title"	3,0
        "# Title"	paragraph	"Title"	0,0
        "# Title"	heading(1)	"Title"	0,0
        "## Section"	heading(2)	"Section"	0,0
        "## Section"	paragraph	"Section"	0,0
        "## Section"	heading(1)	"# Section"	2,0
        "plain line"	heading(2)	"## plain line"	3,0
        "plain line"	paragraph	"plain line"	0,0
        "plain line"	heading(1)	"# plain line"	2,0
        "#NoSpace"	heading(2)	"## #NoSpace"	3,0
        "#NoSpace"	paragraph	"#NoSpace"	0,0
        "#NoSpace"	heading(1)	"# #NoSpace"	2,0
        "   ## Indented"	heading(2)	"## ## Indented"	3,0
        "   ## Indented"	paragraph	"   ## Indented"	0,0
        "   ## Indented"	heading(1)	"# ## Indented"	2,0
        "###### Deep"	heading(2)	"## Deep"	3,0
        "###### Deep"	paragraph	"Deep"	0,0
        "###### Deep"	heading(1)	"# Deep"	2,0
        "####### Seven"	heading(2)	"## ####### Seven"	3,0
        "####### Seven"	paragraph	"####### Seven"	0,0
        "####### Seven"	heading(1)	"# ####### Seven"	2,0
        "- bullet"	heading(2)	"## - bullet"	3,0
        "- bullet"	paragraph	"bullet"	0,0
        "- bullet"	heading(1)	"# - bullet"	2,0
        "> quote"	heading(2)	"## > quote"	3,0
        "> quote"	paragraph	"quote"	0,0
        "> quote"	heading(1)	"# > quote"	2,0
        """#
}
