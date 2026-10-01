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
    /// **Three entries expect an in-body count of 1 rather than 0, and each one is a recorded
    /// exclusion rather than a miss.** `MarkdownTaskEmbedParser`'s `referenceTitleRanges(of:in:)`
    /// interpolates an escaped UUID, so its pattern varies per call and cannot become a stored
    /// `let` without a cache — [[T-1484]] put that shape out of scope by name.
    /// `MarkdownInlinePreviewSupport`'s `regexMatches(pattern:…)` and `MarkdownInlineMarkerRanges`'s
    /// `matchRanges(of pattern:in:)` are generic helpers their callers hand a literal to, so the
    /// construction is not *one* constant pattern and hoisting them is a table refactor rather than
    /// a `let`; [[T-1520]] scoped itself to the image reference and filed the rest as [[T-1660]].
    /// Asserting 1 rather than 0 records all three instead of letting a future hoist go unnoticed.
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

        // **A second control, and the reason for it ([[T-1660]]).** Two of the rows above now
        // read `stored: 0, inBody: 0`, and a pair of zeroes is a reading that cannot distinguish
        // "this file compiles nothing per call" from "this scan saw nothing at all". So the shape
        // that was actually removed is put through the same counter verbatim — the generic
        // `regexMatches(pattern:…)` helper and two of its ten literal call sites, copied from
        // `git show HEAD:Cadence/Services/MarkdownInlinePreviewSupport.swift` — and the two
        // readings are required to DIFFER. The zeroes mean something only because this is a 1.
        let perCallHelper = """
            nonisolated enum Sample {
                private static func inlineMatches(in markdown: String) -> [Int] {
                    var matches: [Int] = []
                    matches += regexMatches(pattern: #"~~(.+?)~~"#, priority: 8, in: markdown)
                    matches += regexMatches(pattern: #"==(.+?)=="#, priority: 8, in: markdown)
                    return matches
                }
                private static func regexMatches(pattern: String, priority: Int, in markdown: String) -> [Int] {
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
                    return [regex.numberOfCaptureGroups, priority]
                }
            }
            """
        let perCall = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: perCallHelper)
        #expect(perCall.inBody == 1, "the counter cannot see the generic-helper shape this ticket removed")
        #expect(perCall.stored == 0)
        let previewSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownInlinePreviewSupport.swift")
        )
        let previewBody = try #require(
            CadenceSourceScan.declarationBody("nonisolated enum MarkdownInlinePreviewSupport", in: previewSource)
        )
        let live = CadenceStartupPopulationSweepTests.regexConstructionCounts(in: previewBody)
        #expect(
            live.inBody != perCall.inBody,
            "the shipping file and the shape it replaced read the same, so this measurement is blind"
        )
        #expect(live.inBody == 0)
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
        // [[T-1520]] from here down, and [[T-1660]] from the two rows that used to say 1.
        //
        // Both of these expected an in-body count of **1** until [[T-1660]], and both of those
        // ones were the same shape: a generic helper (`regexMatches(pattern:…)` here,
        // `matchRanges(of pattern:in:)` in the styler) that callers handed constant literals to,
        // so the construction was not *one* constant pattern and hoisting it was a table refactor
        // rather than a `let`. Both are 0 now. Neither file compiles a pattern at all any more —
        // `stored` is 0 because the patterns themselves moved to the two files that own them, so
        // the non-vacuity for these two rows is the `functions` list below rather than `stored`,
        // and `MarkdownInlineEmphasisPatterns`' row carries the 9 that appeared.
        ConstructionCount(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            declaration: "nonisolated enum MarkdownInlinePreviewSupport",
            stored: 0,
            inBody: 0,
            functions: [
                HoistedFunction(name: "imageMatches", reads: "MarkdownInlineMarkerRanges.inlineImageReferenceRegex"),
                HoistedFunction(name: "inlineMatches", reads: "emphasisRules"),
                HoistedFunction(name: "inlineMatches", reads: "tagRule"),
            ]
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownStyleRangeSupport.swift",
            declaration: "nonisolated enum MarkdownInlineMarkerRanges",
            stored: 0,
            inBody: 0,
            functions: [
                HoistedFunction(name: "imageReferences", reads: "inlineImageReferenceRegex"),
                HoistedFunction(name: "hashtagRanges", reads: "hashtagRegex"),
            ]
        ),
        // [[T-1660]]: the nine emphasis patterns, and the one declaration that compiles them.
        // This row is the half of the count that is *not* a zero — nine stored constructions where
        // this file had none, against nine that left `MarkdownInlinePreviewSupport`'s body and nine
        // per-call ones that left `MarkdownInlineSpanSupport`'s.
        ConstructionCount(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            declaration: "nonisolated enum MarkdownInlineEmphasisPatterns",
            stored: 9,
            inBody: 0,
            functions: []
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            declaration: "nonisolated enum MarkdownInlineSpanSupport",
            stored: 0,
            inBody: 0,
            functions: [
                HoistedFunction(name: "codeRanges", reads: "Compiled.code"),
                HoistedFunction(name: "spans", reads: "Compiled.boldItalic"),
                HoistedFunction(name: "spans", reads: "Compiled.highlight"),
            ]
        ),
        ConstructionCount(
            path: "Cadence/Services/MarkdownImageAssetService.swift",
            declaration: "nonisolated enum MarkdownImageAssetService",
            stored: 2,
            inBody: 0,
            functions: []
        ),
        // The MCP target. `CadenceTests` cannot *execute* anything under `CadenceMCPServer/` —
        // none of those files is in the app target's Sources phase — so this scan and the literal
        // table below are the whole of the guard here, and they are the reason both exist.
        ConstructionCount(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            declaration: "private enum CadenceMCPArgumentPatterns",
            stored: 7,
            inBody: 0,
            functions: []
        ),
        ConstructionCount(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            declaration: "extension Dictionary where Key == String, Value == MCP.Value",
            stored: 0,
            inBody: 0,
            functions: [
                HoistedFunction(name: "parseRelativeDay", reads: "CadenceMCPArgumentPatterns.relativeDayAhead"),
                HoistedFunction(name: "parseRelativeDay", reads: "CadenceMCPArgumentPatterns.relativeDayAgo"),
                HoistedFunction(name: "parseDuration", reads: "CadenceMCPArgumentPatterns.compactMinutes"),
                HoistedFunction(name: "parseDuration", reads: "CadenceMCPArgumentPatterns.compactHours"),
                HoistedFunction(name: "parseWordDuration", reads: "CadenceMCPArgumentPatterns.wordDuration"),
                HoistedFunction(name: "parseMinuteOfDay", reads: "CadenceMCPArgumentPatterns.minuteOfDay"),
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
            let expectedLiteralBytes = (expectation.sourceBytes ?? expectation.bytes) + expectation.delimiters
            #expect(
                expectation.literal.utf8.count == expectedLiteralBytes,
                "the expectation \(expectation.literal) was retyped wrong: \(expectation.literal.utf8.count - expectation.delimiters) literal bytes, not \(expectation.sourceBytes ?? expectation.bytes)"
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
        /// The UTF-8 length of the pattern itself, without the delimiters.
        let bytes: Int
        let occurrences: Int
        /// How many of `literal`'s bytes are delimiter: 4 for a raw `#"…"#`, 2 for a plain
        /// `"…"`. [[T-1660]] needed the second: `MarkdownStylist` wrote five of these patterns
        /// as escaped Swift strings rather than raw ones, which is *why* a grep for the raw
        /// spelling never found them and the duplication survived [[T-1484]] and [[T-1520]].
        /// A row with `delimiters: 2` also measures `bytes` after the escapes are resolved,
        /// so `"\\*\\*\\*(.+?)\\*\\*\\*"` is the same 17 bytes as `#"\*\*\*(.+?)\*\*\*"#`.
        var delimiters: Int = 4
        /// The escaped literal's resolved byte count, when it differs from `literal` minus
        /// delimiters. `nil` means the two agree.
        var sourceBytes: Int?
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
        // [[T-1521]]'s dedup, as an absence. The 19 bytes left this file and the editor; the
        // identical hash stays in `NoteReferenceSupport.swift`, which both the app and
        // `CadenceMCPServer` compile, and both of the others now read it from there.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownReferenceDisplaySupport.swift",
            literal: ##"#"\[\[([^\[\]]+?)\]\]"#"##, bytes: 19, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##"#"\[\[([^\[\]]+?)\]\]"#"##, bytes: 19, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownReferenceDisplaySupport.swift",
            literal: ##"#"^\s*(?:task|note):(?:[^\|\]]*\|)?"#"##, bytes: 33, occurrences: 1
        ),
        // [[T-1661]]'s dedup, as an absence. The 33 bytes left the editor; the identical hash
        // stays in `MarkdownReferenceDisplaySupport.swift`, and the editor reads that file's
        // *compiled* object — so `.caseInsensitive` is written once too, which a shared pattern
        // string would not have achieved.
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##"#"^\s*(?:task|note):(?:[^\|\]]*\|)?"#"##, bytes: 33, occurrences: 0
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

        // MARK: [[T-1520]] — the image reference, and the MCP argument patterns

        // The three pieces `MarkdownImageAssetService.referencePattern` is concatenated from.
        // Nothing moved them; they are pinned because three readers now share the one compiled
        // regex built from them — the lifecycle sweep, the styler and the inline preview — so a
        // character lost here is lost in all three at once.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownImageAssetService.swift",
            literal: ##"#"(?:[^\]\n\\]|\\.)*\\?"#"##, bytes: 21, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownImageAssetService.swift",
            literal: ##"#"!\[("#"##, bytes: 4, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownImageAssetService.swift",
            literal: ##"#")\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#"##, bytes: 41, occurrences: 1
        ),

        // The seven MCP literals, each as `git show HEAD:` printed it before the hoist. The
        // interpolated one keeps the local name `units` precisely so this row can be an identity
        // rather than an equivalence: `\#(units)` is the same eight characters it was.
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^in\s+(\d+)\s+days?$"#"##, bytes: 20, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^\+(\d+)\s+days?$"#"##, bytes: 17, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^(\d+)\s+days?\s+ago$"#"##, bytes: 21, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^(\d+)(?:m|min|mins|minute|minutes)$"#"##, bytes: 36, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^(\d+(?:\.\d+)?)(?:h|hr|hrs|hour|hours)$"#"##, bytes: 40, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"hours?|hrs?|h|minutes?|mins?|m"#"##, bytes: 30, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?: and a half)?\s+(\#(units))$"#"##,
            bytes: 101, occurrences: 1
        ),
        LiteralExpectation(
            path: "CadenceMCPServer/CadenceMCPArgumentParsing.swift",
            literal: ##"#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#"##, bytes: 34, occurrences: 1
        ),

        // MARK: [[T-1660]] — the ten inline patterns, and the five escaped spellings
        //
        // Measured 2026-09-30 before the change: the ten patterns `inlineMatches` ran were
        // written **26** times across five files, not the one duplicate the ticket named.
        // Nine of the ten also stood in `MarkdownInlineSpanSupport`'s span table, five of
        // those nine a third time in `MarkdownStylist`, and the tag pattern a third time in
        // `MarkdownMetadataParser`. Every row below is the literal as `git show HEAD:`
        // printed it, with its byte length beside it; each pattern is now written once.

        // The nine that stay, in the file that owns them.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"\*\*\*(.+?)\*\*\*"#"##, bytes: 17, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"___(.+?)___"#"##, bytes: 11, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"\*\*(.+?)\*\*"#"##, bytes: 13, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#"##, bytes: 31, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#"##, bytes: 35, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#"##, bytes: 53, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"~~(.+?)~~"#"##, bytes: 9, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"`([^`\n]+?)`"#"##, bytes: 12, occurrences: 1
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlineSpanSupport.swift",
            literal: ##"#"==(.+?)=="#"##, bytes: 9, occurrences: 1
        ),

        // The ten that left `MarkdownInlinePreviewSupport`, as absences.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"\*\*\*(.+?)\*\*\*"#"##, bytes: 17, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"___(.+?)___"#"##, bytes: 11, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"\*\*(.+?)\*\*"#"##, bytes: 13, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#"##, bytes: 31, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#"##, bytes: 35, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#"##, bytes: 53, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"~~(.+?)~~"#"##, bytes: 9, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"`([^`\n]+?)`"#"##, bytes: 12, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"==(.+?)=="#"##, bytes: 9, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownInlinePreviewSupport.swift",
            literal: ##"#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#"##, bytes: 46, occurrences: 0
        ),

        // The tag pattern: gone from the styler, kept by the one file in all three targets.
        LiteralExpectation(
            path: "Cadence/Services/MarkdownStyleRangeSupport.swift",
            literal: ##"#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#"##, bytes: 46, occurrences: 0
        ),
        LiteralExpectation(
            path: "Cadence/Services/MarkdownMetadataSupport.swift",
            literal: ##"#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#"##, bytes: 46, occurrences: 1
        ),

        // The five `MarkdownStylist` wrote as escaped Swift strings rather than raw literals —
        // which is why a grep for `#"` never saw them and they outlived two dedup tickets. They
        // are rows with `delimiters: 2`, and `sourceBytes` is the escaped source length while
        // `bytes` stays the pattern's own, so each row says both numbers.
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##""\\*\\*\\*(.+?)\\*\\*\\*""##, bytes: 17, occurrences: 0,
            delimiters: 2, sourceBytes: 23
        ),
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##""\\*\\*(.+?)\\*\\*""##, bytes: 13, occurrences: 0,
            delimiters: 2, sourceBytes: 17
        ),
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##""(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)""##, bytes: 35, occurrences: 0,
            delimiters: 2, sourceBytes: 41
        ),
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##""~~(.+?)~~""##, bytes: 9, occurrences: 0,
            delimiters: 2, sourceBytes: 9
        ),
        LiteralExpectation(
            path: "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
            literal: ##""==(.+?)==""##, bytes: 9, occurrences: 0,
            delimiters: 2, sourceBytes: 9
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

    // MARK: - [[T-1520]]: the image reference is one compiled object

    /// **The inline preview, the styler and the image lifecycle read one `NSRegularExpression`.**
    ///
    /// `MarkdownInlinePreviewSupport.imageMatches` built its own from
    /// `MarkdownInlineMarkerRanges.inlineImageReferencePattern` on every call, although
    /// `MarkdownImageAssetService` had already compiled those same bytes into a stored property —
    /// and `MarkdownInlineMarkerRanges.imageReferences` built a third through
    /// `matchRanges(of:in:)`. [[T-1520]]'s reason for taking it is that duplication, not the time:
    /// [[T-1484]] measured a construction of this shape at ~2µs, because `NSRegularExpression`
    /// caches compiled patterns internally, and `imageMatches` runs once per inline string.
    ///
    /// **The first assertion is `===`, and it has to be.** A second object built from the same
    /// string passes every behavioural row below, and a second object is exactly what was removed.
    /// The rows then pin the property the sharing is *for*: the three readers disagree about what
    /// to do with a reference — draw it, hide its markers, or decide whether the asset is still
    /// alive and may be collected — and they may not disagree about what one **is**. Over-counting
    /// defers garbage; under-counting deletes a picture.
    @Test func theInlineImageReferenceRegexIsOneCompiledObjectThreeReadersShare() {
        #expect(
            MarkdownInlineMarkerRanges.inlineImageReferenceRegex === MarkdownImageAssetService.anyReferenceRegex,
            "the styler alias is a second compiled copy again, not the lifecycle sweep's object"
        )
        #expect(
            MarkdownInlineMarkerRanges.inlineImageReferencePattern == MarkdownImageAssetService.referencePattern
        )
        #expect(
            MarkdownImageAssetService.anyReferenceRegex.pattern == MarkdownImageAssetService.referencePattern,
            "the compiled object is no longer the pattern it is named for"
        )

        let first = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let second = "A1B2C3D4-E5F6-4A5B-8C7D-9E0F1A2B3C4D"
        let corpus: [(markdown: String, images: Int)] = [
            ("![photo](cadence-image://\(first))", 1),
            ("before ![a](cadence-image://\(first)) between ![b](cadence-image://\(second)) after", 2),
            ("![](cadence-image://\(first))", 1),
            // An escaped `]` inside the alt text: the widened label class is why this is one
            // reference and not none, and all three readers have to agree that it is.
            (#"![bracket\] label](cadence-image://\#(first))"#, 1),
            ("plain prose with no picture in it", 0),
            ("![alt](https://example.com/photo.png)", 0),
            ("![alt](cadence-image://not-a-uuid)", 0),
        ]

        for row in corpus {
            let styler = MarkdownInlineMarkerRanges.imageReferences(in: row.markdown)
            let lifecycle = MarkdownImageAssetService.referencedIDs(in: row.markdown)
            let preview = MarkdownInlinePreviewSupport.runs(in: row.markdown)
                .filter { $0.traits.contains(.image) }

            #expect(styler.count == row.images, "the styler saw \(styler.count) references in \(row.markdown.debugDescription)")
            #expect(lifecycle.count == row.images, "the lifecycle sweep saw \(lifecycle.count) in \(row.markdown.debugDescription)")
            #expect(preview.count == row.images, "the inline preview saw \(preview.count) in \(row.markdown.debugDescription)")
            // Not just the same count: the same ids, so two readers cannot agree by arithmetic
            // while pointing at different references.
            let ns = row.markdown as NSString
            let stylerIDs = Set(styler.compactMap { UUID(uuidString: ns.substring(with: $0.idRange)) })
            #expect(
                stylerIDs == lifecycle,
                "the styler and the lifecycle sweep name different references in \(row.markdown.debugDescription)"
            )
        }

        // One concrete answer, so the agreement above cannot be three readers agreeing on nothing.
        let labelled = MarkdownInlinePreviewSupport.runs(in: "see ![photo](cadence-image://\(first)) here")
        #expect(labelled.filter { $0.traits.contains(.image) }.map(\.text) == ["photo"])
        #expect(MarkdownImageAssetService.referencedIDs(in: "see ![photo](cadence-image://\(first)) here")
            == [UUID(uuidString: first)!])

        // Non-vacuity: the corpus both finds and rejects.
        #expect(corpus.contains { $0.images > 0 })
        #expect(corpus.contains { $0.images == 0 })
    }

    // MARK: - [[T-1521]]: three spellings of `[[…]]`, and the boundary that did not forbid one

    /// **`\[\[([^\[\]]+?)\]\]` is written once, in the file both targets compile.**
    ///
    /// [[T-1484]] left the 19 bytes in three files and [[T-1521]] recorded why: `CadenceMCPServer`
    /// compiles `NoteReferenceSupport.swift` and **not** `MarkdownReferenceDisplaySupport.swift`,
    /// so a constant declared in the display file would not link in that target. Both halves of
    /// that are true, and the conclusion drawn from them — that the three cannot share a constant
    /// without moving a file between targets — does not follow. It rules out one **owner**, not
    /// every owner. `NoteReferenceSupport.swift` is in the MCP target's Sources phase *and* in the
    /// app's synchronized folder; the other two are app-target files. So the constant lives there,
    /// the other two read it, and no `project.pbxproj` edit was needed.
    ///
    /// The membership is read out of `project.pbxproj` rather than remembered, because it is the
    /// whole of the argument. If the display file ever joins that target the arrangement could be
    /// simplified — this goes red saying so rather than leaving a comment that quietly stops being
    /// true.
    ///
    /// **What is shared is the pattern, not the compiled object**, and that is deliberate: the
    /// three sites disagree about what to do when a pattern will not compile (`try?` twice, `try!`
    /// in the editor, which enumerates it directly), which is each site's own question. What they
    /// may not disagree about is what `[[…]]` *is* — it decides what becomes a link in the
    /// renderer, in the MCP read service and in the live editor at once.
    @Test func theWikiReferencePatternIsOneConstantAndTheTargetBoundaryAllowedIt() throws {
        let mcp = try cadenceMCPServerMemberFiles()
        #expect(mcp.count >= 50, "the MCP source list parsed as \(mcp.count) files, so this scan read nothing")
        #expect(
            mcp.contains("Cadence/Services/NoteReferenceSupport.swift"),
            "the file that owns wikiReferencePattern is no longer in the MCP target"
        )
        #expect(
            !mcp.contains("Cadence/Services/MarkdownReferenceDisplaySupport.swift"),
            "the display file joined the MCP target, so T-1521's boundary is gone and the ownership could move"
        )
        #expect(!mcp.contains("Cadence/macOS/Editor/MarkdownEditorSupport.swift"))

        #expect(NoteReferenceParser.wikiReferencePattern == ##"\[\[([^\[\]]+?)\]\]"##)
        #expect(NoteReferenceParser.wikiReferencePattern.utf8.count == 19)

        let readers: [(path: String, property: String)] = [
            ("Cadence/Services/MarkdownReferenceDisplaySupport.swift", "wikiReferenceRegex"),
            ("Cadence/macOS/Editor/MarkdownEditorSupport.swift", "wikiLinkRegex"),
        ]
        for reader in readers {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(reader.path)
            )
            let declarations = source
                .components(separatedBy: "\n")
                .filter { $0.contains("static let \(reader.property)") }
            #expect(declarations.count == 1, "\(reader.path) declares \(reader.property) \(declarations.count) times")
            let declaration = try #require(declarations.first)
            #expect(
                declaration.contains("NoteReferenceParser.wikiReferencePattern"),
                "\(reader.property) spells the pattern out again instead of reading the shared constant"
            )
        }

        // And the editor's styling pass reads that property rather than a copy beside it. The two
        // display-side functions are covered by `constructionCounts` above; this is the third
        // reader, the one no test in this target can execute.
        let editor = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorSupport.swift")
        )
        let stylist = try #require(CadenceSourceScan.declarationBody("enum MarkdownStylist", in: editor))
        let applyWikiLinks = try #require(CadenceSourceScan.functionBody(named: "applyWikiLinks", in: stylist))
        #expect(!applyWikiLinks.contains("NSRegularExpression("))
        #expect(applyWikiLinks.contains("wikiLinkRegex"))

        // The behaviour the shared bytes decide, on the two readers this target can run. These
        // rows are [[T-1484]]'s recorded ones: a nested reference yields the inner label, and a
        // reference whose label is a single space is a reference.
        #expect(NoteReferenceParser.noteReferences(in: "[[Alpha]] and [[Beta]]").map(\.fallbackTitle) == ["Alpha", "Beta"])
        #expect(NoteReferenceParser.noteReferences(in: "[[nested [[inner]] ]]").map(\.fallbackTitle) == ["inner"])
        #expect(NoteReferenceParser.noteReferences(in: "[[]]").isEmpty)
        #expect(MarkdownReferenceDisplaySupport.referenceRanges(in: "[[Alpha]] and [[Beta]]").count == 2)
        #expect(MarkdownReferenceDisplaySupport.referenceRanges(in: "nothing here").isEmpty)
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

    // MARK: - [[T-1660]]: the nine emphasis patterns, written once

    /// **The ten patterns `MarkdownInlinePreviewSupport.inlineMatches` runs were written 26 times
    /// across five files, and the ticket said one.**
    ///
    /// [[T-1660]] was filed saying ten constant literals were compiled per inline string and that
    /// *one* of them — the 46-byte tag pattern — duplicated a constant two files away. The first
    /// half is right. The second understates it by an order of magnitude, measured 2026-09-30 over
    /// every Swift string literal in the tree, **raw and escaped**, compared by decoded value:
    ///
    /// ```
    ///   nine emphasis patterns   MarkdownInlinePreviewSupport + MarkdownInlineSpanSupport
    ///   five of those nine       ... + MarkdownStylist, spelled with backslash escapes
    ///   the tag pattern          MarkdownInlinePreviewSupport + MarkdownInlineMarkerRanges
    ///                            + MarkdownMetadataParser          (3 copies, not 2)
    ///   total                    26 occurrences of 10 patterns in 5 files
    /// ```
    ///
    /// **The escaped spellings are why this survived [[T-1484]] and [[T-1520]].** Both of those
    /// enumerated `#"…"#` literals, and `MarkdownStylist` writes `"\\*\\*\\*(.+?)\\*\\*\\*"`, which
    /// is the same 17 pattern bytes and a different 25-byte source literal. A grep for one
    /// spelling cannot see the other, which is exactly the drift a shared constant removes and a
    /// byte-identity test alone would not have found.
    ///
    /// What these decide is one question asked three times — which run of a note is bold, italic,
    /// struck, code or marked — by the renderer, by the iOS live styler and by the macOS live
    /// styler. The `options` assertion is the other half: these are built with **no** options at
    /// all, and a `.caseInsensitive` quietly added to a shared constant would change all three.
    @Test func theInlineEmphasisPatternsAreOneSpellingThreeStylersShare() throws {
        let patterns: [(name: String, value: String, bytes: Int, regex: NSRegularExpression?)] = [
            ("boldItalicAsterisk", MarkdownInlineEmphasisPatterns.boldItalicAsterisk, 17, MarkdownInlineEmphasisPatterns.boldItalicAsteriskRegex),
            ("boldItalicUnderscore", MarkdownInlineEmphasisPatterns.boldItalicUnderscore, 11, MarkdownInlineEmphasisPatterns.boldItalicUnderscoreRegex),
            ("boldAsterisk", MarkdownInlineEmphasisPatterns.boldAsterisk, 13, MarkdownInlineEmphasisPatterns.boldAsteriskRegex),
            ("boldUnderscore", MarkdownInlineEmphasisPatterns.boldUnderscore, 31, MarkdownInlineEmphasisPatterns.boldUnderscoreRegex),
            ("italicAsterisk", MarkdownInlineEmphasisPatterns.italicAsterisk, 35, MarkdownInlineEmphasisPatterns.italicAsteriskRegex),
            ("italicUnderscore", MarkdownInlineEmphasisPatterns.italicUnderscore, 53, MarkdownInlineEmphasisPatterns.italicUnderscoreRegex),
            ("strikethrough", MarkdownInlineEmphasisPatterns.strikethrough, 9, MarkdownInlineEmphasisPatterns.strikethroughRegex),
            ("code", MarkdownInlineEmphasisPatterns.code, 12, MarkdownInlineEmphasisPatterns.codeRegex),
            ("highlight", MarkdownInlineEmphasisPatterns.highlight, 9, MarkdownInlineEmphasisPatterns.highlightRegex),
        ]

        // The bytes, against the literals `git show HEAD:` printed before anything moved.
        #expect(MarkdownInlineEmphasisPatterns.boldItalicAsterisk == ##"\*\*\*(.+?)\*\*\*"##)
        #expect(MarkdownInlineEmphasisPatterns.boldItalicUnderscore == ##"___(.+?)___"##)
        #expect(MarkdownInlineEmphasisPatterns.boldAsterisk == ##"\*\*(.+?)\*\*"##)
        #expect(MarkdownInlineEmphasisPatterns.boldUnderscore == ##"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"##)
        #expect(MarkdownInlineEmphasisPatterns.italicAsterisk == ##"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"##)
        #expect(MarkdownInlineEmphasisPatterns.italicUnderscore == ##"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"##)
        #expect(MarkdownInlineEmphasisPatterns.strikethrough == ##"~~(.+?)~~"##)
        #expect(MarkdownInlineEmphasisPatterns.code == ##"`([^`\n]+?)`"##)
        #expect(MarkdownInlineEmphasisPatterns.highlight == ##"==(.+?)=="##)

        for pattern in patterns {
            #expect(pattern.value.utf8.count == pattern.bytes, "\(pattern.name) is \(pattern.value.utf8.count) bytes, not \(pattern.bytes)")
            let regex = try #require(pattern.regex, "\(pattern.name) no longer compiles")
            #expect(regex.pattern == pattern.value, "\(pattern.name)'s compiled object is not the pattern it is named for")
            #expect(
                regex.options == [],
                "\(pattern.name) gained a regex option; these nine are built with none and three stylers read them"
            )
        }
        // Non-vacuity: nine distinct patterns, not nine aliases of one.
        #expect(Set(patterns.map(\.value)).count == 9)

        // The macOS styler reads the five it shares, and spells none of them. Its inline-code
        // pattern is deliberately NOT one of them — `` `([^`\n]+)` `` is greedy where the shared
        // one is lazy — so it is checked as an exception rather than left ambiguous.
        let editor = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorSupport.swift")
        )
        let stylist = try #require(CadenceSourceScan.declarationBody("enum MarkdownStylist", in: editor))
        let editorReaders: [(property: String, constant: String)] = [
            ("boldItalicRegex", "MarkdownInlineEmphasisPatterns.boldItalicAsterisk"),
            ("boldRegex", "MarkdownInlineEmphasisPatterns.boldAsterisk"),
            ("italicRegex", "MarkdownInlineEmphasisPatterns.italicAsterisk"),
            ("strikethroughRegex", "MarkdownInlineEmphasisPatterns.strikethrough"),
            ("highlightRegex", "MarkdownInlineEmphasisPatterns.highlight"),
        ]
        for reader in editorReaders {
            let declarations = stylist
                .components(separatedBy: "\n")
                .filter { $0.contains("static let \(reader.property)") }
            #expect(declarations.count == 1, "MarkdownStylist declares \(reader.property) \(declarations.count) times")
            #expect(
                try #require(declarations.first).contains(reader.constant),
                "\(reader.property) spells its pattern out again instead of reading \(reader.constant)"
            )
        }
        let inlineCode = try #require(
            stylist.components(separatedBy: "\n").first { $0.contains("static let inlineCodeRegex") }
        )
        #expect(
            !inlineCode.contains("MarkdownInlineEmphasisPatterns"),
            "the greedy editor code pattern was silently unified with the lazy shared one"
        )

        // And the two Services readers hold no literal of their own: the preview's table names
        // each of the nine constants exactly once, which is the half a byte-identity scan on its
        // own cannot state (an absence says nothing about what replaced it).
        let preview = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownInlinePreviewSupport.swift")
        )
        let previewBody = try #require(
            CadenceSourceScan.declarationBody("nonisolated enum MarkdownInlinePreviewSupport", in: preview)
        )
        for pattern in patterns {
            let read = "MarkdownInlineEmphasisPatterns.\(pattern.name)Regex"
            #expect(
                previewBody.components(separatedBy: read).count - 1 == 1,
                "the inline rule table reads \(read) \(previewBody.components(separatedBy: read).count - 1) times, expected once"
            )
        }
    }

    // MARK: - [[T-1660]]: the tag pattern, one compiled object

    /// **`(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)` was written three times, and the owner
    /// is the file a target boundary forces it to be.**
    ///
    /// The ticket said two. Measured: three — `MarkdownInlineMarkerRanges.hashtagPattern`,
    /// `MarkdownInlinePreviewSupport.inlineMatches` (per inline string) and
    /// `MarkdownMetadataParser.inlineTagRegex`.
    ///
    /// **The owner could not be the styler's file, and that is read out of `project.pbxproj`
    /// rather than remembered** — the same argument [[T-1521]] had to make, reaching the opposite
    /// placement. `MarkdownMetadataSupport.swift` is in the app's synchronized folder *and* in the
    /// explicit Sources phases of `CadenceMCPServer` **and** `CadenceWidgets`;
    /// `MarkdownStyleRangeSupport.swift` is in none of the explicit ones. A constant declared in
    /// the styler's file would not link in the two extra targets the metadata file compiles into,
    /// so the metadata file owns it and the styler aliases it. No file moved between targets.
    ///
    /// **The assertion is `===`.** A second object built from the same string passes every
    /// behavioural row, and a second object is exactly what was removed. What the three readers do
    /// with a `#tag` differs — draw it as a chip, hide its marker, or *insert* a `Tag` row the
    /// user never created — and what one **is** may not.
    @Test func theHashtagPatternIsOneCompiledObjectThreeReadersShare() throws {
        let mcp = try cadenceMCPServerMemberFiles()
        #expect(mcp.count >= 50, "the MCP source list parsed as \(mcp.count) files, so this scan read nothing")
        #expect(
            mcp.contains("Cadence/Services/MarkdownMetadataSupport.swift"),
            "the file that owns inlineTagPattern left the MCP target, so the ownership has to move"
        )
        #expect(
            !mcp.contains("Cadence/Services/MarkdownStyleRangeSupport.swift"),
            "the styler's file joined the MCP target, so this boundary argument is gone"
        )
        #expect(!mcp.contains("Cadence/Services/MarkdownInlinePreviewSupport.swift"))

        #expect(MarkdownMetadataParser.inlineTagPattern == ##"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"##)
        #expect(MarkdownMetadataParser.inlineTagPattern.utf8.count == 46)
        #expect(MarkdownInlineMarkerRanges.hashtagPattern == MarkdownMetadataParser.inlineTagPattern)
        #expect(
            MarkdownInlineMarkerRanges.hashtagRegex === MarkdownMetadataParser.inlineTagRegex,
            "the styler alias is a second compiled copy again, not the tag sweep's object"
        )
        let compiled = try #require(MarkdownMetadataParser.inlineTagRegex)
        #expect(compiled.pattern == MarkdownMetadataParser.inlineTagPattern)
        #expect(compiled.options == [], "the tag pattern gained an option three readers did not ask for")

        // The three readers agree on the same rows, by position and not merely by count.
        let corpus: [(markdown: String, tags: [String])] = [
            ("#alpha and #beta", ["alpha", "beta"]),
            ("C#sharp is not a tag and neither is id_#4", []),
            ("#tag-with-dash #tag_under #Mixed99", ["tag-with-dash", "tag_under", "Mixed99"]),
            ("#-bad and #_bad are not tags", []),
            ("plain prose", []),
        ]
        for row in corpus {
            let styler = MarkdownInlineMarkerRanges.hashtagRanges(in: row.markdown)
            let sweep = MarkdownMetadataParser.inlineTagNames(in: row.markdown)
            let preview = MarkdownInlinePreviewSupport.runs(in: row.markdown).filter { $0.traits.contains(.tag) }
            #expect(sweep == row.tags, "the launch tag sweep read \(sweep) in \(row.markdown.debugDescription)")
            #expect(styler.count == row.tags.count, "the styler saw \(styler.count) tags in \(row.markdown.debugDescription)")
            #expect(preview.map(\.text) == row.tags.map { "#\($0)" }, "the preview drew \(preview.map(\.text))")
            let ns = row.markdown as NSString
            #expect(
                styler.map { ns.substring(with: $0) } == row.tags.map { "#\($0)" },
                "the styler and the sweep name different runs in \(row.markdown.debugDescription)"
            )
        }
        #expect(corpus.contains { !$0.tags.isEmpty })
        #expect(corpus.contains { $0.tags.isEmpty })
    }

    // MARK: - [[T-1661]]: the reference prefix, and its one `.caseInsensitive`

    /// **`^\s*(?:task|note):(?:[^\|\]]*\|)?` was written twice with `.caseInsensitive` written
    /// twice, and the measured count is two — the ticket was right about this one.**
    ///
    /// Both copies are app-target only, so unlike [[T-1521]]'s literal there is no boundary
    /// argument at all and the owner is simply the file whose job is reference display.
    ///
    /// **What is shared is the compiled object, not the pattern string, and that is the one place
    /// this departs from [[T-1521]].** There the three sites disagreed about what to do with a
    /// pattern that will not compile, so only the bytes could be shared. Here the option is part
    /// of what the prefix *is*: without `.caseInsensitive`, `[[Task:…|Title]]` stops hiding its
    /// prefix and the label renders as `Task:…|Title`. Sharing the string would have left
    /// `options: [.caseInsensitive]` spelled in two places to drift on its own, so the editor
    /// takes the object and keeps a guard where it had a `try!`.
    @Test func theReferencePrefixIsOneCompiledObjectCarryingItsCaseInsensitiveOption() throws {
        #expect(MarkdownReferenceDisplaySupport.referencePrefixPattern == ##"^\s*(?:task|note):(?:[^\|\]]*\|)?"##)
        #expect(MarkdownReferenceDisplaySupport.referencePrefixPattern.utf8.count == 33)
        let regex = try #require(MarkdownReferenceDisplaySupport.referencePrefixRegex)
        #expect(regex.pattern == MarkdownReferenceDisplaySupport.referencePrefixPattern)
        #expect(
            regex.options == [.caseInsensitive],
            "the shared prefix regex lost .caseInsensitive, so [[Task:…]] stops hiding its prefix"
        )

        // The editor reads that object and compiles nothing.
        let editor = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorSupport.swift")
        )
        let stylist = try #require(CadenceSourceScan.declarationBody("enum MarkdownStylist", in: editor))
        let declarations = stylist
            .components(separatedBy: "\n")
            .filter { $0.contains("static let wikiLinkDisplayPrefixRegex") }
        #expect(declarations.count == 1)
        let declaration = try #require(declarations.first)
        #expect(
            declaration.contains("MarkdownReferenceDisplaySupport.referencePrefixRegex"),
            "the editor builds its own prefix regex again"
        )
        #expect(!declaration.contains("NSRegularExpression("))
        #expect(!declaration.contains("caseInsensitive"), ".caseInsensitive is spelled a second time again")
        #expect(
            stylist.components(separatedBy: "caseInsensitive").count - 1 == 0,
            "MarkdownStylist spells caseInsensitive again"
        )
        let displayRange = try #require(CadenceSourceScan.functionBody(named: "wikiLinkDisplayRange", in: stylist))
        #expect(displayRange.contains("wikiLinkDisplayPrefixRegex"))

        // The behaviour the option decides, on the reader this target can execute. The mixed-case
        // rows are the point: drop `.caseInsensitive` and the hidden length goes to 0.
        #expect(MarkdownReferenceDisplaySupport.display(forWikiLabel: "task:1111|A").hiddenPrefixUTF16Length == 10)
        #expect(MarkdownReferenceDisplaySupport.display(forWikiLabel: "TASK:1111|A").hiddenPrefixUTF16Length == 10)
        #expect(MarkdownReferenceDisplaySupport.display(forWikiLabel: "NOTE:x|y").displayText == "y")
        #expect(MarkdownReferenceDisplaySupport.display(forWikiLabel: "plain label").hiddenPrefixUTF16Length == 0)
    }

    // MARK: - [[T-1660]]: the oracle, recorded from the pre-change implementation

    /// **The shared table answers exactly what the ten per-call literals answered.**
    ///
    /// `inlinePatternRecording` is not a guess. It is the output of `inlinePatternDump()` run
    /// against the **unmodified** tree — the shipping `MarkdownInlinePreviewSupport`,
    /// `MarkdownInlineSpanSupport`, `MarkdownInlineMarkerRanges`, `MarkdownMetadataParser` and
    /// `MarkdownReferenceDisplaySupport`, before a literal moved — captured 2026-09-30 from a test
    /// run of this target against HEAD.
    ///
    /// It is here because the byte-identity rows above cannot see the parts of this change that
    /// are not bytes: the ten rules carry `traits`, a `contentRangeIndex`, a `priority` and a
    /// `normalizesContent` flag, and they are appended in an order that `nonOverlapping` resolves
    /// ties within. A table that hoisted the patterns correctly and transposed two priorities
    /// would pass every assertion above and render `***x***` as a stray asterisk.
    ///
    /// Rows that look surprising are *recorded* behaviour, not this ticket's to change:
    /// `** not bold **` is bold, `== not marked ==` is marked, `snake_case_name and id__x__y`
    /// yields one bold run over `x`, an unclosed backtick leaves `` ` `` in the text, and
    /// `"  task:abc|Deep  "` hides 11 UTF-16 units because `^\s*` eats the leading spaces.
    @Test func theInlinePatternTableAnswersWhatThePerCallPatternsAnswered() {
        let produced = Self.inlinePatternDump().components(separatedBy: "\n")
        let recorded = Self.inlinePatternRecording.components(separatedBy: "\n")
        #expect(produced.count == recorded.count, "the dump is \(produced.count) lines, recorded is \(recorded.count)")
        for (index, expected) in recorded.enumerated() where index < produced.count {
            #expect(
                produced[index] == expected,
                "line \(index + 1) of the inline dump changed:\n  recorded: \(expected)\n  produced: \(produced[index])"
            )
        }

        // Non-vacuity: the recording is the real one, at the length it was captured, and the dump
        // is not a wall of empty answers.
        #expect(recorded.count == 85, "the inline recording was shortened")
        #expect(!recorded.contains { $0.isEmpty })
        #expect(produced.contains { $0.contains(##"["bold"/1/nil/nil " and "/0/nil/nil "italic"/2/nil/nil]"##) })
        #expect(recorded.filter { $0.contains("/32/") }.count >= 2, "the tag rows are gone from the recording")
        #expect(recorded.filter { $0.hasSuffix("\t[]") }.count > 10)
    }

    // MARK: - [[T-1660]] / [[T-1661]]: the inline pattern table

    /// The corpus the inline recording below is taken over. It reaches every one of the ten
    /// patterns `MarkdownInlinePreviewSupport.inlineMatches` runs, both underscore forms, the
    /// precedence between them, the code-span protection, and the two non-emphasis readers of the
    /// tag pattern.
    nonisolated static let inlinePatternCorpus: [String] = [
        "**bold** and *italic*",
        "***triple*** then **double** then *single*",
        "___triple___ then __double__ then _single_",
        "snake_case_name and id__x__y stay plain",
        "~~struck~~ and `code` and ==marked==",
        "`a **b** c` keeps its markers",
        "**bold with `code` inside**",
        "#tag and C#sharp and id_#4 and #1digit",
        "#tag-with-dash #tag_under #Mixed99 #-bad #_bad",
        "a line with [label](https://example.com) in it",
        "[**bold label**](https://example.com/x)",
        "==**marked bold**== together",
        "text with ![photo](cadence-image://3F2504E0-4F89-11D3-9A0C-0305E82C3301) image",
        "[[note:Alpha]] reference and **bold**",
        "[[task:11111111-2222-3333-4444-555555555555|A title]] embed",
        "*a* *b* *c*",
        "== not marked ==",
        "** not bold **",
        #"escaped \*not italic\* here"#,
        "multi\nline **bold** across",
        "`unclosed code and **bold**",
        "",
        "plain prose with nothing at all",
    ]

    /// Labels for the `task:`/`note:` prefix pattern. Four of them are mixed case on purpose:
    /// `.caseInsensitive` is the option [[T-1661]] is about, and without it `[[Task:…]]` stops
    /// hiding its prefix.
    nonisolated static let referencePrefixCorpus: [String] = [
        "task:1111|A",
        "TASK:1111|A",
        "Task: 1111 | A ",
        "note:Alpha",
        "NOTE:x|y",
        "  task:abc|Deep  ",
        "task:",
        "note:",
        "plain label",
        "tasknote:x|y",
        "task:no pipe here",
        "nested|pipe|label",
    ]

    nonisolated static func inlinePatternDump() -> String {
        var lines: [String] = []
        lines.append("--- MarkdownInlinePreviewSupport.runs")
        for row in inlinePatternCorpus {
            let rendered = MarkdownInlinePreviewSupport.runs(in: row).map { run in
                "\(quoted(run.text))/\(run.traits.rawValue)/\(run.linkURL.map(quoted) ?? "nil")/\(run.target?.identity ?? "nil")"
            }.joined(separator: " ")
            lines.append("\(quoted(row))\t[\(rendered)]")
        }
        lines.append("--- MarkdownInlineSpanSupport.spans")
        for row in inlinePatternCorpus {
            let rendered = MarkdownInlineSpanSupport.spans(in: row).map { span in
                let markers = span.markerRanges.map { "\($0.location),\($0.length)" }.joined(separator: "+")
                return "\(span.kind)/\(span.fullRange.location),\(span.fullRange.length)/\(span.contentRange.location),\(span.contentRange.length)/\(markers)"
            }.joined(separator: " ")
            lines.append("\(quoted(row))\t[\(rendered)]")
        }
        lines.append("--- codeRanges / hashtagRanges / inlineTagNames")
        for row in inlinePatternCorpus {
            let code = MarkdownInlineSpanSupport.codeRanges(in: row).map { "\($0.location),\($0.length)" }.joined(separator: "+")
            let hashtags = MarkdownInlineMarkerRanges.hashtagRanges(in: row).map { "\($0.location),\($0.length)" }.joined(separator: "+")
            let names = MarkdownMetadataParser.inlineTagNames(in: row).map { quoted($0) }.joined(separator: "+")
            lines.append("\(quoted(row))\t[\(code)]\t[\(hashtags)]\t[\(names)]")
        }
        lines.append("--- MarkdownReferenceDisplaySupport.display(forWikiLabel:)")
        for label in referencePrefixCorpus {
            let display = MarkdownReferenceDisplaySupport.display(forWikiLabel: label)
            lines.append("\(quoted(label))\t\(display.kind.rawValue)\t\(quoted(display.displayText))\t\(display.hiddenPrefixUTF16Length)")
        }
        return lines.joined(separator: "\n")
    }

    /// The dump above, as the **pre-change** implementations printed it — ten literals compiled per
    /// inline string, nine of them written twice over and five of those a third time. Captured
    /// 2026-09-30 from a run of this target against the unmodified tree. See the test.
    nonisolated static let inlinePatternRecording = #"""
        --- MarkdownInlinePreviewSupport.runs
        "**bold** and *italic*"	["bold"/1/nil/nil " and "/0/nil/nil "italic"/2/nil/nil]
        "***triple*** then **double** then *single*"	["triple"/3/nil/nil " then "/0/nil/nil "double"/1/nil/nil " then "/0/nil/nil "single"/2/nil/nil]
        "___triple___ then __double__ then _single_"	["triple"/3/nil/nil " then "/0/nil/nil "double"/1/nil/nil " then "/0/nil/nil "single"/2/nil/nil]
        "snake_case_name and id__x__y stay plain"	["snake_case_name and id"/0/nil/nil "x"/1/nil/nil "y stay plain"/0/nil/nil]
        "~~struck~~ and `code` and ==marked=="	["struck"/8/nil/nil " and "/0/nil/nil "code"/4/nil/nil " and "/0/nil/nil "marked"/16/nil/nil]
        "`a **b** c` keeps its markers"	["a **b** c"/4/nil/nil " keeps its markers"/0/nil/nil]
        "**bold with `code` inside**"	["bold with code inside"/1/nil/nil]
        "#tag and C#sharp and id_#4 and #1digit"	["#tag"/32/nil/nil " and C#sharp and id_#4 and "/0/nil/nil "#1digit"/32/nil/nil]
        "#tag-with-dash #tag_under #Mixed99 #-bad #_bad"	["#tag-with-dash"/32/nil/nil " "/0/nil/nil "#tag_under"/32/nil/nil " "/0/nil/nil "#Mixed99"/32/nil/nil " #-bad #_bad"/0/nil/nil]
        "a line with [label](https://example.com) in it"	["a line with "/0/nil/nil "label"/0/"https://example.com"/nil " in it"/0/nil/nil]
        "[**bold label**](https://example.com/x)"	["bold label"/0/"https://example.com/x"/nil]
        "==**marked bold**== together"	["marked bold"/16/nil/nil " together"/0/nil/nil]
        "text with ![photo](cadence-image://3F2504E0-4F89-11D3-9A0C-0305E82C3301) image"	["text with "/0/nil/nil "photo"/64/nil/nil " image"/0/nil/nil]
        "[[note:Alpha]] reference and **bold**"	["Alpha"/0/nil/note:Alpha " reference and "/0/nil/nil "bold"/1/nil/nil]
        "[[task:11111111-2222-3333-4444-555555555555|A title]] embed"	["A title"/0/nil/task:11111111-2222-3333-4444-555555555555 " embed"/0/nil/nil]
        "*a* *b* *c*"	["a"/2/nil/nil " "/0/nil/nil "b"/2/nil/nil " "/0/nil/nil "c"/2/nil/nil]
        "== not marked =="	[" not marked "/16/nil/nil]
        "** not bold **"	[" not bold "/1/nil/nil]
        "escaped \\*not italic\\* here"	["escaped \\"/0/nil/nil "not italic\\"/2/nil/nil " here"/0/nil/nil]
        "multi\nline **bold** across"	["multi\nline "/0/nil/nil "bold"/1/nil/nil " across"/0/nil/nil]
        "`unclosed code and **bold**"	["`unclosed code and "/0/nil/nil "bold"/1/nil/nil]
        ""	[]
        "plain prose with nothing at all"	["plain prose with nothing at all"/0/nil/nil]
        --- MarkdownInlineSpanSupport.spans
        "**bold** and *italic*"	[bold/0,8/2,4/0,2+6,2 italic/13,8/14,6/13,1+20,1]
        "***triple*** then **double** then *single*"	[boldItalic/0,12/3,6/0,3+9,3 bold/0,11/2,7/0,2+9,2 bold/18,10/20,6/18,2+26,2 italic/34,8/35,6/34,1+41,1]
        "___triple___ then __double__ then _single_"	[boldItalic/0,12/3,6/0,3+9,3 bold/18,10/20,6/18,2+26,2 italic/34,8/35,6/34,1+41,1]
        "snake_case_name and id__x__y stay plain"	[bold/22,5/24,1/22,2+25,2]
        "~~struck~~ and `code` and ==marked=="	[strikethrough/0,10/2,6/0,2+8,2 code/15,6/16,4/15,1+20,1 highlight/26,10/28,6/26,2+34,2]
        "`a **b** c` keeps its markers"	[code/0,11/1,9/0,1+10,1]
        "**bold with `code` inside**"	[bold/0,27/2,23/0,2+25,2 code/12,6/13,4/12,1+17,1]
        "#tag and C#sharp and id_#4 and #1digit"	[]
        "#tag-with-dash #tag_under #Mixed99 #-bad #_bad"	[]
        "a line with [label](https://example.com) in it"	[]
        "[**bold label**](https://example.com/x)"	[bold/1,14/3,10/1,2+13,2]
        "==**marked bold**== together"	[bold/2,15/4,11/2,2+15,2 highlight/0,19/2,15/0,2+17,2]
        "text with ![photo](cadence-image://3F2504E0-4F89-11D3-9A0C-0305E82C3301) image"	[]
        "[[note:Alpha]] reference and **bold**"	[bold/29,8/31,4/29,2+35,2]
        "[[task:11111111-2222-3333-4444-555555555555|A title]] embed"	[]
        "*a* *b* *c*"	[italic/0,3/1,1/0,1+2,1 italic/4,3/5,1/4,1+6,1 italic/8,3/9,1/8,1+10,1]
        "== not marked =="	[highlight/0,16/2,12/0,2+14,2]
        "** not bold **"	[bold/0,14/2,10/0,2+12,2]
        "escaped \\*not italic\\* here"	[italic/9,13/10,11/9,1+21,1]
        "multi\nline **bold** across"	[bold/11,8/13,4/11,2+17,2]
        "`unclosed code and **bold**"	[bold/19,8/21,4/19,2+25,2]
        ""	[]
        "plain prose with nothing at all"	[]
        --- codeRanges / hashtagRanges / inlineTagNames
        "**bold** and *italic*"	[]	[]	[]
        "***triple*** then **double** then *single*"	[]	[]	[]
        "___triple___ then __double__ then _single_"	[]	[]	[]
        "snake_case_name and id__x__y stay plain"	[]	[]	[]
        "~~struck~~ and `code` and ==marked=="	[15,6]	[]	[]
        "`a **b** c` keeps its markers"	[0,11]	[]	[]
        "**bold with `code` inside**"	[12,6]	[]	[]
        "#tag and C#sharp and id_#4 and #1digit"	[]	[0,4+31,7]	["tag"+"1digit"]
        "#tag-with-dash #tag_under #Mixed99 #-bad #_bad"	[]	[0,14+15,10+26,8]	["tag-with-dash"+"tag_under"+"Mixed99"]
        "a line with [label](https://example.com) in it"	[]	[]	[]
        "[**bold label**](https://example.com/x)"	[]	[]	[]
        "==**marked bold**== together"	[]	[]	[]
        "text with ![photo](cadence-image://3F2504E0-4F89-11D3-9A0C-0305E82C3301) image"	[]	[]	[]
        "[[note:Alpha]] reference and **bold**"	[]	[]	[]
        "[[task:11111111-2222-3333-4444-555555555555|A title]] embed"	[]	[]	[]
        "*a* *b* *c*"	[]	[]	[]
        "== not marked =="	[]	[]	[]
        "** not bold **"	[]	[]	[]
        "escaped \\*not italic\\* here"	[]	[]	[]
        "multi\nline **bold** across"	[]	[]	[]
        "`unclosed code and **bold**"	[]	[]	[]
        ""	[]	[]	[]
        "plain prose with nothing at all"	[]	[]	[]
        --- MarkdownReferenceDisplaySupport.display(forWikiLabel:)
        "task:1111|A"	task	"A"	10
        "TASK:1111|A"	task	"A"	10
        "Task: 1111 | A "	task	" A "	12
        "note:Alpha"	note	"Alpha"	5
        "NOTE:x|y"	note	"y"	7
        "  task:abc|Deep  "	task	"Deep  "	11
        "task:"	task	"task:"	0
        "note:"	note	"note:"	0
        "plain label"	note	"plain label"	0
        "tasknote:x|y"	note	"tasknote:x|y"	0
        "task:no pipe here"	task	"no pipe here"	5
        "nested|pipe|label"	note	"nested|pipe|label"	0
        """#
}
