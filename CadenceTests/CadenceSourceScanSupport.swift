import Foundation
import Testing

/// Reading Swift source as text, for the handful of rules that live inside a private method on a
/// SwiftUI view and can therefore never be called by a test.
///
/// **Use this rather than writing a second copy.** Both moving parts below have a spelling that is
/// wrong in a way that still looks right:
///
/// - the comment stripper must be `(?<!:)//`, not `//`. A stripper that blanks from the slashes in
///   `"https://example.com"` to the end of the line takes that line's braces with it, in whichever
///   direction hurts: eat the `{` and the brace matching below closes the enclosing declaration
///   early, over a body that stops short of the code the scan exists to check; eat the `}` — which
///   is what `guard … else { return URL(string: "cadence://calendar")! }` offers it — and the
///   matching closes *late*, over text from past the end of the declaration. Neither says a word.
///   **The two canaries are `theCommentStripperBlanksCommentsWithoutShortening` and
///   `theCommentStripperKeepsABraceMatchedBodyFromClosingEarly`**, in `CadenceOrderAllocationTests`,
///   and both work on string literals of their own. A third test in that file,
///   `theFunctionBodyExtractorIsScopedToOneFunction`, catches the regression incidentally — its
///   fixture holds a `hasPrefix("http://")`. This paragraph used to name
///   `LinksView.addLink()` instead, and that claim went stale without anything noticing: the only
///   `https://` left in `LinksView.swift` sits inside a `//` comment, which both spellings blank
///   identically, and the code-line literal moved to `CadenceSavedLinkPersistence`, which no
///   brace-matching scan reads. A canary that lives in a production file has a shelf life
///   ([[T-1291]]).
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

    /// The two comment shapes, compiled once. Order matters and is the old loop's order: line
    /// comments first, so a `/*` written inside a `//` line is already blank when the block pass
    /// looks for it.
    ///
    /// **The line-comment pattern is `(?<!:)//`, and the lookbehind is load-bearing.** The bare
    /// `//` that the 54 copied strippers used blanks from the slashes in `https://` to the end of
    /// the line, taking the line's `{`, its closing paren, or the rest of a declaration with it.
    /// The two are not interchangeable and the difference is measured: stripping every `.swift`
    /// file under `Cadence/` and `CadenceTests/` with each spelling, **48 of 915 come out
    /// different** — among them `AIProvider.swift`, `CadenceDeepLink.swift`,
    /// `MarkdownImageAssetService.swift`, `AppStoreReviewReadiness.swift` and
    /// `iOSSampleDataSupport.swift`. `CadenceDeepLink.url` is the clearest of them: its `.calendar`
    /// case is a `guard … else { return URL(string: "cadence://calendar")! }`, and the bare
    /// spelling eats that line's closing `}` outright — which is exactly how a brace-matched body
    /// scan closes early and reads a body that stops short of the code it exists to check.
    ///
    /// [[T-1269]] routed the 54 copies here and kept the bare spelling reachable through a
    /// `lineComments:` parameter, because changing what a scan reads is a different change from
    /// making it fast. [[T-1270]] moved every one of them onto this pattern; the parameter and its
    /// `.plain` case then had no callers left and are gone, because a named, callable bug spelling
    /// is an invitation for the next copied stripper to pass it.
    private static let compiledPatterns: [NSRegularExpression] = {
        let spellings = ["(?<!:)//[^\n]*", "/\\*(?s:.)*?\\*/"]
        let compiled = spellings.compactMap { try? NSRegularExpression(pattern: $0) }
        // A pattern that stopped compiling would leave comments in the text and every scan
        // built on this reading prose as code. Loud here beats green there.
        precondition(compiled.count == spellings.count, "a comment pattern stopped compiling")
        return compiled
    }()

    /// Blanks `//` line comments and `/* */` block comments with spaces of equal length, so
    /// assertions read code rather than prose and the string keeps its length.
    ///
    /// **T-1269: one `matches(in:)` per pattern, not one `range(of:)` per comment.** This used to
    /// re-run `range(of:options: .regularExpression)` from the **start of the string** after every
    /// replacement, so blanking N comments out of a length-L file cost N full scans of L. On this
    /// repository's comment density that is not a constant factor worth shrugging at: measured
    /// 2026-09-14 in a release build, stripping `CadenceTodayUnificationTests.swift` once took
    /// **135 seconds**, and stripping all 915 `.swift` files in `Cadence/` and `CadenceTests/` took
    /// **170 seconds**. The same two numbers below are 0.002s and 0.38s. A `sample` of a live test
    /// host had caught 811 of 847 stacks inside the old loop, under one test that had produced no
    /// output for sixteen minutes.
    ///
    /// Collecting every match of a pattern in one pass is **exactly** equivalent here, not merely
    /// close, and it is worth saying why rather than trusting it:
    ///
    /// - the replacement is spaces, so it can never create a `/` and therefore never a *new* match
    ///   the from-the-start loop would have gone on to find;
    /// - matches of one pattern are non-overlapping and left-to-right, which is the same order the
    ///   loop blanked them in;
    /// - blanking one match cannot reach the `(?<!:)` lookbehind of the next, because a line-comment
    ///   match runs to its end of line, so the character before the following match is never inside
    ///   the preceding one.
    ///
    /// Checked rather than argued: for a fixed line-comment pattern, the one-pass form and the
    /// from-the-start loop produce byte-identical output over every `.swift` file in the tree —
    /// measured for both line-comment spellings, while both still existed.
    ///
    /// An earlier draft of this comment also claimed the two *spellings* agree with each other.
    /// They do not: measured over 915 files, the bare `//` and the guarded `(?<!:)//` disagree on
    /// **48** of them, which is why [[T-1270]] moved the callers in its own commit with its own
    /// test run rather than under [[T-1269]]'s performance fix. See `compiledPatterns`.
    ///
    /// The width stays a **Character** count, because that is what callers depend on:
    /// `CadenceCommitSurfaceScan.scanned` asserts `stripped.count == raw.count`. It is deliberately
    /// not the UTF-8 length — a comment holding a multi-byte character blanks to *fewer bytes* than
    /// it occupied (measured: one 170,209-byte file strips to 169,807), so byte offsets are **not**
    /// preserved here and nothing may start relying on them. Character offsets and the character
    /// count are.
    static func strippingComments(_ source: String) -> String {
        var result = source
        for regex in compiledPatterns {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            guard !matches.isEmpty else { continue }
            var blanked = ""
            blanked.reserveCapacity(result.count)
            var cursor = result.startIndex
            for match in matches {
                guard let range = Range(match.range, in: result), range.lowerBound >= cursor else {
                    continue
                }
                blanked.append(contentsOf: result[cursor..<range.lowerBound])
                let width = result.distance(from: range.lowerBound, to: range.upperBound)
                blanked.append(String(repeating: " ", count: width))
                cursor = range.upperBound
            }
            blanked.append(contentsOf: result[cursor...])
            result = blanked
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
        declarationBody("func \(name)(", in: source)
    }

    /// The text between the braces of the body that follows an **arbitrary declaration prefix** —
    /// `var body: some View`, `struct MacTaskRow: View`, `static func normalizedSelection(`, even
    /// `.onChange(of: scenePhase)`. `nil` when the prefix is absent or a pair never balances.
    ///
    /// **T-668.** `functionBody(named:)` above is this read with `"func \(name)("` as its prefix,
    /// and it is written that way rather than beside it. A second, hand-written brace matcher lived
    /// in `FocusPickerPlayControlTests` with 83 call sites across 19 files; it took the first `{`
    /// after the prefix, so T-644's parameter balancing reached none of them, and one of those call
    /// sites had already widened to a whole-file scan because the copy stopped at a `commit:`
    /// default closure.
    ///
    /// Two parameter lists can stand between the prefix and the body, and both are balanced before
    /// a `{` is looked for: the one the prefix itself left **open** (`"static func rollOver("`) and
    /// the one that **begins** right after a prefix that stopped at the name
    /// (`"static func handleCommandKeyEvent"`). A prefix whose parentheses are already closed
    /// resumes at its own end, which is what keeps `".onChange(of: scenePhase)"` reading the
    /// closure that follows it rather than something inside it.
    static func declarationBody(_ declaration: String, in source: String) -> String? {
        guard let declared = source.range(of: declaration) else { return nil }

        // The prefix's own parentheses, so an argument list it cut through is finished rather than
        // read as a body. `unclosed.first` is the outermost one, which is the parameter list.
        var unclosed: [String.Index] = []
        var index = declared.lowerBound
        while index < declared.upperBound {
            if source[index] == "(" {
                unclosed.append(index)
            } else if source[index] == ")", !unclosed.isEmpty {
                unclosed.removeLast()
            }
            index = source.index(after: index)
        }

        var resume = declared.upperBound
        if let opened = unclosed.first {
            guard let parameters = matchedRange(after: opened, in: source, open: "(", close: ")") else {
                return nil
            }
            resume = source.index(after: parameters.upperBound)
        }

        var next = resume
        while next < source.endIndex, source[next].isWhitespace {
            next = source.index(after: next)
        }
        if next < source.endIndex, source[next] == "(" {
            guard let parameters = matchedRange(after: next, in: source, open: "(", close: ")") else {
                return nil
            }
            resume = source.index(after: parameters.upperBound)
        }

        return matchedBody(after: resume, in: source, open: "{", close: "}")
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

    /// Every match of `pattern` in `text`, with the 0-based index of the line the match **starts**
    /// on and the matched text itself. Empty when the pattern does not compile.
    ///
    /// **Why a whole-text match and not a loop over lines (T-1316).** A scan that runs its regex
    /// line by line cannot see any shape a formatter wraps, and `\s` in the needle then means
    /// "spaces on this one line" rather than "whitespace". `cornerRadius:` with its `10` on the
    /// next line, and `defaults: UserDefaults =` with its `.standard` on the next, are both what
    /// `swift-format` produces on a long signature, and both were invisible to every line-wise
    /// sweep here while reading exactly like a passing run. Matching the whole text and mapping
    /// the offset back to a line keeps the line number a failure message needs — and the line the
    /// match STARTS on is the right one for `enclosingDeclarationPath`, which walks upwards.
    static func matchLines(_ pattern: String, in text: String) -> [(line: Int, matched: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = text as NSString
        var newlines: [Int] = []
        for offset in 0..<text.length where text.character(at: offset) == 10 { newlines.append(offset) }
        func line(containing offset: Int) -> Int {
            var low = 0
            var high = newlines.count
            while low < high {
                let middle = (low + high) / 2
                if newlines[middle] < offset { low = middle + 1 } else { high = middle }
            }
            return low
        }
        return regex
            .matches(in: text as String, range: NSRange(location: 0, length: text.length))
            .map { (line: line(containing: $0.range.location), matched: text.substring(with: $0.range)) }
    }

    /// Every spelling of a corner radius written as the bare literal `value`, as one needle shared
    /// by the `10` and the `7` sweeps rather than as two near-copies of it.
    ///
    /// Three shapes, and the third is the one [[T-1316]] added:
    ///
    /// - a call site or member value — `cornerRadius: 10`, `xRadius: 7`;
    /// - an assignment — `cornerRadius = 10`;
    /// - a **typed declaration** — `let cornerRadius: CGFloat = 10`, `func f(radius: CGFloat = 7)`.
    ///   `CadenceRadiusControlSweepTests` promised in prose that it counted "every
    ///   `someRadius(: CGFloat)? = 10` **declaration** of a named constant" and could not: the type
    ///   annotation sits between the colon and the value, so `\s*[:=]\s*10` never reached the
    ///   literal ([[T-1315]]). The shape is house style at other values — `CadenceHoverStyles`,
    ///   `MarkdownTableLayoutSupport`, `EstimatePickerControl` all write it — so the needle was
    ///   blind to the ordinary way this repository declares a constant, not to a contrivance.
    ///
    /// Whitespace is `\s*` throughout and the needle is run over whole-file text by `matchLines`,
    /// so a wrapped `cornerRadius:` / `10` pair is one match rather than nothing.
    ///
    /// The name is still anchored: `\w*[Cc]ornerRadius`, `[xy][Rr]adius` and a bare `[Rr]adius`,
    /// and nothing else. `CadenceWidgets/WidgetChrome.swift` scales a shadow-blur `elevationRadius`
    /// through 5/6/7/8 across four widget sizes — deliberate per-tier scatter — and a bare
    /// `[Rr]adius\w*` read its `7` tier as a corner radius.
    static func radiusLiteralPattern(_ value: Int) -> String {
        "\\b(?:\\w*[Cc]ornerRadius|[xy][Rr]adius|[Rr]adius)\\s*(?::\\s*[A-Za-z_][\\w.]*\\??\\s*)?[:=]\\s*\(value)\\b"
    }

    /// The chain of declarations enclosing line `index` of `lines`, outermost first, joined with
    /// `.` — `"TimelineBlockStyle.schedule"`, `"CadenceTextView.drawMarkdownImages"`. `""` for a
    /// line at file scope.
    ///
    /// **T-1297.** A sweep that excuses one source site has to say *which* site, and the obvious
    /// handle — the file plus the line number — is the one property of a line that every unrelated
    /// edit above it changes. `CadenceRadiusControlSweepTests` held its two exemptions that way and
    /// went red twice on sites it had already excused, most recently when [[T-1293]] added seven
    /// comment lines above one of them. This is the stable handle with the same discriminating
    /// power: it survives any number of lines inserted above the site, and still names a
    /// *different* declaration in the same file differently, which is the whole reason the line
    /// number was there.
    ///
    /// **`lines` must come from `codeOnly`.** The walk steps outward by strictly decreasing
    /// indentation, so a doc comment sitting at a declaration's own indent would close the step
    /// before the declaration it documents could be read; blanked to spaces it is skipped as empty.
    ///
    /// Canaries: `theDeclarationPathScannerStepsOutOfStatementsRatherThanNamingThem` and
    /// `theDeclarationAnchorSurvivesLinesInsertedAboveTheSiteItExcuses`, in
    /// `CadenceRadiusControlSweepTests`, both over fixtures of their own.
    static func enclosingDeclarationPath(ofLine index: Int, in lines: [String]) -> String {
        guard lines.indices.contains(index) else { return "" }
        var names: [String] = []
        var limit = indentationWidth(of: lines[index])
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // A line that *begins* with `)` or `]` closes a parameter or argument list opened
            // above it, so it is the tail of a declaration rather than a scope of its own.
            // Stepping out at its indent is what loses a multi-line signature: a real
            // `private func drawMarkdownImages(` sits at the same indent as the `) {` four lines
            // below it, and a walk that narrowed to that indent could no longer see it. `}` is
            // deliberately not in this set — it closes a sibling block, and skipping past it
            // would let the walk read that block's own local bindings.
            guard !(trimmed.hasPrefix(")") || trimmed.hasPrefix("]")) else { continue }
            let indent = indentationWidth(of: line)
            guard indent < limit else { continue }
            limit = indent
            if let name = declarationName(of: trimmed) { names.append(name) }
        }
        return names.reversed().joined(separator: ".")
    }

    private static func indentationWidth(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    /// The name a line **declares**, or `nil` when the line is a statement.
    ///
    /// Anchored at the start of the trimmed line, which is the part that matters: `if let image =`
    /// and `guard let info =` bind names too, and a scanner that read them as declarations would
    /// answer `…drawMarkdownImages.image` for a site inside the branch and stop matching the
    /// exemption the first time the branch was rewritten.
    ///
    /// Left as `try?` rather than `compiledPatterns`' `precondition`, because the two fail in
    /// opposite directions: a comment pattern that stops compiling leaves prose in the text and
    /// every scan built on it goes quietly green, whereas a name pattern that stops compiling
    /// makes every path empty, so every exemption stops matching and its sweep goes red.
    private static let declarationNameExpression = try? NSRegularExpression(
        pattern: "^(?:@[A-Za-z_][\\w.]*(?:\\([^)]*\\))?\\s+)*"
            + "(?:(?:public|private|fileprivate|internal|open|final|static|class|override|lazy|"
            + "weak|unowned|mutating|nonisolated|indirect|convenience|required)\\s+)*"
            + "(?:struct|class|enum|extension|protocol|actor|func|var|let|case|typealias)\\b\\s*"
            + "([A-Za-z_]\\w*)"
    )

    private static func declarationName(of trimmed: String) -> String? {
        guard let expression = declarationNameExpression else { return nil }
        guard let match = expression.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ), let name = Range(match.range(at: 1), in: trimmed) else { return nil }
        return String(trimmed[name])
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
    /// **An interpolation is parsed, not skipped to the next quote (T-1328).** `\(…)` holds a real
    /// expression, which can hold literals of its own — so finding where the *outer* literal ends
    /// means reading the inner ones. The scanner used to walk a literal with a single "next
    /// unescaped quote" loop, which meant
    /// `"tags: [\(names.map { "\"\($0)\"" }.joined(separator: ", "))]"` — a closure inside an
    /// interpolation, holding a literal with escaped quotes of its own — ended the outer literal at
    /// the *inner* literal's opening quote. That blanked the `{` of the closure and left its `}`,
    /// so brace depth for the rest of the file came out one short: every `@Test` below it landed at
    /// `<file scope>`, `-only-testing:` for that suite was refused as UNKNOWN-SUITE, and any
    /// `declarationBody` read over the same file silently closed early.
    ///
    /// **T-1328 filed this as a trap. It was not one.** Measured 2026-09-22 by running the old
    /// pass and this one over all 937 `.swift` files in `Cadence/`, `CadenceTests/`,
    /// `CadenceWidgets/` and `CadenceMCPServer/`: the old pass desynchronised
    /// `Cadence/Services/MarkdownMetadataSupport.swift` — the one file in the tree that writes
    /// exactly that line — to a brace depth of **-1**. That is why
    /// `CadenceSaveCommitDisciplineTests` carries an unbalanced-source fallback at all, and it is
    /// the file that guard's own comment calls "one file in 587" while saying that widening this
    /// pass "is somebody else's ticket". It was this one.
    ///
    /// The old pass also leaked the *content* of a nested literal as apparent code on **116 lines
    /// in 60 files**, `"list-detail-\(… ?? "unknown")"` leaving a bare `unknown` behind being the
    /// ordinary shape. The ticket read the suite index clean and concluded the tree was: the suite
    /// index only walks `CadenceTests/`, and the desynchronised file is a product file. This pass
    /// blanks a strict superset of what the old one blanked — zero sites where it now leaves
    /// something the old pass removed — so no needle that used to fire stops firing.
    ///
    /// The interpolation is still **blanked whole**, braces included, and that is deliberate
    /// rather than incidental: `TemporaryDefaultsSuiteRule` exists because `codeOnly` blanks
    /// `"prefix.\(UUID().uuidString)"` down to nothing, and
    /// `theTemporaryDefaultsSuiteRuleReadsLiteralsButNotItsOwnFixtures` pins it. Brace depth
    /// survives anyway, because a closure inside an interpolation contributes its `{` and `}` as a
    /// matched pair and both go; the same holds for the `\(` and the `)` that closes it.
    ///
    /// **Raw literals are read as raw** — `#"…"#` terminates on a quote run followed by the same
    /// run of `#`, a bare `\` inside one is content, and `\#(…)` is its interpolation. This
    /// paragraph used to claim the opposite ("`#"..."#` is read as an ordinary `"..."`", so
    /// `#"he said "hi""#` blanks to the wrong boundary); measured 2026-09-22, that literal blanks
    /// to its own boundary and the code sharing its line survives. The claim was already false when
    /// the `#` branch below was written for T-465.
    ///
    /// **What is still not handled, stated precisely so the next reader inherits a known edge
    /// rather than a surprise** — both are text this scanner does not recognise as a literal at
    /// all, so it blanks nothing and the brace counter reads the source's own characters:
    ///
    /// - a **bare regex literal**, `/\{[a-z]+/`: the `{` in the pattern counts as a brace.
    /// - a **`#if` branch whose braces do not balance on their own**, e.g. an `#if os(macOS)`
    ///   opening a declaration that `#else` opens again.
    ///
    /// Measured 2026-09-22 rather than assumed: all **937** `.swift` files in `Cadence/`,
    /// `CadenceTests/`, `CadenceWidgets/` and `CadenceMCPServer/` balance their braces after this
    /// pass, so neither shape is desynchronising anything today. That is why they are documented
    /// rather than parsed — a half-correct parser for either is worse than an honest boundary, and
    /// `everyTestFileBalancesItsBracesAfterMaskingSoSuiteExtentsCanBeTrusted` is what notices when
    /// one lands. Both are pinned as fixtures by
    /// `theMaskerStillCannotSeeARegexLiteralAndSaysSoWhenAskedWhy`, and when either does land,
    /// `cadenceFileScopeReason` is what turns the silent misread into a located one.
    static func codeOnly(_ source: String) -> String {
        let characters = Array(source)
        let count = characters.count
        // A mark rather than an in-place overwrite, so the blanking *decision* (which Character
        // spans are literal or comment) stays separate from how those spans are spelled back out.
        // Every write below is behind the scan cursor, so nothing reads a position it has already
        // blanked and the two forms are equivalent — see `blankedSpansAsSpaces` for why the
        // spelling had to move.
        var blanked = [Bool](repeating: false, count: count)

        func blank(_ range: Range<Int>) {
            for position in range where position < count {
                blanked[position] = true
            }
        }

        // The length of the `#` run that opens a *raw* literal here, or `nil` when the run is
        // something else entirely (`#if`, `#expect(`, `#filePath`).
        //
        // Reading a raw literal's backslash as an escape is not a cosmetic miss. On `#"photo\"#`
        // an ordinary-literal reading skips the closing quote, runs to the end of the line, and
        // blanks live code with it — including the `{` that opened the enclosing `for` body.
        // Brace depth for that whole file then came out one short, which is invisible to a scan
        // that only counts needles and fatal to one that asks *which suite encloses this test*.
        // One file in `CadenceTests` did exactly that, and it turned
        // `noTestInTheTargetIsDeclaredOutsideEverySuite` into eleven false accusations before this
        // branch existed (T-465).
        func rawLiteralHashes(at position: Int) -> Int? {
            var hashEnd = position
            while hashEnd < count, characters[hashEnd] == "#" { hashEnd += 1 }
            guard hashEnd < count, characters[hashEnd] == "\"" else { return nil }
            return hashEnd - position
        }

        /// Blanks the literal opening at `start` — whose `#` run is `hashes` long — and returns the
        /// index just past it. Interpolated code inside it is handed back to `scanCode`.
        func scanLiteral(from start: Int, hashes: Int) -> Int {
            let quoteStart = start + hashes
            let multiline = quoteStart + 2 < count
                && characters[quoteStart + 1] == "\""
                && characters[quoteStart + 2] == "\""
            let quotes = multiline ? 3 : 1
            var position = quoteStart + quotes
            blank(start..<min(position, count))

            while position < count {
                // The terminator carries the literal's own run of `#`.
                if characters[position] == "\"",
                   position + quotes + hashes <= count,
                   (position..<(position + quotes)).allSatisfy({ characters[$0] == "\"" }),
                   ((position + quotes)..<(position + quotes + hashes)).allSatisfy({ characters[$0] == "#" }) {
                    let close = position + quotes + hashes
                    blank(position..<close)
                    return close
                }
                // A single-line literal cannot span a newline; stopping here keeps an unterminated
                // one from blanking the rest of the file.
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
                        // The interpolation is *parsed* — its own literals, comments and nested
                        // parentheses are read properly, which is the only way to find where this
                        // literal really ends — and then blanked whole, braces included. Blanking
                        // it is what keeps `codeOnly`'s contract ("a literal is blanked, its
                        // interpolation with it") that `TemporaryDefaultsSuiteRule` leans on; the
                        // braces of a closure inside it go in a matched pair, so brace depth is
                        // preserved either way.
                        let terminator = scanCode(from: escaped + 1, stoppingAtUnmatchedCloseParen: true)
                        let close = min(terminator + 1, count)
                        blank(position..<close)
                        position = close
                        continue
                    }
                    blank(position..<(escaped + 1))
                    position = escaped + 1
                    continue
                }
                blank(position..<(position + 1))
                position += 1
            }
            return count
        }

        /// Blanks literals and comments from `start` on. With `stoppingAtUnmatchedCloseParen` it
        /// returns the index **of** the first `)` closing no `(` of its own — the end of the
        /// interpolation that called it — for the caller to blank; otherwise it runs to the end.
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
        return blankedSpansAsSpaces(characters, blanked)
    }

    /// The scalars Swift's own grammar — and therefore `Character.isNewline` — counts as ending a
    /// line: LF, VT, FF, CR, NEL, LS and PS. A `\r\n` is **one** `Character` and **two** scalars,
    /// and both of them are in here, which is what makes the two readings agree on it.
    private static let lineTerminators: Set<Unicode.Scalar> = [
        "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{85}", "\u{2028}", "\u{2029}",
    ]

    /// Spells a scan's blanking decisions back out: an unblanked `Character` unchanged, a blanked
    /// one as **one space per unicode scalar**, with its line terminators kept.
    ///
    /// **T-1338: one space per *scalar*, not one per `Character`.** `codeOnly` walks
    /// `[Character]` — grapheme clusters — and the `blank()` inside `scripts/test-suite-index.sh`
    /// walks code points. These are two implementations of one rule, and the script is what tells
    /// an agent which suite to scope a run to, so a divergence between them is a trap rather than a
    /// cosmetic difference. Writing one space per `Character` is where they diverged: a literal
    /// holding `"cafe\u{301}"`, a ZWJ sequence, an emoji with a variation selector or a flag blanks
    /// to *fewer* characters on the Swift side than on the Python one, and **every column offset
    /// after it on that line differs** — which is exactly what `declarationBody`,
    /// `declarationExtents` and `typeExtents` carry.
    ///
    /// Measured 2026-09-25 against both implementations compiled out of this repository, on a
    /// fixture whose literal holds a combining acute, a ZWJ pair, an emoji with U+FE0F and a
    /// regional-indicator flag: the Swift pass emitted **26** spaces where the Python pass emitted
    /// **31**. With this projection both emit 31.
    ///
    /// The cost is the contract `codeOnly` used to have by accident: the result is no longer the
    /// same *`Character`* count as the input on such a file. It is the same **unicode scalar**
    /// count, which is the stronger of the two and the one both passes can honour. Nothing in the
    /// tree relied on the weaker form — measured at this commit, all 938 `.swift` files under
    /// `Cadence/`, `CadenceTests/`, `CadenceWidgets/` and `CadenceMCPServer/` hold **zero**
    /// combining marks, ZWJ joiners, variation selectors or regional indicators, so this changes
    /// no existing reading. `strippingComments` is a different function and still preserves the
    /// `Character` count, which is what `CadenceCommitSurfaceScan.scanned` asserts.
    ///
    /// **What is left, and it is narrow.** The two passes still index text differently, so a
    /// combining mark written *directly onto* a syntactic character — a `"`, `#`, `/`, `\` or a
    /// parenthesis — would still be one `Character` here and two code points there.
    /// `CadenceBlankingPassParityTests` pins that class at zero across the tree, so the day such a
    /// file arrives the next agent is told rather than surprised.
    private static func blankedSpansAsSpaces(_ characters: [Character], _ blanked: [Bool]) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(characters.count)
        for position in characters.indices {
            guard blanked[position] else {
                result.append(contentsOf: characters[position].unicodeScalars)
                continue
            }
            for scalar in characters[position].unicodeScalars {
                result.append(lineTerminators.contains(scalar) ? scalar : Unicode.Scalar(" "))
            }
        }
        return String(result)
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

/// One declaration's body, or a throw: `CadenceSourceScan.declarationBody` plus the two guards a
/// scoped scan wants. A miss is an error rather than a `nil`, and a body under 40 characters is
/// refused, because a `""` body passes every zero-count assertion written against it — the vacuity
/// trap `Cadence/Shared/AGENTS.md` names.
///
/// Scoping a count to one body is the point: a whole-file needle count is blind to a call moving
/// *between* two functions in the file, which is the hole a mutation of `accept(_:)` walked through
/// and the shape `docs/TODO.md` T-161 is about.
///
/// **T-668, and there must not be a second one.** This used to be declared in
/// `FocusPickerPlayControlTests` and matched braces itself, which is how it still had the
/// pre-T-644 defect after that fix landed. It is a wrapper now, so the repository has one brace
/// matcher and its 83 call sites read the span the shared reader says they do. Anything that wants
/// to scope a scan to one declaration calls this or `declarationBody` rather than writing its own.
func cadenceFunctionBody(_ declaration: String, in code: String) throws -> String {
    guard code.range(of: declaration) != nil else {
        throw SourceBodyScanError.notFound(declaration)
    }
    guard let body = CadenceSourceScan.declarationBody(declaration, in: code) else {
        throw SourceBodyScanError.unbalanced(declaration)
    }
    guard body.count > 40 else { throw SourceBodyScanError.tooShort(declaration) }
    return body
}

enum SourceBodyScanError: Error {
    case notFound(String)
    case tooShort(String)
    case unbalanced(String)
}
