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
/// - ~~**Unqualified names.**~~ ``foo(_:)`` on its own **is** covered now, by a second sweep with a
///   weaker question — [[T-718]], and the weakness is the point. "Declared anywhere in the tree" had
///   no stable reading (139 offenders, or 54, depending on whether a closure-typed property counts)
///   and still owed an SDK allowlist on top. *"Called anywhere in the tree"* has one reading and
///   needs no allowlist, because the framework names a comment is entitled to mention are almost
///   all names this app also calls. See `calledNames(inCode:)`. What stays uncovered is [[T-647]]'s
///   own spelling: a name absent from the file the sentence is *about* but present elsewhere.
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

    // MARK: - The unqualified half (T-718)

    /// A backticked span in canonical Swift **selector** spelling with no type in front of it: a
    /// lowercase base name, then a parenthesised list of argument labels and nothing else.
    ///
    /// **Why the spelling is the grammar and not a regex convenience.** [[T-718]] measured this
    /// population with a loose `name(anything)` reading and had to carry three separate exclusions
    /// for things that are not calls at all: `` `nonisolated(unsafe)` `` is a declaration modifier,
    /// `` `list_tasks(limit: 1)` `` is an MCP tool invocation with a *value* in it, and
    /// `` `sidebarListItem(contextID: UUID)` `` names a parameter's *type*. All three fall out
    /// automatically once the span has to be a selector: every argument is `label:` or `_:` and
    /// nothing follows the colon. That is a rule from the language, not a list that rots.
    static func unqualifiedClaims(inComments comments: String) -> [(span: String, base: String)] {
        CadenceSourceScan.captures("`([^`\\n]+)`", in: comments).compactMap { capture in
            let span = capture.text
            guard !span.contains("*") else { return nil }
            guard let base = CadenceSourceScan.captures(
                selectorSpelling,
                in: span
            ).first else { return nil }
            return (span: span, base: base.text)
        }
    }

    static let selectorSpelling =
        "^([a-z_][A-Za-z0-9_]*)\\((?:(?:[A-Za-z_][A-Za-z0-9_]*|_):)*\\)$"

    /// Every base name this repository **calls**, read off the code half of every source.
    ///
    /// **This is the definition [[T-718]] was missing, and the whole reason the half is landable.**
    /// The ticket's attempts asked *"is this name declared anywhere"*, and that question has no
    /// stable answer here: keying on `func` alone gave 139 offending base names, widening to
    /// closure-typed `var`/`let` properties invoked as calls gave 54, and neither number had yet
    /// paid for an SDK allowlist — `rollback` alone is a real `ModelContext` method called at 24
    /// sites and would have needed its own exclusion on top of the AppKit/UIKit one. A five-fold
    /// swing between two reasonable readings of one word is not a population to assert a floor over,
    /// and o4 was right to decline it on 2026-09-04.
    ///
    /// *"Does this repository call this name"* has exactly one reading, and it dissolves the
    /// allowlist rather than maintaining it: `rollback`, `map`, `min`, `max`,
    /// `trimmingCharacters`, `setFill`, `withAlphaComponent`, `runModal`, `scrollTo` and the rest of
    /// the stdlib and AppKit names in that measurement resolve **because the app calls them**, with
    /// no list anywhere. Measured over the same five roots: 976 selector-shaped spans, 348 distinct
    /// bases, **22 unresolved**, against 48 and 77 for the two "declared" readings.
    ///
    /// **It is a sound proxy, and strictly weaker than the rule it stands in for.** Anything absent
    /// from every call site in the tree is also declared nowhere in it, so this half never refuses a
    /// name the stricter reading would have allowed. What it gives up is [[T-647]]'s own spelling —
    /// `insertSubtask` named in a comment about a file that has neither, and declared elsewhere in
    /// the tree — which resolves here and always will. That half needs "the scope the sentence
    /// implies" and is not this.
    static func calledNames(inCode code: String) -> Set<String> {
        Set(CadenceSourceScan.captures("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(", in: code).map(\.text))
    }

    /// The unqualified spans in one file that name a call this repository never makes.
    ///
    /// The file's own calls are merged in for the reason `offendingSpans` merges its own
    /// declarations: a five-line fixture has to be answerable by the same detector the tree is.
    static func unresolvedUnqualifiedSpans(in source: String, against called: Set<String>) -> [String] {
        let regions = partition(source)
        let world = called.union(calledNames(inCode: regions.code))
        return unqualifiedClaims(inComments: regions.comments)
            .filter { !world.contains($0.base) }
            .map(\.span)
    }

    // MARK: - Witnesses

    /// A call-shaped span naming something this tree never calls.
    static let unqualifiedPositiveWitness = """
    /// The column sizes itself in `commentClaimGutterInset(for:)`.
    enum CadenceCommentClaimGutterFixture {
        static let inset = 4.0
    }
    """

    /// The nearest possible miss: the same sentence, over a tree that does make the call.
    static let unqualifiedNegativeWitness = """
    /// The column sizes itself in `commentClaimGutterInset(for:)`.
    enum CadenceCommentClaimGutterFixture {
        static let inset = commentClaimGutterInset(for: .regular)
    }
    """

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
        // The file's base name is the *claimed* type's own name — `Owner.swift` — matching the
        // convention this exclusion is for. A fixture path that did not match `claim.type` would
        // never reach the file-qualified branch at all, and every assertion below would pass
        // whether or not the narrowing code was even present.
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(from: [
            (path: "CadenceCommentClaimSharedFixtureOwner.swift",
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
        "Cadence/Services/TaskCreationService.swift `SchedulingActions.createTask`",
        "Cadence/Shared/CadenceColorPalette.swift `ColorGrid.colors`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SettingsAISection.settingsField`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "Cadence/Shared/Components/CadenceSidebarCountLabel.swift `SidebarMetrics.countFontSize`",
        "Cadence/iOS/iOSCalendarMetrics.swift `CadencePageHeaderMetrics.iconSize`",
        "Cadence/iOS/iOSListNotesView.swift `CadenceListNoteSupport.firstOrCreateNote`",
        "Cadence/iOS/iOSSchedulePanelCopy.swift `CadenceTodayPresentationSupport.emptyScheduleHint`",
        "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift `SchedulingActions.createTask`",
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

    /// The unqualified half's ledger — [[T-718]].
    ///
    /// **Every entry is deliberate, and that is the measurement, not the hope.** All 27 were read
    /// by hand when the half landed and every one falls into three groups, none of which misleads
    /// a reader:
    ///
    /// - **Tombstones and counterfactuals**, 21 of them, the same class the qualified ledger is
    ///   mostly made of. Their sentences read *"There is no noteLinks(in:)"*, *"moveAnchor(by:) …
    ///   are gone with the ‹ ➤ › cluster"*, *"a shared splits(width:sides:) would trade five
    ///   readable domain expressions for one generic"*, *"a property rather than
    ///   isEmptyState(for:)"*. A sentence whose whole subject is a symbol's **absence** names an
    ///   absent symbol on purpose. (Quoted without backticks here on purpose: this file is swept
    ///   too, and prose about a ledger must not add rows to it.)
    /// - **SDK members this app mentions but never calls**, 4 — reloadInputViews,
    ///   validateMenuItem, unregisterForRemoteNotifications, ranges(of:options:). This is the
    ///   residue of the framework allowlist [[T-718]] feared, and it is four lines rather than a
    ///   list of AppKit, because `calledNames(inCode:)` resolves every framework name the app
    ///   actually calls without being told about it. A ledger line names its file and its reason,
    ///   which an allowlist of bare SDK names cannot.
    /// - **Illustrative spans in these detectors' own prose**, 2: ``foo(_:)`` in the header above,
    ///   and the one in the sentence about what `#function` hands back.
    ///
    /// **Zero stale claims.** No comment in the tree points a present-tense reader at an unqualified
    /// call that was supposed to exist, which is a finding in itself: the defect [[T-647]] found was
    /// the *scoped* spelling, not this one.
    static let unqualifiedLedger = [
        "Cadence/Models/GoalContributionSummary.swift `isHabit(_:dueOn:calendar:)`",
        "Cadence/Services/MarkdownInlinePreviewSupport.swift `plainText(in:)`",
        "Cadence/Services/MarkdownProgrammaticEditSupport.swift `reloadInputViews()`",
        "Cadence/Services/MarkdownQuoteSupport.swift `continuation(after:)`",
        "Cadence/Services/MarkdownReferenceDisplaySupport.swift `replacingWikiLinksWithDisplayText(in:)`",
        "Cadence/Services/NoteReferenceSupport.swift `noteLinks(in:)`",
        "Cadence/Shared/CadenceRegularPaneLayout.swift `regularInspectorWidth(for:)`",
        "Cadence/Shared/CadenceRegularPaneLayout.swift `splits(width:sides:)`",
        "Cadence/Shared/CadenceSettingsSectionCopy.swift `sectionTitle(_:of:)`",
        "Cadence/Shared/Components/CadenceBoardColumnHeader.swift `kanbanColumnHeaderPadding()`",
        "Cadence/iOS/iOSCalendarView.swift `moveAnchor(by:)`",
        "Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift `readSelection(from:)`",
        "Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift `validateMenuItem(_:)`",
        "Cadence/macOS/Views/TasksPanel.swift `taskSections(derived:)`",
        "Cadence/macOS/Views/TasksPanelDerivedState.swift `isEmptyState(for:)`",
        "Cadence/macOS/Views/TasksPanelDropCoordinator.swift `taskDropHandler(scopeTasks:dropKey:)`",
        "CadenceTests/CadenceColorPaletteTests.swift `ranges(of:options:)`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `foo(_:)`",
        "CadenceTests/CadenceLaunchWiringTests.swift `unregisterForRemoteNotifications()`",
        "CadenceTests/CadenceSettingsSectionCopyTests.swift `sectionTitle(_:of:)`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `kanbanColumnHeaderPadding()`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `ranges(of:options:)`",
        "CadenceTests/CadenceTodayUnificationTests.swift `taskDropHandler(scopeTasks:dropKey:)`",
        "CadenceTests/MarkdownImagePasteTests.swift `readSelection(from:)`",
        "CadenceTests/TemporaryDefaultsSupport.swift `freshDefaults(_:)`",
        "CadenceTests/TemporaryDefaultsSupport.swift `someTestName()`",
        "CadenceTests/iOSCalendarMetricsTests.swift `hourLabel(_:)`"
    ]

    /// The two halves are one ledger and must not overlap or repeat.
    @Test func theLedgerIsWellFormed() {
        let tombstones = Self.deliberateTombstones
        let stale = Self.staleClaims
        #expect(Set(tombstones).count == tombstones.count)
        #expect(Set(stale).count == stale.count)
        #expect(Set(tombstones).isDisjoint(with: Set(stale)))
        #expect(tombstones == tombstones.sorted())
        #expect(stale == stale.sorted())
        #expect(tombstones.count == 32)
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

    /// The unqualified half ([[T-718]]): a call-shaped span with no type in front of it names
    /// something this repository calls, or it is ledgered.
    ///
    /// **What a green run here does and does not say.** It says no comment points at a bare call
    /// this tree never makes. It does **not** say the comment points at the right one: a name the
    /// repo calls *somewhere* resolves here even when the sentence is about a file that has no such
    /// thing, which is [[T-647]]'s own spelling and stays uncovered. That limit is the price of
    /// having one stable reading of the question — see `calledNames(inCode:)` for why the stricter
    /// reading was declined twice before this.
    @Test func everyUnqualifiedCallShapedClaimInACommentIsCalledSomewhereOrIsLedgered() throws {
        let sources = try Self.allSources()
        var text: [String: String] = [:]
        for source in sources { text[source.path] = source.text }

        let called = sources.reduce(into: Set<String>()) { names, source in
            names.formUnion(
                CadenceCommentSymbolClaim.calledNames(
                    inCode: CadenceCommentSymbolClaim.partition(source.text).code
                )
            )
        }
        // Non-vacuity for the index: an empty or tiny one makes every span below "unresolved" and
        // a merely large one could still be the wrong half of the partition. `save` is a call this
        // app makes 100+ times; `Cadence` is a type name, never a call, so a `called` set built
        // from raw text rather than code would hold it.
        #expect(called.count >= 2000, "the call index read \(called.count) names")
        #expect(called.contains("save"))

        let instrument = try CadenceScanInstrument(
            "comment names a call this repository never makes",
            fires: CadenceCommentSymbolClaim.unqualifiedPositiveWitness,
            andNotOn: CadenceCommentSymbolClaim.unqualifiedNegativeWitness
        ) { source in
            !CadenceCommentSymbolClaim.unresolvedUnqualifiedSpans(in: source, against: called).isEmpty
        }

        let offendingPaths = try instrument.sweep(
            sources.map(\.path),
            atLeast: 800,
            including: "Cadence/Shared/Theme.swift",
            read: { path in try Self.source(path, in: text) }
        )

        var found: [String] = []
        for path in offendingPaths {
            let spans = Set(CadenceCommentSymbolClaim.unresolvedUnqualifiedSpans(
                in: try Self.source(path, in: text),
                against: called
            ))
            found.append(contentsOf: spans.map { "\(path) `\($0)`" })
        }
        found.sort()

        let unlisted = found.filter { !Self.unqualifiedLedger.contains($0) }
        #expect(unlisted.isEmpty, "a comment names a call this repository never makes: \(unlisted)")
        let stale = Self.unqualifiedLedger.filter { !found.contains($0) }
        #expect(stale.isEmpty, "the unqualified ledger names a span that is no longer there: \(stale)")
        #expect(found == Self.unqualifiedLedger)
    }

    /// The unqualified ledger is sorted, unique, and does not overlap the qualified one.
    @Test func theUnqualifiedLedgerIsWellFormed() {
        let ledger = Self.unqualifiedLedger
        #expect(Set(ledger).count == ledger.count)
        #expect(ledger == ledger.sorted())
        #expect(ledger.count == 27)
        #expect(Set(ledger).isDisjoint(with: Set(Self.ledger)))
    }

    /// The selector spelling is the exclusion, and these are the three spans it subtracts.
    ///
    /// [[T-718]]'s loose reading carried them as separate problems; none of them is a call, and all
    /// three fall out of requiring canonical label syntax. Pinned so a widening of the pattern —
    /// "allow a value after the colon", "allow a bare argument" — cannot happen silently.
    @Test func onlyCanonicalSelectorSpellingCounts() {
        for span in ["nonisolated(unsafe)", "list_tasks(limit: 1)", "sidebarListItem(contextID: UUID)"] {
            #expect(
                CadenceCommentSymbolClaim.unqualifiedClaims(inComments: "/// `\(span)`").isEmpty,
                "\(span) is not a selector and must not be read as a call"
            )
        }
        for span in ["kanbanColumnHeaderPadding()", "readSelection(from:)", "splits(width:sides:)"] {
            #expect(
                CadenceCommentSymbolClaim.unqualifiedClaims(inComments: "/// `\(span)`").count == 1,
                "\(span) is a selector and must be read as a call"
            )
        }
        // Qualified spans stay the other half's business: this one must not double-report them.
        #expect(CadenceCommentSymbolClaim.unqualifiedClaims(inComments: "/// `Theme.accent(for:)`").isEmpty)
    }

    /// The call index is built from the **code** half, and a name that only ever appears in prose
    /// or in a string literal does not resolve.
    ///
    /// Without this the half would be silenced by its own subject matter: a comment naming
    /// something, in a file whose other comments name it too, would vouch for itself.
    @Test func theCallIndexReadsCodeAndNotProseOrLiterals() {
        let source = """
        /// The row calls `commentClaimGutterInset(for:)`, and this line is prose.
        enum CadenceCommentClaimGutterFixture {
            static let name = "commentClaimGutterInset(for:)"
        }
        """
        #expect(
            CadenceCommentSymbolClaim.unresolvedUnqualifiedSpans(in: source, against: [])
                == ["commentClaimGutterInset(for:)"]
        )
    }
}
