import Foundation
import Testing

/// Reading Swift source as text, for the handful of rules that live inside a private method on a
/// SwiftUI view and can therefore never be called by a test.
///
/// **Use this rather than writing a second copy.** Both moving parts below have a spelling that is
/// wrong in a way that still looks right:
///
/// - the comment stripper must be `(?<!:)//`, not `//`. A stripper that blanks from the slashes in
///   `"https://example.com"` to the end of the line eats that line's `{` and leaves its `}`, so the
///   brace matching below closes the enclosing function early and the scan silently reads a body
///   that stops short of the code it exists to check. `LinksView.addLink()` contains exactly that
///   literal.
/// - the stripper replaces comments with spaces of equal length, so the stripped string is never
///   *shorter* than the raw one. Assert `stripped != raw`; `stripped.count < raw.count` is a test
///   that passes by never being true.
///
/// A scan must also be scoped to a **function body**. Scoping it to the enclosing struct passes on
/// an unrelated line elsewhere in the file, which is not the thing being pinned.
enum CadenceSourceScan {
    /// The repository root, from this file's own path.
    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Blanks `//` line comments and `/* */` block comments with spaces of equal length, so
    /// assertions read code rather than prose and the string keeps its length.
    static func strippingComments(_ source: String) -> String {
        var result = source
        for pattern in ["(?<!:)//[^\n]*", "/\\*(?s:.)*?\\*/"] {
            while let range = result.range(of: pattern, options: .regularExpression) {
                let width = result.distance(from: range.lowerBound, to: range.upperBound)
                result.replaceSubrange(range, with: String(repeating: " ", count: width))
            }
        }
        return result
    }

    /// The text between the braces of `func <name>(`, found by brace matching from the first `{`
    /// **after the parameter list closes**. Returns `nil` when the function is absent or either
    /// pair never balances.
    ///
    /// **T-644.** It used to take the first `{` after `func <name>(`, which is only the body when
    /// the signature holds no brace of its own. For
    /// `commit: (ModelContext) throws -> Void = { try $0.save() }` — now the repo's standard
    /// spelling for a committing helper, on 33 declarations — that first `{` is the **default
    /// closure**, so the "body" it returned was `try $0.save()` and every `contains(…)` over it was
    /// answered by a one-expression closure. Not an error and not a warning: a green assertion over
    /// the wrong text, the same family as `codeOnly`'s string blanking.
    ///
    /// Balancing the parentheses first is what fixes it, and it is the same matcher: `matchedRange`
    /// already skips nested pairs, so a defaulted closure, a tuple, or a nested function type in
    /// the signature all fall inside the parameter list rather than opening the body.
    static func functionBody(named name: String, in source: String) -> String? {
        guard let signature = source.range(of: "func \(name)(") else { return nil }
        // The `(` that opens the parameter list is the last character the needle matched, so the
        // parameter scan starts *on* it rather than after it.
        guard let parameters = matchedRange(
            after: source.index(before: signature.upperBound),
            in: source,
            open: "(",
            close: ")"
        ) else { return nil }
        return matchedBody(after: parameters.upperBound, in: source, open: "{", close: "}")
    }

    /// The text between the first `open` at or after `start` and the `close` that balances it.
    /// Returns `nil` when there is no `open` left or the pair never balances.
    ///
    /// Split out of `functionBody(named:)` rather than copied beside it: a *computed property* is
    /// the same read with a different signature in front of it, and an *argument list* is the same
    /// read with `(` and `)`. Two matchers is two chances for one of them to run off the end of the
    /// file — see `codeOnly`'s raw-literal note for what an off-by-one in brace depth does to a
    /// scan (T-465).
    ///
    /// `open` and `close` are not defaulted: a caller that wanted parentheses and got braces reads
    /// the wrong span silently, and this is the repo's standing preference for saying which.
    static func matchedBody(
        after start: String.Index,
        in source: String,
        open opening: Character,
        close closing: Character
    ) -> String? {
        matchedRange(after: start, in: source, open: opening, close: closing)
            .map { String(source[$0]) }
    }

    /// `matchedBody`'s span rather than its text, so a caller that needs to keep reading past the
    /// pair — `functionBody(named:)`, which must find the body's `{` past the parameter list's `)` —
    /// does not need a second matcher to do it (T-644). `upperBound` is the index **of** the
    /// closing character, so resuming a scan there is safe for any `open` that is not also `close`.
    static func matchedRange(
        after start: String.Index,
        in source: String,
        open opening: Character,
        close closing: Character
    ) -> Range<String.Index>? {
        guard let open = source.range(of: String(opening), range: start..<source.endIndex) else {
            return nil
        }

        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return source.index(after: open.lowerBound)..<index
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Every match of `pattern`, as the text of capture group `group` paired with the match's own
    /// range in `source`.
    ///
    /// `matchCount` answers "how many", which is all a needle-counting sweep needs. A sweep whose
    /// *file set* or *symbol set* is derived from the tree needs the captured names themselves, and
    /// that is the only thing this adds. Returns `[]` when the pattern does not compile — the same
    /// convention `matchCount`'s `-1` follows, for the same reason.
    static func captures(
        _ pattern: String,
        in source: String,
        group: Int = 1
    ) -> [(text: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match in
                guard let whole = Range(match.range, in: source),
                      match.numberOfRanges > group,
                      let captured = Range(match.range(at: group), in: source) else { return nil }
                return (String(source[captured]), whole)
            }
    }

    /// Every `.swift` path under `relativeDirectory`, repo-relative.
    ///
    /// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields
    /// absolute paths, and `#filePath` can name the repo through a symlinked prefix (`/tmp` against
    /// `/private/tmp` on an isolated build tree) that `FileManager` resolves and the literal does
    /// not.
    ///
    /// **T-374.** Was `CadenceRetiredCopyTests`' own private helper, copied by the next sweep that
    /// needed it — which is the defect shape that ticket is about, committed inside the test target
    /// that enforces it.
    static func swiftFiles(under relativeDirectory: String) throws -> [String] {
        let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
        return enumerator.compactMap { element in
            guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
            return "\(relativeDirectory)/\(name)"
        }
    }

    /// Reads each file once and hands a sweep source with its comments already blanked.
    ///
    /// Reading and stripping every file once per *needle* would be quadratic twice over:
    /// `strippingComments` rescans from the start of the string after each match, and a sweep runs
    /// dozens of needles over 300-odd files.
    static func strippedSourceReader() -> (String) throws -> String {
        var cache: [String: String] = [:]
        return { path in
            if let hit = cache[path] { return hit }
            let stripped = strippingComments(try sourceFile(path))
            cache[path] = stripped
            return stripped
        }
    }

    /// The number of matches for `pattern`, or `-1` when the pattern itself does not compile — a
    /// value no `== 0` assertion can pass by accident.
    static func matchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

/// A source-text detector bundled with the two witnesses that prove it can still tell the
/// difference — checked when the instrument is built, not in a neighbouring test.
///
/// **Why this type exists (T-161).** Every earlier version of "a test that guards nothing" in this
/// repo was a hollow *assertion*: an arithmetic comparison that could not go red, a needle counted
/// over the wrong scope. `b05869d`'s M2 was the other kind and it is harder to see — the assertion
/// was sound and the **instrument** was hollow. Blinding
/// `misfiledIsWholeFilePlatformFence` to `false` left
/// `sharedComponentsFolderHoldsNoWholeFilePlatformFence` green on a repo where the rule it states
/// was enforced nowhere, because "no offenders" is what a working repo and a blind detector both
/// look like. Only a *separate* test happened to check the detector, and nothing made that test
/// exist.
///
/// So the self-check moved into the constructor. `positive` and `negative` are not optional and
/// not defaulted: a sweep is unreachable without them, and a detector that has stopped
/// discriminating cannot be built, let alone swept with. The two witnesses also catch the
/// degenerate ends of the hollow-assertion family for free — an always-`false` detector fails
/// `positive`, an always-`true` one fails `negative`.
///
/// The witnesses should be **literal fixtures**, not repo files. A fixture read out of the tree can
/// be retuned by the same edit that breaks the rule; a literal in this file cannot.
///
/// What it does not do: it cannot tell you the detector asks the *right* question, only that it
/// still answers two questions differently. Pick witnesses that a plausible mistake would separate.
struct CadenceScanInstrument {

    /// Deliberately spelled without the word "error", because `docs/AGENTS_REFERENCE.md`'s
    /// compile-error count greps for it and a thrown scan failure is a kill, not a build break.
    enum Failure: Swift.Error, CustomStringConvertible {
        /// The detector no longer fires on a source it is defined to catch.
        case blind(String)
        /// The detector fires on the case it exists to leave alone.
        case overreaching(String)
        /// The walk handed the sweep nothing. An empty walk is how a sweep passes forever.
        case walkedNothing(String)
        case walkedTooFew(String, walked: Int, expected: Int)
        case walkMissedItsWitness(String, path: String)

        var description: String {
            switch self {
            case .blind(let name):
                return "instrument '\(name)' does not fire on its own positive witness"
            case .overreaching(let name):
                return "instrument '\(name)' fires on the case it must ignore"
            case .walkedNothing(let name):
                return "instrument '\(name)' was swept over an empty file list"
            case .walkedTooFew(let name, let walked, let expected):
                return "instrument '\(name)' walked \(walked) files, fewer than the \(expected) known to exist"
            case .walkMissedItsWitness(let name, let path):
                return "instrument '\(name)' walked without reaching \(path)"
            }
        }
    }

    let name: String
    private let detect: (String) -> Bool

    /// - Parameters:
    ///   - positive: A fixture the detector must fire on.
    ///   - negative: The nearest fixture it must **not** fire on. Nearest matters: a negative
    ///     witness that shares nothing with the positive one proves very little.
    init(
        _ name: String,
        fires positive: String,
        andNotOn negative: String,
        by detect: @escaping (String) -> Bool
    ) throws {
        guard detect(positive) else { throw Failure.blind(name) }
        guard !detect(negative) else { throw Failure.overreaching(name) }
        self.name = name
        self.detect = detect
    }

    func fires(on source: String) -> Bool { detect(source) }

    /// The paths the instrument fires on, sorted.
    ///
    /// `atLeast` and `including` are non-defaulted on purpose: they are the non-vacuity claim about
    /// the *walk*, and the whole point of this API is that leaving them out is a compile failure
    /// rather than a green run over zero files.
    func sweep(
        _ paths: [String],
        atLeast minimum: Int,
        including witness: String,
        read: (String) throws -> String
    ) throws -> [String] {
        guard !paths.isEmpty else { throw Failure.walkedNothing(name) }
        guard paths.count >= minimum else {
            throw Failure.walkedTooFew(name, walked: paths.count, expected: minimum)
        }
        guard paths.contains(witness) else {
            throw Failure.walkMissedItsWitness(name, path: witness)
        }
        var hits: [String] = []
        for path in paths {
            if detect(try read(path)) { hits.append(path) }
        }
        return hits.sorted()
    }
}

extension CadenceSourceScan {
    /// Source with string literals **and** comments blanked to spaces of equal length, newlines
    /// kept — the form every structural scan over Swift text should be reading.
    ///
    /// Blanking literals is not decoration. Any test that scans for a declaration shape has to
    /// spell that shape in a literal — `"@Test func "`, `"func select("` — and a scan that does not
    /// mask literals counts its own fixtures as code. `CadenceTestTargetHygieneTests` scans the
    /// target it is itself a member of, so without this it would report itself as a duplicate; the
    /// T-161 survey script needed it for the same reason.
    ///
    /// One pass, not `strippingComments` composed with a literal masker, and the ordering is why:
    /// a `"` inside a comment and a `//` inside a literal are each mishandled by whichever pass
    /// runs second. Reading them in one traversal means the first delimiter encountered wins, which
    /// is what the compiler does. It is also the only shape that stays linear — the regex-and-
    /// replace loop in `strippingComments` rescans from the start of the string after every match,
    /// which is fine for one file and quadratic over a whole-repo sweep.
    ///
    /// `strippingComments` is left exactly as it is: 63 files read it, and its `(?<!:)//` rule is
    /// a documented fix for `"https://example.com"`. This function needs no such rule, because by
    /// the time it could see that `//` the literal around it is already blank.
    ///
    /// **Known limit: raw string literals.** `#"..."#` is read as an ordinary `"..."`, so a raw
    /// literal containing a bare quote — `#"he said "hi""#` — is blanked to the wrong boundary and
    /// a few characters of its content survive as apparent code. 67 files here use raw literals,
    /// all of them markdown regex patterns, and none contains a needle any scan looks for. Measured
    /// rather than assumed: no file in `Cadence/` or `CadenceTests/` holds an odd number of `"""`,
    /// which is the other way this scanner could run away.
    static func codeOnly(_ source: String) -> String {
        var characters = Array(source)
        let count = characters.count

        func blank(_ range: Range<Int>) {
            for position in range where !characters[position].isNewline {
                characters[position] = " "
            }
        }

        var index = 0
        while index < count {
            let character = characters[index]

            // A *raw* string literal, before the ordinary one: inside `#"..."#` a backslash is
            // content, not an escape, and the terminator carries the same run of `#`.
            //
            // Reading that backslash as an escape is not a cosmetic miss. On `#"photo\"#` the
            // ordinary branch below skipped the closing quote, ran to the end of the line, and
            // blanked live code with it — including the `{` that opened the enclosing `for` body.
            // Brace depth for that whole file then came out one short, which is invisible to a
            // scan that only counts needles and fatal to one that asks *which suite encloses this
            // test*. One file in `CadenceTests` did exactly that, and it turned
            // `noTestInTheTargetIsDeclaredOutsideEverySuite` into eleven false accusations before
            // this branch existed (T-465).
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
                        // A single-line raw string cannot span a newline; stopping here keeps an
                        // unterminated literal from blanking the rest of the file.
                        if !multiline, characters[end].isNewline {
                            close = end
                            break
                        }
                        end += 1
                    }
                    blank(index..<close)
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
                    blank(index..<close)
                    index = close
                    continue
                }
                var end = index + 1
                while end < count, characters[end] != "\"", !characters[end].isNewline {
                    if characters[end] == "\\" { end += 1 }
                    end += 1
                }
                let close = end < count && characters[end] == "\"" ? end + 1 : min(end, count)
                blank(index..<close)
                index = close
                continue
            }

            if character == "/", index + 1 < count {
                if characters[index + 1] == "/" {
                    var end = index
                    while end < count, !characters[end].isNewline { end += 1 }
                    blank(index..<end)
                    index = end
                    continue
                }
                if characters[index + 1] == "*" {
                    var end = index + 2
                    while end + 1 < count, !(characters[end] == "*" && characters[end + 1] == "/") {
                        end += 1
                    }
                    let close = end + 1 < count ? end + 2 : count
                    blank(index..<close)
                    index = close
                    continue
                }
            }

            index += 1
        }

        return String(characters)
    }
}

// MARK: - Commit-surface scanning

/// The three readers every "**only** on a committed X" source scan needs, in one place.
///
/// **Why they are here (T-503).** `CadenceTagAndNoteCommitSurfaceTests` wrote all three as private
/// methods for T-497's seven sites; T-503's four sites are the same assertion about four more
/// screens, and copying them would have made the second spelling that this file's own doc comment
/// exists to prevent. The ordering helper in particular is the one every such test turns on, and
/// two copies of it is two chances for one of them to stop discriminating.
enum CadenceCommitSurfaceScan {

    /// Whether **every** occurrence of `report` in the body appears after the last `catch` — i.e.
    /// below the failure branch rather than above it.
    ///
    /// Deliberately crude and checkable: an offset comparison. Each calling suite pins that it
    /// answers differently for the two orders.
    ///
    /// **T-659: the report search is forwards, and that is the whole assertion.** It used to be
    /// `options: .backwards`, which anchored on the *last* occurrence and so answered "is **some**
    /// occurrence below the failure branch" — weaker than the question every calling suite means to
    /// ask, and satisfiable by the exact defect they guard against. Found by a surviving mutation
    /// while landing T-631: a second `newTagName = ""` added at the **top** of
    /// `iOSTaskTagPickerPopover.addTag`, clearing the field before the guard, left the original
    /// below it and stayed green. Anchoring on the first occurrence closes that.
    ///
    /// The `catch` search stays backwards, and for the same reason: the *last* failure branch is
    /// the strict end of that comparison, so the report must follow all of them.
    static func reportFollowsTheCatch(_ report: String, in body: String) -> Bool {
        guard let failure = body.range(of: "catch", options: .backwards),
              let reported = body.range(of: report) else { return false }
        return reported.lowerBound > failure.upperBound
    }

    /// The body of the one declaration named `name`.
    ///
    /// **This used to be here because `functionBody(named:)` could not read these** — a function
    /// taking `commit: (ModelContext) throws -> Void = { try $0.save() }` puts a brace inside its
    /// signature, and that reader took the first `{` after it. T-644 fixed that reader, so the two
    /// now agree on the span.
    ///
    /// It stays for the property the other one does not have: `CadenceSaveCommitRule.declarations`
    /// enumerates **every** declaration, so this can assert there is exactly **one** named `name`.
    /// `functionBody(named:)` takes the first match and says nothing about a second — and a sheet
    /// that grows a second `saveEdits` is precisely how one of these assertions would start reading
    /// a screen it was never about.
    static func declarationBody(named name: String, in source: String) throws -> String {
        let matches = CadenceSaveCommitRule.declarations(in: source).filter { $0.name == name }
        #expect(matches.count == 1, "expected one declaration named \(name), found \(matches.count)")
        return try #require(matches.first?.body)
    }

    /// A file read as comment-stripped text, with the two checks that keep the read honest: it is
    /// long enough to be the file, and the stripper preserved its length.
    ///
    /// **No `stripped != raw` here, deliberately.** That is an assertion about the *file* rather
    /// than about the reader — a file carrying no comment at all would fail it for no reason. Each
    /// suite pins the stripper's discrimination on a literal instead.
    static func scanned(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped.count == raw.count, "\(path): the stripper changed the length")
        return stripped
    }
}
