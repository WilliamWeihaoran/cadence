import Foundation
import Testing

/// A comment that names a symbol which does not exist.
///
/// **The defect class (T-333, T-337, T-352, and five more since).** Prose naming machinery the code
/// no longer has is worse than a missing mechanism, because it stops the next reader checking: the
/// sentence sounds like it was written by someone who looked. `CadenceStartupIssueBanner` carried
/// three of them, T-625 claimed a two-device merge its test never pinned, T-644's workaround note
/// went stale the moment the reader was fixed, and T-647's exemption attributed itself to a defect
/// in a file that has no such function at all.
///
/// **What is actually checkable.** Most comments are not assertions about machinery, and a detector
/// that tries to judge whether English is true is worth nothing. The tractable core is a comment
/// that *names a symbol* — and this repo spells symbols in backticks, 23,256 times. So the rule is
/// arithmetic on names, not on sentences:
///
/// > A backticked <Type>.<member> in a comment is an offender when the type is a nominal one declared
/// > in this repository and the member is declared **neither** on any type of that name **nor**
/// > in a file named after it.
///
/// Every hit therefore means one thing: *this name resolves to nothing in this tree.* Not "the
/// sentence reads oddly" — the reader cannot follow the pointer, because there is nothing at the
/// other end of it.
///
/// **What it deliberately cannot see**, stated rather than discovered later:
///
/// - **Prose with no symbol in it.** T-563's whole ticket was a wrong premise carried in English
///   for days ("flakes about 1 run in 5"); no name in it was false, so nothing here would fire.
/// - **Unqualified names.** ``foo(_:)`` on its own is invisible: 24 distinct call-shaped spans name
///   a base declared nowhere in the tree, but half of them are AppKit/UIKit symbols a comment is
///   entitled to mention. Measured and filed as its own ticket rather than guessed at.
/// - **SDK-rooted claims.** ``ModelContext.save()`` cannot be checked, because the repository
///   cannot enumerate a framework's members. The root must be a type this tree declares.
/// - **Behaviour, as opposed to existence.** T-555's fixture comment described a harvest as
///   `static let`-only after it was widened; every name in it still resolved. T-625 is the same
///   shape. A name-resolution rule is blind to both, on purpose.
/// - **File-qualified references.** This repo writes `<FileBaseName>.<symbol>` for a fileprivate
///   type, so a claim whose member is declared anywhere in `Type.swift` is excluded — but only when
///   the file declares exactly one **non-private** nominal type ([[T-717]]). `NotesView.swift` and
///   `SettingsTagsSection.swift` hold several `private` helper types beside their eponymous one and
///   keep the exclusion; `DateFormatters.swift` and `CadenceCalendarDayBadge.swift` each hold two
///   types that are *both* public, so the exclusion no longer covers a claim naming one when the
///   member lives on the other.
///
/// **The ledger is the guard.** Set equality in both directions: no offender may go unlisted, and
/// no listed entry may go stale. The repository uses tombstones deliberately and well — 22 survive
/// T-487 on purpose — so most entries below are memorials and are marked as such. The value is in
/// catching the *claim*, not the *memorial*, and the split is recorded rather than inferred.
enum CadenceCommentSymbolClaim {

    // MARK: - Lexing

    enum Region { case code, string, comment }

    /// `source` split into three strings of its own length, each holding one region and blanking
    /// the other two to spaces (newlines kept everywhere, so offsets and line numbers survive).
    ///
    /// The walk is `CadenceSourceScan.codeOnly`'s, and its `code` half is pinned equal to that
    /// function on the fixtures that separate them — a raw literal holding a bare quote, a `//`
    /// inside a string, a `"` inside a comment. One traversal rather than two passes, for the
    /// reason recorded there: whichever pass runs second mishandles the delimiter the first one
    /// already consumed.
    ///
    /// The `comments` half is the whole reason this exists. `codeOnly` blanks comments *and*
    /// literals, and `strippingComments` blanks only comments — neither hands back the prose, and a
    /// detector that reads prose out of raw source would count its own fixtures as findings.
    static func partition(_ source: String) -> (code: String, strings: String, comments: String) {
        let characters = Array(source)
        let count = characters.count
        var kind = [Region](repeating: .code, count: count)

        func mark(_ range: Range<Int>, _ region: Region) {
            for position in range { kind[position] = region }
        }

        var index = 0
        while index < count {
            let character = characters[index]

            // A raw literal before an ordinary one: inside `#"..."#` a backslash is content.
            if character == "#" {
                var hashEnd = index
                while hashEnd < count, characters[hashEnd] == "#" { hashEnd += 1 }
                let hashes = hashEnd - index
                if hashEnd < count, characters[hashEnd] == "\"" {
                    let multiline = hashEnd + 2 < count
                        && characters[hashEnd + 1] == "\""
                        && characters[hashEnd + 2] == "\""
                    let quotes = multiline ? 3 : 1
                    var end = hashEnd + quotes
                    var close = count
                    while end < count {
                        if characters[end] == "\"",
                           end + quotes + hashes <= count,
                           (end..<(end + quotes)).allSatisfy({ characters[$0] == "\"" }),
                           ((end + quotes)..<(end + quotes + hashes)).allSatisfy({ characters[$0] == "#" }) {
                            close = end + quotes + hashes
                            break
                        }
                        if !multiline, characters[end].isNewline { close = end; break }
                        end += 1
                    }
                    mark(index..<close, .string)
                    index = close
                    continue
                }
            }

            if character == "\"" {
                if index + 2 < count, characters[index + 1] == "\"", characters[index + 2] == "\"" {
                    var end = index + 3
                    while end + 2 < count,
                          !(characters[end] == "\"" && characters[end + 1] == "\"" && characters[end + 2] == "\"") {
                        end += 1
                    }
                    let close = end + 2 < count ? end + 3 : count
                    mark(index..<close, .string)
                    index = close
                    continue
                }
                var end = index + 1
                while end < count, characters[end] != "\"", !characters[end].isNewline {
                    if characters[end] == "\\" { end += 1 }
                    end += 1
                }
                let close = end < count && characters[end] == "\"" ? end + 1 : min(end, count)
                mark(index..<close, .string)
                index = close
                continue
            }

            if character == "/", index + 1 < count {
                if characters[index + 1] == "/" {
                    var end = index
                    while end < count, !characters[end].isNewline { end += 1 }
                    mark(index..<end, .comment)
                    index = end
                    continue
                }
                if characters[index + 1] == "*" {
                    var end = index + 2
                    while end + 1 < count, !(characters[end] == "*" && characters[end + 1] == "/") {
                        end += 1
                    }
                    let close = end + 1 < count ? end + 2 : count
                    mark(index..<close, .comment)
                    index = close
                    continue
                }
            }

            index += 1
        }

        func extract(_ region: Region) -> String {
            String(characters.indices.map { position -> Character in
                let character = characters[position]
                if character.isNewline { return character }
                return kind[position] == region ? character : " "
            })
        }
        return (extract(.code), extract(.string), extract(.comment))
    }

    // MARK: - What the tree declares

    static let nominalTypePattern = "\\b(?:struct|class|enum|protocol|actor)\\s+([A-Za-z_][A-Za-z0-9_]*)"
    static let anyTypePattern = "\\b(?:struct|class|enum|protocol|actor|extension)\\s+([A-Za-z_][A-Za-z0-9_]*)"
    /// The backtick is not decoration: `static var \`default\`` is spelled with one, and a member
    /// pattern without it reads that declaration as absent and accuses two correct comments.
    static let memberPattern =
        "\\b(?:func|var|let|case|typealias|struct|class|enum|actor)\\s+`?([A-Za-z_][A-Za-z0-9_]*)`?"

    /// Whether `range` — a `nominalTypePattern` match's range, so it starts at the `struct` /
    /// `class` / `enum` / `protocol` / `actor` keyword — is modified by `private` or `fileprivate`
    /// on the same line.
    ///
    /// Reads only back to the previous newline, not the whole file: a `private` several
    /// declarations earlier must not be allowed to attach itself to a type it never modified. This
    /// repo writes one declaration per line with its access modifier immediately before the type
    /// keyword (`private struct Helper`, `nonisolated enum DateFormatters`, `private final class
    /// MarkdownEditorScrollView`), so a same-line check is exact for the style actually in use.
    static func isPrivatelyDeclared(_ range: Range<String.Index>, in code: String) -> Bool {
        let prefix = linePrefix(before: range, in: code)
        let tokens = prefix.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        return tokens.contains("private") || tokens.contains("fileprivate")
    }

    /// Whether `range` sits at column 0 — this repo indents every nested declaration, so an
    /// unindented line is a top-level one. `NotesView.swift`'s `NotesPage` is a nested enum with no
    /// `private` of its own (nesting inside a type is not the same disclosure as a second sibling
    /// type at file scope), and counting it as a second public type would have narrowed the
    /// exclusion away from `NotesView.NotesDateJumpButton`, which [[T-717]] says must stay excluded.
    static func isTopLevelDeclaration(_ range: Range<String.Index>, in code: String) -> Bool {
        let prefix = linePrefix(before: range, in: code)
        guard let first = prefix.first else { return true }
        return first != " " && first != "\t"
    }

    private static func linePrefix(before range: Range<String.Index>, in code: String) -> Substring {
        let lineStart = code[code.startIndex..<range.lowerBound]
            .lastIndex(of: "\n")
            .map { code.index(after: $0) } ?? code.startIndex
        return code[lineStart..<range.lowerBound]
    }

    /// Which names exist, and where.
    ///
    /// `membersByType` is deliberately a **superset**: every declaration at any depth inside a
    /// type's braces counts, nested types included. An over-generous member set can only make the
    /// detector quieter, never louder, which is the safe direction for a sweep whose false
    /// positives land on another agent's desk.
    struct SymbolIndex {
        var nominalTypes: Set<String> = []
        var membersByType: [String: Set<String>] = [:]
        var namesByFileBaseName: [String: Set<String>] = [:]
        /// Every **top-level, non-private, non-fileprivate** nominal type declared in a file of
        /// that base name. What the file-qualified exclusion narrows on ([[T-717]]):
        /// `NotesView.swift` has eight nominal types and `SettingsTagsSection.swift` has six, but
        /// all but the eponymous one are `private` — implementation detail the convention is *for*.
        /// `DateFormatters.swift` and `CadenceCalendarDayBadge.swift` each have exactly two, neither
        /// marked `private`, so a claim naming one when the member lives on the other is a genuine
        /// mix-up between two equally public types, not a fileprivate row.
        ///
        /// **Top-level only, not merely non-private.** `NotesView` nests `NotesPage` with no
        /// `private` of its own — nesting inside a type is not the same disclosure as a second
        /// sibling type at file scope — so counting every non-private declaration regardless of
        /// depth would have counted `NotesPage` as a second public type and narrowed the exclusion
        /// away from `NotesView.NotesDateJumpButton`, which [[T-717]] says must stay excluded.
        var publicNominalTypesByFileBaseName: [String: Set<String>] = [:]

        static func build(from files: [(path: String, code: String)]) -> SymbolIndex {
            var index = SymbolIndex()
            for file in files {
                let code = file.code
                for capture in CadenceSourceScan.captures(nominalTypePattern, in: code) {
                    index.nominalTypes.insert(capture.text)
                }

                let base = (file.path as NSString).lastPathComponent
                    .replacingOccurrences(of: ".swift", with: "")
                if !base.isEmpty {
                    var names = index.namesByFileBaseName[base] ?? []
                    for capture in CadenceSourceScan.captures(memberPattern, in: code) {
                        names.insert(capture.text)
                    }
                    for capture in CadenceSourceScan.captures(anyTypePattern, in: code) {
                        names.insert(capture.text)
                    }
                    index.namesByFileBaseName[base] = names

                    var nominals = index.publicNominalTypesByFileBaseName[base] ?? []
                    for capture in CadenceSourceScan.captures(nominalTypePattern, in: code)
                    where isTopLevelDeclaration(capture.range, in: code)
                        && !isPrivatelyDeclared(capture.range, in: code) {
                        nominals.insert(capture.text)
                    }
                    index.publicNominalTypesByFileBaseName[base] = nominals
                }

                for header in CadenceSourceScan.captures(anyTypePattern, in: code) {
                    guard let body = CadenceSourceScan.matchedBody(
                        after: header.range.upperBound,
                        in: code,
                        open: "{",
                        close: "}"
                    ) else { continue }
                    var members = index.membersByType[header.text] ?? []
                    for capture in CadenceSourceScan.captures(memberPattern, in: body) {
                        members.insert(capture.text)
                    }
                    index.membersByType[header.text] = members
                }
            }
            return index
        }

        func merging(_ other: SymbolIndex) -> SymbolIndex {
            var merged = self
            merged.nominalTypes.formUnion(other.nominalTypes)
            for (type, members) in other.membersByType {
                merged.membersByType[type, default: []].formUnion(members)
            }
            for (base, names) in other.namesByFileBaseName {
                merged.namesByFileBaseName[base, default: []].formUnion(names)
            }
            for (base, nominals) in other.publicNominalTypesByFileBaseName {
                merged.publicNominalTypesByFileBaseName[base, default: []].formUnion(nominals)
            }
            return merged
        }
    }

    // MARK: - What a comment claims

    struct Claim: Hashable {
        let span: String
        let type: String
        let member: String
    }

    /// Members no declaration has to spell: a conformance or the compiler supplies them.
    static let synthesizedMembers: Set<String> = [
        "init", "self", "allCases", "rawValue", "hashValue", "id", "description",
        "debugDescription", "none", "some"
    ]

    /// `Theme.swift` and `AGENTS.md` are paths, not symbols, and they parse identically.
    static let fileExtensions: Set<String> = [
        "swift", "md", "plist", "pbxproj", "sh", "json", "yml", "yaml", "xcodeproj",
        "entitlements", "ts", "txt", "png", "xcassets"
    ]

    /// Every backticked span in `comments` that reads as `Type.member`.
    ///
    /// A span containing `*` is skipped: this repo writes ``CadencePendingChangePersistence.commit*``
    /// on purpose, to name a family rather than a member, and a glob is not a claim about one
    /// declaration.
    static func claims(inComments comments: String) -> [Claim] {
        CadenceSourceScan.captures("`([^`\\n]+)`", in: comments).compactMap { capture in
            let span = capture.text
            guard !span.contains("*") else { return nil }
            guard let parsed = CadenceSourceScan.captures(
                "^([A-Z][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)",
                in: span,
                group: 1
            ).first else { return nil }
            let member = CadenceSourceScan.captures(
                "^([A-Z][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)",
                in: span,
                group: 2
            ).first
            guard let member else { return nil }
            guard !fileExtensions.contains(member.text) else { return nil }
            return Claim(span: span, type: parsed.text, member: member.text)
        }
    }

    /// The offending spans in one file, read against the tree plus the file's own declarations.
    ///
    /// Merging the file's own index in is what lets a literal fixture stand alone: the witnesses
    /// `CadenceScanInstrument` checks declare their own type, so the detector answers the same
    /// question for a five-line fixture and for a 900-line screen.
    static func offendingSpans(in source: String, against index: SymbolIndex) -> [String] {
        let regions = partition(source)
        let world = index.merging(SymbolIndex.build(from: [(path: "", code: regions.code)]))
        return claims(inComments: regions.comments).compactMap { claim in
            guard world.nominalTypes.contains(claim.type) else { return nil }
            guard !synthesizedMembers.contains(claim.member) else { return nil }
            guard world.membersByType[claim.type]?.contains(claim.member) != true else { return nil }
            // File-qualified, and only when the file has exactly one non-private nominal type
            // ([[T-717]]): a second *public* type sharing the file has to say which one it means,
            // so the exclusion no longer covers that case — private helper types stay uncounted,
            // because they are exactly what the convention is for.
            if world.namesByFileBaseName[claim.type]?.contains(claim.member) == true,
               world.publicNominalTypesByFileBaseName[claim.type]?.count == 1 {
                return nil
            }
            return claim.span
        }
    }

    // MARK: - Witnesses

    /// A claim about a member the type does not have. `render` is nowhere in the tree.
    static let positiveWitness = """
    /// The row draws through `CadenceCommentClaimWidgetFixture.render`.
    enum CadenceCommentClaimWidgetFixture {
        static let title = "Widget"
    }
    """

    /// The nearest possible miss: the same sentence about the member that is actually there.
    static let negativeWitness = """
    /// The row draws through `CadenceCommentClaimWidgetFixture.title`.
    enum CadenceCommentClaimWidgetFixture {
        static let title = "Widget"
    }
    """
}

/// The sweep, and the ledger it is checked against.
@Suite struct CadenceCommentSymbolClaimTests {

    /// Spelled without the word "err" + "or": a missing source is a kill, not a build break.
    private struct MissingSource: Swift.Error { let path: String }

    private static func source(_ path: String, in text: [String: String]) throws -> String {
        guard let found = text[path] else { throw MissingSource(path: path) }
        return found
    }

    private static let sourceRoots = [
        "Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer", "CadenceUITests"
    ]

    private static func allSources() throws -> [(path: String, text: String)] {
        try sourceRoots
            .flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
            .sorted()
            .map { (path: $0, text: try CadenceSourceScan.sourceFile($0)) }
    }

    // MARK: - The reader

    /// The `code` half is `CadenceSourceScan.codeOnly`, character for character, on the four inputs
    /// that separate a correct lexer from a plausible one.
    @Test func theCodeHalfOfThePartitionIsTheAuditedReader() {
        let inputs = [
            "let url = \"https://example.com\" // trailing\nlet x = 1\n",
            "let raw = #\"photo\\\"# // after\nlet y = 2\n",
            "/* a \" quote inside a block comment */ let z = 3\n",
            "let doc = \"\"\"\n// not a comment\n\"\"\"\nlet w = 4\n",
            CadenceCommentSymbolClaim.positiveWitness
        ]
        for input in inputs {
            let regions = CadenceCommentSymbolClaim.partition(input)
            #expect(regions.code == CadenceSourceScan.codeOnly(input), "diverged on: \(input)")
        }
    }

    /// The three halves reconstruct the file: every non-blank character belongs to exactly one of
    /// them. A partition that lost a region — or double-counted one — fails here rather than by
    /// going quietly silent over a whole target.
    @Test func thePartitionCoversEveryCharacterExactlyOnce() throws {
        let samples = try Self.allSources().prefix(40)
        #expect(samples.count == 40)
        for sample in samples {
            let regions = CadenceCommentSymbolClaim.partition(sample.text)
            let code = Array(regions.code)
            let strings = Array(regions.strings)
            let comments = Array(regions.comments)
            let original = Array(sample.text)
            #expect(code.count == original.count)
            var mismatches = 0
            for position in original.indices {
                let character = original[position]
                if character == " " || character.isNewline {
                    if code[position] != character
                        || strings[position] != character
                        || comments[position] != character { mismatches += 1 }
                    continue
                }
                let owners = [code[position], strings[position], comments[position]]
                    .filter { $0 == character }
                if owners.count != 1 { mismatches += 1 }
            }
            #expect(mismatches == 0, "\(sample.path) did not partition cleanly")
        }
    }

    /// A claim in *code* or in a *string literal* is not a claim. Without this the detector reads
    /// its own witnesses — which are string literals in this file — as findings.
    @Test func onlyProseIsRead() {
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(from: [(
            path: "Fixture.swift",
            code: "enum CadenceCommentClaimWidgetFixture { static let title = \"\" }"
        )])
        let inCode = """
        enum CadenceCommentClaimWidgetFixture { static let title = "" }
        let value = CadenceCommentClaimWidgetFixture.render
        """
        let inLiteral = """
        enum CadenceCommentClaimWidgetFixture { static let title = "" }
        let note = "`CadenceCommentClaimWidgetFixture.render`"
        """
        #expect(CadenceCommentSymbolClaim.offendingSpans(in: inCode, against: index).isEmpty)
        #expect(CadenceCommentSymbolClaim.offendingSpans(in: inLiteral, against: index).isEmpty)
        #expect(
            CadenceCommentSymbolClaim.offendingSpans(
                in: CadenceCommentSymbolClaim.positiveWitness,
                against: index
            ) == ["CadenceCommentClaimWidgetFixture.render"]
        )
    }

    /// The four exclusions, each shown to be load-bearing by the case it exists to let through.
    @Test func theFourExclusionsEachSuppressExactlyTheirOwnCase() {
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(from: [
            (path: "CadenceCommentClaimWidgetFixture.swift",
             code: "enum CadenceCommentClaimWidgetFixture { static let title = \"\" }\n"
                 + "private struct Helper { func paint() {} }"),
            (path: "Other.swift", code: "enum CadenceCommentClaimOtherFixture { static let title = \"\" }")
        ])

        func fires(_ comment: String) -> Bool {
            !CadenceCommentSymbolClaim.offendingSpans(
                in: "/// \(comment)\nlet unused = 0\n",
                against: index
            ).isEmpty
        }

        // A root the tree does not declare cannot be checked at all.
        #expect(fires("`NotATypeInThisTree.render`") == false)
        // A glob names a family, not a declaration.
        #expect(fires("`CadenceCommentClaimOtherFixture.render*`") == false)
        // A path parses as `Type.member` and is not one.
        #expect(fires("`CadenceCommentClaimOtherFixture.swift`") == false)
        // File-qualified: the member is declared on `Helper`, a *private* type sharing the file
        // with `CadenceCommentClaimWidgetFixture`. This repo names a fileprivate type that way, and
        // `Helper` is the only other nominal type in the file, so the reference resolves and the
        // detector must stay quiet.
        #expect(fires("`CadenceCommentClaimWidgetFixture.paint`") == false)
        // The same member name against a type whose file declares nothing of the sort.
        #expect(fires("`CadenceCommentClaimOtherFixture.paint`") == true)
        #expect(fires("`CadenceCommentClaimWidgetFixture.render`") == true)
        #expect(fires("`CadenceCommentClaimOtherFixture.render`") == true)
    }

    /// **[[T-717]]'s narrowing, load-bearing on its own fixture.** A private helper sharing a file
    /// does not cost the file-qualified exclusion — the case above already shows that — but a
    /// *second public type* does, because the reader can no longer tell a correct file-qualified
    /// reference from a genuine mix-up between the two.
    @Test func theFileQualifiedExclusionStopsAtASecondPublicTypeButNotAtAPrivateOne() {
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(from: [
            (path: "CadenceCommentClaimSharedFixture.swift",
             code: "enum CadenceCommentClaimSharedFixtureOwner { static let title = \"\" }\n"
                 + "enum CadenceCommentClaimSharedFixtureCoTenant { static func render() {} }")
        ])

        func fires(_ comment: String) -> Bool {
            !CadenceCommentSymbolClaim.offendingSpans(
                in: "/// \(comment)\nlet unused = 0\n",
                against: index
            ).isEmpty
        }

        // Two nominal types in the file, neither `private` — `render` is `CoTenant`'s, not
        // `Owner`'s, and the file-qualified exclusion must not paper over that.
        #expect(fires("`CadenceCommentClaimSharedFixtureOwner.render`"))
        // The type that actually declares it is never in question.
        #expect(fires("`CadenceCommentClaimSharedFixtureCoTenant.render`") == false)
    }

    // MARK: - The ledger

    /// Deliberate: a tombstone recording what a symbol *used to be*, or a counterfactual naming a
    /// symbol the repository decided **not** to add. Neither misleads a reader; both name a symbol
    /// that is correctly absent, which is why they cannot be told apart from a stale claim by
    /// arithmetic.
    static let deliberateTombstones = [
        "Cadence/Services/MarkdownLineBreakSupport.swift `MarkdownListSupport.continuation`",
        "Cadence/Services/MarkdownNoteSupport.swift `NoteEditorPane.syncTitleFromH1IfNeeded`",
        "Cadence/Services/MarkdownTaskEmbedSupport.swift `CadenceTextView.legacyChecklistMarkerHit`",
        "Cadence/Shared/CadenceColorPalette.swift `ColorGrid.colors`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SettingsAISection.settingsField`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "Cadence/Shared/Components/CadenceSidebarCountLabel.swift `SidebarMetrics.countFontSize`",
        "Cadence/iOS/iOSCalendarMetrics.swift `CadencePageHeaderMetrics.iconSize`",
        "Cadence/iOS/iOSListNotesView.swift `CadenceListNoteSupport.firstOrCreateNote`",
        "Cadence/iOS/iOSSchedulePanelCopy.swift `CadenceTodayPresentationSupport.emptyScheduleHint`",
        "Cadence/macOS/Views/SettingsSupportViews.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "Cadence/macOS/Views/SettingsTemplatesSection.swift `SettingsAISection.settingsField`",
        "Cadence/macOS/Views/TasksPanelSupport.swift `TasksPanel.taskSections`",
        "CadenceMCPServer/CadenceMCPToolDefinitions.swift `CadenceGoalSummary.subGoalCount`",
        "CadenceMCPServer/CadenceMCPToolDefinitions.swift `CadenceGoalSummary.taskCount`",
        "CadenceTests/CadenceColorPaletteTests.swift `Theme.neutralHex`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `CadenceTodayPresentationSupport.emptyScheduleHint`",
        "CadenceTests/CadenceNoteFolderSurfaceTests.swift `CadenceListNoteSupport.firstOrCreateNote`",
        "CadenceTests/CadenceNoteFolderSurfaceTests.swift `ListNotesView.normalizedFolderPath`",
        "CadenceTests/CadenceNoteTitleSyncSurfaceTests.swift `NoteEditorPane.syncTitleFromH1IfNeeded`",
        "CadenceTests/CadenceTodayUnificationTests.swift `TasksPanel.taskSections`",
        "CadenceTests/MarkdownLineBreakSupportTests.swift `MarkdownQuoteSupport.continuation`",
        "CadenceTests/MarkdownListSupportTests.swift `MarkdownListSupport.continuation`",
        "CadenceTests/MarkdownQuoteSupportTests.swift `MarkdownQuoteSupport.continuation`",
        "CadenceTests/MarkdownTaskEmbedRenameSupportTests.swift `CadenceMCPServiceSupport.resolvedTitle`",
        "CadenceTests/MarkdownTaskEmbedRenameSupportTests.swift `CadenceReadService.resolvedTitle`",
        "CadenceTests/SettingsSharedVocabularyTests.swift `SettingsAISection.settingsField`",
        "CadenceTests/SettingsSharedVocabularyTests.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "CadenceTests/TaskOrderingTests.swift `CadenceTaskQuerySupport.sortDateKey`",
        "CadenceTests/iOSCalendarMetricsTests.swift `CadencePageHeaderMetrics.tileSize`"
    ]

    /// Stale, once: the sentence pointed a present-tense reader at a symbol that was not there.
    /// **[[T-716]] fixed all nine** — each comment now names the symbol it meant, in the same
    /// change that deleted its ledger line, so nothing here needs a tombstone: a corrected
    /// sentence names a real declaration, which is the tombstones' territory only if the repo
    /// later removes what it now correctly names.
    static let staleClaims: [String] = []

    static var ledger: [String] { (deliberateTombstones + staleClaims).sorted() }

    /// The two halves are one ledger and must not overlap or repeat.
    @Test func theLedgerIsWellFormed() {
        let tombstones = Self.deliberateTombstones
        let stale = Self.staleClaims
        #expect(Set(tombstones).count == tombstones.count)
        #expect(Set(stale).count == stale.count)
        #expect(Set(tombstones).isDisjoint(with: Set(stale)))
        #expect(tombstones == tombstones.sorted())
        #expect(stale == stale.sorted())
        #expect(tombstones.count == 30)
        #expect(stale.count == 0)
    }

    /// The sweep. Exact set equality, both directions, over every Swift file in all five targets.
    @Test func everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered() throws {
        let sources = try Self.allSources()
        var text: [String: String] = [:]
        for source in sources { text[source.path] = source.text }

        let index = CadenceCommentSymbolClaim.SymbolIndex.build(
            from: sources.map { (path: $0.path, code: CadenceCommentSymbolClaim.partition($0.text).code) }
        )

        let instrument = try CadenceScanInstrument(
            "comment names a symbol that resolves to nothing",
            fires: CadenceCommentSymbolClaim.positiveWitness,
            andNotOn: CadenceCommentSymbolClaim.negativeWitness
        ) { source in
            !CadenceCommentSymbolClaim.offendingSpans(in: source, against: index).isEmpty
        }

        let offendingPaths = try instrument.sweep(
            sources.map(\.path),
            atLeast: 800,
            including: "Cadence/Shared/Theme.swift",
            read: { path in try Self.source(path, in: text) }
        )

        var found: [String] = []
        for path in offendingPaths {
            let spans = Set(CadenceCommentSymbolClaim.offendingSpans(
                in: try Self.source(path, in: text),
                against: index
            ))
            found.append(contentsOf: spans.map { "\(path) `\($0)`" })
        }
        found.sort()

        let unlisted = found.filter { !Self.ledger.contains($0) }
        #expect(unlisted.isEmpty, "a comment names a symbol that resolves to nothing: \(unlisted)")
        let stale = Self.ledger.filter { !found.contains($0) }
        #expect(stale.isEmpty, "the ledger names a claim that is no longer there: \(stale)")
        #expect(found == Self.ledger)
    }
}
