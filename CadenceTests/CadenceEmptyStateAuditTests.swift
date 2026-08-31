import Foundation
import SwiftData
import Testing
@testable import Cadence

// MARK: - Reading empty states out of source

/// The `message:` / `title:` / `subtitle:` arguments of every empty-state call in a file.
///
/// **Why source and not values.** An empty state is two string arguments passed to a `View`
/// initialiser from inside another `View`'s `body`. There is no seam: nothing a test can call
/// returns "the words this screen shows when it is empty", and `Cadence/iOS/` is not compiled by
/// this target at all. So the shape is read as text — but read *scoped to the call*, because a
/// file-wide `contains` cannot tell an empty state's subtitle from a button label thirty lines
/// away.
enum CadenceEmptyStateAudit {

    /// **Every empty-state component in the tree, read out of the declarations** (T-548).
    ///
    /// This used to be `["EmptyStateView(", "iOSEmptyPanel("]` — two of the app's five — and a
    /// hardcoded list is exactly what went stale. `Cadence/iOS/iOSFeatureViews.swift` contained
    /// zero occurrences of either name, so the whole file was invisible to the duplicate sweep
    /// while it re-typed `"No goals yet"` and spelled `"No habits yet"` a second time. It reaches
    /// `iOSEmptyPanel` one hop away, through `iOSFeatureEmptyState` → `iOSFeatureEmptyDetail.body`,
    /// and that call carries only identifiers — so no widening of the *reader* could have found it.
    ///
    /// Adding the three missing names would have left the next component to be noticed by hand, so
    /// the set is derived instead: **a `struct` whose name carries `Empty` or `Placeholder`.**
    /// Measured over `Cadence/` — 23 components against the 2 that were listed, 21 files
    /// hand-spelling copy against 10, 47 literals under audit against 23, and **no new duplicate
    /// beyond the two real ones**, so the widening cost nothing in false positives.
    ///
    /// Two things stop this from being a quieter version of the same staleness:
    ///
    /// - `everyEmptyStateShapedViewIsOneTheSweepReads` derives the family a **second** way, from
    ///   the shape of the declaration rather than its name, and fails when the two disagree. A
    ///   component called `NothingHereView` is caught there.
    /// - An empty derivation cannot reach a sweep. `emptyStateLiteralInstrument`'s positive witness
    ///   spells `EmptyStateView(`, so `try?` returning `[]` here throws `Failure.blind` at the
    ///   instrument's initialiser rather than passing a walk over nothing.
    static let componentNames: [String] = (try? declaredComponentNames()) ?? []

    /// A `struct` declaration whose name carries `Empty` or `Placeholder`.
    static let componentDeclarationPattern =
        "struct +([A-Za-z0-9_]*(?:Empty|Placeholder)[A-Za-z0-9_]*) *[:{]"

    /// The empty-state component names declared under `relativeDirectory`, each with its `(`.
    ///
    /// Read through `codeOnly`, which blanks string literals as well as comments: this is a scan
    /// for a *declaration shape*, so a file quoting `"struct FooEmpty {"` must not be harvested.
    /// The copy assertions elsewhere in this suite need the opposite reader, which
    /// `theCopyReaderKeepsLiteralsAndTheStructuralReaderDoesNot` pins.
    static func declaredComponentNames(under relativeDirectory: String = "Cadence") throws -> [String] {
        let regex = try NSRegularExpression(pattern: componentDeclarationPattern)
        var names: Set<String> = []
        for path in try CadenceSourceScan.swiftFiles(under: relativeDirectory) {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                names.insert(String(source[captured]))
            }
        }
        return names.sorted().map { "\($0)(" }
    }

    /// The argument labels an empty state's words arrive under.
    ///
    /// `text` and `placeholder` are T-548's: `CadenceInlineEmpty` takes `text:` and
    /// `iOSMarkdownEmptyPrompt` takes `placeholder:`, so listing those components without their
    /// labels would have re-made the same defect one level down — a component the sweep names and
    /// reads nothing out of. `everyCopyBearingArgumentOfAnEmptyStateComponentIsReadable` fails when
    /// a component carries a `String` the reader has no label for.
    static let argumentLabels = ["message", "title", "subtitle", "text", "placeholder"]

    /// `String` parameters of an empty-state component that are **not** copy, so the label rule
    /// above does not have to list them one by one.
    ///
    /// `icon` and `systemImage` are SF Symbol names — a picture, not a sentence, the same
    /// distinction `CadenceSharedConstantReuseSweepTests` makes when it drops glyph names from its
    /// harvest. `query` is what the reader typed.
    static let nonCopyArgumentLabels = ["icon", "systemImage", "query"]

    private static let literalPattern = "\"([^\"\\\\\\n]*)\""

    /// The text between the parentheses of each empty-state call, brace-matched over the call's own
    /// `(`…`)` so a later call's arguments cannot leak into an earlier one's segment.
    ///
    /// String literals are skipped while counting depth: a subtitle reading `"Try (again)"` would
    /// otherwise close the call early and truncate everything after it.
    static func callSegments(in source: String) -> [String] {
        var segments: [String] = []
        for name in componentNames {
            var searchStart = source.startIndex
            while let found = source.range(of: name, range: searchStart..<source.endIndex) {
                searchStart = found.upperBound
                // The name must start an identifier. With the set derived rather than listed
                // (T-548), one component's name can be the tail of another's — `EmptyStateView(`
                // inside a hypothetical `GoalsEmptyStateView(` — and a substring match would then
                // read the same call twice under two names.
                if found.lowerBound > source.startIndex {
                    let previous = source[source.index(before: found.lowerBound)]
                    if previous.isLetter || previous.isNumber || previous == "_" { continue }
                }
                var depth = 1
                var index = found.upperBound
                var inLiteral = false
                while index < source.endIndex, depth > 0 {
                    let character = source[index]
                    if inLiteral {
                        if character == "\\" {
                            index = source.index(after: index)
                        } else if character == "\"" || character.isNewline {
                            inLiteral = false
                        }
                    } else if character == "\"" {
                        inLiteral = true
                    } else if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    guard index < source.endIndex else { break }
                    index = source.index(after: index)
                }
                if index <= source.endIndex {
                    segments.append(String(source[found.upperBound..<min(index, source.endIndex)]))
                }
            }
        }
        return segments
    }

    /// The **whole argument expression** written under each `message:` / `title:` / `subtitle:`
    /// label in one call segment, in source order.
    ///
    /// **This is T-540's fix, and the reason it is an expression rather than a literal.** The
    /// reader used to be one regex — `(?:message|title|subtitle)\s*:\s*"…"` — which matches a
    /// literal placed *directly* after the colon and nothing else. Every filter-aware empty state
    /// in the app is written the other way:
    ///
    /// ```swift
    /// message: isNarrowedToEmpty ? "No matching goals" : "No goals yet",
    /// ```
    ///
    /// so the copy that distinguishes "you have nothing" from "your filter matched nothing" — the
    /// exact distinction the second half of this suite exists to enforce — was invisible to the
    /// first half of it. `"No goals yet"` and `"No matching goals"` were spelled in both
    /// `GoalsView` and `GoalTimelineView` while the duplicate sweep reported the tree clean.
    ///
    /// The expression ends at the first `,` written at the argument's own bracket depth, or at the
    /// bracket that closes the call. Depth counts `(`, `[` and `{` alike — a subtitle built by a
    /// closure or a subscript is still one argument — and literals are skipped while counting, so
    /// a sentence containing a comma or a bracket cannot end its own argument early.
    ///
    /// The label is read at the **top level of the call only**, which is stricter than the regex
    /// this replaces. That matters now in a way it did not then: the old reader's worst case for a
    /// wrong match was one wrong sentence, and this one's is everything up to the next comma, so
    /// `icon: symbol(for: .empty, title: "unused")` must not be read as a title. Measured over
    /// `Cadence/` before the change: the top-level rule loses none of the 11 literals the regex
    /// found, and adds 12 more.
    static func argumentExpressions(in segment: String) -> [String] {
        let characters = Array(segment)
        var expressions: [String] = []
        var index = 0
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                index = endOfLiteral(from: index, in: characters)
                continue
            }
            if character == "(" || character == "[" || character == "{" {
                depth += 1
                index += 1
                continue
            }
            if character == ")" || character == "]" || character == "}" {
                depth -= 1
                index += 1
                continue
            }
            if depth == 0, let afterColon = endOfArgumentLabel(at: index, in: characters) {
                let end = endOfArgument(from: afterColon, in: characters)
                expressions.append(String(characters[afterColon..<end]))
                index = afterColon
                continue
            }
            index += 1
        }
        return expressions
    }

    /// Every hand-spelled empty-state literal in `source`, in call order — including the ones
    /// behind a conditional. See `argumentExpressions(in:)`.
    static func literals(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: literalPattern) else { return [] }
        var found: [String] = []
        for segment in callSegments(in: source) {
            for expression in argumentExpressions(in: segment) {
                let range = NSRange(expression.startIndex..., in: expression)
                for match in regex.matches(in: expression, range: range) {
                    guard let captured = Range(match.range(at: 1), in: expression) else { continue }
                    let text = String(expression[captured])
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty { found.append(text) }
                }
            }
        }
        return found
    }

    /// The index just past the closing quote of the literal that opens at `start`.
    private static func endOfLiteral(from start: Int, in characters: [Character]) -> Int {
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == "\"" { return index + 1 }
            if character.isNewline { return index }
            index += 1
        }
        return characters.count
    }

    /// The index just past the `:` when one of the three labels begins at `start`, else `nil`.
    ///
    /// The character before the label must not be able to continue an identifier, so
    /// `kind.noMatchTitle:` and `emptyTitle:` are not read as `title:`. The old regex had no such
    /// guard and did not need one — it is case-sensitive, and every such member in the tree
    /// capitalises the word — but the widened reader hands back a whole expression rather than one
    /// literal, so a wrong match now harvests more than a wrong sentence.
    private static func endOfArgumentLabel(at start: Int, in characters: [Character]) -> Int? {
        if start > 0 {
            let previous = characters[start - 1]
            if previous.isLetter || previous.isNumber || previous == "_" || previous == "." {
                return nil
            }
        }
        for label in argumentLabels {
            let end = start + label.count
            guard end <= characters.count, String(characters[start..<end]) == label else { continue }
            var index = end
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count, characters[index] == ":" else { continue }
            return index + 1
        }
        return nil
    }

    /// The end of the argument that starts at `start`: the first top-level `,`, or the bracket
    /// that closes the call around it.
    private static func endOfArgument(from start: Int, in characters: [Character]) -> Int {
        var index = start
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                index = endOfLiteral(from: index, in: characters)
                continue
            }
            if character == "(" || character == "[" || character == "{" {
                depth += 1
            } else if character == ")" || character == "]" || character == "}" {
                if depth == 0 { return index }
                depth -= 1
            } else if character == ",", depth == 0 {
                return index
            }
            index += 1
        }
        return characters.count
    }

    /// String literals, comments already stripped. Used by the touch-verb rule so an identifier
    /// like `onTapGesture` cannot be read as copy.
    static func stringLiterals(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"\\\\\\n]*)\"") else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captured])
        }
    }

    // MARK: The second derivation — shape rather than name

    /// One `struct` declaration: its name, what it conforms to, and its brace-matched body.
    struct Declaration {
        let name: String
        let path: String
        let conformances: String
        let body: String

        /// The names of its `let`/`var` stored properties of type `String`, which for a component
        /// of this family are the words it is handed.
        var stringProperties: [String] {
            guard let regex = try? NSRegularExpression(pattern: #"\b(?:let|var) +(\w+) *: *String\b"#)
            else { return [] }
            let range = NSRange(body.startIndex..., in: body)
            return regex.matches(in: body, range: range).compactMap { match in
                guard let captured = Range(match.range(at: 1), in: body) else { return nil }
                return String(body[captured])
            }
        }
    }

    /// Every `struct` declared under `relativeDirectory`, read structurally.
    static func declarations(under relativeDirectory: String = "Cadence") throws -> [Declaration] {
        let regex = try NSRegularExpression(pattern: "\\bstruct +([A-Za-z0-9_]+) *([^{]*)\\{")
        var found: [Declaration] = []
        for path in try CadenceSourceScan.swiftFiles(under: relativeDirectory) {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let characters = Array(source)
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: source),
                      let conformanceRange = Range(match.range(at: 2), in: source),
                      let matchRange = Range(match.range, in: source) else { continue }
                let open = source.distance(from: source.startIndex, to: matchRange.upperBound) - 1
                found.append(
                    Declaration(
                        name: String(source[nameRange]),
                        path: path,
                        conformances: String(source[conformanceRange]),
                        body: bracedBody(from: open, in: characters)
                    )
                )
            }
        }
        return found
    }

    /// The text between the `{` at `open` and the `}` that closes it.
    private static func bracedBody(from open: Int, in characters: [Character]) -> String {
        var depth = 0
        var index = open
        while index < characters.count {
            if characters[index] == "{" {
                depth += 1
            } else if characters[index] == "}" {
                depth -= 1
                if depth == 0 { return String(characters[(open + 1)..<index]) }
            }
            index += 1
        }
        return String(characters[min(open + 1, characters.count)...])
    }

    /// **A view shaped like an empty state**: an icon, a headline and a sentence under it.
    ///
    /// The name-derived set above and this one are two readings of the same family, and
    /// `everyEmptyStateShapedViewIsOneTheSweepReads` fails when they disagree — which is what makes
    /// a component named outside the family a red test rather than an invisible one.
    ///
    /// **`…Row` is subtracted as a rule, not as an allowlist.** A row is a list *item*: its title
    /// and subtitle describe something that is there, not the absence of everything. Nine views
    /// have this exact shape and are rows (`iOSListPickerRow`, `AttachListCandidateRow`,
    /// `ListLifecycleRow`, …). The one row that really is an empty state —
    /// `iOSSettingsEmptyInlineRow` — is carried by the *name* derivation, which is the point of
    /// running two. It used to be two rows; T-600(a) deleted `iOSSettingsEmptyRow`, which was the
    /// same component with the glyph hardcoded to `tray` and a title a point smaller.
    static func emptyStateShapedViews(among declarations: [Declaration]) -> [Declaration] {
        declarations.filter { declaration in
            guard declaration.conformances.contains("View") else { return false }
            guard !declaration.name.hasSuffix("Row") else { return false }
            let properties = Set(declaration.stringProperties)
            let hasHeadline = properties.contains("title") || properties.contains("message")
            let hasGlyph = properties.contains("icon") || properties.contains("systemImage")
            return hasHeadline && properties.contains("subtitle") && hasGlyph
        }
    }
}

// MARK: - The audit

/// **Empty states, audited as a family rather than one screen at a time.**
///
/// Three defects had already been found and fixed one by one — T-469's "Add a task above" beside a
/// field that exists at no width, T-473's "Create a task to get started" under the `+` it restates,
/// and `TasksPanel` saying both of them at once — and each fix was pinned against the single file
/// it was found in. This suite asks the two questions those fixes imply, over every surface:
///
/// 1. **Is the copy shared?** A sentence spelled at two call sites is a sentence that will drift,
///    and it does: the Notes page's four tab pairs claimed in a comment to be "Same words macOS
///    uses, tab for tab" while the Events subtitle differed by a full stop, and Saved Links said
///    "Tap + to save a link" on the Mac against "Save URLs that belong with this list." on the
///    phone.
/// 2. **Is the copy true?** Two halves — does it name a control that is on *that* screen at *that*
///    width, and does it tell "you have nothing" apart from "your filter matched nothing".
@MainActor
struct CadenceEmptyStateAuditTests {

    // MARK: One spelling per sentence

    /// **No empty-state sentence is written out in two files.**
    ///
    /// The generalisation of the per-screen fixes: rather than pinning one screen's words, this
    /// says that any wording two screens share has to live in one place. It is the assertion
    /// `CadenceEmptyStateCopy` was created for and that nothing enforced — the file's own doc
    /// comment lists three pairs that had already drifted before anyone noticed.
    @Test func noEmptyStateSentenceIsSpelledInTwoFiles() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let read = CadenceSourceScan.strippedSourceReader()

        let handSpelled = try emptyStateLiteralInstrument().sweep(
            files,
            // The same floor `CadenceRetiredCopyTests` uses for the same tree.
            atLeast: 300,
            // The month agenda, which still spells its own two lines because no other screen
            // says them — so a walk that skipped the iOS tree cannot report this map clean.
            including: "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            read: read
        )

        var spellings: [String: [String]] = [:]
        for path in handSpelled {
            for literal in Set(CadenceEmptyStateAudit.literals(in: try read(path))) {
                spellings[literal, default: []].append(path)
            }
        }

        // No allowance any more (T-522). The one entry there had ever been was "List not found"
        // and its subtitle, deferred to a guard in `CadenceDeletedSelectionGuardTests` that pinned
        // the two files as matching literals rather than removing the second copy; both now read
        // `CadenceEmptyStateCopy.missingList*`, so the exemption and its staleness check went with
        // the duplication they were describing.
        let duplicates = spellings
            .filter { $0.value.count > 1 }
            .map { "\"\($0.key)\" in \($0.value.sorted())" }
            .sorted()
        #expect(
            duplicates.isEmpty,
            """
            \(duplicates.joined(separator: "; ")) — an empty-state sentence spelled in two files \
            drifts. Move it to CadenceEmptyStateCopy and read it from both.
            """
        )
    }

    // MARK: T-548 — the sweep cannot lose a component again

    /// **The component set is derived from the tree, and the derivation is not empty.**
    ///
    /// `componentNames` is a `static let` over a `try?`, so a walk that failed would leave it `[]`
    /// and every sweep above green over nothing. Two things stop that, and this is the louder one:
    /// the instrument's positive witness is the quiet one, and both are cheaper than finding out
    /// the way T-548 was found.
    @Test func theEmptyStateComponentSetIsDerivedFromTheDeclarations() throws {
        let derived = try CadenceEmptyStateAudit.declaredComponentNames()
        #expect(
            derived == CadenceEmptyStateAudit.componentNames,
            "componentNames is not what the derivation returns — the walk failed and was swallowed"
        )

        // The five the app actually has, plus the fourth entry point T-548 found. Named rather
        // than counted so a derivation that silently stopped matching `iOS…` cannot pass on volume.
        for name in [
            "EmptyStateView(",
            "iOSEmptyPanel(",
            "iOSFeatureEmptyState(",
            "iOSFeatureEmptyDetail(",
            "CadenceInlineEmpty(",
            "NotesEditorPlaceholder(",
        ] {
            #expect(derived.contains(name), "the derivation no longer finds \(name)")
        }
        // Measured at 23. A floor rather than an equality, because adding a component should not
        // fail a test that is about the derivation working.
        #expect(derived.count >= 20, "the derivation found only \(derived.count) components")
    }

    /// **A view shaped like an empty state is one the sweep reads** — the guard that makes an
    /// uncovered component a failure rather than a silence.
    ///
    /// The set above is derived from the *name*, which leaves one way to escape it: a component
    /// called something else. So the family is derived a second time from the declaration's shape —
    /// a glyph, a headline and a sentence — and the two readings have to agree. `NothingHereView`
    /// would fail here on the day it was written.
    @Test func everyEmptyStateShapedViewIsOneTheSweepReads() throws {
        let declarations = try CadenceEmptyStateAudit.declarations()
        // 1226 `struct` declarations under `Cadence/` when this was written.
        #expect(declarations.count >= 500, "the declaration walk read \(declarations.count) structs")

        let shaped = CadenceEmptyStateAudit.emptyStateShapedViews(among: declarations)
        // Non-vacuity: the shape reader finds the components it is meant to, on both platforms and
        // in both the shared and the feature layers.
        for name in ["EmptyStateView", "iOSEmptyPanel", "iOSFeatureEmptyDetail", "CommitmentEmptyDetail"] {
            #expect(shaped.contains { $0.name == name }, "the shape reader no longer finds \(name)")
        }

        let uncovered = shaped
            .filter { !CadenceEmptyStateAudit.componentNames.contains("\($0.name)(") }
            .map { "\($0.name) in \($0.path)" }
            .sorted()
        #expect(
            uncovered.isEmpty,
            """
            \(uncovered.joined(separator: "; ")) — a view with an empty state's shape that the \
            duplicate sweep does not read. Name it in the Empty/Placeholder family, or say here \
            why its title and subtitle are not empty-state copy.
            """
        )

        // The `…Row` subtraction is doing work rather than being decorative, and everything it
        // drops really is a row: nine views have this shape and describe an item that is there.
        let droppedRows = declarations.filter { declaration in
            guard declaration.conformances.contains("View"), declaration.name.hasSuffix("Row") else {
                return false
            }
            let properties = Set(declaration.stringProperties)
            return (properties.contains("title") || properties.contains("message"))
                && properties.contains("subtitle")
                && (properties.contains("icon") || properties.contains("systemImage"))
        }
        #expect(droppedRows.count >= 5, "the row subtraction dropped \(droppedRows.count) views")
        #expect(droppedRows.allSatisfy { $0.name.hasSuffix("Row") })
    }

    /// **Every `String` an empty-state component is handed is one the reader has a label for.**
    ///
    /// The other half of T-548's shape, one level down: a component can be in the swept set and
    /// still be read as having no words in it, if its argument label is not one of the three the
    /// reader knew. `CadenceInlineEmpty(text:)` was exactly that, and would have joined the sweep
    /// as a name with nothing behind it.
    @Test func everyCopyBearingArgumentOfAnEmptyStateComponentIsReadable() throws {
        let known = Set(CadenceEmptyStateAudit.argumentLabels)
            .union(CadenceEmptyStateAudit.nonCopyArgumentLabels)
        let components = try CadenceEmptyStateAudit.declarations()
            .filter { CadenceEmptyStateAudit.componentNames.contains("\($0.name)(") }

        // Non-vacuity: components with words in them were found at all.
        let withStrings = components.filter { !$0.stringProperties.isEmpty }
        #expect(withStrings.count >= 8, "only \(withStrings.count) components carry a String")
        #expect(withStrings.contains { $0.name == "CadenceInlineEmpty" })

        let unreadable = withStrings
            .flatMap { declaration in
                declaration.stringProperties
                    .filter { !known.contains($0) }
                    .map { "\(declaration.name).\($0) in \(declaration.path)" }
            }
            .sorted()
        #expect(
            unreadable.isEmpty,
            """
            \(unreadable.joined(separator: "; ")) — an empty-state component takes a String the \
            copy reader has no label for, so its call sites are swept and read as wordless. Add \
            the label to argumentLabels, or to nonCopyArgumentLabels if it is not a sentence.
            """
        )
    }

    /// **No empty-state call site re-types a sentence `CadenceEmptyStateCopy` already declares.**
    ///
    /// T-540 converged the goals title into `goalsTitle(isNarrowed:)` and
    /// `Cadence/iOS/iOSFeatureViews.swift` went on spelling `"No goals yet"` anyway. Neither sweep
    /// could see it: the duplicate sweep above counts *files*, and after the convergence there was
    /// only one file left spelling it; `CadenceSharedConstantReuseSweepTests` harvests `static let`
    /// and `goalsTitle` is a `static func`.
    ///
    /// So this asks the narrower question the audit can answer exactly — every literal declared in
    /// `CadenceEmptyStateCopy`, against every empty-state call site in the app — without widening
    /// the app-wide harvest to function bodies, which is a bigger measurement than this ticket.
    @Test func noEmptyStateCallSiteRetypesTheSharedCopy() throws {
        let declaringFile = "Cadence/Shared/CadenceEmptyStateCopy.swift"
        let read = CadenceSourceScan.strippedSourceReader()
        let declared = Set(
            CadenceEmptyStateAudit
                .stringLiterals(in: try read(declaringFile))
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        )
        // Non-vacuity: the harvest read the constants rather than an empty file.
        #expect(declared.count >= 25, "the shared copy harvest found \(declared.count) sentences")
        #expect(declared.contains("No goals yet"), "the harvest misses a static func's literals")

        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") where path != declaringFile {
            for literal in Set(CadenceEmptyStateAudit.literals(in: try read(path)))
            where declared.contains(literal) {
                offenders.append("\"\(literal)\" in \(path)")
            }
        }
        #expect(
            offenders.sorted().isEmpty,
            """
            \(offenders.sorted().joined(separator: "; ")) — CadenceEmptyStateCopy already declares \
            this sentence. Read it instead of typing it again.
            """
        )
    }

    /// The detector the sweep turns on, checked against the tree rather than only its fixtures: a
    /// file that reads the shared constants must come back clean, and one that spells its own words
    /// must not.
    @Test func theEmptyStateDetectorSeparatesAConstantFromALiteral() throws {
        let instrument = try emptyStateLiteralInstrument()

        let converged = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        #expect(converged.contains("CadenceEmptyStateCopy.savedLinksTitle"), "non-vacuity: wrong file")
        #expect(
            instrument.fires(on: converged) == false,
            "a screen reading only shared constants is still counted as hand-spelling"
        )

        let handSpelled = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        #expect(instrument.fires(on: handSpelled))
    }

    /// The reader is scoped to the call, not to the file.
    ///
    /// The mistake this rules out is the cheap spelling of the sweep above — `subtitle: "…"`
    /// matched file-wide — which would count a `TextField` placeholder or a button label as empty-
    /// state copy and make the duplicate map mostly noise.
    @Test func theEmptyStateReaderIgnoresCopyOutsideTheCall() {
        let source = """
        struct Screen: View {
            var body: some View {
                TextField("Search", text: $query)
                Button("Add") { add() }
                EmptyStateView(message: "Nothing here", subtitle: "Add one with +.", icon: "tray")
                Text("A footnote")
            }
        }
        """
        #expect(CadenceEmptyStateAudit.literals(in: source) == ["Nothing here", "Add one with +."])

        // A literal carrying the call's own closing character does not truncate the read.
        let awkward = """
        EmptyStateView(message: "Nothing (yet)", subtitle: "Try again.", icon: "tray")
        """
        #expect(CadenceEmptyStateAudit.literals(in: awkward) == ["Nothing (yet)", "Try again."])

        #expect(CadenceEmptyStateAudit.literals(in: "Text(\"Not an empty state\")").isEmpty)
    }

    // MARK: T-540 — the copy the reader could not see

    /// **Both branches of a conditional argument are copy, and the reader now reads both.**
    ///
    /// The blind spot this closes: the old reader was one regex matching a literal placed
    /// *directly* after `message:`, so `message: narrowed ? "A" : "B"` harvested nothing at all —
    /// and every filter-aware empty state in the app is written in exactly that shape. The
    /// duplicate sweep therefore reported the tree clean while `"No goals yet"` and
    /// `"No matching goals"` were spelled in two files each.
    ///
    /// The fixtures are literals here rather than repo files, per `CadenceScanInstrument`'s rule:
    /// one read out of the tree can be retuned by the same edit that breaks the rule.
    @Test func theEmptyStateReaderSeesCopyBehindAConditionalBranch() {
        let branched = """
        EmptyStateView(
            message: isNarrowedToEmpty ? "No matching goals" : "No goals yet",
            subtitle: isNarrowedToEmpty
                ? "Try a different filter."
                : "Create a goal with New Goal.",
            icon: "flag.fill"
        )
        """
        #expect(
            CadenceEmptyStateAudit.literals(in: branched) == [
                "No matching goals",
                "No goals yet",
                "Try a different filter.",
                "Create a goal with New Goal.",
            ]
        )

        // A nested conditional is still one argument, and the argument still ends at its comma:
        // the icon below is not copy and must not be harvested as any.
        let nested = """
        iOSEmptyPanel(
            title: searching ? (matched ? "No matches" : "No results") : "Nothing yet",
            icon: "tray"
        )
        """
        #expect(
            CadenceEmptyStateAudit.literals(in: nested) == ["No matches", "No results", "Nothing yet"]
        )

        // And the direct form still reads exactly as it did — this is a widening, not a rewrite.
        #expect(
            CadenceEmptyStateAudit.literals(in: "EmptyStateView(message: \"Only this\", icon: \"tray\")")
                == ["Only this"]
        )
    }

    /// The widened reader stays scoped to the *label*, not to the word.
    ///
    /// Handing back a whole expression is what makes this matter: under the old regex a wrong
    /// match cost one wrong sentence, and under this one it costs everything up to the next comma.
    /// `kind.noMatchTitle` and a member called `emptyTitle` are both live in
    /// `iOSMarkdownAccessoryViews`, so a reader that matched `title:` inside an identifier would
    /// harvest from the file this suite already reads.
    @Test func theWidenedEmptyStateReaderDoesNotMatchALabelInsideAnIdentifier() throws {
        let members = """
        EmptyStateView(
            message: hasNothingToOffer ? kind.emptyTitle : kind.noMatchTitle,
            subtitle: kind.noMatchSubtitle,
            icon: "tray"
        )
        """
        #expect(CadenceEmptyStateAudit.literals(in: members).isEmpty)

        // The argument expressions are found, though — the call is read, it simply holds no copy.
        let segment = try #require(CadenceEmptyStateAudit.callSegments(in: members).first)
        #expect(CadenceEmptyStateAudit.argumentExpressions(in: segment).count == 2)

        // A `title:` belonging to a nested call is that call's argument, not this one's.
        let nestedLabel = """
        EmptyStateView(
            message: "Nothing here",
            icon: symbol(for: .empty, title: "unused"),
            subtitle: "Add one."
        )
        """
        #expect(CadenceEmptyStateAudit.literals(in: nestedLabel) == ["Nothing here", "Add one."])
    }

    /// **The widening is load-bearing on the tree, not only on its fixtures.**
    ///
    /// `HabitsView`'s **subtitles** are the one filter-aware desktop pair whose copy did not turn
    /// out to be shareable — the two surfaces genuinely say different things — so they stay
    /// hand-spelled, which makes this file the standing witness that the reader still reaches
    /// conditional copy in real source. Narrow the reader back and it reads as an empty state with
    /// no words in it.
    ///
    /// Its *title* was the witness until T-548, and it is the shared constant now: the phone spelled
    /// `"No habits yet"` too, in a file no version of this sweep could see.
    @Test func theDuplicateSweepReachesAFilterAwarePageInTheTree() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/HabitsView.swift")
        )
        #expect(code.contains("struct HabitsView"), "non-vacuity: wrong file")

        let found = CadenceEmptyStateAudit.literals(in: code)
        #expect(
            found.contains("Try a different search or filter."),
            "the reader cannot see a narrowed subtitle again"
        )
        #expect(
            found.contains("Create a habit, then link it to the goal it supports."),
            "the reader cannot see a first-run subtitle again"
        )

        // The literals really are behind a branch, so the claim above is about the reader rather
        // than about a file that happens to spell them plainly.
        #expect(code.contains("subtitle: isNarrowedToEmpty"))
        #expect(code.contains("? \"Try a different search or filter.\""))

        // And the title above them is read, not typed.
        #expect(code.contains("CadenceEmptyStateCopy.habitsTitle(isNarrowed: isNarrowedToEmpty)"))
        #expect(found.contains("No habits yet") == false, "HabitsView spells the title again")
    }

    /// **The two Goals view modes share one title.**
    ///
    /// The only duplicate the widened reader found, converged. It had *not* drifted — both files
    /// spelled the same two sentences — which is the whole point: this pair was one edit away from
    /// the drift that `savedLinksSubtitle` and `meetingNotesSubtitle` were found already in, and
    /// nothing in the app could have reported it.
    @Test func theTwoGoalsViewModesShareOneTitleAndKeepTheirOwnSubtitles() throws {
        #expect(CadenceEmptyStateCopy.goalsTitle(isNarrowed: false) == "No goals yet")
        #expect(CadenceEmptyStateCopy.goalsTitle(isNarrowed: true) == "No matching goals")

        for path in [
            "Cadence/macOS/Views/GoalsView.swift",
            "Cadence/macOS/Views/GoalTimelineView.swift",
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let empty = try #require(
                CadenceEmptyStateAudit.callSegments(in: code).first,
                "\(path) no longer draws an empty state"
            )
            #expect(
                empty.contains("CadenceEmptyStateCopy.goalsTitle(isNarrowed: isNarrowedToEmpty)"),
                "\(path) does not read the shared title, or does not pass it the page's own predicate"
            )
            #expect(
                empty.contains("\"No goals yet\"") == false && empty.contains("\"No matching goals\"") == false,
                "\(path) spells the goals title at its call site again"
            )
        }

        // The subtitles stay apart, because the two modes carry different controls. Asserted as
        // values so "converge the rest of it" is a decision somebody has to make on purpose.
        let list = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalsView.swift")
        )
        let roadmap = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalTimelineView.swift")
        )
        #expect(list.contains("\"Try a different search or status.\""))
        #expect(roadmap.contains("\"Try a different filter.\""))
    }

    // MARK: Copy that names a control that is there

    /// **A Mac is not tapped.** `LinksView` said "Tap + to save a link" and `ListNotesEmptyState`
    /// "Tap + to create one", both inside `#if os(macOS)` files, and both beside a `+` that is
    /// clicked. It is the same defect as T-469's "Add a task above" one step less obvious: the
    /// control is there, but the sentence describes reaching it in a way that surface does not
    /// support.
    ///
    /// Swept over the whole desktop tree rather than the two files it was found in, for the reason
    /// `CadenceRetiredCopyTests` gives: a per-screen guard finds the screen you were looking at.
    ///
    /// **And over `Cadence/Shared/` too, which is T-520's half.** The sweep used to walk
    /// `Cadence/macOS/` alone, so it could not see the shape that ticket found:
    /// `CadenceTodayPresentationSupport.emptyScheduleHint` ended "…tap an hour to schedule one" and
    /// sat in `Shared/` with exactly one reader, `iOSSchedulePanel`. Correct on the day, and wrong
    /// the moment any Mac surface read it — which is a defect a desktop-only walk finds only after
    /// somebody has shipped it. A shared folder is every platform's folder, so copy in it has to be
    /// true on the desktop whether or not the desktop reads it yet. The hint is
    /// `iOSSchedulePanelCopy`'s now.
    @Test func noMacReachableCopyAsksForATouchGesture() throws {
        let desktop = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        let shared = try CadenceSourceScan.swiftFiles(under: "Cadence/Shared")
        let files = (desktop + shared).sorted()
        let read = CadenceSourceScan.strippedSourceReader()

        // Both halves of the union are named, because `including:` can only witness one and a walk
        // that lost either folder would still clear the floor on the other.
        #expect(files.contains("Cadence/macOS/Views/LinksView.swift"))
        #expect(files.contains("Cadence/Shared/CadenceTodayPresentationSupport.swift"))

        let offenders = try touchGestureInstrument().sweep(
            files,
            atLeast: 300,
            including: "Cadence/Shared/CadenceEmptyStateCopy.swift",
            read: read
        )
        #expect(
            offenders.isEmpty,
            "\(offenders) tell a Mac user to tap, swipe or pinch. Name the click, or name no gesture."
        )
    }

    /// The touch-verb detector reads copy, not identifiers. `onTapGesture` is on almost every
    /// desktop view in the app, so a detector that matched it would report the whole tree.
    @Test func theTouchGestureDetectorReadsCopyRatherThanIdentifiers() throws {
        let instrument = try touchGestureInstrument()

        let ordinary = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesViewSupportViews.swift")
        #expect(ordinary.contains(".onTapGesture"), "non-vacuity: the gesture modifier is gone")
        #expect(instrument.fires(on: ordinary) == false, "the sweep counts .onTapGesture as copy")
    }

    // MARK: "You have nothing" against "your filter matched nothing"

    /// The predicate itself. Both inputs decide the answer, and whitespace is not a search.
    @Test func aNarrowedListIsOneWithASearchOrAFilter() {
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "", filterNarrows: false) == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "", filterNarrows: true))
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "roadmap", filterNarrows: false))
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "roadmap", filterNarrows: true))

        // A field holding only spaces narrows nothing: every matcher in the app trims before
        // comparing, so reporting it as a search would put "No matching goals" on a first run.
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "   ", filterNarrows: false) == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "\n ", filterNarrows: false) == false)
    }

    /// Both desktop filter bars can hide a row that exists, and both say so — including in their
    /// **default** selection, which is what made this reachable without the reader touching
    /// anything. Goals opens on Active; Habits opens on Due Today.
    @Test func everyDesktopFilterKnowsWhetherItHidesAnything() {
        #expect(GoalStatusFilter.all.narrowsResults == false)
        for filter in [GoalStatusFilter.active, .paused, .done] {
            #expect(filter.narrowsResults, "\(filter.label) hides goals but does not say so")
        }

        #expect(HabitListFilter.all.narrowsResults == false)
        for filter in [HabitListFilter.today, .completed, .streaking] {
            #expect(filter.narrowsResults, "\(filter.label) hides habits but does not say so")
        }

        // The two defaults, named: these are the selections a reader who has touched nothing is
        // under, and they are the ones that were being reported as "you have none".
        #expect(GoalStatusFilter.active.narrowsResults)
        #expect(HabitListFilter.today.narrowsResults)
    }

    /// The three desktop pages ask the predicate rather than the search field.
    ///
    /// Read as source because the branch is a `?:` inside a private computed property of a `View`.
    /// The negative half is the one that matters: `searchText.isEmpty` as the empty state's own
    /// condition is exactly the bug, and it is what a revert looks like.
    @Test func theThreeFilteredDesktopPagesAskTheFilterAndNotJustTheSearchField() throws {
        for path in [
            "Cadence/macOS/Views/GoalsView.swift",
            "Cadence/macOS/Views/GoalTimelineView.swift",
            "Cadence/macOS/Views/HabitsView.swift",
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            // Exactly one *filter-aware* empty state per page. It used to be exactly one empty
            // state, full stop, but T-548's widened component set also sees each page's own
            // detail-pane component (`GoalsEmptyDetail()`, `HabitsEmptyDetail()`) — which carries
            // no arguments and is a different situation, "nothing selected" rather than "the
            // filter matched nothing". The claim that matters is unchanged: one page, one
            // narrowing question.
            let segments = CadenceEmptyStateAudit.callSegments(in: code)
                .filter { $0.contains("isNarrowedToEmpty") }
            #expect(segments.count == 1, "\(path) draws \(segments.count) filter-aware empty states")
            let empty = try #require(
                segments.first,
                "\(path)'s empty state does not ask whether a filter is narrowing the page"
            )

            #expect(
                empty.contains("searchText.isEmpty") == false,
                "\(path)'s empty state is back to reading the search field alone"
            )
            #expect(
                code.contains("CadenceEmptyStateCopy.isNarrowedToEmpty("),
                "\(path) re-rolls the narrowing rule instead of asking the shared one"
            )
            #expect(
                code.contains("narrowsResults"),
                "\(path) passes the shared rule something other than its filter"
            )
        }
    }

    /// The phone's reference picker, which had the same defect in its purest form: `isEmpty` was
    /// computed from the **search-filtered** candidates and fed the first-run words, so a query
    /// that missed told a reader with a full library to go and create their first note.
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` is not compiled by this target.
    @Test func thePhoneReferencePickerTellsAMissedSearchFromAnEmptyLibrary() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift")
        )
        #expect(code.contains("struct iOSMarkdownReferencePickerSheet"), "non-vacuity: wrong file")

        // The unfiltered read exists and is asked of the same candidate functions, so a cancelled
        // task still counts as unreferenceable rather than as something the search hid.
        #expect(code.contains("private var hasNothingToOffer: Bool"))
        #expect(code.contains("candidateNotes(from: notes, query: \"\")"))
        #expect(code.contains("candidateTasks(from: tasks, query: \"\")"))

        // And the panel branches on it, on all three arguments.
        let segments = CadenceEmptyStateAudit.callSegments(in: code)
        let picker = try #require(segments.first { $0.contains("kind.emptyTitle") })
        for argument in ["kind.noMatchTitle", "kind.noMatchSubtitle", "kind.noMatchIcon"] {
            #expect(picker.contains(argument), "the picker's empty state never reaches \(argument)")
        }
        #expect(picker.contains("hasNothingToOffer ?"), "the picker's empty state does not branch")

        // The first-run words are still there and still say what they said; the fix adds a second
        // statement rather than replacing the one that was right when the library really is empty.
        // "No tasks yet" here is also `cadenceRetiredCopy`'s one live exemption.
        for firstRun in ["No notes yet", "No tasks yet", "Create a task first, then reference it here."] {
            #expect(code.contains(firstRun), "the picker lost its genuine first-run copy: \(firstRun)")
        }
    }

    // MARK: The constants themselves

    /// The converged pairs, by value, so a "convergence" that quietly adopted the wrong side of a
    /// drift still fails.
    @Test func theConvergedEmptyStateCopySaysTheTrueHalfOfEachPair() {
        // Names no control, because the two surfaces do not carry the same one: a bare `+` on the
        // Mac, a labelled "Add Link" button on the phone.
        #expect(CadenceEmptyStateCopy.savedLinksSubtitle == "Save URLs that belong with this list.")
        #expect(CadenceEmptyStateCopy.savedLinksSubtitle.contains("+") == false)

        // Names one, because here both surfaces really do show a bare `+`.
        #expect(CadenceEmptyStateCopy.listNotesSubtitle == "Add a note with +.")

        // The scoped sentence, not the restatement of the title above it.
        #expect(CadenceEmptyStateCopy.completedTasksSubtitle == "Completed work from this list will collect here.")
        #expect(CadenceEmptyStateCopy.completedTasksSubtitle.contains("Completed tasks will appear here") == false)

        // The Notes page's Events tab, which is the pair that had drifted by a full stop.
        #expect(CadenceEmptyStateCopy.meetingNotesSubtitle == "Create one from a calendar event.")

        // T-548's pairs. The habits title had not drifted — it was byte-identical in two files,
        // which is the state T-540 found the goals pair in and one edit away from drifting.
        #expect(CadenceEmptyStateCopy.habitsTitle(isNarrowed: false) == "No habits yet")
        #expect(CadenceEmptyStateCopy.habitsTitle(isNarrowed: true) == "No matching habits")
        #expect(CadenceEmptyStateCopy.selectNoteTitle == "Select a note")
        #expect(CadenceEmptyStateCopy.selectWeekTitle == "Select a week")
        #expect(CadenceEmptyStateCopy.selectMeetingNoteTitle == "Select a meeting note")

        // A title is not a sentence: the full-stop rule below is about subtitles, and these three
        // are the whole empty state on a pane with nothing selected.
        for title in [
            CadenceEmptyStateCopy.selectNoteTitle,
            CadenceEmptyStateCopy.selectWeekTitle,
            CadenceEmptyStateCopy.selectMeetingNoteTitle,
            CadenceEmptyStateCopy.habitsTitle(isNarrowed: false),
            CadenceEmptyStateCopy.goalsTitle(isNarrowed: false),
        ] {
            #expect(title.hasSuffix(".") == false, "\"\(title)\" is a title with a full stop")
        }

        // Every shared sentence ends in a full stop. The drift this file exists to stop was a
        // missing one, twice.
        for sentence in [
            CadenceEmptyStateCopy.savedLinksSubtitle,
            CadenceEmptyStateCopy.listNotesSubtitle,
            CadenceEmptyStateCopy.completedTasksSubtitle,
            CadenceEmptyStateCopy.missingListSubtitle,
            CadenceEmptyStateCopy.noteActionTasksSubtitle,
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true),
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false),
            CadenceEmptyStateCopy.dailyNotesSubtitle,
            CadenceEmptyStateCopy.weeklyNotesSubtitle,
            CadenceEmptyStateCopy.notepadSubtitle,
            CadenceEmptyStateCopy.meetingNotesSubtitle,
        ] {
            #expect(sentence.hasSuffix("."), "\"\(sentence)\" is a sentence without a full stop")
            #expect(sentence.contains("\n") == false, "an empty state's line is one line")
        }
    }

    // MARK: T-526 — the Lists empty state, against the section it points at

    /// **The clause that names Archived is only said when Archived is drawn.**
    ///
    /// Behavioural: `Cadence/Shared/` is compiled by this target, so these are the values the two
    /// shells will render, not a reading of their source.
    ///
    /// The first-run half is the one the defect was about. The empty state shows only when there
    /// are no *active* lists, and on a fresh or fully emptied store there is nothing archived
    /// either — so the reader most certain to see this sentence was the reader for whom the
    /// section it pointed at does not exist.
    @Test func theListsEmptyStateOnlyOffersArchivedRestoreWhenArchivedIsOnScreen() {
        #expect(
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false)
                == "Create an area or project here."
        )
        #expect(
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true)
                == "Create an area or project here, or restore one from Archived."
        )

        // Stated as an absence too, so a rewording that keeps the promise under different words
        // fails rather than passing on a changed literal.
        let firstRun = CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false)
        #expect(firstRun.localizedCaseInsensitiveContains("archiv") == false)
        #expect(firstRun.localizedCaseInsensitiveContains("restore") == false)

        // And the half that is still true keeps saying it: the fix is a condition, not a deletion.
        #expect(CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true).contains("Archived"))

        // "here" survives on both, because iOSListCreateButtonsRow is directly above the panel on
        // both shells — that clause was never the false one.
        #expect(firstRun.contains("here"))
    }

    /// **Both shells ask the same predicate that draws the section, and each spells it once.**
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` is not compiled by this target, so nothing
    /// here executes a `View`. What it can say is the thing the defect was made of — the sentence
    /// and the section were deciding independently. Now `hasArchivedLists` is the single reader of
    /// `archivedAreas`/`archivedProjects` emptiness in each file, and both the section and the
    /// subtitle go through it.
    @Test func bothListShellsAskTheSamePredicateThatDrawsTheArchivedSection() throws {
        for path in [
            "Cadence/iOS/iOSListViews.swift",
            "Cadence/iOS/iOSListsRegularPane.swift",
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code != raw, "\(path) carries comments and the stripper blanked none of them")

            #expect(
                code.contains("private var hasArchivedLists: Bool"),
                "\(path) has no single predicate for whether Archived is on screen"
            )
            let body = try #require(
                bodyOfComputedProperty("hasArchivedLists", in: code),
                "\(path)'s hasArchivedLists has no body"
            )
            #expect(
                body.contains("!archivedAreas.isEmpty || !archivedProjects.isEmpty"),
                "\(path)'s hasArchivedLists is not the predicate the Archived section was drawn from"
            )

            // The section is drawn from it...
            #expect(
                code.contains("if hasArchivedLists {"),
                "\(path)'s archivedSection no longer branches on the shared predicate"
            )
            // ...and the empty state asks it before offering to restore from it.
            let empty = try #require(
                CadenceEmptyStateAudit.callSegments(in: code)
                    .first { $0.contains("CadenceEmptyStateCopy.activeListsTitle") },
                "\(path) no longer draws the active-lists empty state"
            )
            #expect(
                empty.contains("CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: hasArchivedLists)"),
                "\(path)'s empty state does not pass the section's own predicate"
            )

            // Spelled once. Two copies of this expression is how the sentence and the section came
            // to disagree, so a second one is the regression rather than a style slip.
            #expect(
                CadenceSourceScan.matchCount(
                    #"!archivedAreas\.isEmpty \|\| !archivedProjects\.isEmpty"#,
                    in: code
                ) == 1,
                "\(path) spells the archived predicate more than once again"
            )
        }
    }

    // MARK: T-519 — the Focus detail pane, against the pane beside it

    /// **The Focus detail pane no longer promises tasks that are already next to it.**
    ///
    /// It said "Ready when you are / Today tasks will appear here." for both of the two ways this
    /// branch is reached, and `selectedItem` falls back to `pickItems.first`, so those two are:
    /// nothing is ready — in which case the picker pane beside it is showing the shared focus
    /// empty state and this was a second, differently worded promise about it — or a chosen
    /// subject was deleted while the picker still lists others, in which case today's tasks are
    /// literally on screen to the left.
    ///
    /// Source-shape: `Cadence/iOS/` is not compiled by this target. The retirement of the sentence
    /// itself is enforced app-wide by `cadenceRetiredCopy`, not here.
    @Test func theFocusDetailPaneNeverPromisesTasksThatAreAlreadyBesideIt() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("struct iOSFocusView"), "non-vacuity: wrong file")
        #expect(code != raw, "the stripper blanked no comments in a file that has them")

        // The branch exists and is the thing `case nil` draws.
        #expect(code.contains("private var unselectedDetail: some View"))
        #expect(
            CadenceSourceScan.matchCount(#"case nil:\s+unselectedDetail"#, in: code) == 1,
            "focusDetailPane's nil case no longer draws unselectedDetail"
        )

        let body = try #require(
            bodyOfComputedProperty("unselectedDetail", in: code),
            "unselectedDetail has no body"
        )
        // It branches, on the same list the pane beside it is showing.
        #expect(
            body.contains("if pickItems.isEmpty {"),
            "the placeholder does not ask whether there is anything to select"
        )
        // Empty: the same words the picker pane says, because it is one page and not two.
        #expect(body.contains("CadenceEmptyStateCopy.focusTitle"))
        #expect(body.contains("CadenceEmptyStateCopy.focusSubtitle"))
        // Full: the house pattern for a detail pane with no selection, which Goals and Habits use.
        #expect(body.contains("iOSFeatureEmptyDetail(systemImage: \"timer\", title: \"No session selected\")"))

        // The picker pane really does say the shared sentence at the same moment — the claim that
        // makes the empty half a convergence rather than a new spelling.
        #expect(CadenceSourceScan.matchCount("CadenceEmptyStateCopy.focusTitle", in: code) == 3)

        // And the house pattern is still the house pattern.
        let components = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        )
        #expect(components.contains("struct iOSFeatureEmptyDetail: View"))
        // The house line is the component's *default* now (T-533): a screen whose detail pane is
        // only reachable beside an empty list passes its own copy through `init(matching:)`
        // instead. `iOSFocusView` is not one of those, so it takes the default, above.
        #expect(components.contains("subtitle: String = \"Select an item from the list.\""))
        #expect(components.contains("init(matching empty: iOSFeatureEmptyState)"))
    }

    /// **A detail pane may not tell the reader to pick from a list that has nothing in it**
    /// (T-533). Goals and Habits both drew `iOSFeatureEmptyDetail` — "No goal selected / Select an
    /// item from the list." — unconditionally, and at iPad regular width the chooser beside it was
    /// saying "No goals yet" about the same emptiness.
    ///
    /// **It is not T-519's shape, and the difference is the reachability.** `unselectedDetail`
    /// needed `if pickItems.isEmpty` because its picker can be full while nothing is selected.
    /// These two panes cannot reach that state: `selected` falls back through the *whole*
    /// collection, so `nil` means the collection is empty — and `iOSFeatureListPane` draws its own
    /// empty panel on exactly that. So the fix is unconditional, and the two fallback expressions
    /// are pinned below because they are what makes it correct: restore either one to something
    /// that can return `nil` beside a full list and this pane needs a branch again.
    ///
    /// Source-shape, not behavioural: `Cadence/iOS/` is fed to this target but sits entirely
    /// inside `#if os(iOS)`, so there is no declaration to call and scanning is the only reader.
    @Test func theGoalsAndHabitsDetailPanesNeverNameAListWithNoItems() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureViews.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("struct iOSGoalsView"), "non-vacuity: wrong file")
        #expect(code.contains("struct iOSHabitsView"), "non-vacuity: wrong file")
        #expect(code != raw, "the stripper blanked no comments in a file that has them")

        // Both detail panes render the chooser's own empty state rather than the house line.
        #expect(
            emptyStateOccurrences(of: "iOSFeatureEmptyDetail(matching: Self.emptyState)", in: code) == 2,
            "a detail pane no longer repeats its own list's empty state"
        )
        #expect(
            emptyStateOccurrences(of: "iOSFeatureEmptyDetail(systemImage:", in: code) == 0,
            "a detail pane on this page still takes the \"Select an item from the list.\" default"
        )

        // And they read it from the same value the chooser does, so the two panes cannot drift.
        #expect(emptyStateOccurrences(of: "empty: Self.emptyState", in: code) == 2)

        // **The titles are read, not typed** (T-548). This used to pin each of the four sentences
        // at exactly one occurrence in this file, which held the two panes of *this* page level
        // and said nothing about the Mac — and the Mac was spelling `"No habits yet"` too, while
        // `"No goals yet"` had been re-typed here after T-540 moved it into a shared constant.
        // Both titles are `CadenceEmptyStateCopy` functions now, and the pin is that this file
        // reads each once and spells neither.
        for reader in [
            "CadenceEmptyStateCopy.goalsTitle(isNarrowed: false)",
            "CadenceEmptyStateCopy.habitsTitle(isNarrowed: false)",
        ] {
            #expect(
                emptyStateOccurrences(of: reader, in: code) == 1,
                "\(reader) is not read exactly once in this file"
            )
        }
        for title in ["No goals yet", "No habits yet"] {
            #expect(
                emptyStateOccurrences(of: title, in: code) == 0,
                "\(title) is spelled at a call site again instead of read"
            )
        }

        // **The subtitles stay at their call sites and are pinned as they were, because they have
        // already drifted from the Mac's** — "Create a goal for an ongoing direction, then nest
        // milestones inside it." against the first below, and "Create a habit, then link it to the
        // goal it supports." against the second. Which sentence is true of which surface is a copy
        // decision (the Mac's Goals page *does* show habit counts, so its wording is incomplete
        // rather than false), so the pair is left visible rather than collapsed.
        for sentence in [
            "Create a direction, then nest milestones and habits underneath it.",
            "Create repeating commitments and track today.",
        ] {
            #expect(
                emptyStateOccurrences(of: sentence, in: code) == 1,
                "\(sentence) is spelled more than once in this file"
            )
        }

        // The retired titles named a selection the reader could not make.
        #expect(emptyStateOccurrences(of: "No goal selected", in: code) == 0)
        #expect(emptyStateOccurrences(of: "No habit selected", in: code) == 0)

        // What makes the unconditional branch correct: `nil` here means "nothing exists".
        #expect(
            emptyStateOccurrences(
                of: "return topLevelGoals.first ?? activeGoals.first ?? goals.first",
                in: code
            ) == 1,
            "the goals fallback no longer resolves through the whole collection"
        )
        #expect(
            emptyStateOccurrences(of: "return dueToday.first ?? habits.first", in: code) == 1,
            "the habits fallback no longer resolves through the whole collection"
        )

        // The chooser really does draw its empty panel on the same emptiness.
        let components = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        )
        #expect(components.contains("struct iOSFeatureEmptyState"))
        #expect(components.contains("if count == 0 {"))
        #expect(emptyStateOccurrences(of: "count: activeGoals.count", in: code) == 1)
        #expect(emptyStateOccurrences(of: "count: habits.count", in: code) == 1)
    }

    /// Literal occurrences of `needle` in `haystack`. `CadenceSourceScan.matchCount` takes a
    /// regular expression, and these needles carry `?`, `(` and `.`.
    private func emptyStateOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return -1 }
        var count = 0
        var cursor = haystack.startIndex
        while let found = haystack.range(of: needle, range: cursor..<haystack.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }

    // MARK: T-520 — a shared hint only one platform could act on

    /// **The schedule hint is iOS's copy, and lives where iOS's copy lives.**
    ///
    /// Behavioural in its first line: `iOSSchedulePanelCopy` is deliberately outside
    /// `#if os(iOS)`, like the four `Cadence/iOS/*Metrics.swift` files, so this target reads the
    /// value rather than inferring it from source. The rest is source-shape and stated as such.
    ///
    /// The sweep above is the general half — nothing in `Shared/` may ask for a touch gesture
    /// again. This is the particular half: the sentence did not merely lose the word "tap", it
    /// stopped being a shared constant, because macOS's `SchedulePanel` draws no empty state at all
    /// and there was never a second reader for it to be shared with.
    @Test func theScheduleHintIsAnIOSConstantAndNoLongerASharedOne() throws {
        #expect(
            iOSSchedulePanelCopy.emptyScheduleHint == "No timed blocks yet — tap an hour to schedule one."
        )

        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTodayPresentationSupport.swift")
        )
        #expect(shared.contains("static let emptySubtitle"), "non-vacuity: wrong file")
        #expect(
            shared.contains("emptyScheduleHint") == false,
            "the schedule hint is declared in Shared/ again"
        )

        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )
        #expect(panel.contains("struct iOSSchedulePanel: View"), "non-vacuity: wrong file")
        #expect(panel.contains("iOSSchedulePanelCopy.emptyScheduleHint"))
        #expect(panel.contains("CadenceTodayPresentationSupport.emptyScheduleHint") == false)
    }

    // MARK: T-523 — the one filter-aware empty state, and the space bar

    /// **A whitespace-only query is not a search on the phone's Attach Lists sheet either.**
    ///
    /// Behavioural, in both halves that decide the branch.
    /// `GoalLinkPresentation.candidateGroups` trims before it matches, so a field holding only
    /// spaces returns the whole library rather than none of it — which means the only reader a
    /// whitespace query can put this empty state in front of is one who has no lists at all, and
    /// `query.isEmpty` greeted that reader's first run with "No matching lists / Nothing matches
    /// that search."
    @Test func theAttachListsSheetTreatsAWhitespaceQueryAsNoSearch() throws {
        // The question the sheet used to ask, and the one it asks now, disagreeing.
        #expect("   ".isEmpty == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "   ", filterNarrows: false) == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "Home", filterNarrows: false))

        // And the reason they disagree is a fact about the sheet's own candidate builder rather
        // than an argument about whitespace: the same query narrows nothing there.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Home")
        modelContext.insert(area)

        let spaces = GoalLinkPresentation.candidateGroups(
            contexts: [], areas: [area], projects: [], query: "   "
        )
        #expect(GoalLinkPresentation.candidateCount(in: spaces) == 1, "a whitespace query narrowed the sheet")

        let miss = GoalLinkPresentation.candidateGroups(
            contexts: [], areas: [area], projects: [], query: "zzz"
        )
        #expect(miss.isEmpty, "non-vacuity: the candidate builder never narrows")
    }

    /// The sheet asks the shared rule, and no longer branches on the raw field.
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` is not compiled by this target.
    @Test func theAttachListsSheetAsksTheSharedNarrowingRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSGoalAttachListsSheet.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("struct iOSGoalAttachListsSheet: View"), "non-vacuity: wrong file")
        #expect(code != raw, "the file carries comments and the stripper blanked none of them")

        #expect(
            code.contains("CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: query, filterNarrows: false)"),
            "the sheet re-rolls the narrowing rule instead of asking the shared one"
        )

        let empty = try #require(
            CadenceEmptyStateAudit.callSegments(in: code).first,
            "the sheet no longer draws an empty state"
        )
        #expect(empty.contains("isNarrowedToEmpty"), "the sheet's empty state does not ask the rule")
        #expect(
            empty.contains("query.isEmpty") == false,
            "the sheet's empty state is back to reading the search field alone"
        )
        // Both branches survive: this was a fix to *which* branch is reached, not a deletion.
        #expect(empty.contains("\"No matching lists\""))
        #expect(empty.contains("\"No lists yet\""))
    }

    // MARK: T-525 — the roadmap's first run, against what a roadmap row needs

    /// **One undated goal is enough to leave the roadmap's empty state.**
    ///
    /// Behavioural, and the reason the reword is a measurement rather than a reading:
    /// `GoalTimelineView.rows` is `groups.flatMap { group row + group.goals }`, so it is empty
    /// exactly when `GoalMissionGrouping.groups` is — and nothing in that grouping looks at a date.
    /// "Create a goal, then set its date range." therefore told a reader who had already created a
    /// goal that the page still in front of them was waiting on dates. It was not; it was waiting
    /// on nothing.
    @Test func anUndatedGoalIsEnoughToLeaveTheRoadmapEmptyState() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let goal = Goal(title: "Learn to sail")
        modelContext.insert(goal)
        #expect(goal.startDateDate == nil, "the fixture is not the undated goal this is about")
        #expect(goal.endDateDate == nil, "the fixture is not the undated goal this is about")

        // Under the default filter, which is the selection a reader who has touched nothing is in.
        let groups = GoalMissionGrouping.groups(from: [goal]) {
            GoalStatusFilter.active.matches($0.status)
        }
        #expect(groups.count == 1, "an undated goal does not reach the roadmap at all")

        // `rows`, rebuilt the one way the view builds it.
        let rows = groups.flatMap { group in
            [GoalTimelineRow.group(group, height: 48)]
                + group.goals.map { GoalTimelineRow.goal($0, height: 42) }
        }
        #expect(rows.isEmpty == false, "the roadmap would still be drawing its empty state")
        // And it is a real row rather than a placeholder: the rail hangs its chip off `row.goal`,
        // which is what renders "No date" for this one.
        #expect(rows.first?.goal?.id == goal.id)
    }

    /// The reworded sentence, read off the page that draws it.
    @Test func theRoadmapFirstRunCopyAsksForAGoalAndNotForADateRange() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalTimelineView.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("struct GoalTimelineView: View"), "non-vacuity: wrong file")
        #expect(code != raw, "the file carries comments and the stripper blanked none of them")

        let empty = try #require(
            CadenceEmptyStateAudit.callSegments(in: code).first,
            "the roadmap no longer draws an empty state"
        )
        #expect(empty.contains("\"Create a goal with New Goal. Add dates to draw its bar.\""))
        // Stated as an absence as well, so a revert wearing different words fails rather than
        // passing on a changed literal. The retired sentence itself is swept app-wide by
        // `cadenceRetiredCopy`.
        #expect(empty.localizedCaseInsensitiveContains("date range") == false)
        // The narrowed half is untouched: this was a truth fix, not a rewrite of the branch.
        #expect(empty.contains("\"Try a different filter.\""))

        // And the control the new sentence names is on this page, at the one width it has.
        #expect(
            CadenceSourceScan.matchCount(#"CadenceActionButton\(\s*title: "New Goal""#, in: code) == 1,
            "the roadmap's copy names a New Goal button its own toolbar does not draw"
        )
    }

    /// The text between the braces of `var <name>` — the shape `CadenceSourceScan.functionBody`
    /// cannot read, because a computed property has no parameter list to key on.
    private func bodyOfComputedProperty(_ name: String, in source: String) -> String? {
        guard let declaration = source.range(of: "var \(name)") else { return nil }
        guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else {
            return nil
        }
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[source.index(after: open.lowerBound)..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Every screen that used to spell one of these now reads it. Counted by *file*, because the
    /// point is that no surface kept a private copy.
    @Test func bothSurfacesReadEachConvergedConstant() throws {
        let readers: [String: [String]] = [
            "savedLinks": ["Cadence/macOS/Views/LinksView.swift", "Cadence/iOS/iOSListSupportViews.swift"],
            "listNotes": ["Cadence/macOS/Views/ListNotesViewSupportViews.swift", "Cadence/iOS/iOSListNotesView.swift"],
            "completedTasks": ["Cadence/macOS/Views/ListDetailSupportViews.swift", "Cadence/iOS/iOSListSupportViews.swift"],
            "noteActionTasks": ["Cadence/macOS/Views/NoteActionReviewSheets.swift", "Cadence/iOS/iOSAINoteActionsViews.swift"],
            "activeLists": ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSListsRegularPane.swift"],
            "meetingNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            // T-522. The last pair that was held level by a test asserting two files matched,
            // rather than by there being one declaration for them to read.
            "missingList": ["Cadence/macOS/Views/ListDetailView.swift", "Cadence/iOS/iOSRootSidebar.swift"],
            "notepad": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            "dailyNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            "weeklyNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
        ]

        for (constant, paths) in readers.sorted(by: { $0.key < $1.key }) {
            for path in paths {
                let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                #expect(
                    code.contains("CadenceEmptyStateCopy.\(constant)Title"),
                    "\(path) does not read CadenceEmptyStateCopy.\(constant)Title"
                )
                #expect(
                    code.contains("CadenceEmptyStateCopy.\(constant)Subtitle"),
                    "\(path) does not read CadenceEmptyStateCopy.\(constant)Subtitle"
                )
            }
        }

        // **Titles with no subtitle beside them** — the pairs T-540 and T-548 converged. A title
        // alone is the whole empty state on a "nothing selected" pane, and on Goals and Habits the
        // subtitles are deliberately *not* shared, so these cannot go in the map above.
        let titleOnly: [String: [String]] = [
            // T-540 converged the two Mac view modes; T-548 added the phone, which had re-typed it.
            "goalsTitle(isNarrowed:": [
                "Cadence/macOS/Views/GoalsView.swift",
                "Cadence/macOS/Views/GoalTimelineView.swift",
                "Cadence/iOS/iOSFeatureViews.swift",
            ],
            "habitsTitle(isNarrowed:": [
                "Cadence/macOS/Views/HabitsView.swift",
                "Cadence/iOS/iOSFeatureViews.swift",
            ],
            // Four entry points, two of them on the Mac: the Notes page's own placeholder and the
            // list-detail notes column's.
            "selectNoteTitle": [
                "Cadence/macOS/Views/NotesView.swift",
                "Cadence/macOS/Views/ListNotesViewSupportViews.swift",
                "Cadence/iOS/iOSNotesView.swift",
                "Cadence/iOS/iOSListNotesView.swift",
            ],
            "selectWeekTitle": [
                "Cadence/macOS/Views/NotesView.swift",
                "Cadence/iOS/iOSNotesView.swift",
            ],
            "selectMeetingNoteTitle": [
                "Cadence/macOS/Views/NotesView.swift",
                "Cadence/iOS/iOSNotesView.swift",
            ],
        ]
        for (constant, paths) in titleOnly.sorted(by: { $0.key < $1.key }) {
            for path in paths {
                let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                #expect(
                    code.contains("CadenceEmptyStateCopy.\(constant)"),
                    "\(path) does not read CadenceEmptyStateCopy.\(constant)"
                )
            }
        }
    }

    /// The two readers used across this suite genuinely differ.
    ///
    /// `CadenceSourceScan.codeOnly` blanks string literals as well as comments, so every literal
    /// assertion here would be permanently green against it. Pinned rather than trusted, because
    /// three separate agents have reached for the wrong one.
    @Test func theCopyReaderKeepsLiteralsAndTheStructuralReaderDoesNot() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEmptyStateCopy.swift")
        let stripped = CadenceSourceScan.strippingComments(source)
        let structural = CadenceSourceScan.codeOnly(source)

        #expect(stripped.contains("Save URLs that belong with this list."))
        #expect(structural.contains("Save URLs that belong with this list.") == false)
        #expect(structural.contains("static let savedLinksSubtitle"))
        #expect(stripped != source, "the file carries comments and the stripper blanked none of them")
        #expect(stripped.count == source.count, "the stripper changed the file's length")
    }
}

// MARK: - Fixtures

/// Fires on a file that writes an empty state's words at the call site; silent on one that reads
/// them from the shared constants.
///
/// The two witnesses are the nearest possible miss — the same component, the same three arguments,
/// once as literals and once as constants — because that is the pair this detector gets wrong if it
/// gets anything wrong.
private func emptyStateLiteralInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "empty-state copy spelled at the call site",
        fires: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(message: "Nothing here", subtitle: "Add one.", icon: "tray")
            }
        }
        """,
        andNotOn: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(
                    message: CadenceEmptyStateCopy.inboxTitle,
                    subtitle: CadenceEmptyStateCopy.inboxSubtitle,
                    icon: "tray"
                )
            }
        }
        """,
        by: { !CadenceEmptyStateAudit.literals(in: CadenceSourceScan.strippingComments($0)).isEmpty }
    )
}

/// Fires on desktop copy that asks for a touch gesture; silent on the gesture *modifier*, which is
/// on nearly every view in the tree.
private func touchGestureInstrument() throws -> CadenceScanInstrument {
    let pattern = "(?i)\\b(tap|taps|tapped|tapping|swipe|swipes|swiped|pinch|pinches)\\b"
    return try CadenceScanInstrument(
        "desktop copy asking for a touch gesture",
        fires: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(message: "No links", subtitle: "Tap + to save a link", icon: "link")
            }
        }
        """,
        andNotOn: """
        struct Screen: View {
            var body: some View {
                Text("Saved Links")
                    .onTapGesture { select() }
                    .highPriorityGesture(TapGesture().onEnded { open() })
            }
        }
        """,
        by: { source in
            CadenceEmptyStateAudit
                .stringLiterals(in: CadenceSourceScan.strippingComments(source))
                .contains { $0.range(of: pattern, options: .regularExpression) != nil }
        }
    )
}
