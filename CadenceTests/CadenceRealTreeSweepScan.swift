import Foundation

/// Which `@Test` functions in this target sweep the **real product tree**, derived from the target's
/// own source rather than listed by hand.
///
/// **Why this exists (T-808).** An audit measured 216 tests that walk `Cadence/`,
/// `CadenceWidgets/` or `CadenceMCPServer/` and found that **none** of them was pinned: delete any
/// one `@Test` function and no other test goes red, because the ledgers, parsers and fixtures
/// beside it all keep passing while the app-wide sweep silently stops happening. "The suite is
/// green" then rests on 216 tests that nothing requires to exist.
///
/// The fix is one exact manifest — `CadenceRealTreeSweepManifest.txt` — checked by
/// `CadenceTestTargetHygieneTests`. Two properties make it an instrument rather than the next
/// stale ledger:
///
/// - **It is generated, not typed.** This scan is the generator;
///   `scripts/real-tree-sweep-manifest.sh` runs it and rewrites the file from what it computed.
///   `scripts/test-suite-index.sh` cannot produce it: that script answers *which suite declares a
///   test*, and has no notion of what a test's body reaches, so the classification below would have
///   had to live in a shell script where no test can fail on it.
/// - **It duplicates no detector.** It never asks what any swept rule asserts — only whether a
///   test's own reach contains a walk of the product tree. The original suites stay the
///   behavioural authority; the manifest exists so that deleting one of them is visible.
///
/// ## The rule, in one sentence
///
/// A `@Test` is a real-tree sweep when its body, plus every declaration in this target that body
/// transitively names, contains all three of: a **walk** (`swiftFiles(`, `enumerator(atPath:`,
/// `enumerator(at:`, `contentsOfDirectory(at`, `subpathsOfDirectory`, or a
/// `CadenceScanInstrument.sweep(`), a **product-root path literal** (`Cadence`, `CadenceWidgets`
/// or `CadenceMCPServer`, optionally with a subpath), and **Swift-source evidence** (`swiftFiles(`
/// or a `.swift` path literal).
///
/// All three are load-bearing, and each excludes a family the audit's own boundary excludes:
///
/// - without the walk, every fixed-file `sourceFile("Cadence/…")` assertion would qualify;
/// - without the product root, `themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse`'s walk
///   of `CadenceTests` would, and it sweeps the *test* target, not the app;
/// - without the Swift evidence, `AgentContextBudgetTests` would, and it walks `AGENTS.md`.
///
/// ## Two things that look like details and are not
///
/// - **Walk needles are read from code, path literals from the raw source.** A test that *quotes*
///   `swiftFiles(under: "Cadence")` in a fixture is not a sweep, so the walk is looked for in
///   `CadenceSourceScan.codeOnly` output, where literals are blanked. The path literal is the
///   opposite question and has to be read where literals survive.
/// - **The product-root pattern is assembled rather than spelled.** Written out, this file's own
///   source would contain the literal it scans for, and every test that calls into this scan would
///   classify itself as a product-tree sweep. Same family as `codeOnly`'s reason for existing.
enum CadenceRealTreeSweepScan {

    /// Deliberately spelled without the word "error": `docs/AGENTS_REFERENCE.md`'s compile-error
    /// count greps for it and a thrown scan failure is a kill, not a build break.
    enum Failure: Swift.Error, CustomStringConvertible {
        case maskOffsetsDisagree(path: String)
        case patternDidNotCompile(String)
        case manifestLineMalformed(String)

        var description: String {
            switch self {
            case .maskOffsetsDisagree(let path):
                return "masking \(path) changed its offsets, so spans read the wrong text"
            case .patternDidNotCompile(let pattern):
                return "the scan's own pattern did not compile: \(pattern)"
            case .manifestLineMalformed(let line):
                return "manifest line is not Suite/testName: \(line)"
            }
        }
    }

    /// One `@Test`, as the manifest spells it.
    struct Entry: Hashable, Comparable, CustomStringConvertible {
        let suite: String
        let name: String

        var description: String { "\(suite)/\(name)" }

        static func < (lhs: Entry, rhs: Entry) -> Bool { lhs.description < rhs.description }
    }

    /// The three facts a sweep's reach must contain. An `OptionSet` rather than three `Bool`s
    /// because the transitive step is a union, and a union of triples is one line.
    struct Markers: OptionSet {
        let rawValue: Int
        static let walk = Markers(rawValue: 1 << 0)
        static let productPath = Markers(rawValue: 1 << 1)
        static let swiftSource = Markers(rawValue: 1 << 2)
        static let sweep: Markers = [.walk, .productPath, .swiftSource]
    }

    static let manifestPath = "CadenceTests/CadenceRealTreeSweepManifest.txt"

    /// The marker `scripts/real-tree-sweep-manifest.sh` reads the regenerated file back out of.
    static let regeneratedBanner = "REGENERATED REAL-TREE SWEEP MANIFEST"

    // MARK: - Needles

    private static let walkNeedles = [
        "swiftFiles(",
        "enumerator(atPath:",
        "enumerator(at:",
        "contentsOfDirectory(at",
        "subpathsOfDirectory",
        ".sweep(",
    ]

    /// `"Cadence"`, `"Cadence/…"`, `"CadenceWidgets…"`, `"CadenceMCPServer…"` — and assembled from
    /// pieces so this file does not contain the literal it looks for. `CadenceTests` is not a
    /// product root and must not match, which is why the alternation is anchored by the closing
    /// quote or a `/`.
    private static var productRootPattern: String {
        let quote = "\u{22}"
        return quote + "(?:Cadence|CadenceWidgets|CadenceMCPServer)(?:/[^" + quote + "\n]*)?" + quote
    }

    /// A walk that never mentions Swift source is a walk of something else — `AGENTS.md`, a
    /// `docs/` tree, an asset catalogue.
    private static var swiftSourcePattern: String {
        "swiftFiles\\(|\\.swift" + "\u{22}"
    }

    // MARK: - The public reads

    /// Every real-tree sweep in `CadenceTests`, sorted.
    static func entries() throws -> [Entry] {
        try entries(inSources: cadenceTestFiles().map { (path: $0, source: try cadenceTestSource($0)) })
    }

    /// The same computation over sources handed in, so the classifier can be shown two witnesses
    /// that a plausible mistake separates without touching the repository.
    static func entries(inSources sources: [(path: String, source: String)]) throws -> [Entry] {
        guard let productRegex = try? NSRegularExpression(pattern: productRootPattern) else {
            throw Failure.patternDidNotCompile(productRootPattern)
        }
        guard let swiftRegex = try? NSRegularExpression(pattern: swiftSourcePattern) else {
            throw Failure.patternDidNotCompile(swiftSourcePattern)
        }
        guard let declarationRegex = try? NSRegularExpression(
            pattern: "\\b(?:func|var|let)\\s+([A-Za-z0-9_]+)"
        ) else { throw Failure.patternDidNotCompile("declaration") }
        guard let testRegex = try? NSRegularExpression(
            pattern: "@Test\\b(?s:.)*?\\bfunc\\s+([A-Za-z0-9_]+)"
        ) else { throw Failure.patternDidNotCompile("@Test") }
        guard let identifierRegex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*"),
              let qualifiedRegex = try? NSRegularExpression(
                  pattern: "\\b([A-Z][A-Za-z0-9_]*)\\s*\\.\\s*([a-z][A-Za-z0-9_]*)"
              )
        else { throw Failure.patternDidNotCompile("reference") }

        func markers(codeSlice: String, rawSlice: String) -> Markers {
            var found: Markers = []
            if walkNeedles.contains(where: { codeSlice.contains($0) }) { found.insert(.walk) }
            let rawRange = NSRange(location: 0, length: (rawSlice as NSString).length)
            if productRegex.firstMatch(in: rawSlice, range: rawRange) != nil {
                found.insert(.productPath)
            }
            if swiftRegex.firstMatch(in: rawSlice, range: rawRange) != nil {
                found.insert(.swiftSource)
            }
            return found
        }

        func references(in codeSlice: String) -> (names: Set<String>, qualified: Set<String>) {
            let text = codeSlice as NSString
            let range = NSRange(location: 0, length: text.length)
            var names: Set<String> = []
            for match in identifierRegex.matches(in: codeSlice, range: range) {
                names.insert(text.substring(with: match.range))
            }
            var qualified: Set<String> = []
            for match in qualifiedRegex.matches(in: codeSlice, range: range) {
                qualified.insert(
                    "\(text.substring(with: match.range(at: 1))).\(text.substring(with: match.range(at: 2)))"
                )
            }
            return (names, qualified)
        }

        var declarations: [ParsedDeclaration] = []
        var parsedTests: [ParsedTest] = []
        var testNames: Set<String> = []

        for (fileIndex, file) in sources.enumerated() {
            let raw = offsetStableSource(file.source)
            let code = CadenceSourceScan.codeOnly(raw)
            let nsRaw = raw as NSString
            let nsCode = code as NSString
            guard nsCode.length == nsRaw.length else {
                throw Failure.maskOffsetsDisagree(path: file.path)
            }

            var depths = [Int](repeating: 0, count: nsCode.length)
            var depth = 0
            for offset in 0..<nsCode.length {
                depths[offset] = depth
                let unit = nsCode.character(at: offset)
                if unit == 0x7B { depth += 1 } else if unit == 0x7D { depth -= 1 }
            }

            let extents = cadenceTopLevelTypeExtents(inCodeOnly: code)
            // The same reader again, over a copy in which `extension Foo {` reads as a type
            // declaration. Two questions, two answers: which **suite** declares a test has to stay
            // character for character what `cadenceTestDeclarations` says (a `@Test` in an
            // extension is file scope there, and a test already asserts that), while *who owns
            // this member* must count `extension CadenceSourceScan`'s members as
            // `CadenceSourceScan`'s, or a `Type.member` hop into one resolves to nothing.
            let ownerExtents = cadenceTopLevelTypeExtents(inCodeOnly: extensionsReadAsTypes(code))
            let whole = NSRange(location: 0, length: nsCode.length)

            for match in testRegex.matches(in: code, range: whole) {
                let nameRange = match.range(at: 1)
                let name = nsCode.substring(with: nameRange)
                testNames.insert(name)
                guard let span = declarationSpan(
                    inCode: nsCode,
                    declaration: nameRange.location,
                    afterName: nameRange.location + nameRange.length,
                    isFunction: true
                ) else { continue }
                let suite = extents.last { $0.open < match.range.location && match.range.location < $0.close }?.name
                    ?? CadenceTestDeclaration.fileScope
                let codeSlice = nsCode.substring(with: span)
                let found = references(in: codeSlice)
                parsedTests.append(
                    ParsedTest(
                        entry: Entry(suite: suite, name: name),
                        fileIndex: fileIndex,
                        markers: markers(codeSlice: codeSlice, rawSlice: nsRaw.substring(with: span)),
                        references: found.names,
                        qualified: found.qualified
                    )
                )
            }

            for match in declarationRegex.matches(in: code, range: whole) {
                // File scope and one type deep. A `let` inside a function body is a local, and
                // resolving those by name across a file is what turned an earlier version of this
                // scan into "every test walks the tree".
                guard depths[match.range.location] <= 1 else { continue }
                let nameRange = match.range(at: 1)
                let isFunction = nsCode.substring(
                    with: NSRange(location: match.range.location, length: 4)
                ) == "func"
                guard let span = declarationSpan(
                    inCode: nsCode,
                    declaration: match.range.location,
                    afterName: nameRange.location + nameRange.length,
                    isFunction: isFunction
                ) else { continue }
                let codeSlice = nsCode.substring(with: span)
                let found = references(in: codeSlice)
                declarations.append(
                    ParsedDeclaration(
                        name: nsCode.substring(with: nameRange),
                        isFileScope: depths[match.range.location] == 0,
                        owner: ownerExtents.last {
                            $0.open < match.range.location && match.range.location < $0.close
                        }?.name,
                        fileIndex: fileIndex,
                        markers: markers(codeSlice: codeSlice, rawSlice: nsRaw.substring(with: span)),
                        references: found.names,
                        qualified: found.qualified
                    )
                )
            }
        }

        // A `@Test` is never a hop target: one test naming another test's function does not make
        // the caller a sweep, and `@Test` functions match the declaration pattern too.
        var byFileAndName: [Int: [String: [Int]]] = [:]
        var byQualifiedName: [String: [Int]] = [:]
        var byFileScopeName: [String: [Int]] = [:]
        for (index, declaration) in declarations.enumerated() where !testNames.contains(declaration.name) {
            byFileAndName[declaration.fileIndex, default: [:]][declaration.name, default: []].append(index)
            if let owner = declaration.owner {
                byQualifiedName["\(owner).\(declaration.name)", default: []].append(index)
            }
            if declaration.isFileScope {
                // `CadenceTests` is one module, so a file-scope `func retiredCopySwiftFiles` is
                // callable unqualified from any file in it. Resolving these only inside their own
                // file is how a sweep written as a bare call to a helper next door reads as a test
                // that touches nothing.
                byFileScopeName[declaration.name, default: []].append(index)
            }
        }

        // An unqualified name is resolved **in the file of the test being classified**, never in
        // the file of whichever helper mentioned it. That asymmetry is deliberate and measured:
        // resolving each helper's own bare names inside its own file walks the shared support file
        // by its internal plumbing — `functionBody` reaches `declarationBody` reaches a walker —
        // and then every one of the 700-odd tests that calls `CadenceSourceScan.functionBody`
        // classifies as a product-tree sweep. That spelling returned 592 tests where this one
        // returns 240, and the extra 352 do not walk anything.
        func resolved(
            inFile fileIndex: Int,
            references: Set<String>,
            qualified: Set<String>
        ) -> [Int] {
            var indices: [Int] = []
            for (name, declared) in byFileAndName[fileIndex] ?? [:] where references.contains(name) {
                indices.append(contentsOf: declared)
            }
            for name in references {
                indices.append(contentsOf: byFileScopeName[name] ?? [])
            }
            for name in qualified {
                indices.append(contentsOf: byQualifiedName[name] ?? [])
            }
            return indices
        }

        var sweeps: [Entry] = []
        for test in parsedTests {
            var union = test.markers
            var visited: Set<Int> = []
            var frontier = resolved(
                inFile: test.fileIndex,
                references: test.references,
                qualified: test.qualified
            )
            while let index = frontier.popLast() {
                guard visited.insert(index).inserted else { continue }
                union.formUnion(declarations[index].markers)
                if union.contains(Markers.sweep) { break }
                frontier.append(
                    contentsOf: resolved(
                        inFile: test.fileIndex,
                        references: declarations[index].references,
                        qualified: declarations[index].qualified
                    )
                )
            }
            if union.contains(Markers.sweep) { sweeps.append(test.entry) }
        }
        return Array(Set(sweeps)).sorted()
    }

    /// The committed manifest, parsed. Blank lines and `#` comments are ignored so the file can
    /// carry the one line that says how to regenerate it.
    static func manifest() throws -> [Entry] {
        try manifest(in: cadenceTestSource(manifestPath))
    }

    static func manifest(in contents: String) throws -> [Entry] {
        try contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { line in
                let halves = line.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty else {
                    throw Failure.manifestLineMalformed(line)
                }
                return Entry(suite: String(halves[0]), name: String(halves[1]))
            }
    }

    /// The file `scripts/real-tree-sweep-manifest.sh` writes, printed between banners so the
    /// script can lift it out of an `xcodebuild` log without a second copy of the classifier.
    static func printRegenerated(_ entries: [Entry]) {
        print("--- BEGIN \(regeneratedBanner)")
        print(manifestContents(entries), terminator: "")
        print("--- END \(regeneratedBanner)")
    }

    static func manifestContents(_ entries: [Entry]) -> String {
        var lines = [
            "# Every @Test in CadenceTests that sweeps the real product tree (T-808).",
            "# Generated — do not hand-edit. Regenerate with:",
            "#   scripts/real-tree-sweep-manifest.sh <agent-id> --write",
            "# Deleting a line here, or the @Test it names, fails CadenceTestTargetHygieneTests.",
        ]
        lines.append(contentsOf: entries.map(\.description))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    private struct ParsedDeclaration {
        let name: String
        /// Brace depth 0 — a declaration the whole module can call unqualified. Depth is the test,
        /// not "has no enclosing type": a `let enumerator = FileManager.default.enumerator(atPath:)`
        /// inside a file-scope function has no owning type either, and registering *that* as a
        /// module-wide name called `enumerator` hands a walk marker to every test whose reach
        /// mentions the word. Measured: 554 tests classified as sweeps instead of 240.
        let isFileScope: Bool
        /// The top-level type that encloses it, or `nil` for a file-scope declaration — which in
        /// one module is visible to every other file, and is resolved that way below.
        let owner: String?
        let fileIndex: Int
        let markers: Markers
        let references: Set<String>
        let qualified: Set<String>
    }

    private struct ParsedTest {
        let entry: Entry
        let fileIndex: Int
        let markers: Markers
        let references: Set<String>
        let qualified: Set<String>
    }

    /// `extension Foo {` rewritten to `enum      Foo {` — ten characters for ten, so every offset
    /// in the copy still points at the same text in the original. Reusing the shared extent reader
    /// on a rewritten copy rather than writing a second brace matcher beside it: this repository's
    /// most common defect is the second copy of an answer like that, and a matcher that runs off
    /// the end of a file is invisible to everything except the wrong answer it produces (T-465).
    ///
    /// Only a real declaration survives to be rewritten — comments and literals are already blank
    /// in the code this is handed, and `extension` is a keyword, so nothing else can spell it.
    static func extensionsReadAsTypes(_ code: String) -> String {
        code.replacingOccurrences(of: "extension ", with: "enum      ")
    }

    /// Every `Character` becomes one UTF-16 unit, so `codeOnly`'s masked copy keeps the source's
    /// offsets and a span read from one can be read from the other.
    ///
    /// Not hypothetical: two files in this target hold `🙂` inside a fixture literal.
    /// `codeOnly` blanks a whole `Character` to one space, so past that emoji the masked string is
    /// one UTF-16 unit shorter than the source and every span afterwards reads the wrong text —
    /// silently, in the direction that loses sweeps.
    static func offsetStableSource(_ source: String) -> String {
        guard source.contains(where: { $0.utf16.count > 1 }) else { return source }
        return String(source.map { $0.utf16.count == 1 ? $0 : "?" })
    }

    /// The span of one declaration, from its keyword to the end of its body or initialiser.
    ///
    /// The signature is inside the span on purpose: `declaredComponentNames(under: String =
    /// "Cadence")` keeps the only path literal it has in a *parameter default*, and a span that
    /// started at the opening brace would drop it.
    private static func declarationSpan(
        inCode code: NSString,
        declaration start: Int,
        afterName nameEnd: Int,
        isFunction: Bool
    ) -> NSRange? {
        var cursor = nameEnd
        while cursor < code.length {
            let unit = code.character(at: cursor)
            if unit == 0x28 || unit == 0x7B || unit == 0x0A || unit == 0x3D { break }
            cursor += 1
        }
        guard cursor < code.length else { return nil }
        let unit = code.character(at: cursor)

        if isFunction {
            var resume = cursor
            if unit == 0x28 {
                guard let closed = balanced(in: code, from: cursor, open: 0x28, close: 0x29) else {
                    return nil
                }
                resume = closed + 1
            }
            // The body's `{`, not a `{` further down the file: a declaration whose body never
            // opens (a protocol requirement, a `func` in a comment-stripped fixture) must return
            // nothing rather than swallow the next declaration whole.
            var scan = resume
            var open = NSNotFound
            while scan < code.length, scan - resume <= 400 {
                if code.character(at: scan) == 0x7B { open = scan; break }
                scan += 1
            }
            guard open != NSNotFound,
                  let closed = balanced(in: code, from: open, open: 0x7B, close: 0x7D)
            else { return nil }
            return NSRange(location: start, length: closed + 1 - start)
        }

        if unit == 0x7B {
            guard let closed = balanced(in: code, from: cursor, open: 0x7B, close: 0x7D) else {
                return nil
            }
            return NSRange(location: start, length: closed + 1 - start)
        }

        guard unit == 0x3D else { return nil }
        var value = cursor + 1
        while value < code.length, isWhitespaceUnit(code.character(at: value)) { value += 1 }
        if value < code.length {
            let opening = code.character(at: value)
            let closing: unichar? = opening == 0x5B ? 0x5D : (opening == 0x28 ? 0x29 : (opening == 0x7B ? 0x7D : nil))
            if let closing, let closed = balanced(in: code, from: value, open: opening, close: closing) {
                return NSRange(location: start, length: closed + 1 - start)
            }
        }
        var end = cursor
        while end < code.length, code.character(at: end) != 0x0A { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespaceUnit(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    /// The offset of the delimiter that closes the pair opening at `start`, or `nil` when it never
    /// balances.
    private static func balanced(
        in code: NSString,
        from start: Int,
        open: unichar,
        close: unichar
    ) -> Int? {
        var depth = 0
        var cursor = start
        while cursor < code.length {
            let unit = code.character(at: cursor)
            if unit == open {
                depth += 1
            } else if unit == close {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }
}
