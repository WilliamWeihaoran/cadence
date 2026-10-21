import Foundation
import Testing

/// **[[T-3277]] option (a).** An attribute left on its own line after the declaration it belonged to
/// was deleted, so it now falls through onto whatever declaration comes next — or onto nothing.
///
/// **The shape that bit, exactly ([[T-3276]]).** [[T-3197]] (`db2b561e`) deleted
/// `emptyStateSection` from `TasksPanel` and wrote its tombstone comment *between* the function's
/// `@ViewBuilder` and the deleted declaration. Comments are invisible to attribute attachment, so the
/// bare `@ViewBuilder` attached ~40 lines down to `naturalTodayRows(derived:showsRollover:)`, which
/// returns `[AppTask]`. Xcode 27 on this Mac compiled that; CI's Xcode 26.0.1 failed it with
/// `static method 'buildExpression' requires that '[AppTask]' conform to 'View'`, so every local
/// gate stayed green and the first sign was a red CI run (39552321106). `5a3839e0` deleted the line.
///
/// **The rule: an attribute-only line must not reach its declaration across a BLANK line.** Lines
/// made only of comments may sit between them — the tree does that deliberately, a `@Suite("…")`
/// over the `//` paragraph explaining the `@MainActor` below it, a `@discardableResult` above a
/// `///` parameter doc — but a blank line is where one declaration ended and the next began, and
/// the tombstone shape always has one: the deleted body's paragraph, a blank, then the next
/// declaration's own doc comment. Measured at this commit over every `.swift` file in the five
/// compiled roots: the "any comment in between" rule fires twice, on exactly those two deliberate
/// sites; this rule fires **zero** times on the tree and once on `5a3839e0~1`'s `TasksPanel.swift`,
/// at line 397, the attribute CI rejected.
///
/// **What it does not see, stated so it is inherited rather than rediscovered.**
/// - A deleted body with **no** blank line or comment left behind: the attribute then sits directly
///   on the next declaration, which is indistinguishable in text from an intended attribute. Only
///   a type check sees that, and a result-builder mismatch is exactly what Xcode 27 lets through.
/// - An attribute whose argument list spans several lines (`@available(\n…)`): its first line is not
///   attribute-only, so it is never a candidate.
/// - Any other compile error that only the CI toolchain raises. This lint covers the one shape that
///   happened; [[T-3277]]'s options (b) and (c) are the owner's decision about the rest.
///
/// **Cost.** One walk and one read per file, then one ICU regex pass over the raw text; `codeOnly`
/// and the line splits run only on a file whose raw text already holds a candidate line, so most of
/// the corpus is never masked ([[T-3261]] records that the scan suites are the slow part of the run).
struct CadenceOrphanedAttributeLintTests {

    /// The roots CI compiles. `CadenceUITests` is in the list although the macOS test scheme does not
    /// run it, because CI still builds it and an orphaned attribute there fails the build the same way.
    static let compiledRoots = ["Cadence", "CadenceTests", "CadenceUITests", "CadenceWidgets", "CadenceMCPServer"]

    /// 1-based line numbers of every attribute-only line whose next code line lies across a blank
    /// line (or never arrives). Empty when the source is clean; `[0]` when the two views below
    /// disagree on the line count, which no clean file can produce.
    ///
    /// Reads two aligned views of the same lines: the RAW text, to tell a truly blank line from a
    /// comment line, and `CadenceSourceScan.codeOnly`, to decide what is code — so an `@Name` spelled
    /// inside a comment or a string literal (this file's own fixtures) is never a candidate. Both are
    /// split on `Character.isNewline`, which `codeOnly` preserves terminator-for-terminator, so the
    /// two arrays have the same count and index the same lines.
    static func orphanedAttributeLines(in source: String) -> [Int] {
        guard hasRawCandidate(source) else { return [] }
        let raw = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let code = CadenceSourceScan.codeOnly(source)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        // Misaligned views would make every index below a guess. Loud rather than quiet: line 0 is
        // never a real line, so the sweep names the file instead of passing it.
        guard code.count == raw.count else { return [0] }
        var hits: [Int] = []
        for index in code.indices where isAttributeOnly(code[index]) {
            var next = index + 1
            var orphaned = true
            while next < code.count {
                if !isBlank(code[next]) { orphaned = false; break }
                if isBlank(raw[next]) { break }
                next += 1
            }
            if orphaned { hits.append(index + 1) }
        }
        return hits
    }

    /// An `@`-led line followed by a blank, `/`- or `*`-led line, or by the end of the file; or an
    /// `@`-led line that opens a block comment, whose continuation lines can start with anything.
    /// One ICU pass over the raw text, which is what keeps the debug-built test host's per-
    /// `Character` work (`codeOnly`, the line splits) off the files that cannot hold a hit.
    private static let rawCandidateLine = try? NSRegularExpression(
        pattern: #"(?m)^[ \t]*(@[^\n]*)(?:\n[ \t]*(?:$|/|\*)|\z)|^[ \t]*(@[^\n]*/\*[^\n]*)$"#
    )

    /// The cheap raw pre-check that keeps `codeOnly` off most files, and a SUPERSET of what
    /// `orphanedAttributeLines` can flag. A flagged line is attribute-only in `codeOnly`, so in the
    /// raw text it is `@`-led (a line that opens inside a comment or a literal is blanked there, so
    /// it is never attribute-only) and is attributes plus, at most, literal text inside an argument
    /// list and a trailing comment. Its next line is blank in `codeOnly`, so in the raw text it is
    /// blank, a `//`/`/*`/`*` line, or the inside of a block comment the attribute line opened. A
    /// matched line is passed on when it holds a quote, a `#` (a raw literal) or a `/*`, which this
    /// cheap reading cannot see through, or when it is attribute-only once a trailing `//` is cut.
    private static func hasRawCandidate(_ source: String) -> Bool {
        guard let expression = rawCandidateLine else { return true }
        let text = source as NSString
        for match in expression.matches(in: source, range: NSRange(location: 0, length: text.length)) {
            let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            let line = text.substring(with: group)
            if line.contains("\"") || line.contains("#") || line.contains("/*") { return true }
            let code = line.range(of: "//").map { line[..<$0.lowerBound] } ?? Substring(line)
            if isAttributeOnly(code) { return true }
        }
        return false
    }

    private static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// One or more `@Name` / `@Name(…)` attributes and nothing else on the line. `@unknown default:`
    /// is not — `default:` is not an attribute — and neither is `@State private var …`.
    static func isAttributeOnly(_ line: Substring) -> Bool {
        var cursor = line.startIndex
        var attributes = 0
        while cursor < line.endIndex {
            let character = line[cursor]
            if character.isWhitespace { cursor = line.index(after: cursor); continue }
            guard character == "@" else { return false }
            cursor = line.index(after: cursor)
            let nameStart = cursor
            while cursor < line.endIndex,
                  line[cursor].isLetter || line[cursor].isNumber || line[cursor] == "_" || line[cursor] == "." {
                cursor = line.index(after: cursor)
            }
            guard cursor > nameStart else { return false }
            if cursor < line.endIndex, line[cursor] == "(" {
                var depth = 0
                repeat {
                    if line[cursor] == "(" { depth += 1 } else if line[cursor] == ")" { depth -= 1 }
                    cursor = line.index(after: cursor)
                } while depth > 0 && cursor < line.endIndex
                guard depth == 0 else { return false }
            }
            attributes += 1
        }
        return attributes > 0
    }

    /// `5a3839e0~1`'s `TasksPanel.swift` around line 397, cut down: the attribute, the tombstone, the
    /// blank, and the next declaration's doc comment and signature.
    static let t3276Shape = """
        struct TasksPanel {
            @ViewBuilder
            // [[T-3197]] removed TasksPanel.emptyStateSection — Today's "Nothing planned" box.
            //
            // What is NOT gone, and was checked per reader rather than assumed:
            //   - `TasksPanelDerivedState.isEmptyState`. It keeps its tests and its meaning.

            /// **The rows Today draws, in natural order.**
            private func naturalTodayRows(derived: TasksPanelDerivedState, showsRollover: Bool) -> [AppTask] {
                []
            }
        }
        """

    /// The nearest legitimate shape, and the one the tree holds: the comment between the attribute
    /// and its declaration has no blank line in it (`CadenceListNoteFiling.createNote`).
    static let attachedAcrossADocComment = """
        enum Filing {
            @discardableResult
            /// - Parameter title: The note's title.
            ///   It is a parameter rather than a second write.
            static func createNote(title: String) -> Int { 0 }
        }
        """

    static func instrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "attribute separated from its declaration by a blank line",
            fires: t3276Shape,
            andNotOn: attachedAcrossADocComment,
            by: { !orphanedAttributeLines(in: $0).isEmpty }
        )
    }

    @Test func theLintNamesTheLineCIRejectedAndLeavesItsNeighboursAlone() throws {
        // The positive witness, pinned to the attribute's own line rather than "fires somewhere".
        #expect(Self.orphanedAttributeLines(in: Self.t3276Shape) == [2])
        #expect(Self.orphanedAttributeLines(in: Self.attachedAcrossADocComment).isEmpty)

        let firing: [(String, [Int])] = [
            // The deleted body's attribute with nothing at all after it but a blank line.
            ("@MainActor\n\nfunc next() {}\n", [1]),
            // Two attributes on one line, and an argument list, are still one attribute-only line.
            ("@MainActor @discardableResult\n\nfunc next() -> Int { 0 }\n", [1]),
            ("@available(*, deprecated, message: \"gone\")\n// tombstone\n\nvar next: Int { 0 }\n", [1]),
            // A trailing comment on the attribute line does not make it code.
            ("    @ViewBuilder // was emptyStateSection\n\n    func rows() -> [Int] { [] }\n", [1]),
            // A block comment the attribute line opens, whose middle line starts with a letter.
            ("@MainActor /* was the store's\n   main-actor hop */\n\nfunc next() {}\n", [1]),
            // Attached to nothing: comments run to the end of the file.
            ("struct S {}\n@MainActor\n// the body below was deleted\n", [2]),
        ]
        for (source, lines) in firing {
            #expect(Self.orphanedAttributeLines(in: source) == lines, "\(source.debugDescription)")
        }

        let quiet = [
            // `MarkdownTableMobileEditingTests`: a `//` paragraph between two attributes, no blank.
            "@Suite(\"Mobile\")\n// isolated because the conformance is main-actor\n@MainActor\nstruct T {}\n",
            "@MainActor\nfinal class Store {}\n",
            "switch x {\n@unknown default:\n\n    break\n}\n",
            "    @State private var isOpen = false\n\n    var body: some View { EmptyView() }\n",
            // Attribute text inside a comment and inside a literal is not an attribute.
            "// @ViewBuilder\n\nfunc rows() -> [Int] { [] }\n",
            "let fixture = \"\"\"\n@ViewBuilder\n\nfunc rows()\n\"\"\"\n",
        ]
        for source in quiet {
            #expect(Self.orphanedAttributeLines(in: source).isEmpty, "\(source.debugDescription)")
        }
    }

    /// **The sweep.** Every `.swift` file in the compiled roots, walked by the shared whole-tree walk
    /// so a nested checkout (`.claude/worktrees/…`) and the root `scratchpad/` are pruned the way
    /// every other whole-tree scan prunes them ([[T-3241]]).
    @Test func noAttributeInTheCompiledTreeIsSeparatedFromItsDeclarationByABlankLine() throws {
        let instrument = try Self.instrument()
        let roots = Self.compiledRoots.map { $0 + "/" }
        let paths = CadenceSourceScan.repositoryPaths(pruningAtRoot: ["scratchpad"])
            .filter { path in path.hasSuffix(".swift") && roots.contains { path.hasPrefix($0) } }
        for witness in ["CadenceWidgets/TodayTasksWidget.swift", "CadenceMCPServer/CadenceMCPToolRouter.swift"] {
            #expect(paths.contains(witness), "the walk stopped reaching \(witness)")
        }

        var sources: [String: String] = [:]
        let hits = try instrument.sweep(
            paths,
            atLeast: 1000,
            including: "Cadence/macOS/Views/TasksPanel.swift",
            read: { path in
                let source = try CadenceSourceScan.sourceFile(path)
                sources[path] = source
                return source
            }
        )
        let located = hits.flatMap { path in
            Self.orphanedAttributeLines(in: sources[path] ?? "").map { "\(path):\($0)" }
        }
        #expect(
            hits.isEmpty,
            """
            an attribute-only line reaches its declaration across a blank line, so it is attached to \
            whatever comes next — the T-3276 shape Xcode 26.0.1 rejects and Xcode 27 accepts. Delete the \
            attribute with the body it belonged to, or move it back onto its declaration: \(located)
            """
        )
    }
}
