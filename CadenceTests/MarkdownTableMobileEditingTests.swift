import Foundation
import Testing

@testable import Cadence

/// **T-221's iOS half: the four boundary concerns, established here rather than argued.**
///
/// The macOS half measured its four on a real offscreen `CadenceTextView`. That is not available
/// here — `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS — so each
/// concern is pinned at the level where a value exists, and the two that live only in UIKit
/// lifecycle are pinned by scanning the one function that decides them. Which is which is stated on
/// every test, because a source scan that is mistaken for a behavioural measurement is worse than no
/// test at all (`Cadence/Shared/AGENTS.md`, "Source-Scanning Tests").
@Suite("Markdown table editing, mobile")
// `MarkdownStyleSignature`'s `Equatable` conformance is main-actor-isolated, so comparing two of
// them inside a nonisolated `#expect` warns 18 times per comparison through macro expansion — and
// is an *error* under the Swift 6 language mode this repo is deciding about separately (T-122).
// The suite is main-actor rather than the conformance being loosened: the signature exists to be
// read by the styler, which is main-actor anyway.
@MainActor
struct MarkdownTableMobileEditingTests {
    private let note = """
    Above the table.

    | Name | Qty |
    | --- | ---: |
    | Apples | 3 |
    | Pears | 5 |

    Below the table.
    """

    private func tableBlock() throws -> MarkdownRenderedBlock {
        let block = MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: note).first { $0.kind == .table }
        return try #require(block)
    }

    private func firstGrid() throws -> MarkdownTableGrid {
        try #require(MarkdownTableEditor.grids(in: note).first)
    }

    // MARK: - Concern 4: the render gate

    /// **The concern that does not exist on macOS.** `MarkdownStyleSignature` has exactly one reader
    /// and it is `Cadence/iOS/iOSMarkdownEditor.swift`; the Mac re-runs its styler from
    /// `textDidChange`. "Show Table Source" changes what the styler draws with **no text edit behind
    /// it**, so without an entry of its own the gate compares equal, skips, and the command does
    /// nothing at all.
    @Test("Revealing a table's source moves the style signature")
    func tableSourceAnchorsMoveTheStyleSignature() {
        let hidden = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [])
        let revealed = MarkdownStyleSignature.current(
            revealedBlockRange: nil,
            imageAssets: [],
            tableSourceAnchors: [18]
        )
        let other = MarkdownStyleSignature.current(
            revealedBlockRange: nil,
            imageAssets: [],
            tableSourceAnchors: [64]
        )
        #expect(hidden != revealed)
        #expect(revealed != other)
        #expect(
            revealed == MarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: [],
                tableSourceAnchors: [18]
            )
        )
    }

    /// Two tables revealed is not one table revealed, and the set's iteration order is not part of
    /// the answer.
    @Test("The revealed set is compared by content, not by how it was accumulated")
    func tableSourceAnchorsAreCompareByContent() {
        let one = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], tableSourceAnchors: [18])
        let two = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], tableSourceAnchors: [18, 64])
        #expect(one != two)
        #expect(two.tableSourceAnchors == [18, 64])
        #expect(
            MarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: [],
                tableSourceAnchors: Set([64, 18])
            ).tableSourceAnchors == [18, 64]
        )
    }

    /// The reveal command is routed *through* the gate, which is what makes the signature entry
    /// load-bearing rather than decorative.
    @Test("Show Table Source asks the gate it is part of")
    func theSourceCommandGoesThroughTheGate() throws {
        let body = try cadenceFunctionBody(
            "private func tableSourceAction(anchor: Int, in textView: UITextView) -> UIAction",
            in: strippingComments(sourceFile("Cadence/iOS/iOSMarkdownTableEditing.swift"))
        )
        #expect(body.contains("tableSourceAnchors.remove(anchor)"))
        #expect(body.contains("tableSourceAnchors.insert(anchor)"))
        #expect(body.contains("refreshStylingIfNeeded(on: textView)"))
    }

    /// The other half of the gate, and the trap itself: the signature carries **no digest of the
    /// note's text**, so a committed cell leaves it unchanged. A table mutation therefore restyles
    /// synchronously instead of asking, or the grid keeps drawing the old value.
    @Test("A table mutation restyles synchronously rather than asking a gate that cannot see text")
    func aTableMutationRestylesRatherThanAskingTheGate() throws {
        let body = try cadenceFunctionBody(
            "func applyMarkdownTableEdit(_ edit: MarkdownTableEdit, in textView: UITextView) -> Bool",
            in: strippingComments(sourceFile("Cadence/iOS/iOSMarkdownTableEditing.swift"))
        )
        #expect(body.contains("applyMarkdownStyle(to: textView, text: updated)"))
        #expect(!body.contains("refreshStylingIfNeeded"))
    }

    // MARK: - Concern 1: selection

    /// A drag from the prose above to the prose below still covers the table's own characters. The
    /// selection is left exactly as the user made it.
    @Test("A selection spanning the table is left alone")
    func aSelectionSpanningTheTableIsLeftAlone() throws {
        let whole = NSRange(location: 0, length: (note as NSString).length)
        #expect(MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: whole, in: note) == nil)
        #expect((note as NSString).substring(with: whole).contains("| Apples | 3 |"))
    }

    /// **New with T-221.** A table used to un-render whenever the caret was inside it, so a
    /// selection there was a selection over visible pipes. Now its characters are hidden like a task
    /// embed's, and a selection lying wholly inside one is a selection of nothing.
    @Test("A selection wholly inside a rendered table collapses past it")
    func aSelectionInsideARenderedTableCollapses() throws {
        let table = try tableBlock()
        let inside = NSRange(location: table.storageRange.location + 2, length: 6)
        #expect(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: inside, in: note)
                == NSRange(location: NSMaxRange(table.storageRange), length: 0)
        )
    }

    /// …and stands down the moment the reader asks to see the source, which is the one way the
    /// pipes become visible again.
    @Test("A table showing its source keeps its selection")
    func aRevealedTableKeepsItsSelection() throws {
        let table = try tableBlock()
        let inside = NSRange(location: table.storageRange.location + 2, length: 6)
        #expect(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(
                for: inside,
                in: note,
                sourceRevealedRanges: [table.storageRange]
            ) == nil
        )
    }

    /// A caret arrowed at the table steps over it rather than vanishing inside. The storage here is
    /// built the way `iOSMarkdownStyler.applyLiveTableBlocks` builds it — the run marked
    /// `cadenceMarkdownHidden`, the characters still present.
    @Test("A caret arrowed at a rendered table steps over it")
    func aCaretStepsOverARenderedTable() throws {
        let table = try tableBlock()
        let storage = NSMutableAttributedString(string: note)
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: table.storageRange)
        let inside = table.storageRange.location + 5

        #expect(
            MarkdownHiddenRangeSupport.snappedCaretLocation(inside, in: storage, preferringForward: true)
                == NSMaxRange(table.storageRange)
        )
        #expect(
            MarkdownHiddenRangeSupport.snappedCaretLocation(inside, in: storage, preferringForward: false)
                == table.storageRange.location
        )
        #expect(storage.string == note)
    }

    /// Backspace inside a rendered table deletes the whole block, as it does for every other
    /// rendered block — and does **not** while its source is on screen, which is what makes the
    /// escape hatch usable rather than self-destructing.
    @Test("Backspace leaves a table alone while its source is showing")
    func backspaceSparesARevealedTable() throws {
        let table = try tableBlock()
        let caret = NSRange(location: table.storageRange.location + 5, length: 0)
        #expect(
            MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(in: note, selection: caret)
                == table.deletionRange
        )
        #expect(
            MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
                in: note,
                selection: caret,
                sourceRevealedRanges: [table.storageRange]
            ) == nil
        )
    }

    // MARK: - Concern 2: copy and paste

    /// Copying yields markdown, because the styler never removes a character — it hides one. The
    /// pass that would have to break this is scanned rather than run: it is `#if os(iOS)`.
    @Test("The table pass hides its source and never rewrites the storage's string")
    func theTablePassOnlyHides() throws {
        let body = try cadenceFunctionBody(
            "static func applyLiveTableBlocks(",
            in: strippingComments(sourceFile("Cadence/iOS/iOSMarkdownStylingBlockSupport.swift"))
        )
        #expect(body.contains("hide(storage, range)"))
        #expect(!body.contains("replaceCharacters"))
        #expect(!body.contains("deleteCharacters"))
        #expect(!body.contains("mutableString"))
    }

    /// Pasting elsewhere renders a table again: what the editor writes is what the parser reads.
    @Test("A table round-trips through its own serialisation")
    func aTableRoundTripsThroughItsSource() {
        let source = MarkdownTableEditor.tableSource(
            rows: [["Name", "Qty"], ["Apples", "3"]],
            alignments: [.leading, .trailing],
            columnCount: 2
        )
        let pasted = "Intro\n\n\(source)\n\nOutro"
        let grids = MarkdownTableEditor.grids(in: pasted)
        #expect(grids.count == 1)
        #expect(grids.first?.rows == [["Name", "Qty"], ["Apples", "3"]])
        #expect(grids.first?.alignments == [.leading, .trailing])
    }

    // MARK: - Concern 3: undo

    /// **A commit whose value did not change registers no edit**, so tabbing across five cells does
    /// not cost five undos. One rule, in `Services/`, called by both platforms' hosted fields.
    @Test("An unchanged cell is not an edit")
    func anUnchangedCellIsNotAnEdit() throws {
        let grid = try firstGrid()
        let apples = MarkdownTableCellAddress(row: 1, column: 0)
        #expect(grid.cell(at: apples) == "Apples")
        #expect(MarkdownTableEditor.commit("Apples", at: apples, in: grid) == nil)
        #expect(MarkdownTableEditor.commit("   Apples  ", at: apples, in: grid) == nil)
        #expect(MarkdownTableEditor.commit("Plums", at: apples, in: grid) != nil)
        #expect(MarkdownTableEditor.commit("x", at: MarkdownTableCellAddress(row: 9, column: 0), in: grid) == nil)
    }

    /// The edit a commit does produce rewrites **one row**, and the rest of the note is untouched —
    /// which is why `Cmd+Z` restores the note rather than reflowing every other block in it.
    @Test("A committed cell is a one-row replacement")
    func aCommittedCellIsAOneRowReplacement() throws {
        let grid = try firstGrid()
        let apples = MarkdownTableCellAddress(row: 1, column: 0)
        let edit = try #require(MarkdownTableEditor.commit("Plums", at: apples, in: grid))
        #expect(edit.replacementRange == grid.rowLineRanges[1])
        #expect(edit.replacement == "| Plums | 3 |")

        let updated = (note as NSString).replacingCharacters(in: edit.replacementRange, with: edit.replacement)
        let after = try #require(MarkdownTableEditor.grids(in: updated).first)
        #expect(after.cell(at: apples) == "Plums")
        #expect(after.cell(at: MarkdownTableCellAddress(row: 2, column: 1)) == "5")
        #expect(updated.hasPrefix("Above the table."))
        #expect(updated.hasSuffix("Below the table."))
    }

    /// The mobile write path is the text view's own editing route, which is the only one that
    /// registers on its undo manager. Assigning `text` or reaching into `textStorage` would compile
    /// and would leave `Cmd+Z` with nothing to replay.
    @Test("The mobile write path goes through the text view's own editing route")
    func theMobileWritePathIsUndoable() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownTableEditing.swift"))
        let body = try cadenceFunctionBody(
            "func applyMarkdownTableEdit(_ edit: MarkdownTableEdit, in textView: UITextView) -> Bool",
            in: source
        )
        #expect(body.contains("replaceProgrammatically(edit.replacementRange, with: edit.replacement, in: textView)"))
        #expect(!body.contains("textView.text ="))
        #expect(!body.contains("storage.replaceCharacters"))
        #expect(!body.contains("setAttributedString"))

        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        let write = try cadenceFunctionBody(
            "func replaceProgrammatically(",
            in: editor
        )
        #expect(write.contains("textView.replace(textRange, withText: replacement)"))
    }

    /// Both hosted fields ask the same function whether a cell changed. A second hand-written copy
    /// of the trim-and-compare is the shape that drifts.
    @Test("Both platforms commit a cell through one rule")
    func bothPlatformsShareTheCommitRule() throws {
        for path in [
            "Cadence/iOS/iOSMarkdownTableEditing.swift",
            "Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift"
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(source.contains("MarkdownTableEditor.commit("), "\(path) does not call the shared commit rule")
            #expect(
                !source.contains("trimmingCharacters(in: .whitespaces)"),
                "\(path) re-spells the trim the shared commit rule owns"
            )
        }
    }

    // MARK: - The smart-punctuation defect

    /// **The defect this section exists for, stated as the thing that breaks.**
    ///
    /// A cell commit rewrote the delimiter row above it from `---` to an em dash, and the table
    /// stopped being a table: `alignment(ofDelimiterCell:)` wants `-` and `U+2014` is not `U+002D`.
    /// Pinned so that nobody is ever tempted to "fix" the corruption by teaching the parser to read
    /// an em dash — that would make a broken document parse rather than stop it being broken, and
    /// would silently accept every future substitution too.
    @Test("An em-dash delimiter is not a table, and must never become one")
    func anEmDashDelimiterIsNotATable() {
        let corrupted = """
        Above the table.

        | Name | Qty |
        | \u{2014} | \u{2014}: |
        | Apples | 3 |

        Below the table.
        """
        #expect(MarkdownTableEditor.grids(in: corrupted).isEmpty)
        #expect(!MarkdownTableEditor.grids(in: note).isEmpty)
    }

    /// With nothing in flight every change is the user's own, and the guard must never become a
    /// veto on typing. An em dash typed as prose is a perfectly good em dash.
    @Test("With no write in flight the editor's own rules apply")
    func noWriteInFlightAcceptsEverything() {
        #expect(MarkdownProgrammaticEditSupport.acceptsDelegateChange(
            range: NSRange(location: 42, length: 3),
            replacement: "\u{2014}",
            whileWriting: nil
        ))
        #expect(MarkdownProgrammaticEditSupport.acceptsDelegateChange(
            range: NSRange(location: 0, length: 0),
            replacement: "x",
            whileWriting: nil
        ))
    }

    /// **The measurement, replayed as a unit.** Committing `one` to `ZZZ` in this suite's own note
    /// asked the text view to write `{49, 13}` with `| ZZZ | two |`; UIKit then proposed `{42, 3}`
    /// and `{36, 3}` — the two `---` runs on the delimiter line above — each with an em dash, from
    /// inside `checkSmartPunctuationForWordInRange:`. Neither is the write, so neither is accepted.
    @Test("A substitution proposed around a programmatic write is refused")
    func aSubstitutionAroundTheWriteIsRefused() {
        let write = MarkdownProgrammaticEdit(
            range: NSRange(location: 49, length: 13),
            replacement: "| ZZZ | two |"
        )
        #expect(MarkdownProgrammaticEditSupport.acceptsDelegateChange(
            range: write.range,
            replacement: write.replacement,
            whileWriting: write
        ))
        for proposal in [NSRange(location: 42, length: 3), NSRange(location: 36, length: 3)] {
            #expect(!MarkdownProgrammaticEditSupport.acceptsDelegateChange(
                range: proposal,
                replacement: "\u{2014}",
                whileWriting: write
            ))
        }
    }

    /// Equality, not intersection. A proposal landing **inside** the range being written is still
    /// not the write — a cell whose value is `---` is the obvious case, and an overlap test would
    /// wave exactly that one through while catching its neighbours.
    @Test("A substitution inside the written range is refused too")
    func aSubstitutionInsideTheWriteIsRefused() {
        let write = MarkdownProgrammaticEdit(
            range: NSRange(location: 49, length: 13),
            replacement: "| --- | two |"
        )
        #expect(!MarkdownProgrammaticEditSupport.acceptsDelegateChange(
            range: NSRange(location: 51, length: 3),
            replacement: "\u{2014}",
            whileWriting: write
        ))
        #expect(!MarkdownProgrammaticEditSupport.acceptsDelegateChange(
            range: write.range,
            replacement: "| \u{2014} | two |",
            whileWriting: write
        ))
    }

    /// The delegate is the lever, so the delegate has to pull it — and pull it **first**, before the
    /// line-break, deletion and list rules that would otherwise reason about a document mid-write.
    @Test("The text view delegate answers the write window before its own rules")
    func theDelegateAnswersTheWriteWindowFirst() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        let body = try cadenceFunctionBody(
            "shouldChangeTextIn range: NSRange,",
            in: source
        )
        let guardCall = try #require(body.range(of: "MarkdownProgrammaticEditSupport.acceptsDelegateChange"))
        for laterRule in ["expandRenderedBlockDeletionIfNeeded", "deleteListPrefixIfNeeded", "MarkdownLineBreakSupport"] {
            let rule = try #require(body.range(of: laterRule), "\(laterRule) is no longer in this delegate")
            #expect(guardCall.lowerBound < rule.lowerBound, "the write window is consulted after \(laterRule)")
        }
    }

    /// **One write, swept for.** Every programmatic write into the editor's text view announces
    /// itself, and the sweep is what keeps that true: a second raw `replace` added anywhere in the
    /// iOS markdown surface is a second way to corrupt the line above it, and is a test failure
    /// rather than something found on a device weeks later.
    @Test("The iOS editor has exactly one raw text-view write")
    func theEditorHasOneRawWrite() throws {
        let folder = repositoryRoot().appendingPathComponent("Cadence/iOS")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        #expect(names.count > 50, "the iOS folder read as \(names.count) files")

        var writers: [String] = []
        for name in names {
            let source = try strippingComments(String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))
            let count = source.components(separatedBy: "textView.replace(").count - 1
            writers.append(contentsOf: Array(repeating: name, count: count))
        }
        #expect(writers == ["iOSMarkdownEditor.swift"], "raw text-view writes: \(writers)")
    }

    // MARK: - The un-render-on-caret path is gone

    /// The behaviour T-221 exists to remove, removed rather than left reachable as a fallback.
    @Test("The caret no longer un-renders a table")
    func theCaretNoLongerUnRendersATable() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        let body = try cadenceFunctionBody(
            "private func revealedBlockRange(in textView: UITextView) -> NSRange?",
            in: source
        )
        #expect(body.contains("case .code:"))
        #expect(body.contains("case .image, .task, .divider, .table:"))
        #expect(!body.contains("case .code, .table"))
    }

    /// …and the double tap that used to reveal one does not either.
    @Test("A double tap no longer reveals a table")
    func aDoubleTapNoLongerRevealsATable() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        let body = try cadenceFunctionBody("private func revealableBlock(", in: source)
        #expect(body.contains("block.kind == .code"))
        #expect(!body.contains(".table"))
    }

    /// A cell tap opens a cell, and the styler is the thing that draws the grid it opens over — so
    /// the tap and the paint read one `MarkdownTableLayout` rather than two walks of the widths.
    @Test("The touch and the paint read one layout")
    func theTouchAndThePaintReadOneLayout() throws {
        let rendering = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownTableGridRendering.swift"))
        let editing = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownTableEditing.swift"))
        let canvas = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift"))

        // One producer of the layout, and it is the styler's.
        #expect(rendering.components(separatedBy: "MarkdownTableLayout.compute(").count - 1 == 1)
        #expect(!editing.contains("MarkdownTableLayout.compute("))
        #expect(!canvas.contains("MarkdownTableLayout.compute("))
        // Both the draw pass and the hit test go through the same rect.
        #expect(canvas.contains("info.gridRect(inLineFragment: fragment)"))
        #expect(editing.contains("info.address(") && editing.contains("info.cellRect("))
    }

    // MARK: - Non-vacuity

    /// Every zero-count assertion above passes against an empty string, and an isolated build tree
    /// with a symlinked prefix is exactly how a reader silently returns one.
    ///
    /// **The stripper blanks comments to spaces of equal length, so `stripped.count == raw.count`
    /// by construction** — this suite's first draft asserted `stripped.count < raw.count`, which is
    /// red on correct code and on broken code alike, i.e. the zero-discriminating-power shape
    /// `Cadence/Shared/AGENTS.md` warns about. `CadenceGoalTimelineRouteTests` had already written
    /// the correct spelling down, comment and all. Measured over these six files: every one reports
    /// identical counts and different bytes.
    @Test("The files these tests scan were actually read")
    func theScannedFilesWereRead() throws {
        for path in [
            "Cadence/iOS/iOSMarkdownEditor.swift",
            "Cadence/iOS/iOSMarkdownTableEditing.swift",
            "Cadence/iOS/iOSMarkdownTableGridRendering.swift",
            "Cadence/iOS/iOSMarkdownStylingBlockSupport.swift",
            "Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift",
            "Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift"
        ] {
            let raw = try sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
            let stripped = try strippingComments(raw)
            #expect(stripped.contains("MarkdownTable"), "\(path) does not mention a table")
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper blanks rather than deletes")
        }
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
