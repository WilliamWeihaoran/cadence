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
/// > **And since [[T-3209]], a root that names nothing is a finding of its own**: not a declared
/// > type, not a file base name, not an identifier the code spells, not a listed framework type,
/// > and not a literal value the app spells. That is the claim a rename or a deletion leaves
/// > behind, and the guard that used to drop it was blind in exactly the case it was built for.
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
/// - ~~**Bare names.**~~ A backticked camelCase identifier with no type and no call shape is
///   covered in **product** comments by a third sweep since [[T-7620]]: some code must spell it.
///   [[T-7552]]'s stale property name was this spelling and survived the other two. Test comments
///   are not swept yet, and the product ledger it landed with is grandfathered, not triaged.
/// - **SDK-rooted claims.** ``ModelContext.save()`` cannot be checked, because the repository
///   cannot enumerate a framework's members. Such a root is `uncheckable` — but only because the
///   code spells it; a root nothing spells is no longer assumed to be a framework type ([[T-3209]]).
/// - **A value root that happens to be spelled.** `task.title` is admitted by the grammar and
///   excused because `task` is an identifier in code. A stale root that collides with a live
///   variable name is excused the same way; that is the price of not keeping an SDK list.
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
    /// inside a string, a `"` inside a comment, and an interpolated closure. One traversal rather
    /// than two passes, for the reason recorded there: whichever pass runs second mishandles the
    /// delimiter the first one already consumed.
    ///
    /// **It is `codeOnly`'s walk because it was copied from it, and for eight days it was a copy
    /// of the wrong version ([[T-1571]]).** [[T-1328]] taught `codeOnly` to *parse* an
    /// interpolation rather than skip to the next quote; this function kept the old single "next
    /// unescaped quote" loop, and the sentence above went on claiming they were the same walk.
    /// Only the four ASCII fixtures separated them, and none of them holds an interpolation, so
    /// the pin was green over the divergence. What that cost, measured at the fix over all **977**
    /// `.swift` files in the five roots: the two readings disagreed on **131 lines in 64 files**,
    /// and on **one** of them — `Cadence/Services/MarkdownMetadataSupport.swift`, the one file in
    /// the tree that writes
    /// `"tags: [\(orderedUnique(tags).map { "\"\($0)\"" }.joined(separator: ", "))]"` — the
    /// old walk ended the outer literal at the *inner* literal's opening quote, blanked the
    /// closure's `{` and left its `}`. Brace depth came out **-1**, so `SymbolIndex.build` closed
    /// `MarkdownMetadataParser` 237 lines early and indexed **24** of the 57 names inside it —
    /// none of the thirteen members declared below that line, `headingPrefixRegex` among them.
    /// The sweep then reported a correct comment naming one of them as resolving to nothing. The
    /// other 63 files leaked a nested literal's *content* as apparent code, which feeds
    /// `calledNames(inCode:)` names the tree never calls. After the fix all 977 balance and the
    /// new reading is a strict **superset** on that type: 57 names, none lost.
    ///
    /// The lesson is the pin, not the lexer: a copy of a walk needs a fixture for every shape the
    /// original was *fixed* for, or it silently reverts to the bug the original was fixed from.
    /// `theCodeHalfOfThePartitionIsTheAuditedReader` now carries that shape, and
    /// `theInterpolatedClosureDoesNotCloseTheTypeThatHoldsIt` reads it end to end.
    ///
    /// The `comments` half is the whole reason this exists. `codeOnly` blanks comments *and*
    /// literals, and `strippingComments` blanks only comments — neither hands back the prose, and a
    /// detector that reads prose out of raw source would count its own fixtures as findings.
    static func partition(_ source: String) -> (code: String, strings: String, comments: String) {
        partitionCache.value(for: source, derive: partitionUncached)
    }

    /// [[T-3261]]: each sweep re-partitioned the whole corpus; see `CadenceSourceDerivationCache`.
    private static let partitionCache = CadenceSourceDerivationCache<(code: String, strings: String, comments: String)>()

    private static func partitionUncached(_ source: String) -> (code: String, strings: String, comments: String) {
        let characters = Array(source)
        let count = characters.count
        var kind = [Region](repeating: .code, count: count)

        func mark(_ range: Range<Int>, _ region: Region) {
            for position in range where position < count { kind[position] = region }
        }

        // The length of the `#` run that opens a *raw* literal here, or `nil` when the run is
        // something else entirely (`#if`, `#expect(`, `#filePath`).
        func rawLiteralHashes(at position: Int) -> Int? {
            var hashEnd = position
            while hashEnd < count, characters[hashEnd] == "#" { hashEnd += 1 }
            guard hashEnd < count, characters[hashEnd] == "\"" else { return nil }
            return hashEnd - position
        }

        /// Marks the literal opening at `start` — whose `#` run is `hashes` long — and returns the
        /// index just past it. Interpolated code inside it is handed to `scanCode` so that its own
        /// literals and comments are read properly, and is then marked `.string` **whole**, which
        /// is what keeps this function's `code` half equal to `codeOnly`'s output.
        func scanLiteral(from start: Int, hashes: Int) -> Int {
            let quoteStart = start + hashes
            let multiline = quoteStart + 2 < count
                && characters[quoteStart + 1] == "\""
                && characters[quoteStart + 2] == "\""
            let quotes = multiline ? 3 : 1
            var position = quoteStart + quotes
            mark(start..<min(position, count), .string)

            while position < count {
                // The terminator carries the literal's own run of `#`.
                if characters[position] == "\"",
                   position + quotes + hashes <= count,
                   (position..<(position + quotes)).allSatisfy({ characters[$0] == "\"" }),
                   ((position + quotes)..<(position + quotes + hashes)).allSatisfy({ characters[$0] == "#" }) {
                    let close = position + quotes + hashes
                    mark(position..<close, .string)
                    return close
                }
                // A single-line literal cannot span a newline; stopping here keeps an unterminated
                // one from swallowing the rest of the file.
                if !multiline, characters[position].isNewline {
                    return position
                }
                // An escape, which in a raw literal is `\` followed by that literal's run of `#`
                // — so a lone `\` inside `#"…"#` falls through to the content case below.
                if characters[position] == "\\",
                   position + 1 + hashes < count,
                   ((position + 1)..<(position + 1 + hashes)).allSatisfy({ characters[$0] == "#" }) {
                    let escaped = position + 1 + hashes
                    if characters[escaped] == "(" {
                        let terminator = scanCode(from: escaped + 1, stoppingAtUnmatchedCloseParen: true)
                        let close = min(terminator + 1, count)
                        mark(position..<close, .string)
                        position = close
                        continue
                    }
                    mark(position..<(escaped + 1), .string)
                    position = escaped + 1
                    continue
                }
                mark(position..<(position + 1), .string)
                position += 1
            }
            return count
        }

        /// Marks literals and comments from `start` on. With `stoppingAtUnmatchedCloseParen` it
        /// returns the index **of** the first `)` closing no `(` of its own — the end of the
        /// interpolation that called it — for the caller to mark; otherwise it runs to the end.
        func scanCode(from start: Int, stoppingAtUnmatchedCloseParen: Bool) -> Int {
            var index = start
            var parentheses = 0
            while index < count {
                let character = characters[index]

                if character == "#", let hashes = rawLiteralHashes(at: index) {
                    index = scanLiteral(from: index, hashes: hashes)
                    continue
                }
                if character == "\"" {
                    index = scanLiteral(from: index, hashes: 0)
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
                // Counted after the literal and comment branches, so a parenthesis inside either
                // is never seen: those branches consume their whole span before this reads it.
                if stoppingAtUnmatchedCloseParen {
                    if character == "(" {
                        parentheses += 1
                    } else if character == ")" {
                        if parentheses == 0 { return index }
                        parentheses -= 1
                    }
                }

                index += 1
            }
            return count
        }

        _ = scanCode(from: 0, stoppingAtUnmatchedCloseParen: false)

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
    static let identifierPattern = "\\b([A-Za-z_][A-Za-z0-9_]*)\\b"

    /// An **implicit member expression**: a leading-dot name written where an argument, a value
    /// or an element starts — after `:`, `(`, `,`, `=` or `[` — so the type it belongs to is the
    /// contextual one, never spelled. `cursor: .arrow` is the measured case ([[T-3271]]). Such a
    /// spelling names a case or a static member, and a member is not a root: it cannot vouch for
    /// the root of an SF Symbol path that happens to start with the same word. Anything else
    /// before the dot (an explicit receiver, a chain continued on the next line, a `return`) is left alone,
    /// so the narrowing only ever moves a verdict the way the ticket asked.
    static let implicitMemberPattern = "[:(,=\\[]\\s*\\.([A-Za-z_][A-Za-z0-9_]*)\\b"

    /// The content of every single-line literal in a `strings` half. Interpolations are kept as
    /// written, so a literal holding one never equals a backticked span — which is the safe way
    /// round: it can only leave a span to be judged, never excuse one.
    static func literalContents(inStrings strings: String) -> Set<String> {
        Set(CadenceSourceScan.captures("\"([^\"\\n]+)\"", in: strings).map(\.text))
    }

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
        /// Every identifier the **code** half spells, at any position ([[T-3209]]). What the root
        /// verdict asks of a name the tree does not declare: a framework type this app uses, or a
        /// value a span is rooted on (`task.title`, `self.order`), is spelled in code somewhere;
        /// a type that was renamed or deleted is not. The same trade `calledNames(inCode:)` makes,
        /// for the same reason — it dissolves the SDK allowlist instead of maintaining one.
        var codeIdentifiers: Set<String> = []
        /// How many times the code spells each identifier, and how many of those are implicit
        /// member expressions (`implicitMemberPattern`). A name whose every spelling is one of
        /// the latter is an enum case or static member only, and `vouchesForRoot` refuses it
        /// ([[T-3271]]). Counts, not sets, so merging a fixture's index into the tree's stays exact.
        var identifierCounts: [String: Int] = [:]
        var implicitMemberCounts: [String: Int] = [:]

        /// Whether the code spells `name` at least once as something other than an implicit
        /// member: what the root verdict asks of a root the tree does not declare.
        func vouchesForRoot(_ name: String) -> Bool {
            (identifierCounts[name] ?? 0) > (implicitMemberCounts[name] ?? 0)
        }
        /// Every single-line string literal's content, whole. A backticked `tray.fill` or
        /// `com.haoranwei.Cadence` is a *value* the tree spells in a literal, not a symbol claim,
        /// and this is what tells the root verdict so without a list of SF Symbols ([[T-3209]]).
        var literals: Set<String> = []
        /// Every `typealias` name. A root that is an alias (`CadenceContextPickerSupport` is
        /// `CadencePickerSupport<Context>`) has its members on another declaration, possibly a
        /// generic one, so a claim rooted on it is uncheckable rather than missing ([[T-3209]]).
        var typeAliases: Set<String> = []

        /// The whole index for whole sources: partitions each once, indexes the code half, and
        /// reads the literals off the strings half. The sweeps use this; fixtures that only have
        /// code use `build(from:)`.
        static let literalExcludedRoots = ["CadenceTests/", "CadenceUITests/"]

        static func build(fromSources sources: [(path: String, text: String)]) -> SymbolIndex {
            var index = SymbolIndex()
            var files: [(path: String, code: String)] = []
            for source in sources {
                let regions = partition(source.text)
                files.append((path: source.path, code: regions.code))
                // Product literals only. A test spells a stale name as a *needle* constantly —
                // `source.contains("iOSFoo.bar")` — and a needle must not vouch for the claim it
                // is hunting; measured on the first run, when this suite's own expected-value
                // literal excused the deleted-root witness it was asserting about.
                if !literalExcludedRoots.contains(where: { source.path.hasPrefix($0) }) {
                    index.literals.formUnion(literalContents(inStrings: regions.strings))
                }
            }
            return index.merging(build(from: files))
        }

        static func build(from files: [(path: String, code: String)]) -> SymbolIndex {
            var index = SymbolIndex()
            for file in files {
                let code = file.code
                for capture in CadenceSourceScan.captures(identifierPattern, in: code) {
                    index.codeIdentifiers.insert(capture.text)
                    index.identifierCounts[capture.text, default: 0] += 1
                }
                for capture in CadenceSourceScan.captures(implicitMemberPattern, in: code) {
                    index.implicitMemberCounts[capture.text, default: 0] += 1
                }
                for capture in CadenceSourceScan.captures("\\btypealias\\s+([A-Za-z_][A-Za-z0-9_]*)", in: code) {
                    index.typeAliases.insert(capture.text)
                }
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
            merged.codeIdentifiers.formUnion(other.codeIdentifiers)
            merged.identifierCounts.merge(other.identifierCounts, uniquingKeysWith: +)
            merged.implicitMemberCounts.merge(other.implicitMemberCounts, uniquingKeysWith: +)
            merged.literals.formUnion(other.literals)
            merged.typeAliases.formUnion(other.typeAliases)
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
        "entitlements", "ts", "txt", "png", "xcassets",
        // [[T-3209]]: `SecTask.h`, `iPhoneOS.sdk`, `CoreBuildSystem.xcspec` became visible to the
        // root verdict once an undeclared root stopped being dropped, and are file names too.
        "h", "sdk", "xcspec", "framework",
        // [[T-7381]]: `Assets.car` is the compiled asset catalog an app bundle carries.
        "car"
    ]

    /// Every backticked span in `comments` that reads as `Type.member`.
    ///
    /// A span containing `*` is skipped: this repo writes ``CadencePendingChangePersistence.commit*``
    /// on purpose, to name a family rather than a member, and a glob is not a claim about one
    /// declaration.
    ///
    /// **The root may begin lowercase ([[T-3209]]).** Both arms used to anchor on `[A-Z]`, which
    /// left every `iOS*` type — 504 of the tree's nominal types on 2026-10-17 — unparseable here
    /// and, being qualified, never handed to the unqualified half either. A lowercase root is now
    /// a claim like any other; what a root *resolves to* is `verdict(of:in:)`'s question, not the
    /// grammar's, so a value root such as `task.title` is admitted here and excused there.
    static let qualifiedSpelling = "^([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)"

    static func claims(inComments comments: String) -> [Claim] {
        CadenceSourceScan.captures("`([^`\\n]+)`", in: comments).compactMap { capture in
            let span = capture.text
            guard !span.contains("*") else { return nil }
            guard let parsed = CadenceSourceScan.captures(
                qualifiedSpelling,
                in: span,
                group: 1
            ).first else { return nil }
            let member = CadenceSourceScan.captures(
                qualifiedSpelling,
                in: span,
                group: 2
            ).first
            guard let member else { return nil }
            guard !fileExtensions.contains(member.text) else { return nil }
            return Claim(span: span, type: parsed.text, member: member.text)
        }
    }

    /// What a qualified claim's root and member resolve to ([[T-3209]]).
    ///
    /// **Why there are four answers and not two.** The sweep used to ask one question — *is the
    /// member declared on the root?* — and answered "not my business" for every root the tree
    /// does not declare, on the theory that such a root is an SDK type nobody can enumerate. That
    /// silently excused exactly the claim most likely to be stale: one naming a type that was
    /// **renamed or deleted**. Three such comments survived twelve passes of [[T-3170]].
    ///
    /// - `resolves`: the member is declared on the root type, or in the file the root names.
    /// - `memberMissing`: the root is a declared type **or a file base name with a file behind
    ///   it**, and the member is declared on neither. The offender the ledger has always held.
    /// - `rootUnresolvable`: the root is not a declared type, not a file base name, not spelled
    ///   anywhere in the tree's code (where every framework type this app uses is spelled) other
    ///   than as an implicit member expression ([[T-3271]]), not a
    ///   framework type in `frameworkRootsNamedButNeverSpelled`, and the span is a pure symbol
    ///   path rather than a literal value the tree spells. **Nothing at the other end of it.**
    /// - `uncheckable`: everything else — a typealias, or a framework or value root whose members
    ///   the tree cannot enumerate, a span that is an expression rather than a name, or a literal value.
    enum Verdict: Equatable {
        // One case per line: `memberPattern` reads the first name after `case`, and this doc names
        // each of them qualified.
        case resolves
        case memberMissing
        case rootUnresolvable
        case uncheckable
    }

    /// A span that is a symbol path and nothing else: dotted identifiers, then optionally a
    /// selector's label list. `X.isEmpty ? a : b`, `dayTasks.filter { … }` and `MacOSX.sdk/System`
    /// are not — they are expressions or paths, and only a name can be judged to name nothing.
    static let symbolPathSpelling =
        "^[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)+(?:\\((?:(?:[A-Za-z_][A-Za-z0-9_]*|_):)*\\))?$"

    /// Framework types this tree's comments name but whose name its code never spells — so
    /// `codeIdentifiers` cannot vouch for them. The residue of the SDK allowlist the root verdict
    /// otherwise dissolves, the same trade [[T-999]] priced for the unqualified half; each entry
    /// is pinned absent from both the declarations and the code by
    /// `theFrameworkRootsAreNeitherDeclaredNorSpelled`, so one the app starts using goes stale.
    static let frameworkRootsNamedButNeverSpelled: Set<String> = [
        // SwiftUI: the app reads the phase through `onScrollPhaseChange`'s closure, never by name.
        "ScrollPhase",
        // SwiftUI: a `Canvas` closure's parameter, never named by its type.
        "GraphicsContext",
        // SwiftData: caught as `any Error` and described, never named.
        "SwiftDataError",
    ]

    static func verdict(of claim: Claim, in world: SymbolIndex) -> Verdict {
        if world.nominalTypes.contains(claim.type) {
            guard !synthesizedMembers.contains(claim.member) else { return .resolves }
            guard world.membersByType[claim.type]?.contains(claim.member) != true else { return .resolves }
            // File-qualified, and only when the file has exactly one non-private nominal type
            // ([[T-717]]): a second *public* type sharing the file has to say which one it means,
            // so the exclusion no longer covers that case — private helper types stay uncounted,
            // because they are exactly what the convention is for.
            if world.namesByFileBaseName[claim.type]?.contains(claim.member) == true,
               world.publicNominalTypesByFileBaseName[claim.type]?.count == 1 {
                return .resolves
            }
            return .memberMissing
        }
        if world.typeAliases.contains(claim.type) { return .uncheckable }
        // `<FileBaseName>.<symbol>` for a file that declares no type of its own name
        // (`iOSCalendarBoardView.swift` declares `iOSCalendarBoardPlanner`). The convention makes
        // that a legitimate spelling, so it is checked against the file rather than dropped.
        if let names = world.namesByFileBaseName[claim.type] {
            guard !synthesizedMembers.contains(claim.member) else { return .resolves }
            return names.contains(claim.member) ? .resolves : .memberMissing
        }
        if world.vouchesForRoot(claim.type) { return .uncheckable }
        if frameworkRootsNamedButNeverSpelled.contains(claim.type) { return .uncheckable }
        guard claim.span.range(of: symbolPathSpelling, options: .regularExpression) != nil else {
            return .uncheckable
        }
        // A file name (`com.haoranwei.Cadence.plist`) is a path whatever its root.
        if let last = claim.span.split(separator: ".").last, fileExtensions.contains(String(last)) {
            return .uncheckable
        }
        if world.literals.contains(claim.span) { return .uncheckable }
        return .rootUnresolvable
    }

    /// Every claim in one file with its verdict, read against the tree plus the file's own
    /// declarations and identifiers.
    ///
    /// Merging the file's own index in is what lets a literal fixture stand alone: the witnesses
    /// `CadenceScanInstrument` checks declare their own type, so the detector answers the same
    /// question for a five-line fixture and for a 900-line screen.
    static func verdicts(in source: String, against index: SymbolIndex) -> [(span: String, verdict: Verdict)] {
        let regions = partition(source)
        // Not the file's own literals: a product file's are in `index` already, and a test file's
        // are needles (see `literalExcludedRoots`).
        let world = index.merging(SymbolIndex.build(from: [(path: "", code: regions.code)]))
        return claims(inComments: regions.comments).map { (span: $0.span, verdict: verdict(of: $0, in: world)) }
    }

    /// The offending spans in one file: a declared root, or a file, without the member.
    static func offendingSpans(in source: String, against index: SymbolIndex) -> [String] {
        verdicts(in: source, against: index).filter { $0.verdict == .memberMissing }.map(\.span)
    }

    /// The spans in one file whose root names nothing at all ([[T-3209]]).
    static func unresolvableRootSpans(in source: String, against index: SymbolIndex) -> [String] {
        verdicts(in: source, against: index).filter { $0.verdict == .rootUnresolvable }.map(\.span)
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

    // MARK: - The bare half (T-7620)

    /// A backticked span that is ONE camelCase identifier and nothing else: a lowercase or `_`
    /// head, then at least one capital. The shape a property, a local or a case is written in.
    ///
    /// **Why this half exists.** [[T-7552]]'s stale comment named a deleted property bare, so it
    /// was neither `Type.member` (the qualified half) nor `name(labels:)` (the unqualified half),
    /// and a mutation restoring it SURVIVED both. The capital is what keeps English words and
    /// keywords out without a list: `count`, `body`, `self` and `nil` cannot match.
    static let bareIdentifierSpelling = "^[a-z_][a-z0-9_]*[A-Z][A-Za-z0-9_]*$"

    /// `en_US`, `ja_JP`: a locale identifier is camel-shaped by accident and is a value, not a
    /// symbol, so the grammar subtracts it rather than the ledger carrying one line per locale.
    static let localeIdentifierSpelling = "^[a-z]{2,3}_[A-Z]{2}$"

    static func bareClaims(inComments comments: String) -> [String] {
        CadenceSourceScan.captures("`([^`\\n]+)`", in: comments).map(\.text).filter { span in
            span.range(of: bareIdentifierSpelling, options: .regularExpression) != nil
                && span.range(of: localeIdentifierSpelling, options: .regularExpression) == nil
        }
    }

    /// The bare spans in one file that name nothing: not an identifier any code spells, not a
    /// file base name, and not a product string literal.
    ///
    /// **The weakest stable question, on purpose.** "Does the code spell this anywhere" has one
    /// reading, exactly as `calledNames(inCode:)` does for the unqualified half, and it answers a
    /// deletion: once the last declaration and use of a name go, every comment still naming it
    /// lands here. Test literals do not vouch (`SymbolIndex.literalExcludedRoots`): the tests that
    /// pin a deleted name absent spell it as a needle, and [[T-7552]]'s own name is one of them.
    static func unresolvedBareSpans(in source: String, against index: SymbolIndex) -> [String] {
        let regions = partition(source)
        let own = Set(CadenceSourceScan.captures(identifierPattern, in: regions.code).map(\.text))
        return bareClaims(inComments: regions.comments).filter { span in
            !index.codeIdentifiers.contains(span)
                && !own.contains(span)
                && index.namesByFileBaseName[span] == nil
                && !index.literals.contains(span)
        }
    }

    // MARK: - Witnesses

    /// A bare span naming something no code spells: the shape [[T-7552]] left behind.
    static let barePositiveWitness = """
    /// The editor is put back by `commentClaimRetiredObserver` when the finger lifts.
    enum CadenceCommentClaimBareFixture {
        static let inset = 4.0
    }
    """

    /// The nearest possible miss: the same sentence over a file that still declares the name.
    static let bareNegativeWitness = """
    /// The editor is put back by `commentClaimRetiredObserver` when the finger lifts.
    enum CadenceCommentClaimBareFixture {
        static let commentClaimRetiredObserver = 4.0
    }
    """

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

    /// A claim rooted on a type nothing in the tree declares or spells ([[T-3209]]) — the shape a
    /// rename leaves behind. Its root appears in this file only inside string literals.
    static let rootPositiveWitness = """
    /// The row draws through `CadenceCommentClaimRetiredFixture.render`.
    enum CadenceCommentClaimWidgetFixture {
        static let title = "Widget"
    }
    """

    /// The nearest possible miss: the same sentence, in a tree where that type exists.
    static let rootNegativeWitness = """
    /// The row draws through `CadenceCommentClaimRetiredFixture.render`.
    enum CadenceCommentClaimRetiredFixture {
        static let render = "Widget"
    }
    """

    /// A claim about a member the type does not have. `render` is nowhere in the tree.
    static let positiveWitness = """
    /// The row draws through `CadenceCommentClaimWidgetFixture.render`.
    enum CadenceCommentClaimWidgetFixture {
        static let title = "Widget"
    }
    """

    /// The nearest possible miss: the same sentence about the member that is actually there —
    /// **declared below an interpolated closure** ([[T-1571]]).
    ///
    /// The second half is the lexer trap, and it is in the *negative* witness on purpose. A
    /// `partition` that reverts to skipping an interpolation ends this type's body at the literal,
    /// never indexes `title`, and therefore reports this correct sentence as an offender — which
    /// `CadenceScanInstrument` turns into `Failure.overreaching` before the sweep runs at all.
    /// That is a named failure at the instrument, rather than one unattributable ledger line
    /// somewhere in the tree, which is exactly how [[T-1571]] presented itself.
    ///
    /// Measured on this fixture rather than assumed: the pre-fix walk left it at brace depth
    /// **-1** and indexed 1 of its 2 members; the fixed walk leaves it at **0** and indexes both.
    static let negativeWitness = """
    /// The row draws through `CadenceCommentClaimWidgetFixture.title`.
    enum CadenceCommentClaimWidgetFixture {
        static func tagLine(_ tags: [String]) -> String {
            "tags: [\\(tags.map { "\\"\\($0)\\"" }.joined(separator: ", "))]"
        }
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

    /// The `code` half is `CadenceSourceScan.codeOnly`, character for character, on the six inputs
    /// that separate a correct lexer from a plausible one.
    ///
    /// **The sixth was added by [[T-1571]], and its absence is the whole of why that ticket
    /// existed.** The first four are ASCII and interpolation-free, so this pin stayed green for
    /// eight days over a `partition` that had never learned what [[T-1328]] taught `codeOnly`.
    /// An input list for a copied walk is a claim about which shapes the two agree on, not a
    /// spot check.
    ///
    /// **The equality is SCOPED TO SINGLE-SCALAR TEXT, and that is deliberate as of [[T-1590]].**
    /// Every input below is one scalar per `Character`, and on such text the two walks agree
    /// exactly. They do not agree on anything else, and cannot: `partition`'s `extract` emits one
    /// `Character` per `Character` while `codeOnly` ends in `blankedSpansAsSpaces`, which [[T-1338]]
    /// deliberately changed to emit one space per unicode SCALAR so that the Swift pass and the
    /// Python `blank()` in `scripts/test-suite-index.sh` agree on column offsets. The scoping is
    /// not a hedge written into a comment — `theTwoBlankingPassesAgreeOnlyWhileAGraphemeIsOneScalar`
    /// below measures the divergence, and
    /// `CadenceGuardScriptSelftestTests.noSourceFileHoldsAMultiScalarGraphemeTheTwoBlankingPassesWouldSpellDifferently`
    /// is what holds the tree inside the scope.
    @Test func theCodeHalfOfThePartitionIsTheAuditedReader() {
        let inputs = [
            "let url = \"https://example.com\" // trailing\nlet x = 1\n",
            "let raw = #\"photo\\\"# // after\nlet y = 2\n",
            "/* a \" quote inside a block comment */ let z = 3\n",
            "let doc = \"\"\"\n// not a comment\n\"\"\"\nlet w = 4\n",
            CadenceCommentSymbolClaim.positiveWitness,
            // T-1571: the shape the two walks diverged on for eight days. Without it here, this
            // pin is green over a `partition` that reverts to T-1328's bug.
            CadenceCommentSymbolClaim.negativeWitness
        ]
        for input in inputs {
            let regions = CadenceCommentSymbolClaim.partition(input)
            #expect(regions.code == CadenceSourceScan.codeOnly(input), "diverged on: \(input)")
        }
    }

    /// **T-1590, measured rather than reasoned: exactly where the pin above stops being true, and
    /// which contract each side owes.**
    ///
    /// The two functions have INCOMPATIBLE contracts, which is why this is a pinned divergence and
    /// not a one-line repair:
    ///
    /// * `thePartitionCoversEveryCharacterExactlyOnce` compares the three halves position by
    ///   position against `Array(source)` and asserts `code.count == original.count` in
    ///   `Character` terms. The scalar spelling breaks it.
    /// * `codeOnly`'s callers — `declarationBody`, `declarationExtents`, `typeExtents` and the
    ///   `blank()` mirror in `scripts/test-suite-index.sh` — need the scalar one, because a column
    ///   offset shared with a Python pass is counted in code points ([[T-1338]]).
    ///
    /// **Deliberately left diverging.** Closing it means picking which contract `partition` owes
    /// and re-reading every assertion leaning on the other, which is not proportionate to a class
    /// with zero members — and [[T-1489]] is the precedent for writing the reasoning down instead.
    /// What T-1590 asked for is *"state in `theCodeHalfOfThePartitionIsTheAuditedReader` that its
    /// equality is scoped to single-scalar inputs and add a fixture proving the scoping is
    /// deliberate"*, and this is that fixture. It also does what prose alone cannot: if somebody
    /// later makes the two agree, this goes red and points at the decision rather than letting the
    /// scoping note rot into a false sentence — which is [[T-1571]]'s whole lesson about two
    /// copies of one walk held together by an assertion that they are the same.
    ///
    /// The tripwire is named and it is NOT the one T-1590 cited:
    /// `CadenceGuardScriptSelftestTests.noSourceFileHoldsAMultiScalarGraphemeTheTwoBlankingPassesWouldSpellDifferently`.
    /// The ticket named `noSourceFileWritesAJoiningScalarOntoASyntacticCharacter`, which is
    /// T-1338's narrower class and which explicitly asserts that `"cafe\u{301}"` — T-1590's own
    /// worked example — must NOT fire it.
    @Test func theTwoBlankingPassesAgreeOnlyWhileAGraphemeIsOneScalar() {
        // A combining acute inside a string literal: 14 `Character`s, 15 unicode scalars. The
        // exact pair T-1590 measured on 2026-09-29.
        let acute = "let s = \"cafe\u{301}\"\n"
        #expect(acute.count == 15, "the fixture is \(acute.count) characters")          // 14 + newline
        #expect(acute.unicodeScalars.count == 16, "the fixture is \(acute.unicodeScalars.count) scalars")

        let partitioned = CadenceCommentSymbolClaim.partition(acute).code
        let blanked = CadenceSourceScan.codeOnly(acute)

        // Each side keeps its OWN contract, and the contracts are what disagree.
        #expect(partitioned.count == acute.count,
                "partition stopped owing a Character-for-Character reading; thePartitionCoversEveryCharacterExactlyOnce leans on it")
        #expect(blanked.unicodeScalars.count == acute.unicodeScalars.count,
                "codeOnly stopped owing a scalar-for-scalar reading; scripts/test-suite-index.sh's blank() leans on it")

        // ...and therefore the pin above cannot hold here. Asserted as an inequality on purpose:
        // the day this becomes an equality, somebody has changed one of the two contracts and
        // owes the other side's callers an answer.
        #expect(partitioned != blanked,
                "the two blanking passes now agree on a multi-scalar grapheme; re-read T-1590 before deleting this")
        #expect(partitioned.count == 15)
        #expect(blanked.count == 16)

        // A ZWJ family emoji, the wider end of the same measurement, so the fixture is not one
        // cherry-picked scalar: 11 against 15 in the ticket's own figures, before the newline.
        let family = "let s = \"\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\"\n"
        let familyPartitioned = CadenceCommentSymbolClaim.partition(family).code
        let familyBlanked = CadenceSourceScan.codeOnly(family)
        #expect(familyPartitioned.count == family.count)
        #expect(familyBlanked.count == family.unicodeScalars.count)
        // Non-vacuity for the pair above: the fixture really is a five-scalar cluster, so the two
        // counts are four apart rather than equal by accident.
        #expect(family.unicodeScalars.count - family.count == 4,
                "the ZWJ family fixture is \(family.unicodeScalars.count - family.count) scalars wider than it is characters, not 4")
        #expect(familyPartitioned.count < familyBlanked.count)

        // Non-vacuity for all of it: on single-scalar text the two are identical, which is the
        // scope `theCodeHalfOfThePartitionIsTheAuditedReader` really pins.
        let ascii = "let s = \"cafe\" // note\n"
        #expect(CadenceCommentSymbolClaim.partition(ascii).code == CadenceSourceScan.codeOnly(ascii))
    }

    /// **T-1571, end to end: an interpolated closure must not close the type that holds it.**
    ///
    /// `theCodeHalfOfThePartitionIsTheAuditedReader` compares two strings; this asserts the
    /// *consequence* the comparison stands in for, because that is the sentence T-1571's three
    /// filings all got wrong. The claim is not "the lexer is nicer" — it is that a member declared
    /// below a line of this shape is **findable**, and it is made against the real file as well as
    /// the fixture, so a future `partition` that passes the fixture and fails the tree is caught.
    ///
    /// The refuted leads are worth keeping written down, because two agents spent a run each on
    /// them: it is **not** that the reader cannot see a `nonisolated static let` (`memberPattern`
    /// matches `let headingPrefixRegex` fine), and **not** that a top-level `nonisolated enum`
    /// fails `isTopLevelDeclaration` (`MarkdownMetadataParser.splitFrontmatter` is claimed in a
    /// comment elsewhere in the tree and has always resolved). The defect was **positional**, and
    /// position is what this test reads.
    @Test func theInterpolatedClosureDoesNotCloseTheTypeThatHoldsIt() throws {
        func braceDepth(_ code: String) -> Int {
            code.reduce(into: 0) { depth, character in
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
            }
        }

        // The fixture first: the whole shape in seven lines.
        let witness = CadenceCommentSymbolClaim.negativeWitness
        #expect(witness.contains(".map { "), "non-vacuity: the witness lost the closure it exists for")
        let witnessCode = CadenceCommentSymbolClaim.partition(witness).code
        #expect(braceDepth(witnessCode) == 0)
        let witnessIndex = CadenceCommentSymbolClaim.SymbolIndex.build(
            from: [(path: "Witness.swift", code: witnessCode)]
        )
        #expect(
            witnessIndex.membersByType["CadenceCommentClaimWidgetFixture"]?.contains("title") == true,
            "the member below the interpolated literal was not indexed"
        )

        // Then the file the sweep actually accused, read by literal path rather than walked.
        let path = "Cadence/Services/MarkdownMetadataSupport.swift"
        let source = try CadenceSourceScan.sourceFile(path)
        #expect(
            source.contains("let tagLine = \"tags: [\\(orderedUnique(tags).map {"),
            "non-vacuity: \(path) no longer writes the line this test is about"
        )
        let code = CadenceCommentSymbolClaim.partition(source).code
        #expect(braceDepth(code) == 0, "\(path) does not balance after partitioning")

        let index = CadenceCommentSymbolClaim.SymbolIndex.build(from: [(path: path, code: code)])
        let members = index.membersByType["MarkdownMetadataParser"] ?? []
        // One declared before the bad line and one after it, so a reader that indexes nothing and
        // a reader that stops at the literal both fail, and for different reasons.
        #expect(members.contains("splitFrontmatter"))
        #expect(members.contains("headingPrefixRegex"),
                "the members below the interpolated literal are invisible to the sweep again")

        // And the accusation itself: the comment that was reported is clean against that index.
        let claimant = try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownFormatCommandSupport.swift")
        #expect(claimant.contains("`MarkdownMetadataParser.headingPrefixRegex`"),
                "non-vacuity: the comment T-1571 was filed about is gone")
        #expect(
            CadenceCommentSymbolClaim.offendingSpans(in: claimant, against: index)
                .contains("MarkdownMetadataParser.headingPrefixRegex") == false
        )
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

        // A root the tree does not declare is not a MEMBER offender — it is [[T-3209]]'s own
        // verdict, which this fixture tree reports through the other door.
        #expect(fires("`NotATypeInThisTree.render`") == false)
        #expect(CadenceCommentSymbolClaim.unresolvableRootSpans(
            in: "/// `NotATypeInThisTree.render`\nlet unused = 0\n",
            against: index
        ) == ["NotATypeInThisTree.render"])
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
        "Cadence/Shared/CadenceRegularPaneLayout.swift `iOSCalendarView.regularInspectorWidth(for:)`",
        "Cadence/Shared/CadenceTaskDateEditing.swift `iOSTaskDetailSheet.applyDates()`",
        "Cadence/Shared/CadenceTodayPresentationSupport.swift `TasksPanel.emptyStateSection`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SettingsAISection.settingsField`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "Cadence/Shared/Components/CadenceSidebarCountLabel.swift `SidebarMetrics.countFontSize`",
        "Cadence/Shared/Components/CadenceSidebarCountLabel.swift `iOSSidebarMetrics.countFontSize`",
        "Cadence/iOS/iOSCalendarMetrics.swift `CadencePageHeaderMetrics.iconSize`",
        "Cadence/iOS/iOSCalendarMetrics.swift `iOSSchedulePanel.rowHeight`",
        "Cadence/iOS/iOSListNotesView.swift `CadenceListNoteSupport.firstOrCreateNote`",
        "Cadence/iOS/iOSSchedulePanelCopy.swift `CadenceTodayPresentationSupport.emptyScheduleHint`",
        "Cadence/iOS/iOSTaskCollectionPage.swift `iOSAllTasksView.allTasksPanel`",
        "Cadence/iOS/iOSTaskCollectionPage.swift `iOSInboxView.inboxColumn`",
        "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift `SchedulingActions.createTask`",
        "Cadence/macOS/Views/SettingsSupportViews.swift `SidebarTabEditorSheet.settingsPanelRow`",
        "Cadence/macOS/Views/SettingsTemplatesSection.swift `SettingsAISection.settingsField`",
        "Cadence/macOS/Views/TasksPanelDerivedState.swift `TasksPanel.emptyStateSection`",
        "Cadence/macOS/Views/TasksPanelSupport.swift `TasksPanel.taskSections`",
        "CadenceMCPServer/CadenceMCPToolDefinitions.swift `CadenceGoalSummary.subGoalCount`",
        "CadenceMCPServer/CadenceMCPToolDefinitions.swift `CadenceGoalSummary.taskCount`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `iOSCalendarTimelineGrid.formBundle`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `CadenceTodayPresentationSupport.emptyScheduleHint`",
        "CadenceTests/CadenceNoteFolderSurfaceTests.swift `CadenceListNoteSupport.firstOrCreateNote`",
        "CadenceTests/CadenceNoteFolderSurfaceTests.swift `ListNotesView.normalizedFolderPath`",
        "CadenceTests/CadenceNoteTitleSyncSurfaceTests.swift `NoteEditorPane.syncTitleFromH1IfNeeded`",
        "CadenceTests/CadenceRecurrenceScopeCommitTests.swift `iOSTaskDetailSheet.apply(_:scope:)`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `CadenceNoteFolderSupport.createNote`",
        // T-1091. Named as an *example of the defect being fixed* — a declaration the old filing
        // attributed to the last type declared above it rather than the type containing it: that
        // method belongs to the migration service, while the type it is credited to is a private
        // struct declared ten lines above it. Written unqualified on purpose — spelling it as a
        // qualified claim here would make this comment an unresolvable claim, which the rule
        // would then flag.
        //
        // **A second line stood here and was never a finding ([[T-1571]]).** The same comment
        // names `MarkdownMetadataParser.parseFrontmatter`, and that resolves: `membersByType` is
        // a deliberate superset with no access filter, so a `private` member of an indexed type
        // has always been findable. It was ledgered because `partition` closed that type 237
        // lines early on an interpolated literal, which is [[T-1328]]'s bug surviving in this
        // file's copy of the walk. Removing the line is the whole of the change; nothing about
        // the comment or the declaration moved. The irony is on the record: the sentence that
        // entry accused is the one explaining that T-1328 fixed this exact shape in `codeOnly`.
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `MigrationTracking.migrateIfNeeded`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `iOSFocusView.logBundleSession`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `iOSTaskDetailSheet.finishEditingAndDismiss`",
        "CadenceTests/CadenceTasksPanelMetricsTests.swift `TasksPanelCompletedSectionView.allTasks`",
        "CadenceTests/CadenceTodayUnificationTests.swift `CadenceTodayPresentationSupport.overdueSectionTitle`",
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
    ///
    /// **It was emptied once by the change it named.** The one entry was the Calendar Board's
    /// formBundle doc, whose sentence about the Mac timeline having the gesture as
    /// SchedulingActions.createBundle(from:adding:) went stale when [[T-3170]] removed that
    /// gesture; it was held here rather than fixed because the file was Codex-leased. The grant
    /// `41ded784` unblocked the file and T-3170's Board pass deleted the whole function the
    /// comment documented, so the claim is gone with its comment rather than struck off.
    ///
    /// **Seven, since [[T-3170]]'s trio pass.** That pass deleted insertBundle, updateBundle,
    /// assignTask, the Mac's addTask and the Block failure wording, and its test-repair half was
    /// barred from product files, so seven present-tense product comments still name them -- each
    /// a real stale claim, not a memorial. They are held here so the sweep can stay exact; the
    /// product pass that rewrites each sentence deletes its line in the same change, which
    /// `everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered` forces in both directions.
    ///
    /// **One, since the `staleclaims` pass.** Six were rewritten in one change: where the
    /// substance was still live the sentence was reworded to the past tense or to a symbol that
    /// exists (the retirement pass's `-1` members, the enum split's spelling pin), and where it was
    /// gone the claim was deleted. T-3170's final pass fixes the remaining TaskCreationService
    /// comment under the Codex grant, so none of those seven remain.
    ///
    /// **Eleven, since [[T-3209]].** Widening the root to lowercase, and checking a
    /// `<FileBaseName>.<symbol>` root against its file instead of dropping it, surfaced fourteen
    /// present-tense claims naming members that are gone. Four were corrected in that change
    /// (the styler, layout-manager, schedule-support and suite renames). The ten held here could
    /// not be: two sit in Codex-leased files (`CadenceTaskMutationSupport.swift`,
    /// `iOSTaskRowActionViews.swift`), and the rest describe a behaviour or a figure — a commit
    /// exemption, a sidebar width, a timeline row height — whose correct present-tense replacement
    /// needs the code read, not just a name swapped. [[T-3224]] owned them.
    ///
    /// **None, since [[T-3224]].** All ten were read against the code and rewritten in one
    /// change: four repointed to the symbol that now does the job, six reworded because the
    /// behaviour they described had moved (the Block removal, the drafted detail sheet, the
    /// shared shell width, Today drawing the Calendar's own column). The list stays, empty, so the
    /// next held claim has a home and a count to move.
    static let staleClaims: [String] = []

    static var ledger: [String] { (deliberateTombstones + staleClaims).sorted() }

    /// [[T-3209]]'s third verdict, ledgered. Every line was read by hand when the verdict landed;
    /// the split is recorded rather than inferred, as for the member ledger above.
    ///
    /// Memorials: the sentence's subject is a type that is gone ("lived here", "was deleted",
    /// "the first spelling was"), or a counterfactual or defect inventory naming one on purpose.
    static let rootTombstones = [
        "Cadence/Shared/CadenceColorPalette.swift `iOSListPalette.colors`",
        "Cadence/Shared/CadenceFocusPlanningSupport.swift `CadenceHabitSupport.toggle`",
        "Cadence/Shared/CadenceNotesEditorPreferences.swift `iOSMarkdownEditorPreferences.modeKey`",
        "CadenceTests/CadenceCalendarEventTimingTests.swift `iOSCalendarBundleDetailSheet.timeDate(on:minute:)`",
        "CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift `CadenceTaskGroupHeadingMetrics.countSize`",
        // A defect inventory of the four create sheets as audited; the habit sheet went with
        // [[T-2079]] and the paragraph is the record of what it did.
        "CadenceTests/CadenceCreateSheetCommitSurfaceTests.swift `CreateHabitSheet.create`",
        "CadenceTests/CadenceIconOnlyHelperIdiomDuplicationTests.swift `TimelineBundleBlockSupportViews.rowIconButton`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `CadenceMCPRowOrderSnapshot.restore()`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `TimelineBundleBlock.body`",
        // Both moved here from `deliberateTombstones` by [[T-3090]], which deleted the root
        // rather than the member: the rail case went with [[T-3079]] and the one-case sidebar
        // style enum that survived it went with T-3090, so the two memorials are now rooted on a
        // type that is gone as well as naming a case that is. Both sentences are deliberate
        // history -- the rail-retirement suite's statement of what it keeps deleted, and the
        // count suite's note of why its figure read three. Spelled without backticks here for the
        // same reason the empty-state memorial below the member ledger is: a qualified claim in
        // the file that keeps the list of them would be one more dangling claim.
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `iOSSidebarStyle.rail`",
        "CadenceTests/CadenceSidebarRailRetirementTests.swift `iOSSidebarStyle.rail`",
        // The "a caller that cannot say Copy.goalsTitle in one token" illustration left with
        // [[T-5002]]: goalsTitle is deleted, so the sentence names it without backticks now and
        // the scan no longer reads a claim there.
        "CadenceTests/SettingsCategoryReachTests.swift `iOSMobileCapability.all`",
    ]

    /// Spans shaped like a symbol path that are not Swift symbols at all: SF Symbol names the app
    /// does not spell as a whole product literal, and Python names that [[T-3087]]'s
    /// cross-language sweep checks against the script instead. A value, not a pointer.
    static let rootNonSymbols = [
        "Cadence/Shared/CadenceColorPalette.swift `dollarsign.circle.fill`",
        "Cadence/iOS/iOSTrackingEditorComponents.swift `brain.head.profile`",
        // Off this list 2026-10-21 ([[T-3270]]) and back on 2026-10-22 ([[T-3271]]). T-3253's
        // cursor call in MarkdownInlineTaskPanelSupport.swift spells the word as an implicit
        // member, the only bare spelling in code, and that used to vouch for the root; an implicit
        // member no longer does. A local or parameter named arrow would still excuse it.
        "Cadence/macOS/Sheets/ListEditorSupportViews.swift `arrow.up.bin`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `MCPClient.__init__`",
        "CadenceTests/CadenceMCPWriteFenceTests.swift `MCPClient.__init__`",
        "CadenceTests/CadenceMCPWriteFenceTests.swift `tempfile.TemporaryDirectory`",
    ]

    /// Present-tense claims rooted on a type that no longer exists. Empty since [[T-3224]]: the
    /// one line it held named the new-goal sheet [[T-2079]] deleted, and the constant whose doc
    /// named it did go dead with it. The doc now says so in the past tense, and deleting the
    /// constant is [[T-4465]]'s, not a comment fix.
    static let rootStaleClaims: [String] = []

    static var rootLedger: [String] { (rootTombstones + rootNonSymbols + rootStaleClaims).sorted() }

    @Test func theRootLedgerIsWellFormed() {
        let groups = [Self.rootTombstones, Self.rootNonSymbols, Self.rootStaleClaims]
        for group in groups {
            #expect(group == group.sorted())
            #expect(Set(group).count == group.count)
        }
        #expect(Set(Self.rootLedger).count == Self.rootLedger.count, "a line sits in two groups")
        #expect(Set(Self.rootLedger).isDisjoint(with: Set(Self.ledger)), "one span, two verdicts")
        // Measured when the verdict landed ([[T-3209]], 2026-10-18): 30 found while test
        // literals still counted, 4 corrected in place, 10 excused by the file-extension rule;
        // 3 more surfaced once test literals stopped vouching, leaving 11 + 7 + 1. **One
        // non-symbol left with [[T-3171]]'s seventh adoption slice**, which deleted the file it
        // pointed at — QuickCreateChoiceSupportViews.swift, and with it the SF Symbol name its
        // doc comment spelled — so the second group is 6. (Named without backticks here on
        // purpose: this file is swept too, and prose about the ledger must not add rows to it.)
        // **A second non-symbol left on 2026-10-21** ([[T-3270]]), so the group is 5. Nothing
        // about that claim changed: T-3253 put a bare arrow token into code for the first
        // time, the root verdict answers uncheckable rather than unresolvable while it is
        // there, and the ledger has to mirror what the detector finds. **It came back on
        // 2026-10-22** ([[T-3271]]): an implicit member expression no longer vouches for a root,
        // so the group is 6 again.
        // **10 since [[T-5002]]**: the "a caller that cannot say Copy.goalsTitle in one
        // token" illustration in CadenceSharedConstantReuseSweepTests named a constant that
        // ticket deleted, so the sentence names it without backticks now and the scan reads
        // no claim there. Removed rather than struck off, as the estimate chip's row was.
        // **12 since [[T-3090]]**, which collapsed the one-case iOS sidebar style enum away: the
        // two rail memorials in the sidebar suites did not change a word, but their root stopped
        // resolving, so they crossed from the member ledger to this one. The member ledger lost
        // the same two, which is why its count moved by two in the opposite direction.
        #expect(Self.rootTombstones.count == 12)
        #expect(Self.rootNonSymbols.count == 6)
        #expect(Self.rootStaleClaims.count == 0)
    }

    /// The unqualified half's ledger — [[T-718]].
    ///
    /// **Every entry is deliberate, and that is the measurement, not the hope.** All 27 were read
    /// by hand when the half landed and every one falls into three groups, none of which misleads
    /// a reader:
    ///
    /// - **Tombstones and counterfactuals**, 20 of them, the same class the qualified ledger is
    ///   mostly made of. Their sentences read *"There is no noteLinks(in:)"*, *"moveAnchor(by:) …
    ///   are gone with the ‹ ➤ › cluster"*, *"a shared splits(width:sides:) would trade five
    ///   readable domain expressions for one generic"*, *"a property rather than
    ///   isEmptyState(for:)"*. A sentence whose whole subject is a symbol's **absence** names an
    ///   absent symbol on purpose. (Quoted without backticks here on purpose: this file is swept
    ///   too, and prose about a ledger must not add rows to it.)
    /// - **SDK members this app mentions but never calls**, **5 lines** naming **4 distinct
    ///   members** — reloadInputViews, validateMenuItem, unregisterForRemoteNotifications, and
    ///   ranges(of:options:), which two different test files mention. This is the residue of the
    ///   framework allowlist [[T-718]] feared, and it is five lines rather than a list of AppKit,
    ///   because `calledNames(inCode:)` resolves every framework name the app actually calls
    ///   without being told about it. A ledger line names its file and its reason, which an
    ///   allowlist of bare SDK names cannot.
    /// - **Illustrative spans in these detectors' own prose**, 2: foo(_:) in the header above, and
    ///   the one in the sentence about what `#function` hands back.
    ///
    /// **[[T-999]]: the arithmetic above is now derived, because it was wrong when it was typed.**
    /// It read "21 + 4 + 2 = 27", which sums only if the first two groups are counted in different
    /// units — 4 is the number of *distinct SDK members*, and the group occupies 5 ledger *lines*,
    /// so the tombstone remainder is 20 and not 21. One reading throughout, and it is lines:
    /// **20 + 5 + 2 = 27**. `unqualifiedSDKMentions` and `unqualifiedIllustrativeSpans` below name
    /// their lines exactly and `theUnqualifiedLedgerSplitsIntoItsThreeGroups` sums them against the
    /// ledger, so the next entry cannot be classified in prose and left out of the total. T-999's
    /// standing instruction — *watch the SDK count; past roughly a dozen the trade has changed* —
    /// is asserted there too, rather than being a sentence for a reader to remember.
    ///
    /// **Zero stale claims, with one exception that is recorded rather than hidden.** No comment in
    /// the tree pointed a present-tense reader at an unqualified call that was supposed to exist,
    /// which is a finding in itself: the defect [[T-647]] found was the *scoped* spelling, not this
    /// one. [[T-3170]]'s trio pass added five product lines below. Four are tombstones its own
    /// product half wrote ("was declared here"). The fifth,
    /// CadenceTaskMutationSupport.swift's "same rule as insertBundle(from:adding:)" on
    /// rollOverTaskToToday, is a stale comparison to a deleted function, held here because that
    /// pass's test half could not touch product files; it is counted in the tombstone remainder by
    /// `theUnqualifiedLedgerSplitsIntoItsThreeGroups`, which has no stale group.
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
        // [[T-3170]]'s trio pass: two tombstones, and one stale comparison (see the doc above).
        "Cadence/Shared/CadenceTaskMutationSupport.swift `addTask(_:to:modelContext:commit:)`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `insertBundle(from:adding:)`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `insertBundle(from:adding:modelContext:commit:)`",
        "Cadence/Shared/Components/CadenceBoardColumnHeader.swift `kanbanColumnHeaderPadding()`",
        "Cadence/iOS/iOSCalendarView.swift `moveAnchor(by:)`",
        "Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift `readSelection(from:)`",
        "Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift `validateMenuItem(_:)`",
        // [[T-3170]]'s trio pass: two tombstones for the Mac's SchedulingActions block helpers.
        "Cadence/macOS/Services/SchedulingService.swift `addTask(_:to:)`",
        "Cadence/macOS/Services/SchedulingService.swift `updateBundleTime(_:startMin:endMin:)`",
        "Cadence/macOS/Views/TasksPanel.swift `taskSections(derived:)`",
        "Cadence/macOS/Views/TasksPanelDerivedState.swift `isEmptyState(for:)`",
        "Cadence/macOS/Views/TasksPanelDropCoordinator.swift `taskDropHandler(scopeTasks:dropKey:)`",
        "CadenceTests/CadenceColorPaletteTests.swift `ranges(of:options:)`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `foo(_:)`",
        // [[T-3170]]: a tombstone for the iOS quick-create sheet's Block arm. It resolved by accident
        // until the Mac's SchedulingActions spelling of the same name went too.
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `createBundle()`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `createScheduledTask()`",
        "CadenceTests/CadenceLaunchWiringTests.swift `unregisterForRemoteNotifications()`",
        "CadenceTests/CadenceSettingsSectionCopyTests.swift `sectionTitle(_:of:)`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `kanbanColumnHeaderPadding()`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `ranges(of:options:)`",
        "CadenceTests/CadenceTodayUnificationTests.swift `taskDropHandler(scopeTasks:dropKey:)`",
        "CadenceTests/MarkdownImagePasteTests.swift `readSelection(from:)`",
        "CadenceTests/TemporaryDefaultsSupport.swift `freshDefaults(_:)`",
        "CadenceTests/TemporaryDefaultsSupport.swift `someTestName()`"
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
        // 36 before T-1091 ledgered its two examples; 37 since [[T-1571]] removed the one of
        // those two that was never a finding, only a member the reader could not reach; 36 again
        // since [[T-3196]] deleted the macOS row's estimate chip, whose doc comment carried the
        // TasksPanelComponents half of the setEstimatedMinutes tombstone. The comment went with
        // the struct, so the row is removed rather than struck off. 49 since [[T-3209]] widened
        // the root to lowercase and let a file base name be a root: thirteen memorials naming
        // retired `iOS*` members became visible. 48 since T-3196's iOS half deleted
        // `iOSTaskRowEstimateChip`, whose doc comment carried the other half of the same
        // tombstone; it went with the struct, as the macOS half did. 50 since [[T-3197]] took
        // Today's "Nothing planned" box off macOS as well as iOS: the removed macOS empty-state
        // section is named by the tombstones left in `CadenceTodayPresentationSupport` (the copy
        // it was the last drawing reader of) and in `TasksPanelDerivedState` (whose
        // `isEmptyState` it was the last view reader of). Both are memorials to a deletion the
        // owner asked for, so they are ledgered rather than reworded — the reader of either file
        // wants to know what used to draw there. This comment spells the section's name without
        // its type on purpose: a qualified claim here would be a third dangling one, in the very
        // file that keeps the list of them.
        // **49 since [[T-5002]]**, which deleted CadenceEmptyStateCopy.goalsTitle: the
        // CadenceColorPaletteTests memorial naming Theme.neutralHex went with the test that
        // carried it, so the row is removed rather than struck off, as the estimate chip's was.
        // **47 since [[T-3090]]**: the two sidebar-rail memorials moved to `rootTombstones`
        // unchanged when that ticket deleted the type they root on. Moved, not struck off --
        // the sentences are still there and still deliberate.
        #expect(tombstones.count == 47)
        // It was 1 while the Calendar Board's formBundle doc named a Mac spelling [[T-3170]] had
        // removed and the file was still Codex-leased; the grant `41ded784` unblocked it and
        // T-3170's Board pass deleted the function that comment documented, taking it to 0. It is
        // 7 since T-3170's trio pass left seven product comments naming what it deleted -- see
        // `staleClaims`. The `staleclaims` pass fixed six, taking it to 1; the last is
        // TaskCreationService.swift's, held for a live Codex lease. 11 since [[T-3209]] made ten
        // more visible that it could not fix in place -- see `staleClaims`. Fixing them brings
        // this to 0. T-3170 now fixes the TaskCreationService comment, taking 11 to 10, and
        // [[T-3224]] fixed the other ten, taking it to 0.
        #expect(stale.count == 0)
    }

    /// The sweep. Exact set equality, both directions, over every Swift file in all five targets.
    @Test func everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered() throws {
        let sources = try Self.allSources()
        var text: [String: String] = [:]
        for source in sources { text[source.path] = source.text }

        let index = CadenceCommentSymbolClaim.SymbolIndex.build(fromSources: sources)

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

    /// [[T-3209]]'s third verdict: a qualified claim whose ROOT names nothing — not a declared
    /// type, not a file, not a name the code spells, not a known framework type — is a finding of
    /// its own, ledgered with the same set equality as the member half.
    @Test func everyQualifiedClaimRootsOnSomethingThatExistsOrIsLedgered() throws {
        let sources = try Self.allSources()
        var text: [String: String] = [:]
        for source in sources { text[source.path] = source.text }

        let index = CadenceCommentSymbolClaim.SymbolIndex.build(fromSources: sources)
        // Non-vacuity for the two new halves of the index: an empty identifier set would turn
        // every value root into a finding, and an empty literal set every SF Symbol name.
        #expect(index.codeIdentifiers.count >= 10_000, "the code spells \(index.codeIdentifiers.count) identifiers")
        #expect(index.codeIdentifiers.contains("ModelContext"))
        #expect(index.literals.contains("tray.fill"), "the literal index lost an SF Symbol the app draws")

        let instrument = try CadenceScanInstrument(
            "comment roots a claim on a name that resolves to nothing",
            fires: CadenceCommentSymbolClaim.rootPositiveWitness,
            andNotOn: CadenceCommentSymbolClaim.rootNegativeWitness
        ) { source in
            !CadenceCommentSymbolClaim.unresolvableRootSpans(in: source, against: index).isEmpty
        }

        let offendingPaths = try instrument.sweep(
            sources.map(\.path),
            atLeast: 800,
            including: "Cadence/Shared/Theme.swift",
            read: { path in try Self.source(path, in: text) }
        )

        var found: [String] = []
        for path in offendingPaths {
            let spans = Set(CadenceCommentSymbolClaim.unresolvableRootSpans(
                in: try Self.source(path, in: text),
                against: index
            ))
            found.append(contentsOf: spans.map { "\(path) `\($0)`" })
        }
        found.sort()

        let unlisted = found.filter { !Self.rootLedger.contains($0) }
        #expect(unlisted.isEmpty, "a comment roots a claim on a name that resolves to nothing: \(unlisted)")
        let stale = Self.rootLedger.filter { !found.contains($0) }
        #expect(stale.isEmpty, "the root ledger names a claim that is no longer there: \(stale)")
        #expect(found == Self.rootLedger)
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

    /// The roots the bare half reads: the shipping targets since [[T-7620]], and the two test
    /// targets since [[T-7641]]. A test comment is read as a description of the tree as much as a
    /// product one is -- "pinned by X below", "the same shape as Y above" -- and when X is renamed
    /// the pointer goes stale exactly the way a product claim does. Of the 343 test-root lines
    /// first measured, 25 were that alone and left the ledger when their sentences were fixed.
    private static let bareSweepRoots = [
        "Cadence/", "CadenceWidgets/", "CadenceMCPServer/", "CadenceTests/", "CadenceUITests/"
    ]

    /// The two test roots, which the needle group below is confined to.
    private static let bareTestRoots = ["CadenceTests/", "CadenceUITests/"]

    /// **Triaged ([[T-7620]], [[T-7641]]).** Every line is a backticked camelCase name in a comment
    /// that no code in the tree spells. 227 product lines were grandfathered untriaged when this
    /// half landed on 2026-10-27; `cmtriage2238` read each one in place and split them the way the
    /// qualified ledger above is split. The test roots joined on 2026-10-28 with 343 more, read the
    /// same way by `cmtests0408`: 34 stale sentences fixed in place (renamed tests, mostly the
    /// suite-suffixed self-checks; 25 lines left the ledger), 232 memorials, 30 non-symbols and 56
    /// needles. **The count may only fall.** A new finding is a comment to fix or a
    /// deletion to finish, not a line to add here, and `theBareLedgerIsWellFormedAndOnlyShrinks`
    /// fails on growth to say so.
    ///
    /// Memorials: the sentence's subject is a symbol that is gone -- "was declared here", "used to",
    /// "This replaces", "It was", a retired view named in a defect history -- or a counterfactual
    /// naming one the repository decided not to add ("There is no `removeColumns`, deliberately").
    /// The bare half cannot tell these from a stale claim by arithmetic, which is why they are read
    /// and recorded rather than inferred. In the test roots the common shape is a retired test's
    /// tombstone ("was declared here", "left with [[T-5002]]", "[[T-3170]] retired ...").
    static let bareMemorials: [String] = [
        "Cadence/Models/AppTask.swift `focusEyebrowTitle`",
        "Cadence/Models/AppTask.swift `logSessionTitle`",
        "Cadence/Models/AppTask.swift `tasksSectionLabel`",
        "Cadence/Models/GoalContributionSummary.swift `detachGoalListLink`",
        "Cadence/Models/Note.swift `canonicalNoteKey`",
        "Cadence/Services/CadenceTaskContainerLifecycleService.swift `onDidSettle`",
        "Cadence/Services/CadenceWidgetRefreshCenter.swift `reloadTodayWidgets`",
        "Cadence/Services/DataIntegrityRepairService.swift `contextScore`",
        "Cadence/Services/DataIntegrityRepairService.swift `repairDuplicateHabitCompletions`",
        "Cadence/Services/DataIntegrityRepairService.swift `repairOutOfRangeHabitReminders`",
        "Cadence/Services/MCPReadOnly/CadenceMCPServiceSupport.swift `requestedSectionName`",
        "Cadence/Services/MCPReadOnly/CadenceReadDTOs.swift `subGoalCount`",
        "Cadence/Services/MCPReadOnly/CadenceReadService.swift `getHabit`",
        "Cadence/Services/MCPReadOnly/CadenceReadService.swift `getTaskBundle`",
        "Cadence/Services/MCPReadOnly/CadenceReadService.swift `notesForContainer`",
        "Cadence/Services/MCPReadOnly/CadenceWriteService.swift `coreNoteCreatedButNotAppended`",
        "Cadence/Services/MCPReadOnly/CadenceWriteService.swift `removeColumns`",
        "Cadence/Services/MarkdownNoteSupport.swift `containsLoosePhrase`",
        "Cadence/Services/MarkdownNoteSupport.swift `tableLineIndexes`",
        "Cadence/Services/MarkdownTaskEmbedSupport.swift `isLegacyChecklistMarkerCharacter`",
        "Cadence/Services/MarkdownTaskEmbedSupport.swift `legacyChecklistMarkerRange`",
        "Cadence/Services/TagSupport.swift `newSlug`",
        "Cadence/Services/TagSupport.swift `newTagSlug`",
        "Cadence/Services/TaskCreationService.swift `addTask`",
        "Cadence/Shared/CadenceArchiveImportPresentation.swift `focusMinutesWithoutSessionsNote`",
        "Cadence/Shared/CadenceBoardCardMetadata.swift `doDateMetaItem`",
        "Cadence/Shared/CadenceCalendarEventStyle.swift `eventFill`",
        "Cadence/Shared/CadenceCalendarEventStyle.swift `taskTitleColor`",
        "Cadence/Shared/CadenceCalendarWeekdayHeaderMetrics.swift `weekdaySymbolSize`",
        "Cadence/Shared/CadenceDetailPanelPresentation.swift `iOSCalendarBoardBundleCard`",
        "Cadence/Shared/CadenceDetailPanelPresentation.swift `iOSCalendarBundleDetailSheet`",
        "Cadence/Shared/CadenceDetailPanelPresentation.swift `iOSTimelineBundleBlock`",
        "Cadence/Shared/CadenceEmptyStateCopy.swift `allComplete`",
        "Cadence/Shared/CadenceEmptyStateCopy.swift `emptyStateDuplicateAllowance`",
        "Cadence/Shared/CadenceEmptyStateCopy.swift `iOSGoalAttachListsSheet`",
        "Cadence/Shared/CadenceEventCreationSupport.swift `eventRecurrenceRule`",
        "Cadence/Shared/CadenceFeatureDestination.swift `primaryOrder`",
        "Cadence/Shared/CadenceFeatureDestination.swift `secondaryOrder`",
        "Cadence/Shared/CadenceFeatureDestination.swift `utilityOrder`",
        "Cadence/Shared/CadenceFeatureDestination.swift `workspaceDrawerSections`",
        "Cadence/Shared/CadenceListDetailPage.swift `iOSListDetailPage`",
        "Cadence/Shared/CadenceListNoteFiling.swift `defaultNoteContent`",
        "Cadence/Shared/CadencePageHeaderMetrics.swift `iOSPageHeaderMetrics`",
        "Cadence/Shared/CadencePageHeaderMetrics.swift `tileSize`",
        "Cadence/Shared/CadencePluralization.swift `iOSFeatureViews`",
        "Cadence/Shared/CadenceScheduleSupport.swift `bundlesByDate`",
        "Cadence/Shared/CadenceSettingsSectionCopy.swift `cancelledAreas`",
        "Cadence/Shared/CadenceSettingsSectionCopy.swift `pausedAreas`",
        "Cadence/Shared/CadenceTaskBundleMutationSupport.swift `addTask`",
        "Cadence/Shared/CadenceTaskBundleMutationSupport.swift `insertBundle`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `bundleCreateFailureAlertTitle`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `bundleDeleteFailureAlertTitle`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `bundleDeleteFailureNotice`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `bundleEditFailureAlertTitle`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `bundleSaveFailureNotice`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `detachGoalListLink`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `iOSCalendarBundleDetailSheet`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `moveBundle`",
        "Cadence/Shared/CadenceTaskMutationSupport.swift `updateBundle`",
        "Cadence/Shared/CadenceTaskPlanningSupport.swift `sortDateKey`",
        "Cadence/Shared/CadenceTaskPresentationSupport.swift `iOSPageHeaderMetrics`",
        "Cadence/Shared/CadenceTaskPresentationSupport.swift `iOSTaskRowDensity`",
        "Cadence/Shared/CadenceTaskQuerySupport.swift `planningDisplayGroups`",
        "Cadence/Shared/CadenceTaskQuerySupport.swift `sortDateKey`",
        "Cadence/Shared/CadenceTaskRowIndicators.swift `hasNotes`",
        "Cadence/Shared/CadenceTaskSurfaceOptions.swift `iOSCompactAllTasksView`",
        "Cadence/Shared/CadenceTodayLayoutSupport.swift `drawsCard`",
        "Cadence/Shared/CadenceTodayLayoutSupport.swift `iPadTodayLayoutMode`",
        "Cadence/Shared/CadenceTodayPresentationSupport.swift `iOSCompactTodayEmptyState`",
        "Cadence/Shared/CadenceTodayPresentationSupport.swift `overdueSectionAccent`",
        "Cadence/Shared/CadenceTodayPresentationSupport.swift `overdueSectionTitle`",
        "Cadence/Shared/CadenceTodayRolloverSupport.swift `claimedByDueDate`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `goalDeleteConfirmationMessage`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `goalDeleteFailureNotice`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `goalSaveFailureNotice`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `habitDeleteFailureNotice`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `habitSaveFailureNotice`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `iOSTrackingEditorSheets`",
        "Cadence/Shared/CadenceTrackingMutationSupport.swift `saveGoal`",
        "Cadence/Shared/Components/CadenceBoardColumnHeader.swift `iOSBoardColumnHeader`",
        "Cadence/Shared/Components/CadenceBoardColumnHeader.swift `kanbanColumnDotSize`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSCalendarBundleEditorSection`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSCalendarEventEditorSection`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSCalendarQuickCreateSection`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSSettingsInfoRow`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSTemplateEditorField`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `iOSTrackingPickerSection`",
        "Cadence/Shared/Components/CadenceFieldRows.swift `settingsField`",
        "Cadence/Shared/Components/CadenceInlineEmpty.swift `iOSInlineEmpty`",
        "Cadence/Shared/Components/CadenceStartTimeFieldRow.swift `iOSCalendarBundleDetailSheet`",
        "Cadence/Shared/Components/CadenceTagChip.swift `iOSTagChip`",
        "Cadence/Shared/DateFormatters.swift `isLate`",
        "Cadence/Shared/GoalAssignmentRules.swift `iOSGoalEditorSheet`",
        "Cadence/Shared/GoalAssignmentRules.swift `saveGoal`",
        "Cadence/Shared/GoalListLinkHelpers.swift `attachList`",
        "Cadence/Shared/GoalListLinkHelpers.swift `detachGoalListLink`",
        "Cadence/Shared/GoalListLinkHelpers.swift `iOSGoalAttachListsSheet`",
        "Cadence/Shared/GoalListLinkHelpers.swift `makeLink`",
        "Cadence/Shared/GoalListLinkHelpers.swift `toggleGoalListLink`",
        "Cadence/iOS/iOSCalendarMonthViews.swift `isEventPlate`",
        "Cadence/iOS/iOSCalendarMonthViews.swift `weekdaySymbolSize`",
        "Cadence/iOS/iOSCalendarTimelineViews.swift `draftRangeUnderTouch`",
        "Cadence/iOS/iOSCalendarTimelineViews.swift `iOSCalendarBundleDetailSheet`",
        "Cadence/iOS/iOSCalendarTimelineViews.swift `iOSScheduleHourRow`",
        "Cadence/iOS/iOSCalendarTimelineViews.swift `iOSTimelineBundleBlock`",
        "Cadence/iOS/iOSCompactTabShell.swift `iOSCompactHomeView`",
        "Cadence/iOS/iOSDesignSystem.swift `iOSBoardColumnHeader`",
        "Cadence/iOS/iOSDesignSystem.swift `iOSInlineEmpty`",
        "Cadence/iOS/iOSDesignSystem.swift `showsPlate`",
        "Cadence/iOS/iOSInboxView.swift `iPadInboxView`",
        "Cadence/iOS/iOSListDetailView.swift `iOSListNotesPanel`",
        "Cadence/iOS/iOSListNotesView.swift `iOSListNotesPanel`",
        "Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift `iOSMarkdownLiveTableLayoutInfo`",
        "Cadence/iOS/iOSMarkdownEditor.swift `pendingCommand`",
        "Cadence/iOS/iOSMarkdownImageLayoutInfo.swift `fittedImageSize`",
        "Cadence/iOS/iOSNotesView.swift `iOSCompactNotesView`",
        "Cadence/iOS/iOSNotesView.swift `iOSNotesPanel`",
        "Cadence/iOS/iOSNotesView.swift `showsEventsTab`",
        "Cadence/iOS/iOSRootSidebar.swift `iOSSidebarStyle`",
        "Cadence/iOS/iOSSearchSupportViews.swift `listRoute`",
        "Cadence/iOS/iOSSettingsComponents.swift `iOSSettingsEmptyRow`",
        "Cadence/iOS/iOSTaskCollectionPage.swift `iOSCompactAllTasksView`",
        "Cadence/iOS/iOSTaskCollectionPage.swift `iOSCompactInboxView`",
        "Cadence/iOS/iOSTaskCollectionViews.swift `allTasksPanel`",
        "Cadence/iOS/iOSTaskCollectionViews.swift `iOSCompactAllTasksView`",
        "Cadence/iOS/iOSTaskGroupSection.swift `iOSTodayCompletedSection`",
        "Cadence/iOS/iOSTaskInspectorHost.swift `iOSCalendarBundleDetailSheet`",
        "Cadence/iOS/iOSTaskInspectorHost.swift `iOSScheduleReadyTaskRow`",
        "Cadence/iOS/iOSTaskRowActionViews.swift `doChip`",
        "Cadence/iOS/iOSTaskRowActionViews.swift `iOSTaskRowDensity`",
        "Cadence/iOS/iOSTaskViews.swift `iOSTaskContainerChip`",
        "Cadence/iOS/iOSTaskViews.swift `iOSTaskRowDensity`",
        "Cadence/iOS/iOSTaskViews.swift `tagScroller`",
        "Cadence/iOS/iOSTimelineDraftCreate.swift `iOSScheduleQuickCreateBar`",
        "Cadence/iOS/iOSTodaySchedulePanel.swift `iOSScheduleHourRow`",
        "Cadence/iOS/iOSTodaySchedulePanel.swift `quickCreateComposer`",
        "Cadence/iOS/iOSTodayTaskSections.swift `iOSTodayOverdueListSheet`",
        "Cadence/iOS/iOSTodayTaskSections.swift `iOSTodayOverdueSummaries`",
        "Cadence/iOS/iOSTodayView.swift `iOSTaskRowDensity`",
        "Cadence/iOS/iOSTodayView.swift `openList`",
        "Cadence/iOS/iOSTodayView.swift `overdueSummaries`",
        "Cadence/iOS/iOSTodayView.swift `todayRowDensity`",
        "Cadence/iOS/iPadTodaySupportViews.swift `iPadInboxView`",
        "Cadence/iOS/iPadTodaySupportViews.swift `iPadTodaySidePanel`",
        "Cadence/iOS/iPadTodaySupportViews.swift `iPadTodayView`",
        "Cadence/macOS/Editor/MarkdownEditorSupport.swift `prefixLen`",
        "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift `priorityMarkButton`",
        "Cadence/macOS/Views/CadenceContextPicker.swift `iOSTrackingEditorSheets`",
        "Cadence/macOS/Views/CalendarPageStateSupport.swift `boardDateByMovingMonth`",
        "Cadence/macOS/Views/CommitmentSharedViews.swift `iOSInlineEmpty`",
        "Cadence/macOS/Views/KanbanColumnSupportViews.swift `iOSBoardColumnHeader`",
        "Cadence/macOS/Views/KanbanSectionColumnView.swift `sectionDueDateIsOverdue`",
        "Cadence/macOS/Views/KanbanSectionColumnView.swift `unfrozenActiveTasks`",
        "Cadence/macOS/Views/ListDetailSupportViews.swift `showsCapsule`",
        "Cadence/macOS/Views/SchedulePanel.swift `todayBundles`",
        "Cadence/macOS/Views/SettingsCalendarWorkHoursSection.swift `readyScheduleSlots`",
        "Cadence/macOS/Views/SettingsSectionViews.swift `settingsField`",
        "Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift `testEscapeClosesEachInspectorChildPanelAndLeavesTheInspectorOpen`",
        "Cadence/macOS/Views/TasksListView.swift `taskLookup`",
        "Cadence/macOS/Views/TasksPanel.swift `controlsBar`",
        "Cadence/macOS/Views/TasksPanel.swift `taskSortPrecedes`",
        "Cadence/macOS/Views/TasksPanelComponents.swift `metadataRow`",
        "Cadence/macOS/Views/TasksPanelDerivedState.swift `byDoDateBaseSortedTasks`",
        "Cadence/macOS/Views/TasksPanelDerivedState.swift `byDoDateBaseTasks`",
        "Cadence/macOS/Views/TasksPanelDropCoordinator.swift `liveFlatSection`",
        "Cadence/macOS/Views/TasksPanelSupport.swift `regularCount`",
        "Cadence/macOS/Views/TildeContainerPicker.swift `clampTildeHighlight`",
        "Cadence/macOS/Views/TildeContainerPicker.swift `selectTildeContainer`",
        "Cadence/macOS/Views/TildeContainerPicker.swift `tildeFlatContainers`",
        "Cadence/macOS/Views/TimelineDayCanvasOverlaySupport.swift `pendingEndMin`",
        "Cadence/macOS/Views/TimelineDayCanvasOverlaySupport.swift `pendingStartMin`",
        "Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift `dragEndMin`",
        "Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift `dragStartMin`",
        "Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift `pendingEndMin`",
        "Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift `pendingStartMin`",
        "Cadence/macOS/Views/TimelineDropInteractionSupport.swift `dragYOffset`",
        "Cadence/macOS/Views/TimelineMetrics.swift `activeResizeEdge`",
        "Cadence/macOS/Views/TimelineMetrics.swift `majorGridOpacity`",
        "Cadence/macOS/Views/TimelineMetrics.swift `resizeOriginEndMin`",
        "Cadence/macOS/Views/TimelineMetrics.swift `resizeOriginStartMin`",
        "CadenceMCPServer/CadenceMCPArgumentParsing.swift `intArray`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `aDropThatCannotBecomeABlockIsRefusedRatherThanGuessedAt`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `aTaskCardClaimingADragSuppressesTheDayDropTheSameWayABundleCardDoes`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `droppingATaskOnAScheduledTaskFormsABlockHoldingBoth`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `formingABlockClampsAStartMinuteThatWouldOverflowTheDay`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `formingABlockClearsStaleCalendarLinksOnBothMembers`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `deletingTheBundleUnderneathThePanelClosesItInBothPhasesOfTheDelete`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `reschedulingABundleOutOfTheDayAndHourQueriesKeepsThePanelOpen`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `theBundleHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `theBundleHostIsANoOpStubHeldOpenByOneLeasedCallSite`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `thePatternHelperMatchesWhatItLooksLike`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `theRootAppliesTheBundleHostAboveBothShellsRatherThanInsideOne`",
        "CadenceTests/CadenceCalendarConsistencySurfaceTests.swift `iOSCalendarBundleDetailSheet`",
        "CadenceTests/CadenceCalendarConsistencySurfaceTests.swift `startMinuteBinding`",
        "CadenceTests/CadenceCalendarEventTimingTests.swift `theBundleEditSheetSeedsItsPickerBySettingTheClock`",
        "CadenceTests/CadenceCalendarEventTimingTests.swift `timeDate`",
        "CadenceTests/CadenceCalendarOverlapLayoutTests.swift `aCompactIOSColumnCascadesBundlesOnTheSameRuleAsTasks`",
        "CadenceTests/CadenceCalendarOverlapLayoutTests.swift `theIOSDayColumnPutsAnEventBesideTheBundleItOverlaps`",
        "CadenceTests/CadenceCancelledTaskReachabilityTests.swift `finishRemainingActiveTasks`",
        "CadenceTests/CadenceCancelledTaskReachabilityTests.swift `sortedTasksForSection`",
        "CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift `showsCapsule`",
        "CadenceTests/CadenceCodexTrackingUIRetirementTests.swift `codexRetiredTrackingViewsStayOutsideTheLiveViewGraph`",
        "CadenceTests/CadenceCodexWidgetFollowupTests.swift `summaryRail`",
        "CadenceTests/CadenceColorPaletteTests.swift `theUnassignedHabitGroupReadsTheAppsOneNeutral`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `iOSTaskRowEstimateChip`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `theClaimGrammarCannotSeeALowercaseRootedTypeAndThatIsThisManyTypes`",
        "CadenceTests/CadenceContrastFloorTests.swift `theChromaCeilingBindsOnlyOnHuesOutsideTheOrdinaryBand`",
        "CadenceTests/CadenceContrastFloorTests.swift `theRailIsTheTitlesColourAndClearsTheNonTextFloorByConstruction`",
        "CadenceTests/CadenceCreateSheetCommitSurfaceTests.swift `theHabitCreatorReconcilesAndClosesOnlyOnACommittedInsert`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `cancelQuickCreate`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `selectQuickCreateStart`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `theBlockCreationFailureNoticeNamesTheBlockRatherThanATask`",
        "CadenceTests/CadenceDeletedSelectionGuardTests.swift `emptyStateDuplicateAllowance`",
        "CadenceTests/CadenceDeletedSelectionGuardTests.swift `goalsNoLongerLetsAnEmptySearchBoxExcuseAMissingGoal`",
        "CadenceTests/CadenceDeletedSelectionGuardTests.swift `selectedBundle`",
        "CadenceTests/CadenceDesktopSplitLayoutTests.swift `goalsKeepsARouteToItsInspectorAtTheWidthsThatDropTheColumn`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `anUndatedGoalIsEnoughToLeaveTheRoadmapEmptyState`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `eachFilteredDesktopPageAnswersHasCandidatesFromItsWholeCollection`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `everyDesktopFilterKnowsWhetherItHidesAnything`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `goalsTitle`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `habitsTitle`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `iOSGoalAttachListsSheet`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `iOSGoalsView`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `iOSHabitsView`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `iOSSettingsEmptyRow`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theAttachListsSheetAsksTheSharedNarrowingRule`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theDuplicateSweepReachesAFilterAwarePageInTheTree`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theGoalPickerListReadsGoalsTitleRatherThanTypingEitherAnswer`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theGoalsAndHabitsDetailPanesNeverNameAListWithNoItems`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theRoadmapFirstRunCopyAsksForAGoalAndNotForADateRange`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theThreeFilteredDesktopPagesAskTheFilterAndNotJustTheSearchField`",
        "CadenceTests/CadenceEmptyStateAuditTests.swift `theTwoGoalsViewModesShareOneTitleAndKeepTheirOwnSubtitles`",
        "CadenceTests/CadenceEmptyTitleFallbackSweepTests.swift `noGoalPickerCallSiteRepeatsTheEmptyTextDefault`",
        "CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift `renamingADefaultTagBringsTheOriginalBackOnTheNextLaunch`",
        "CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift `theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `adropOfATaskOnItselfMakesNoBlockAndRaisesNoRefusal`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `anAcceptedDropOfATaskOnATaskCommitsTheBlockAndBothMembers`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `arefusedDropOfATaskOnATaskLeavesNoBlockAndBothTasksWhereTheyWere`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `arefusedSharedTwoTaskBlockMutationLeavesTheStoreUntouched`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `bundleDeleteFailureNotice`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `bundleSaveFailureNotice`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `theSharedTwoTaskBlockMutationNoLongerCommitsThroughASwallowedSaveOfItsOwn`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `theblockCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise`",
        "CadenceTests/CadenceFocusTeardownDeferralTests.swift `arefusedDeleteOfASelectedBundleMemberKeepsItSelected`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `attachList`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `bothPlatformsReadTheSharedLinkPresentation`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `detachGoalListLink`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `existingLink`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `makeLink`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `onlyTheSharedHelperConstructsALink`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `theIOSGoalDetailShowsTheLinkedListsSectionAndTheAttribution`",
        "CadenceTests/CadenceGoalListLinkSurfaceTests.swift `toggleGoalListLink`",
        "CadenceTests/CadenceGoalsObservedDayTests.swift `iOSGoalDetail`",
        "CadenceTests/CadenceGoalsObservedDayTests.swift `iOSGoalsView`",
        "CadenceTests/CadenceHabitCompletionDuplicateTests.swift `everyHabitToggleCallSiteNamesTheSharedStore`",
        "CadenceTests/CadenceHabitCompletionDuplicateTests.swift `onlyTheHabitCompletionStoreConstructsAHabitCompletion`",
        "CadenceTests/CadenceHabitsObservedDayTests.swift `rowsAndDetailsAskTheObservedDayWhetherTheHabitIsDue`",
        "CadenceTests/CadenceHabitsObservedDayTests.swift `theIOSPageHandsItsObservedDayToItsRows`",
        "CadenceTests/CadenceHabitsObservedDayTests.swift `theMacPageFiltersAndRendersAgainstItsObservedDay`",
        "CadenceTests/CadenceIconOnlyButtonAccessibilityTests.swift `focusRowIconButton`",
        "CadenceTests/CadenceIconOnlyButtonAccessibilityTests.swift `stepButton`",
        "CadenceTests/CadenceIconOnlyButtonAccessibilityTests.swift `timelineNavButton`",
        "CadenceTests/CadenceIconOnlyHelperIdiomDuplicationTests.swift `focusRowIconButton`",
        "CadenceTests/CadenceIconOnlyHelperIdiomDuplicationTests.swift `rowIconButton`",
        "CadenceTests/CadenceIconOnlyHelperIdiomDuplicationTests.swift `stepButton`",
        "CadenceTests/CadenceIconOnlyHelperIdiomDuplicationTests.swift `timelineNavButton`",
        "CadenceTests/CadenceIconOnlyTapGestureAccessibilityTests.swift `iOSCalendarBundleDetailSheet`",
        "CadenceTests/CadenceInboxRemindersSurfaceTests.swift `showsCapsule`",
        "CadenceTests/CadenceInspectorChildPopoverPlacementTests.swift `theHeaderPanelsArePresentedFromTheTitleRow`",
        "CadenceTests/CadenceListPagesObservedDayTests.swift `theGoalsPageHandsItsObservedDayToEveryDueFlag`",
        "CadenceTests/CadenceMCPToolContractTests.swift `listTaskBundles`",
        "CadenceTests/CadenceMacTaskInspectorStatusActionsTests.swift `startThenStopRoundTripsThroughInProgress`",
        "CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift `detachGoalListLink`",
        "CadenceTests/CadenceMarkdownImageInsertionScopeTests.swift `quickCreateRefusesImagesOnlyInEventMode`",
        "CadenceTests/CadenceNotesEditorPreferencesTests.swift `iOSCompactNotesView`",
        "CadenceTests/CadenceNotesEditorPreferencesTests.swift `iOSNotesPanel`",
        "CadenceTests/CadenceOrphanRowInertnessTests.swift `repairDuplicateHabitCompletions`",
        "CadenceTests/CadencePageHeaderMetricsTests.swift `tileSize`",
        "CadenceTests/CadencePluralizationTests.swift `iOSFeatureViews`",
        "CadenceTests/CadencePluralizationTests.swift `iOSGoalDetail`",
        "CadenceTests/CadenceRadiusControlCompactSweepTests.swift `iOSScheduleHourRow`",
        "CadenceTests/CadenceRecurrenceEndAndSyncSurfaceTests.swift `thePhonesPrivateCalendarScopeEnumMatchesTheMacOne`",
        "CadenceTests/CadenceRecurrenceScopeCommitTests.swift `applyPendingRecurrenceChange`",
        "CadenceTests/CadenceResidueBatchTests.swift `goalTimelineMonthHeaderRuleIsUnrelatedAndUnchanged`",
        "CadenceTests/CadenceResidueBatchTests.swift `goalTimelineRowRulesReadTheNamedSeparator`",
        "CadenceTests/CadenceRootContextSwapAdoptionTests.swift `aRunningBundleSessionIsRepointedToo`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `goalLinkedListVisibleTitleMatchesTheAnnouncedNormalisedTitle`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `goalTaskContributorDetachButtonNamesTheTaskItDetaches`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `goalTaskContributorVisibleTitleMatchesTheAnnouncedDisplayTitle`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `habitToggleCircleReadsTheSharedCompletionStateLabelAndNamesTheHabit`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `quickCreateDraftSubtaskRemoveButtonNamesTheDraftItRemoves`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `quickCreateSelectedTaskRemoveButtonNamesTheTaskItRemoves`",
        "CadenceTests/CadenceRowSubjectAccessibilityTests.swift `selectedTaskRow`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `addTask`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `saveGoal`",
        "CadenceTests/CadenceSectionLabelGroupingTests.swift `fieldGroup`",
        "CadenceTests/CadenceSectionLabelGroupingTests.swift `theGoalSheetGroupsEveryLabelWithTheControlItNames`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `sectionDueDateIsOverdue`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `weekdaySymbolSizeZZZ`",
        "CadenceTests/CadenceSharedConstantReuseSweepTests.swift `iOSGoalDetail`",
        "CadenceTests/CadenceSharedConstantReuseSweepTests.swift `theMilestoneRowsAllNameAMilestone`",
        "CadenceTests/CadenceSharedTaskRowJobsTests.swift `doDateMetaItem`",
        "CadenceTests/CadenceSharedTaskRowJobsTests.swift `iOSPageHeaderMetrics`",
        "CadenceTests/CadenceSharedTaskRowJobsTests.swift `theFocusPanelsSelectionControlDoesNotWearTheCompletionGlyph`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `iOSSidebarCountLabel`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `listColorBarHeight`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `listColorBarLeadingInset`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `listColorBarWidth`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `railLabel`",
        "CadenceTests/CadenceTaskComposerSupportTests.swift `doDatePickLabel`",
        "CadenceTests/CadenceTaskComposerSupportTests.swift `isCustomDoDate`",
        "CadenceTests/CadenceTaskComposerSupportTests.swift `toggledDoDateKey`",
        "CadenceTests/CadenceTaskInspectorHostTests.swift `iOSScheduleReadyTaskRow`",
        "CadenceTests/CadenceTaskPresentationSupportTests.swift `iOSTaskRowDensity`",
        "CadenceTests/CadenceTaskRowIndicatorTests.swift `hasNotes`",
        "CadenceTests/CadenceTaskStatusLifecycleSurfaceTests.swift `resolvedFrozenFlatSections`",
        "CadenceTests/CadenceTaskStatusLifecycleSurfaceTests.swift `resolvedFrozenListGroups`",
        "CadenceTests/CadenceTestTargetHygieneTests.swift `requireInteractiveUITestsEnabled`",
        "CadenceTests/CadenceTestTargetHygieneTests.swift `theCommentStrippingIsActuallyStripping`",
        "CadenceTests/CadenceTestTargetHygieneTests.swift `theSourceScanActuallyReachesBothPlatformsSource`",
        "CadenceTests/CadenceTestTargetHygieneTests.swift `theSourceScanActuallyReadsTheseFiles`",
        "CadenceTests/CadenceTestTargetHygieneTests.swift `theSourceScanIsNotVacuous`",
        "CadenceTests/CadenceTimelineNowLineTests.swift `iOSScheduleHourRow`",
        "CadenceTests/CadenceTodayLayoutSupportTests.swift `threePaneMinimumWidth`",
        "CadenceTests/CadenceTodayUnificationTests.swift `bothRowsCarryAnEstimateChipOverTheSharedPicker`",
        "CadenceTests/CadenceTodayUnificationTests.swift `currentFrozenFlatSectionSnapshot`",
        "CadenceTests/CadenceTodayUnificationTests.swift `currentFrozenListGroupSnapshot`",
        "CadenceTests/CadenceTodayUnificationTests.swift `iOSTodayCompletedSection`",
        "CadenceTests/CadenceTodayUnificationTests.swift `liveFlatSection`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `arefusedBlockEditPutsTheBlockAndItsMembersBack`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `bundleDeleteFailureNotice`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `bundleSaveFailureNotice`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `eachRefusalNamesItsOwnObjectAndOnlyTheDeleteClaimsNothingWasRemoved`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `iOSGoalEditorSheet`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `iOSHabitEditorSheet`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `moveBundle`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `saveGoal`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `saveHabit`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `theIOSBlockSheetSaveDismissesOnlyThroughASuccessfulTry`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `theIOSTrackingEditorsAndBlockDeleteDismissOnlyThroughASuccessfulTry`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `updateBundle`",
        "CadenceTests/CadenceTrackingWriteRetirementTests.swift `saveGoal`",
        "CadenceTests/CadenceWriteServiceTests.swift `aRefusedAddToBundlePutsBackBothTheTaskAndTheBlocksMemberList`",
        "CadenceTests/CadenceWriteServiceTests.swift `aRefusedBlockCreateLeavesNoRowForTheNextCallsSave`",
        "CadenceTests/CadenceWriteServiceTests.swift `addTaskToBundleRefusesARepeatAndACancelledTask`",
        "CadenceTests/CadenceWriteServiceTests.swift `addTaskToBundleWritesEveryFieldOfTheSharedMembershipRule`",
        "CadenceTests/CadenceWriteServiceTests.swift `coreNoteCreatedButNotAppended`",
        "CadenceTests/CadenceWriteServiceTests.swift `createTaskBundleMintsThroughTheSharedConstructorAndItsClamps`",
        "CadenceTests/CadenceWriteServiceTests.swift `createTaskBundleRefusesAPlacementItWasNotGiven`",
        "CadenceTests/CalendarBoardPlannerSupportTests.swift `aFrameLeftBehindByABundleThatMovedAwayCannotClaimADrop`",
        "CadenceTests/CalendarBoardPlannerSupportTests.swift `aReleaseInsideABundleCardBelongsToThatCardNotToTheDayColumn`",
        "CadenceTests/CalendarBoardPlannerSupportTests.swift `aReleaseOnBareColumnBackgroundBelongsToTheDayEvenBetweenTwoCards`",
        "CadenceTests/CalendarMonthAgendaTests.swift `agendaListsDaysWhateverTheyHold`",
        "CadenceTests/CalendarMonthCellPriorityTests.swift `bundlesOutrankBothAndEventsStillOutrankTasksBelowThem`",
        "CadenceTests/CalendarTimelineGridTests.swift `iOSScheduleHourRow`",
        "CadenceTests/CalendarTimelineRangeTests.swift `bundlesTakeTheirOwnHourTheSameWay`",
        "CadenceTests/CrossPlatformParityTests.swift `bothHabitEditorsOpenACorruptReminderTimeAsUnsetRatherThanInventingOne`",
        "CadenceTests/DataIntegrityRepairServiceTests.swift `contextScore`",
        "CadenceTests/DataIntegrityRepairServiceTests.swift `repairOutOfRangeHabitReminders`",
        "CadenceTests/EstimateRollerMetricsTests.swift `startIsStillReachableAsTheSoleMacOSWriterOfInProgress`",
        "CadenceTests/FocusPickerPlayControlTests.swift `aBlockWithNothingLeftInItCannotBeTheSubjectOfASession`",
        "CadenceTests/FocusPickerPlayControlTests.swift `aBundleAndItsMemberAreDifferentSubjectsEvenWithTheSameID`",
        "CadenceTests/FocusPickerPlayControlTests.swift `anEmptyBlockCannotBeTheSubjectEvenThoughItIsNotCompleted`",
        "CadenceTests/FocusPickerPlayControlTests.swift `bothAffordancesRequestAHandoff`",
        "CadenceTests/FocusPickerPlayControlTests.swift `endingABundleSessionCreditsOnlyTheTickedMembers`",
        "CadenceTests/FocusPickerPlayControlTests.swift `theBlockInspectorsFocusSectionIsGatedOnTheBundlePredicate`",
        "CadenceTests/FocusPickerPlayControlTests.swift `theMacBlockInspectorsStartFocusReadsTheSharedPredicate`",
        "CadenceTests/FocusSessionAuditTests.swift `bundleRanksOrderTodayThenUpcomingThenUndatedThenPast`",
        "CadenceTests/FocusSessionAuditTests.swift `closingABundleSessionDistributesTimeAndClearsSelection`",
        "CadenceTests/FocusSessionAuditTests.swift `reSelectingTheBundleAlreadyFocusedResumesInsteadOfDiscarding`",
        "CadenceTests/FocusSessionAuditTests.swift `upcomingBundlesSortByDayThenStartTime`",
        "CadenceTests/GoalPresentationTests.swift `bothGoalEditorsRefuseToNestAGoalThatOwnsMilestones`",
        "CadenceTests/GoalPresentationTests.swift `saveGoal`",
        "CadenceTests/GoalPresentationTests.swift `theIOSGoalsListDrawsTheFlattenedSubtree`",
        "CadenceTests/ListTasksSectionGroupsTests.swift `aPageWithNoTasksDrawsNoEmptyHeadings`",
        "CadenceTests/MarkdownInlineSpanSupportTests.swift `iOSMarkdownStylingSupportTests`",
        "CadenceTests/MarkdownStyleSignatureTests.swift `iOSMarkdownStyleSignature`",
        "CadenceTests/MarkdownTaskEmbedPreviewTitleTests.swift `iOSMeetingNoteRow`",
        "CadenceTests/MarkdownTaskEmbedRenameSupportTests.swift `sanitizedReferenceTitle`",
        "CadenceTests/PursuitToGoalMigrationTests.swift `runIfNeededSeparatesAFoldFromAStoreWithNothingLeftToFold`",
        "CadenceTests/SettingsCategoryReachTests.swift `theMacOSHabitDetailDrawsBestStreakAndTheSevenDayStrip`",
        "CadenceTests/SettingsSharedVocabularyTests.swift `noSettingsPaneStillPaintsUnderTheSystemSeparator`",
        "CadenceTests/TagSupportTests.swift `renamingATagLeavesInlineMentionsInTheBodyAlone`",
        "CadenceTests/TaskBundleTests.swift `addingTaskToBundleUsesBundleDateWithoutTaskTime`",
        "CadenceTests/TaskBundleTests.swift `bundleFocusLoggingDistributesByEstimate`",
        "CadenceTests/TaskBundleTests.swift `bundleOrderCanBeChangedManually`",
        "CadenceTests/TaskBundleTests.swift `bundleTimesAreClampedInsideOneDay`",
        "CadenceTests/TaskBundleTests.swift `creatingBundleFromTwoTimedTasksUsesTargetSlotAndMembersLoseIndividualTimes`",
        "CadenceTests/TaskBundleTests.swift `everyKnownBundleSiteReadsTheSharedVocabulary`",
        "CadenceTests/TaskBundleTests.swift `existingBundle`",
        "CadenceTests/TaskBundleTests.swift `focusEyebrowTitle`",
        "CadenceTests/TaskBundleTests.swift `insertBundle`",
        "CadenceTests/TaskBundleTests.swift `isTimed`",
        "CadenceTests/TaskBundleTests.swift `logSessionTitle`",
        "CadenceTests/TaskBundleTests.swift `reassigningTaskBetweenBundlesRemovesOldMembership`",
        "CadenceTests/TaskBundleTests.swift `showsTimedControls`",
        "CadenceTests/TaskBundleTests.swift `tasksSectionLabel`",
        "CadenceTests/TaskDeleteHelpersScenarioTests.swift `deletingAllMembersOfActiveFocusBundleClearsFocusManagerSession`",
        "CadenceTests/TaskDeleteHelpersScenarioTests.swift `deletingOneMemberOfActiveFocusBundleKeepsSessionWhenBundleStillHasTasks`",
        "CadenceTests/TaskOverdueSupportTests.swift `regularCount`",
        "CadenceTests/TimelineDraftAndResizeTests.swift `aDropOnTheShelfIsInsideItAndADropBelowTheShelfIsNot`",
        "CadenceTests/TimelineDraftAndResizeTests.swift `pendingEndMin`",
        "CadenceTests/TimelineDraftAndResizeTests.swift `pendingStartMin`",
        "CadenceTests/TimelineDraftAndResizeTests.swift `theBundleShelfRectIsTheRegionTheShelfActuallyDraws`",
        "CadenceTests/TimelineMetricsTests.swift `overlappingBundleAndTaskShareColumnsWithoutCollision`",
        "CadenceTests/TrackingDeleteHelpersTests.swift `deletingAGoalTakesAMilestoneWhoseOwnContextIsElsewhere`",
        "CadenceTests/TrackingDeleteHelpersTests.swift `taskPriorityRank`",
        "CadenceTests/TrackingDeleteHelpersTests.swift `taskSortPrecedes`",
        "CadenceTests/iOSCalendarMetricsTests.swift `iOSScheduleReadyTaskRow`",
        "CadenceTests/iOSCalendarMetricsTests.swift `quickCreateStartMin`",
        "CadenceTests/iOSCalendarMetricsTests.swift `tileSize`",
        "CadenceTests/iOSEditorSheetMetricsTests.swift `theBlockSheetsTitleFieldJoinedTheSharedSubjectSize`",
        "CadenceUITests/CadenceUITests.swift `requireInteractiveUITestsEnabled`"
    ]

    /// Not this repository's symbols at all: framework members the app relies on without spelling
    /// them (16 lines -- a `DecodingError` case, AppKit and UIKit members, private Foundation
    /// storage), UserDefaults key fragments the code builds by interpolation rather than spells
    /// whole (`_sortField`, `todaySortField`), and two illustrative names (`iOSFoo`, the bare
    /// `iPad` prefix). A value or a vocabulary word, not a pointer into the tree. The test roots
    /// add 30 of the same kinds: AppKit and Foundation members the tests measure, SwiftData's
    /// in-memory store names, a scheme key, a shell variable suffix, and the hypothetical names
    /// an instrument's doc says it does or does not match.
    static let bareNonSymbols: [String] = [
        "Cadence/Models/TaskOrdering.swift `_sortDir`",
        "Cadence/Models/TaskOrdering.swift `_sortField`",
        "Cadence/Services/CadenceDataExportService.swift `keyNotFound`",
        "Cadence/Services/DataIntegrityRepairService.swift `keyNotFound`",
        "Cadence/Services/MCPReadOnly/CadenceReadDTOs.swift `fetchOffset`",
        "Cadence/Services/MarkdownImageAssetService.swift `validateUserInterfaceItem`",
        "Cadence/Services/MarkdownProgrammaticEditSupport.swift `smartInsertDeleteType`",
        "Cadence/Services/NoteMigrationService.swift `keyNotFound`",
        "Cadence/Services/PersistenceController.swift `_underlyingCocoaError`",
        "Cadence/Services/TagSupport.swift `isInserted`",
        "Cadence/Shared/CadenceLookPreferenceStore.swift `_sortDir`",
        "Cadence/Shared/CadenceLookPreferenceStore.swift `_sortField`",
        "Cadence/Shared/CadenceReorderVisibility.swift `_sortField`",
        "Cadence/Shared/DateFormatters.swift `setLocalizedDateFormatFromTemplate`",
        "Cadence/iOS/iOSDesignSystem.swift `iOSFoo`",
        "Cadence/iOS/iOSListEditorViews.swift `secondarySystemGroupedBackground`",
        "Cadence/iOS/iOSListViews.swift `secondarySystemGroupedBackground`",
        "Cadence/iOS/iOSMarkdownEditor.swift `inputAccessoryView`",
        "Cadence/iOS/iOSMarkdownInlineTaskPanelSupport.swift `keyboardLayoutGuide`",
        "Cadence/iOS/iPadTodaySupportViews.swift `iPad`",
        "Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift `updateDragTypeRegistration`",
        "Cadence/macOS/Views/TasksPanel.swift `todaySortDirection`",
        "Cadence/macOS/Views/TasksPanel.swift `todaySortField`",
        "Cadence/macOS/Views/macOSRootLifecycleSupport.swift `setActionName`",
        "Cadence/macOS/Views/macOSRootShellViews.swift `initialFirstResponder`",
        "CadenceTests/CadenceArchiveImportSurfaceTests.swift `keyNotFound`",
        "CadenceTests/CadenceEmptyTitleFallbackSweepTests.swift `nilTitle`",
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `_WHY`",
        "CadenceTests/CadenceIOSAllTasksSortBindingTests.swift `_sortMode`",
        "CadenceTests/CadenceIconOnlyMenuAccessibilityTests.swift `fooMenu`",
        "CadenceTests/CadenceInMemoryStoreHygieneTests.swift `inMemory_store`",
        "CadenceTests/CadenceMCPToolContractTests.swift `encodeIfPresent`",
        "CadenceTests/CadenceMacPageAccessibilityAuditTests.swift `accessibilityCustomActions`",
        "CadenceTests/CadenceMacPageAccessibilityAuditTests.swift `isAccessibilitySelected`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadTodayCompactViewsSomething`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadTodayViewModel`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPad`",
        "CadenceTests/CadenceRecurrenceEndAndSyncSurfaceTests.swift `eventScopeTitleShort`",
        "CadenceTests/CadenceRecurrenceEndAndSyncSurfaceTests.swift `macCalendarRecurrenceEditScope`",
        "CadenceTests/CadenceSidebarResizeHandleTests.swift `focusRingMaskBounds`",
        "CadenceTests/CadenceStartupRecoveryReasonTests.swift `_underlyingCocoaError`",
        "CadenceTests/CadenceTestHostEnvironmentPinTests.swift `shouldUseLaunchSchemeArgsEnv`",
        "CadenceTests/CadenceTestStoreSupport.swift `inMemory_store_ckAssets`",
        "CadenceTests/CadenceTestStoreSupport.swift `inMemory_store`",
        "CadenceTests/CadenceTimeZoneIndependenceTests.swift `autoupdatingCurrent`",
        "CadenceTests/CadenceTimeZoneIndependenceTests.swift `minimumDaysInFirstWeek`",
        "CadenceTests/CadenceTodayUnificationTests.swift `todaySortDirection`",
        "CadenceTests/CadenceTodayUnificationTests.swift `todaySortField`",
        "CadenceTests/DataIntegrityRepairServiceTests.swift `keyNotFound`",
        "CadenceTests/MarkdownImageDropAffordanceTests.swift `acceptableDragTypes`",
        "CadenceTests/MarkdownImageDropAffordanceTests.swift `orderFront`",
        "CadenceTests/MarkdownImageDropAffordanceTests.swift `unregisterDraggedTypes`",
        "CadenceTests/MarkdownImageDropAffordanceTests.swift `updateDragTypeRegistration`",
        "CadenceTests/MarkdownImagePasteTests.swift `validateUserInterfaceItem`",
        "CadenceTests/NoteMigrationServiceTests.swift `keyNotFound`"
    ]

    /// Present-tense claims naming something that is gone. **Empty since the triage**: the twenty
    /// lines found stale were fixed in place in the same change -- repointed to the symbol that now
    /// does the job (a renamed test, the `*Opacity` hairline constants, `handleSystemDidWake`,
    /// `iOSTaskRowSwipeActions`, `drawMarkdownTaskEmbeds`, `iOSCompactTabShell`,
    /// `iOSCalendarMonthDayCell`) or reworded where the thing they described had gone with
    /// [[T-3170]]'s Block removal or the habits retirement. The list stays, empty, so the next held
    /// claim has a home and a count to move.
    static let bareStaleClaims: [String] = []

    /// **Test roots only ([[T-7641]]).** A name a test comment quotes because the test's own code
    /// searches for it: the needle a pin-it-absent test counts to zero, a fixture an instrument is
    /// run against, or a line of this file's own ledgers. Test literals do not vouch
    /// (`SymbolIndex.literalExcludedRoots`), so each of these is unresolved by construction, and
    /// the group is the one place that is SAID rather than read: every line's name occurs in the
    /// string half of its own file, and no test-root memorial's does, this file excepted because
    /// its ledgers are themselves literals (`theBareLedgerIsWellFormedAndOnlyShrinks`).
    static let bareNeedles: [String] = [
        "CadenceTests/CadenceBundleCreationParityTests.swift `bundleFormingDrop`",
        "CadenceTests/CadenceBundleCreationParityTests.swift `landedOnBundleShelf`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `iOSCalendarBundleDetailSheet`",
        "CadenceTests/CadenceBundleInspectorHostTests.swift `iOSTimelineBundleBlock`",
        "CadenceTests/CadenceCalendarChipTreatmentTests.swift `isEventPlate`",
        "CadenceTests/CadenceCapturePaletteTests.swift `baseSeed`",
        "CadenceTests/CadenceCodexFunctionalParityTests.swift `showsCompletedControl`",
        "CadenceTests/CadenceCodexTrackingUIRetirementTests.swift `iOSHabitDetail`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `_sortField`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `formBundle`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `iOSFoo`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `iPad`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `removeColumns`",
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `todaySortField`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `iOSScheduleQuickCreateBar`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `quickCreateError`",
        "CadenceTests/CadenceCreateTaskCommitSurfaceTests.swift `quickCreateTitle`",
        "CadenceTests/CadenceEmptyTitleFallbackSweepTests.swift `iOSTaskRowGoalChip`",
        "CadenceTests/CadenceEventSeriesEndCarryTests.swift `eventRecurrenceRule`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `addTask`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `bundleCreateFailureAlertTitle`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `createBundle`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `formBundle`",
        "CadenceTests/CadenceFocusSessionAndBlockCommitTests.swift `insertBundle`",
        "CadenceTests/CadenceKanbanColumnLifecycleSurfaceTests.swift `onNameChanged`",
        "CadenceTests/CadenceMCPToolContractTests.swift `stringArray`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadInboxView`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadTodayCompactViews`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadTodaySidePanel`",
        "CadenceTests/CadenceMisfiledSurfaceTests.swift `iPadTodayView`",
        "CadenceTests/CadenceNoteFolderSurfaceTests.swift `iOSListNotesPanel`",
        "CadenceTests/CadenceQuickCreateTaskInspectorTests.swift `droppingTaskOnlyFields`",
        "CadenceTests/CadenceQuickCreateTaskInspectorTests.swift `priorityMarkButton`",
        "CadenceTests/CadenceReadServiceTests.swift `subGoalCount`",
        "CadenceTests/CadenceRecurrenceEndAndSyncSurfaceTests.swift `iOSCalendarRecurrenceEditScope`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `createBundle`",
        "CadenceTests/CadenceSaveCommitDisciplineTests.swift `insertBundle`",
        "CadenceTests/CadenceScheduleDraftTests.swift `eventIsAllDay`",
        "CadenceTests/CadenceSearchCandidateSupportTests.swift `progressResults`",
        "CadenceTests/CadenceSettingsSectionCopyTests.swift `iOSSettingsEmptyRow`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `iOSBoardColumnHeader`",
        "CadenceTests/CadenceSharedBoardChromeTests.swift `weekdaySymbolSize`",
        "CadenceTests/CadenceSidebarRailRetirementTests.swift `iOSSidebarStyle`",
        "CadenceTests/CadenceSidebarRailRetirementTests.swift `railLabel`",
        "CadenceTests/CadenceTildeContainerPickerTests.swift `tildeFlatContainers`",
        "CadenceTests/CadenceTodayOverdueSummarySurfaceTests.swift `openRequest`",
        "CadenceTests/CadenceTodaySectionMetricsTests.swift `drawsCard`",
        "CadenceTests/CadenceTodayUnificationTests.swift `todayDateSections`",
        "CadenceTests/CadenceTrackingEditorSaveCommitTests.swift `iOSCalendarBundleDetailSheet`",
        "CadenceTests/CalendarBoardDayDropCommitTests.swift `onDropBundleOnDay`",
        "CadenceTests/CalendarTimelineRangeTests.swift `iOSScheduleHourRow`",
        "CadenceTests/MarkdownHeadingRampTests.swift `headingSize`",
        "CadenceTests/MarkdownHeadingRampTests.swift `prefixLen`",
        "CadenceTests/SettingsCategoryReachTests.swift `iOSSettingsInfoRow`",
        "CadenceTests/TaskSurfaceRenderPassCensusTests.swift `sortedTasksForSection`",
        "CadenceTests/iOSCalendarMetricsTests.swift `iOSScheduleHourRow`"
    ]

    static var bareLedger: [String] {
        (bareMemorials + bareNonSymbols + bareStaleClaims + bareNeedles).sorted()
    }

    /// The bare half ([[T-7620]]): a backticked camelCase identifier in a product comment is one
    /// some code in the tree spells, or it is ledgered. Exact set equality, both directions.
    ///
    /// **What a green run here does and does not say.** It says every bare name a product comment
    /// points at is spelled by code somewhere, so a deletion that strands a comment goes red at
    /// the deletion. It does not say the name is the one the sentence means, or that it is
    /// spelled in the file the sentence is about: the same trade the unqualified half makes.
    @Test func everyBareIdentifierInAProductCommentIsSpelledByCodeOrIsLedgered() throws {
        let sources = try Self.allSources()
        var text: [String: String] = [:]
        for source in sources { text[source.path] = source.text }

        let index = CadenceCommentSymbolClaim.SymbolIndex.build(fromSources: sources)
        #expect(index.codeIdentifiers.count >= 10_000, "the code spells \(index.codeIdentifiers.count) identifiers")
        #expect(index.codeIdentifiers.contains("modelContext"))

        let product = sources.filter { source in
            Self.bareSweepRoots.contains { source.path.hasPrefix($0) }
        }
        // Non-vacuity for the grammar: a bare-span population of zero would leave this green.
        // Counted per half, so narrowing the roots back to the product cannot pass on the
        // product's spans alone ([[T-7641]]: ~5,600 product, ~4,500 test when the roots widened).
        func population(_ roots: [String]) -> Int {
            product.filter { source in roots.contains { source.path.hasPrefix($0) } }
                .reduce(0) { total, source in
                    total + CadenceCommentSymbolClaim.bareClaims(
                        inComments: CadenceCommentSymbolClaim.partition(source.text).comments
                    ).count
                }
        }
        let productPopulation = population(["Cadence/", "CadenceWidgets/", "CadenceMCPServer/"])
        let testPopulation = population(Self.bareTestRoots)
        #expect(productPopulation >= 3000, "the bare grammar read \(productPopulation) spans in product comments")
        #expect(testPopulation >= 2500, "the bare grammar read \(testPopulation) spans in test comments")

        let instrument = try CadenceScanInstrument(
            "comment names a bare identifier no code spells",
            fires: CadenceCommentSymbolClaim.barePositiveWitness,
            andNotOn: CadenceCommentSymbolClaim.bareNegativeWitness
        ) { source in
            !CadenceCommentSymbolClaim.unresolvedBareSpans(in: source, against: index).isEmpty
        }

        let offendingPaths = try instrument.sweep(
            product.map(\.path),
            atLeast: 1100,
            including: "Cadence/Shared/Theme.swift",
            read: { path in try Self.source(path, in: text) }
        )

        var found: [String] = []
        for path in offendingPaths {
            let spans = Set(CadenceCommentSymbolClaim.unresolvedBareSpans(
                in: try Self.source(path, in: text),
                against: index
            ))
            found.append(contentsOf: spans.map { "\(path) `\($0)`" })
        }
        found.sort()

        let unlisted = found.filter { !Self.bareLedger.contains($0) }
        #expect(unlisted.isEmpty, "BARE-UNLISTED \(unlisted.count): \(unlisted.joined(separator: "\n"))")
        let stale = Self.bareLedger.filter { !found.contains($0) }
        #expect(stale.isEmpty, "the bare ledger names a span that is no longer there: \(stale)")
        #expect(found == Self.bareLedger)
    }

    /// The bare ledger is sorted, unique, inside the swept roots, and no larger than when it was
    /// measured; the needle group is checked against the source it claims to quote.
    @Test func theBareLedgerIsWellFormedAndOnlyShrinks() throws {
        let ledger = Self.bareLedger
        #expect(Set(ledger).count == ledger.count)
        #expect(ledger == ledger.sorted())
        #expect(ledger.allSatisfy { line in Self.bareSweepRoots.contains { line.hasPrefix($0) } })
        // 227 when [[T-7620]] landed the half; 207 since its triage fixed twenty stale comments in
        // place; 207 + 318 = 525 since [[T-7641]] widened the roots to the tests (343 measured, 25
        // fixed in place). Lower this as lines go; never raise it -- a new unresolved bare name is
        // a comment to fix, not a line to grandfather.
        #expect(ledger.count <= 525, "the bare ledger grew to \(ledger.count); fix the comment instead")
        // The four groups are a partition: sorted, disjoint, and summing to the whole.
        let groups = [Self.bareMemorials, Self.bareNonSymbols, Self.bareStaleClaims, Self.bareNeedles]
        for group in groups {
            #expect(group == group.sorted())
            #expect(Set(group).count == group.count)
        }
        for (index, group) in groups.enumerated() {
            for other in groups[(index + 1)...] {
                #expect(Set(group).isDisjoint(with: Set(other)))
            }
        }
        #expect(groups.map(\.count).reduce(0, +) == ledger.count)
        // 182 + 231 test-root memorials, 25 + 30 non-symbols, 56 needles ([[T-7641]]; 414 before
        // [[T-8181]] rewrote the `iOSBoardCards` tombstone the 414th covered — the list only ever
        // shrinks, which is what this count is here to make visible).
        #expect(Self.bareMemorials.count == 413)
        #expect(Self.bareNonSymbols.count == 55)
        #expect(Self.bareNeedles.count == 56)
        #expect(Self.bareStaleClaims.isEmpty, "a held stale claim is a comment to fix in place")
        // The needle group is the test roots' own, and is what it says: each name is in the string
        // half of its file. The converse holds for the test-root memorials, so the boundary between
        // the two is measured rather than asserted.
        #expect(Self.bareNeedles.allSatisfy { line in Self.bareTestRoots.contains { line.hasPrefix($0) } })
        func quotedInItsOwnStrings(_ line: String) throws -> Bool {
            let parts = line.components(separatedBy: " `")
            let path = try #require(parts.first)
            let name = String(try #require(parts.last).dropLast())
            let strings = CadenceCommentSymbolClaim.partition(try CadenceSourceScan.sourceFile(path)).strings
            return strings.contains(name)
        }
        // This file is the exception both ways: its own ledger lines are string literals, so every
        // name it ledgers is quoted in it. Its needles are lines of its other ledgers, quoted before
        // this one existed; its memorials are read, not measured.
        let ownPath = "CadenceTests/CadenceCommentSymbolClaimTests.swift"
        for line in Self.bareNeedles where !line.hasPrefix(ownPath) {
            #expect(try quotedInItsOwnStrings(line), "a needle its file never quotes: \(line)")
        }
        for line in Self.bareMemorials
        where Self.bareTestRoots.contains(where: { line.hasPrefix($0) }) && !line.hasPrefix(ownPath) {
            #expect(try !quotedInItsOwnStrings(line), "a memorial its file also quotes is a needle: \(line)")
        }
        // The grammar's two exclusions, pinned so a widening cannot happen silently.
        #expect(CadenceCommentSymbolClaim.bareClaims(inComments: "/// `en_US` and `count` and `self`").isEmpty)
        #expect(CadenceCommentSymbolClaim.bareClaims(inComments: "/// `draftRangeUnderTouch`").count == 1)
        #expect(CadenceCommentSymbolClaim.bareClaims(inComments: "/// `Theme.accent` and `save()`").isEmpty)
    }

    /// The lines of the unqualified ledger that are **framework members this repository mentions
    /// but never calls** — [[T-999]]'s residual allowlist, made countable.
    ///
    /// Five lines, four distinct members: two different test files quote the same Foundation
    /// selector for two different reasons, and each states its own, which is the whole argument for
    /// a ledger over a list of bare names.
    ///
    /// **The threshold is asserted, not remembered.** T-999's finding was that this list will grow
    /// — one line per framework name the repo mentions without calling — and that the trade stops
    /// paying somewhere around a dozen, at which point an explicit SDK allowlist is cheaper than
    /// per-line reasons. A sentence saying so is the kind of instruction this repository keeps
    /// finding stale, so `theUnqualifiedLedgerSplitsIntoItsThreeGroups` fails at 13 and says what
    /// the decision is rather than leaving it to whoever notices.
    static let unqualifiedSDKMentions = [
        "Cadence/Services/MarkdownProgrammaticEditSupport.swift `reloadInputViews()`",
        "Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift `validateMenuItem(_:)`",
        "CadenceTests/CadenceColorPaletteTests.swift `ranges(of:options:)`",
        "CadenceTests/CadenceLaunchWiringTests.swift `unregisterForRemoteNotifications()`",
        "CadenceTests/CadenceSidebarCountMetricsTests.swift `ranges(of:options:)`"
    ]

    /// The lines that are these detectors' own worked examples, quoted in their own prose.
    static let unqualifiedIllustrativeSpans = [
        "CadenceTests/CadenceCommentSymbolClaimTests.swift `foo(_:)`",
        "CadenceTests/TemporaryDefaultsSupport.swift `someTestName()`"
    ]

    /// **[[T-3209]], closed: the population this suite could not see is now seen, and counted.**
    ///
    /// This test was written as `theClaimGrammarCannotSeeALowercaseRootedTypeAndThatIsThisManyTypes`
    /// to go red when either hole closed, and has been rewritten into its opposite rather than
    /// deleted, so the holes cannot reopen behind a re-narrowed regex or a restored guard with
    /// nothing to say so.
    ///
    /// - **Hole 1, the anchor.** Both arms of `claims(inComments:)` rooted on `[A-Z]`, so 504 of
    ///   the tree's nominal types — 396 of them all of `Cadence/iOS/` — could not be the root of a
    ///   claim (measured 2026-10-17). The census below now requires **every** declared type to be
    ///   rootable, and still counts the lowercase ones so the requirement is not met vacuously.
    /// - **Hole 2, the existence guard, and the one that cost [[T-3170]] twelve passes.**
    ///   `offendingSpans` dropped any claim whose root was not a declared type, assuming an SDK
    ///   type — so a comment naming a RENAMED OR DELETED type was unreportable. It is now
    ///   `Verdict.rootUnresolvable`, a finding of its own; and a root that is a file base name
    ///   with no type of that name is checked against the file instead of dropped.
    ///
    /// **Why a count and not a sample.** What failed here was an *absence* — nothing fired. Only a
    /// census of what the reader can and cannot reach fails when the gap reopens.
    @Test func theClaimGrammarSeesALowercaseRootedTypeAndAnUndeclaredRootIsAFinding() throws {
        let sources = try Self.allSources()
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(fromSources: sources)

        // --- Hole 1, closed. A lowercase-rooted span parses, exactly like its capitalised twin.
        #expect(CadenceCommentSymbolClaim.claims(inComments: "/// `CadenceScheduleSupport.bundles(on:from:)`").count == 1)
        #expect(CadenceCommentSymbolClaim.claims(inComments: "/// `iOSRootView.body`").count == 1,
                "the grammar no longer roots on a lowercase type: T-3209's hole 1 has reopened")
        #expect(CadenceCommentSymbolClaim.claims(inComments: "/// `OSRootView.body`").count == 1)
        // Still the qualified half's business alone: the unqualified arm must not double-report it.
        #expect(CadenceCommentSymbolClaim.unqualifiedClaims(inComments: "/// `iOSRootView.body`").isEmpty)
        // And a real lowercase type's real member resolves, while a missing one is an offender.
        #expect(CadenceCommentSymbolClaim.offendingSpans(in: "/// `iOSRootView.body`", against: index).isEmpty)
        #expect(
            CadenceCommentSymbolClaim.offendingSpans(in: "/// `iOSRootView.commentClaimNoSuchMember`", against: index)
                == ["iOSRootView.commentClaimNoSuchMember"]
        )

        // --- Hole 2, closed. A root the tree neither declares nor spells is its own verdict.
        let deletedRoot = "/// `CadenceTypeThatWasDeletedLongAgo.someMember`"
        #expect(!index.nominalTypes.contains("CadenceTypeThatWasDeletedLongAgo"), "the tree has no such type")
        #expect(!index.codeIdentifiers.contains("CadenceTypeThatWasDeletedLongAgo"), "and no code spells it")
        #expect(
            CadenceCommentSymbolClaim.unresolvableRootSpans(in: deletedRoot, against: index)
                == ["CadenceTypeThatWasDeletedLongAgo.someMember"],
            "a claim naming a type this tree does not declare is silently dropped again: T-3209's hole 2 has reopened"
        )
        // A different verdict, not a louder offender: the member ledger is not where it lands.
        #expect(CadenceCommentSymbolClaim.offendingSpans(in: deletedRoot, against: index).isEmpty)
        // The excuses are each narrow: a framework type the app spells, a value root, and a
        // literal value are not findings, and none of them is excused by the others' rule.
        #expect(CadenceCommentSymbolClaim.verdicts(in: "/// `ModelContext.save()`", against: index).map(\.verdict) == [.uncheckable])
        #expect(CadenceCommentSymbolClaim.verdicts(in: "/// `self.order`", against: index).map(\.verdict) == [.uncheckable])
        #expect(CadenceCommentSymbolClaim.verdicts(in: "/// `tray.fill`", against: index).map(\.verdict) == [.uncheckable])

        // [[T-3271]]: a name the code spells only as an implicit member expression is an enum case
        // or static member, and cannot vouch for a root. One case, the cursor's arrow, used to
        // retire the verdict over every SF Symbol name starting with that word. Fixtures, so the
        // claim does not hang on what the tree happens to spell today.
        let span = "/// `arrow.up.bin`"
        let implicitOnly = CadenceCommentSymbolClaim.SymbolIndex.build(
            from: [(path: "", code: "addCursorRect(bounds, cursor: .arrow)\nlet all: [Cursor] = [.arrow, .plus]\n")]
        )
        #expect(implicitOnly.codeIdentifiers.contains("arrow"), "the fixture must still spell the word")
        #expect(implicitOnly.implicitMemberCounts["arrow"] == 2)
        #expect(
            CadenceCommentSymbolClaim.verdicts(in: span, against: implicitOnly).map(\.verdict) == [.rootUnresolvable],
            "an enum case vouches for a root again: T-3271 has reopened"
        )
        // Any other spelling still vouches, so a value root or an explicit member path stays excused.
        for code in ["let arrow = 1\n", "let y = scroll.arrow\n", "f(cursor: .arrow)\nlet arrow = 1\n"] {
            let world = CadenceCommentSymbolClaim.SymbolIndex.build(from: [(path: "", code: code)])
            #expect(CadenceCommentSymbolClaim.verdicts(in: span, against: world).map(\.verdict) == [.uncheckable], "\(code)")
        }

        // The live witnesses that proved it: `iOSCalendarBoardView` is a FILE base name whose file
        // declares `iOSCalendarBoardPlanner` and no type of its own name. Its claims are now read
        // against the file — `schedule` is declared there, `formBundle` (gone with [[T-3170]]) is not.
        #expect(!index.nominalTypes.contains("iOSCalendarBoardView"))
        #expect(index.nominalTypes.contains("iOSCalendarBoardPlanner"))
        #expect(index.namesByFileBaseName["iOSCalendarBoardView"]?.contains("schedule") == true)
        #expect(CadenceCommentSymbolClaim.offendingSpans(in: "/// `iOSCalendarBoardView.schedule(_:on:)`", against: index).isEmpty)
        #expect(
            CadenceCommentSymbolClaim.offendingSpans(in: "/// `iOSCalendarBoardView.formBundle`", against: index)
                == ["iOSCalendarBoardView.formBundle"],
            "a file-qualified claim whose member the file does not declare is silently dropped again"
        )

        // --- The census: no declared type may be unrootable, and the formerly invisible
        // population is counted so the requirement cannot be met by an empty index.
        let lowercase = index.nominalTypes.filter { $0.first?.isUppercase == false }
        let unrootable = index.nominalTypes.filter {
            CadenceCommentSymbolClaim.claims(inComments: "/// `\($0).body`").isEmpty
        }
        #expect(sources.count > 900, "the scan found \(sources.count) files and cannot be doing its job")
        #expect(index.nominalTypes.count > 1_500, "only \(index.nominalTypes.count) types; the index is not being built")
        #expect(lowercase.count >= 400, "the formerly invisible population is \(lowercase.count), measured at 504")
        #expect(unrootable.isEmpty, "the claim grammar cannot root on \(unrootable.count) declared types: \(unrootable.sorted().prefix(5))")
        for witness in ["iOSRootView", "iOSCalendarBoardPlanner", "iOSCompactRootShell"] {
            #expect(lowercase.contains(witness), "\(witness) is not a declared lowercase type; re-anchor this census")
        }
    }

    /// The framework allowlist is self-pruning: an entry the tree declares or its code spells is
    /// already resolved some other way, and must come off rather than linger as a stale excuse.
    @Test func theFrameworkRootsAreNeitherDeclaredNorSpelled() throws {
        let index = CadenceCommentSymbolClaim.SymbolIndex.build(fromSources: try Self.allSources())
        #expect(index.codeIdentifiers.count >= 10_000)
        for root in CadenceCommentSymbolClaim.frameworkRootsNamedButNeverSpelled.sorted() {
            #expect(!index.nominalTypes.contains(root), "\(root) is declared in this tree; it is not a framework root")
            #expect(!index.vouchesForRoot(root), "\(root) is spelled in code now; drop it from the allowlist")
        }
        #expect(CadenceCommentSymbolClaim.frameworkRootsNamedButNeverSpelled.count <= 12,
                "past roughly a dozen, T-999's trade has changed: reconsider the allowlist")
    }

    /// [[T-999]]: every ledger line belongs to exactly one of the three groups, and the two named
    /// groups plus the remainder sum to the whole.
    ///
    /// **What this replaces.** The doc above used to assert its classification in prose and its
    /// total by hand, and the hand total was wrong — it counted one group in distinct names and the
    /// rest in lines. A miscount in a comment about a ledger is the same failure as a stale ledger
    /// entry: it tells a reader the population has been accounted for when it has not. Named lines
    /// and a subtraction cannot drift apart.
    @Test func theUnqualifiedLedgerSplitsIntoItsThreeGroups() {
        let ledger = Set(Self.unqualifiedLedger)
        let sdk = Self.unqualifiedSDKMentions
        let illustrative = Self.unqualifiedIllustrativeSpans

        #expect(Set(sdk).isSubset(of: ledger), "an SDK line is not in the ledger: \(Set(sdk).subtracting(ledger))")
        #expect(Set(illustrative).isSubset(of: ledger))
        #expect(Set(sdk).isDisjoint(with: Set(illustrative)))
        #expect(sdk == sdk.sorted())
        #expect(illustrative == illustrative.sorted())

        let tombstones = ledger.subtracting(sdk).subtracting(illustrative)
        // 21 since [[T-3170]] ledgered the quick-create sheet's createBundle() tombstone; 26 since
        // its trio pass added five product lines (four tombstones and one stale comparison, see
        // `unqualifiedLedger`'s doc).
        #expect(tombstones.count == 26, "the tombstone remainder is \(tombstones.count), not 26")
        #expect(sdk.count == 5)
        #expect(illustrative.count == 2)
        #expect(tombstones.count + sdk.count + illustrative.count == Self.unqualifiedLedger.count)

        // Four distinct members across five lines: the duplication is the point of the line count.
        let members = Set(sdk.compactMap { $0.split(separator: " ").last.map(String.init) })
        #expect(members.count == 4, "the SDK group names \(members.count) distinct members")

        #expect(
            sdk.count <= 12,
            """
            the residual SDK allowlist is \(sdk.count) lines. T-999 set the threshold at roughly a \
            dozen: past it, one explicit allowlist of framework names costs less than a per-line \
            reason for each, and this half should take that trade rather than keep adding lines.
            """
        )
    }

    /// The unqualified ledger is sorted, unique, and does not overlap the qualified one.
    @Test func theUnqualifiedLedgerIsWellFormed() {
        let ledger = Self.unqualifiedLedger
        #expect(Set(ledger).count == ledger.count)
        #expect(ledger == ledger.sorted())
        // 28 until [[T-3170]]'s trio pass added five product lines; see the ledger's doc.
        #expect(ledger.count == 33)
        #expect(Set(ledger).isDisjoint(with: Set(Self.ledger)))
    }

    /// [[T-998]]: **the scoped reading stays declined, and the decline is now a number that
    /// re-prices itself.**
    ///
    /// **The question.** [[T-718]] landed on *is this base name called anywhere in the tree*, which
    /// has one reading and needs no SDK allowlist. What it gives up is exactly [[T-647]]'s defect: a
    /// comment naming insertSubtask and deleteSubtask, about a file that has neither, in a tree that
    /// declares both elsewhere. That resolves here and always will. Catching it needs *the scope the
    /// sentence implies* — roughly, does the file this comment sits in make the call — which is a
    /// third rule and not a widening of this one.
    ///
    /// **Why it is declined, measured rather than argued.** `unresolvedUnqualifiedSpans(in:against:)`
    /// already unions the file's own calls into its world, so handing it an empty index *is* the
    /// file-scoped reading, exactly. Run both over the same five roots and the file-scoped one is an
    /// order of magnitude noisier: a comment in a view that names a helper the view calls through a
    /// support file is not a stale claim, and there are hundreds of them. Every one would need a
    /// ledger line saying so, and a ledger that large stops being read — which is the failure mode
    /// this whole family exists to avoid.
    ///
    /// **Why a ratio and not the counts.** A pinned count rots on the next commit that adds a
    /// comment, and gets bumped without being read, which is how a measurement turns into a number
    /// nobody believes. The ratio is the actual argument — *the scoped reading costs this much more
    /// ledger than the tree-scoped one* — and it re-prices itself as the tree changes. If it ever
    /// falls below the floor here, the trade has changed and T-998 should be reopened rather than
    /// this line relaxed. **That is what a failure here means; it is not a number to bump.**
    @Test func theScopedReadingIsAnOrderOfMagnitudeMoreLedgerThanTheTreeScopedOne() throws {
        let sources = try Self.allSources()

        let called = sources.reduce(into: Set<String>()) { names, source in
            names.formUnion(
                CadenceCommentSymbolClaim.calledNames(
                    inCode: CadenceCommentSymbolClaim.partition(source.text).code
                )
            )
        }
        #expect(called.count >= 2000, "the call index read \(called.count) names")

        var population = 0
        var treeScoped = 0
        var fileScoped = 0
        for source in sources {
            let regions = CadenceCommentSymbolClaim.partition(source.text)
            population += CadenceCommentSymbolClaim.unqualifiedClaims(inComments: regions.comments).count
            treeScoped += CadenceCommentSymbolClaim
                .unresolvedUnqualifiedSpans(in: source.text, against: called).count
            fileScoped += CadenceCommentSymbolClaim
                .unresolvedUnqualifiedSpans(in: source.text, against: []).count
        }

        // Non-vacuity in all three directions. A population of zero, or two readings that agree,
        // would make the ratio below meaningless while leaving it green.
        #expect(population >= 700, "the sweep found \(population) selector-shaped spans")
        #expect(treeScoped >= Self.unqualifiedLedger.count, "the tree-scoped reading found \(treeScoped)")
        #expect(fileScoped > treeScoped, "the two readings agree, so one of them is not being computed")

        #expect(
            fileScoped >= treeScoped * 5,
            """
            the scoped reading now costs \(fileScoped) ledger lines against the tree-scoped \
            \(treeScoped), out of \(population) spans — under 5x, so T-998's decline is no longer \
            obviously right and the ticket should be reopened. Do not raise this floor to pass.
            """
        )
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

// MARK: - T-3087: a comment naming a symbol in another language

/// **A Swift comment that names a Python, shell or YAML symbol, checked against the script it is
/// about ([[T-3087]]).**
///
/// Both halves above resolve a backticked name against Swift: declarations through `SymbolIndex`,
/// call sites through `calledNames(inCode:)`. A name that lives in a script is invisible to both,
/// so it could neither be an offender nor be ledgered. The sharp edge was [[T-3018]]'s own repair:
/// `CadenceMCPWriteFenceTests` once wrote the smoke test's helper in call shape, the Swift sweep
/// went red for the wrong reason, and the prescribed fix (drop the parentheses) left the sentence
/// true and guarded by nothing.
///
/// **The rule, read off the prose rather than a list of files:**
///
/// 1. A comment **block** is a run of consecutive lines that carry comment text, from the
///    `comments` half of `CadenceCommentSymbolClaim.partition`.
/// 2. A block is *about* a script when one of its backticked spans names one: a repository path
///    ending in a script extension (an optional `:<line>` suffix is allowed) that exists on disk,
///    or a bare file name that is the basename of exactly one repository script.
/// 3. In such a block, a backticked span is a **claim** when it is shaped like a script-language
///    name rather than a Swift one: dotted identifiers, an optional trailing pair of parentheses,
///    and at least one component that is snake case, screaming snake case, or a dunder. Swift
///    names in this repository are camel case, so this is what keeps a Swift type mentioned in
///    the same paragraph out of it.
/// 4. A claim **resolves** when every component of it is declared in the comment-blanked text of
///    one of the scripts the block names — a Python `def`, `class`, assignment or import binding,
///    a shell or awk function, a shell assignment, or a YAML key — or, for a screaming-snake
///    environment name, is read there as `$NAME`, `${NAME` or a quoted literal.
///
/// **Why the block and not the sentence.** The ticket's own sketch said "the surrounding
/// sentence", and measured that drops one of the five names it listed: the write fence's scope
/// note names `MCPClient.__init__` three bullets below the sentence that names
/// `docs/screenshots/seed-screenshot-data.py`. The block is the smallest unit that keeps all five.
///
/// **What it cannot see.** A script named without backticks (several comments write
/// `agent-commit.sh's` as plain text in code lines rather than prose), a camel-case script name,
/// and whether the claim is *about* the right script when a block names several — the per-block
/// union is the price of not parsing English. Those land in `crossLanguageLedger` when they
/// matter, with the reason written down.
enum CadenceCrossLanguageCommentClaim {

    struct Claim: Hashable {
        let span: String
        let line: Int
        let scripts: [String]
        let resolves: Bool
    }

    static let scriptExtensions: Set<String> = ["py", "sh", "bash", "zsh", "yml", "yaml"]

    private static let identifier = "[A-Za-z_][A-Za-z0-9_]*"

    /// The comment blocks of `source`, each with the 1-based line it starts on and its text.
    static func commentBlocks(in source: String) -> [(line: Int, text: String)] {
        let lines = CadenceCommentSymbolClaim.partition(source).comments.components(separatedBy: "\n")
        var blocks: [(line: Int, text: String)] = []
        var start: Int?
        var buffer: [String] = []
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let begun = start { blocks.append((begun, buffer.joined(separator: "\n"))) }
                start = nil
                buffer = []
            } else {
                if start == nil { start = index + 1 }
                buffer.append(line)
            }
        }
        if let begun = start { blocks.append((begun, buffer.joined(separator: "\n"))) }
        return blocks
    }

    static func backtickedSpans(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range(at: 1)) }
    }

    /// The script-path part of `span` when it is spelled like one, line suffix removed.
    static func scriptPathSpelling(_ span: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "^([A-Za-z0-9_./-]+)(?::[0-9,-]+)?$"),
              let match = regex.firstMatch(in: span, range: NSRange(span.startIndex..., in: span)),
              let range = Range(match.range(at: 1), in: span)
        else { return nil }
        let path = String(span[range])
        guard let ext = path.split(separator: ".").last, path.contains("."),
              scriptExtensions.contains(String(ext).lowercased())
        else { return nil }
        return path
    }

    /// `true` when `span` is shaped like a script-language name (rule 3).
    static func isClaimShaped(_ span: String) -> Bool {
        let pattern = "^\(identifier)(?:\\.\(identifier))*(?:\\(\\))?$"
        guard span.range(of: pattern, options: .regularExpression) != nil else { return false }
        return components(of: span).contains { component in
            let inner = component.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            let dunder = component.count > 4 && component.hasPrefix("__") && component.hasSuffix("__")
            return dunder || inner.contains("_")
        }
    }

    static func components(of span: String) -> [String] {
        let bare = span.hasSuffix("()") ? String(span.dropLast(2)) : span
        return bare.components(separatedBy: ".")
    }

    /// `true` when `name` is declared — or, for an environment name, read — in `script`, which
    /// must already be comment-blanked (rule 4).
    static func isDeclared(_ name: String, in script: String) -> Bool {
        let n = NSRegularExpression.escapedPattern(for: name)
        var patterns = [
            "^[ \\t]*(?:async[ \\t]+)?def[ \\t]+\(n)[ \\t]*\\(",
            "^[ \\t]*class[ \\t]+\(n)\\b",
            "^[ \\t]*(?:function[ \\t]+)?\(n)[ \\t]*\\(\\)",
            "\\bfunction[ \\t]+\(n)\\b",
            "(?<![A-Za-z0-9_])\(n)[\"']?\\]?[ \\t]*=(?!=)",
            "^[ \\t]*(?:from[ \\t]+\\S+[ \\t]+)?import[ \\t]+[^\\n]*\\b\(n)\\b",
            "\\bas[ \\t]+\(n)\\b",
            "\\bfor[ \\t]+\(n)[ \\t]+in\\b",
            "^[ \\t]*-?[ \\t]*\(n):",
        ]
        if name == name.uppercased(), name.contains("_") {
            patterns.append("\\$\\{?\(n)(?![A-Za-z0-9_])")
            patterns.append("[\"']\(n)[\"']")
        }
        let range = NSRange(script.startIndex..., in: script)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                return false
            }
            return regex.firstMatch(in: script, range: range) != nil
        }
    }

    /// Every claim in `source`. `resolve` turns a script spelling into a repository path or `nil`;
    /// `script` returns that path's comment-blanked text.
    static func claims(
        in source: String,
        resolve: (String) -> String?,
        script: (String) -> String?
    ) -> [Claim] {
        var found: [Claim] = []
        for block in commentBlocks(in: source) {
            let spans = backtickedSpans(in: block.text)
            let scripts = Array(Set(spans.compactMap { scriptPathSpelling($0).flatMap(resolve) })).sorted()
            guard !scripts.isEmpty else { continue }
            let texts = scripts.compactMap(script)
            var seen: Set<String> = []
            for span in spans where isClaimShaped(span) && seen.insert(span).inserted {
                let resolves = components(of: span).allSatisfy { component in
                    texts.contains { isDeclared(component, in: $0) }
                }
                found.append(Claim(span: span, line: block.line, scripts: scripts, resolves: resolves))
            }
        }
        return found
    }

    /// The fixture pair the instrument is built on: the same sentence, once naming the helper the
    /// fixture script declares and once naming one it does not.
    static let fixtureScriptPath = "fixtures/seed.py"
    static let fixtureScript = """
        import tempfile
        REFUSED = ("Library/Containers/com.haoranwei.Cadence",)
        def prepare_store():
            return tempfile.TemporaryDirectory()
        """
    static let positiveWitness = """
        /// `fixtures/seed.py` builds its store through `prepare_stores`.
        enum CadenceCrossLanguageWitness {}
        """
    static let negativeWitness = """
        /// `fixtures/seed.py` builds its store through `prepare_store`.
        enum CadenceCrossLanguageWitness {}
        """

    static func fixtureClaims(_ source: String) -> [Claim] {
        claims(
            in: source,
            resolve: { $0 == fixtureScriptPath ? $0 : nil },
            script: { $0 == fixtureScriptPath ? CadenceSourceScan.strippingHashComments(fixtureScript) : nil }
        )
    }
}

/// The sweep for [[T-3087]], and the ledger it is checked against. Its own suite so the test index
/// files it under a name; it reads the same five roots as `CadenceCommentSymbolClaimTests`.
@Suite struct CadenceCrossLanguageCommentClaimTests {

    private static let sourceRoots = [
        "Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer", "CadenceUITests"
    ]

    private static func allSources() throws -> [(path: String, text: String)] {
        try sourceRoots
            .flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
            .sorted()
            .map { (path: $0, text: try CadenceSourceScan.sourceFile($0)) }
    }

    /// Claims that do not resolve and are not drift, each with its reason. Set equality both ways:
    /// a new unresolved claim fails, and so does an entry whose claim has gone.
    static let crossLanguageDeliberateAbsences = [
        // "there is no `update_tag` arm": adding one makes this entry stale, which is the point.
        "CadenceTests/CadenceWriteServiceTests.swift `update_tag`",
    ]

    static let crossLanguageNonSymbols = [
        // A system call and an architecture name, not script symbols.
        "CadenceTests/CadenceBuildInvocationHygieneTests.swift `x86_64`",
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `posix_spawn`",
        "CadenceTests/CadenceTestHostSandboxCapabilityTests.swift `posix_spawn`",
        // A prefix, spelled with its trailing underscore.
        "CadenceTests/CadenceAgentDefaultsIsolationTests.swift `SIMCTL_CHILD_`",
    ]

    static let crossLanguageNamedOutsideTheProse = [
        // The script passes it as `SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID`, which `simctl` strips.
        "Cadence/Shared/CadenceDefaults.swift `CADENCE_UI_TEST_STORE_ID`",
        // These four live in a script the block names only in code (simulator-claim.sh,
        // ledger-lag-check.sh, test-host-lock.sh) while it backticks a different one.
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `CADENCE_LOCK_SELFTEST_TARGET`",
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `CADENCE_SIMCTL`",
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `CADENCE_SIM_CLAIMS_DIR`",
        "CadenceTests/CadenceGuardScriptSelftestTests.swift `partial_named_here`",
    ]

    static var crossLanguageLedger: [String] {
        (crossLanguageDeliberateAbsences + crossLanguageNonSymbols + crossLanguageNamedOutsideTheProse).sorted()
    }

    /// The five names [[T-3087]] was filed over. Each must be read as a claim AND resolve, so a
    /// reader that silently stopped seeing the write fence's prose is red rather than clean.
    static let crossLanguageWitnessFile = "CadenceTests/CadenceMCPWriteFenceTests.swift"
    static let crossLanguageWitnessSpans = [
        "MCPClient.__init__", "REFUSED_SUBSTRINGS", "guard_store_path", "prepare_fixture_store", "temp_store",
    ]

    /// The sweep. Every claim-shaped span in a comment block that names a repository script is
    /// declared in that script, or is ledgered.
    @Test func everyCommentNamingAScriptSymbolNamesOneTheScriptDeclaresOrIsLedgered() throws {
        let sources = try Self.allSources()
        let root = CadenceSourceScan.repositoryRoot()
        let scriptPaths = try CadenceMCPWriteFenceTests.repositoryScriptPaths()
        var byBasename: [String: [String]] = [:]
        for path in scriptPaths {
            byBasename[(path as NSString).lastPathComponent, default: []].append(path)
        }
        let resolve: (String) -> String? = { spelling in
            if spelling.contains("/") {
                return FileManager.default.fileExists(atPath: root.appendingPathComponent(spelling).path)
                    ? spelling : nil
            }
            guard let matches = byBasename[spelling], matches.count == 1 else { return nil }
            return matches[0]
        }
        var scriptCache: [String: String] = [:]
        let script: (String) -> String? = { path in
            if let cached = scriptCache[path] { return cached }
            guard let raw = try? CadenceSourceScan.sourceFile(path) else { return nil }
            let blanked = CadenceSourceScan.strippingHashComments(raw)
            scriptCache[path] = blanked
            return blanked
        }

        let instrument = try CadenceScanInstrument(
            "comment names a script symbol the script does not declare",
            fires: CadenceCrossLanguageCommentClaim.positiveWitness,
            andNotOn: CadenceCrossLanguageCommentClaim.negativeWitness
        ) { source in
            CadenceCrossLanguageCommentClaim.fixtureClaims(source).contains { !$0.resolves }
        }
        try instrument.checkWalk(sources.map(\.path), atLeast: 800, including: Self.crossLanguageWitnessFile)

        var claimCount = 0
        var resolvedCount = 0
        var filesWithClaims: Set<String> = []
        var found: Set<String> = []
        var witnessResolved: Set<String> = []
        for source in sources {
            let claims = CadenceCrossLanguageCommentClaim.claims(in: source.text, resolve: resolve, script: script)
            guard !claims.isEmpty else { continue }
            filesWithClaims.insert(source.path)
            for claim in claims {
                claimCount += 1
                if claim.resolves {
                    resolvedCount += 1
                    if source.path == Self.crossLanguageWitnessFile { witnessResolved.insert(claim.span) }
                } else {
                    found.insert("\(source.path) `\(claim.span)`")
                }
            }
        }

        // Non-vacuity: the basename index, the claims and the resolver all have to still work.
        #expect(byBasename.count >= 25, "the script index holds \(byBasename.count) basenames")
        #expect(filesWithClaims.count >= 10, "only \(filesWithClaims.count) files hold a script claim")
        #expect(claimCount >= 30, "the sweep read \(claimCount) script claims")
        #expect(resolvedCount > found.count, "resolved \(resolvedCount) of \(claimCount); the resolver stopped matching")
        let missingWitnesses = Set(Self.crossLanguageWitnessSpans).subtracting(witnessResolved)
        #expect(
            missingWitnesses.isEmpty,
            "\(Self.crossLanguageWitnessFile) no longer names, or no longer resolves: \(missingWitnesses.sorted())"
        )

        let ledger = Set(Self.crossLanguageLedger)
        let unlisted = found.subtracting(ledger).sorted()
        #expect(
            unlisted.isEmpty,
            "a comment names a script symbol that the script it names does not declare: \(unlisted)"
        )
        let stale = ledger.subtracting(found).sorted()
        #expect(stale.isEmpty, "the cross-language ledger names a claim that is no longer unresolved: \(stale)")
    }

    /// The rule on fixtures, so a red run separates "the rule is wrong" from "a comment is wrong".
    @Test func theCrossLanguageReaderTakesScriptShapedNamesAndChecksEachDeclarationForm() {
        typealias Rule = CadenceCrossLanguageCommentClaim
        // Shape: script-language names in, Swift names and expressions out.
        for span in ["prepare_fixture_store", "REFUSED_SUBSTRINGS", "MCPClient.__init__", "guard_store_path()"] {
            #expect(Rule.isClaimShaped(span), "\(span) is a script name")
        }
        for span in ["CadenceSourceScan", "partition", "guard_store_path(args.store)", "_private", "a.b"] {
            #expect(!Rule.isClaimShaped(span), "\(span) is not a script name")
        }
        // Script spellings, with and without a line suffix; a Swift file is not one.
        #expect(Rule.scriptPathSpelling("plugins/cadence-mcp/scripts/smoke-test.py:195-196")
            == "plugins/cadence-mcp/scripts/smoke-test.py")
        #expect(Rule.scriptPathSpelling("agent-commit.sh") == "agent-commit.sh")
        #expect(Rule.scriptPathSpelling("Cadence/Shared/Theme.swift") == nil)

        // Every declaration form, and the two that must not count.
        let python = CadenceSourceScan.strippingHashComments("""
            import tempfile
            from pathlib import Path as P
            class MCPClient:
                def __init__(self):
                    pass
            REFUSED_SUBSTRINGS = ("x",)
            with prepare() as temp_store:
                for row_item in rows:
                    env["CADENCE_MCP_STORE_URL"] = "y"
            # def commented_out_helper():
            if lookup_value == 3:
                pass
            """)
        for name in ["tempfile", "P", "MCPClient", "__init__", "REFUSED_SUBSTRINGS", "temp_store",
                     "row_item", "CADENCE_MCP_STORE_URL"] {
            #expect(Rule.isDeclared(name, in: python), "\(name) is declared in the python fixture")
        }
        #expect(!Rule.isDeclared("commented_out_helper", in: python), "a commented-out def is not a declaration")
        #expect(!Rule.isDeclared("lookup_value", in: python), "a comparison is not an assignment")

        let shell = CadenceSourceScan.strippingHashComments("""
            ledger_closed_ids() {
              awk 'function closure_visible(s) { return s }'
            }
            local scratch_dir=/tmp/x
            SIMCTL=${CADENCE_SIMCTL:-xcrun}
            jobs:
              ios-build:
                runs_on: macos
            #   CADENCE_UI_TEST_STORE_ID=..
            """)
        for name in ["ledger_closed_ids", "closure_visible", "scratch_dir", "CADENCE_SIMCTL", "runs_on"] {
            #expect(Rule.isDeclared(name, in: shell), "\(name) is declared in the shell fixture")
        }
        #expect(!Rule.isDeclared("CADENCE_UI_TEST_STORE_ID", in: shell), "a header comment is not a declaration")

        // End to end: a block naming the fixture script, a renamed helper, and a Swift name beside it.
        let source = """
            /// `fixtures/seed.py` calls `prepare_store` and then `prepare_stores`, from
            /// `CadenceMCPStorePreparation`.
            enum CadenceCrossLanguageFixture {}
            /// `prepare_stores` with no script named in its block is not read at all.
            enum CadenceCrossLanguageFixtureTwo {}
            """
        let claims = Rule.fixtureClaims(source)
        #expect(claims.map(\.span) == ["prepare_store", "prepare_stores"])
        #expect(claims.map(\.resolves) == [true, false])
        #expect(claims.allSatisfy { $0.scripts == [Rule.fixtureScriptPath] && $0.line == 1 })
    }

    @Test func theCrossLanguageLedgerIsWellFormed() {
        let ledger = Self.crossLanguageLedger
        #expect(Set(ledger).count == ledger.count, "an entry is listed twice")
        for entry in ledger {
            let parts = entry.components(separatedBy: " `")
            #expect(parts.count == 2 && entry.hasSuffix("`"), "malformed entry: \(entry)")
            if let path = parts.first {
                #expect((try? CadenceSourceScan.sourceFile(path)) != nil, "ledger names a missing file: \(path)")
            }
        }
    }
}
