import Foundation
import Testing

@testable import Cadence

/// Covers the two rules that keep the caret out of a task embed's hidden source.
///
/// Both exist because a standalone `[[task:UUID|Title]]` line is styled as a fully hidden run with
/// a card painted over it. Anything that puts the caret or a selection inside that run is invisible
/// to the user, and typing there edits the reference without renaming the task it points at.
struct MarkdownTaskEmbedCaretSupportTests {
    private static let reference = "[[task:E61773C7-6340-46EB-AED8-3F9DB88CE535|Buy milk]]"

    // MARK: - Draft lines

    @Test func draftTitleReadsATypedTitle() {
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "( ) Buy milk") == "Buy milk")
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "  ( )   Buy milk  ") == "Buy milk")
    }

    @Test func recognisesABareDraftMarker() {
        #expect(MarkdownTaskEmbedParser.isUntitledDraftLine("( )"))
        #expect(MarkdownTaskEmbedParser.isUntitledDraftLine("()"))
        #expect(MarkdownTaskEmbedParser.isUntitledDraftLine("( ) "))
        #expect(MarkdownTaskEmbedParser.isUntitledDraftLine("\t( )  "))
    }

    @Test func ignoresLinesThatAreNotDrafts() {
        for line in ["", "Buy milk", "(x) Buy milk", "Call ( ) later", "- [ ] Buy milk"] {
            #expect(MarkdownTaskEmbedParser.draftTitle(in: line) == nil)
            #expect(!MarkdownTaskEmbedParser.isUntitledDraftLine(line))
        }
        // A titled draft is not a bare one, and vice versa: exactly one of the two rules fires.
        #expect(!MarkdownTaskEmbedParser.isUntitledDraftLine("( ) Buy milk"))
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "( )") == nil)
    }

    // MARK: - Selections over rendered blocks

    @Test func collapsesASelectionInsideATaskEmbed() throws {
        let markdown = "Notes\n\(Self.reference)\nMore"
        let embedStart = ("Notes\n" as NSString).length
        let embedRange = NSRange(location: embedStart, length: (Self.reference as NSString).length)

        // The title range inside the reference — exactly what the old insert path selected.
        let titleRange = try #require(
            MarkdownTaskEmbedParser.referenceTitleRange(in: Self.reference, lineStart: embedStart)
        )
        let collapsed = try #require(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: titleRange, in: markdown)
        )
        #expect(collapsed == NSRange(location: NSMaxRange(embedRange), length: 0))

        // The whole embed line collapses the same way.
        #expect(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: embedRange, in: markdown) ==
                NSRange(location: NSMaxRange(embedRange), length: 0)
        )
    }

    @Test func leavesAnEmptySelectionToTheCaretSnap() {
        let markdown = "Notes\n\(Self.reference)\nMore"
        let embedStart = ("Notes\n" as NSString).length
        #expect(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(
                for: NSRange(location: embedStart + 4, length: 0),
                in: markdown
            ) == nil
        )
    }

    @Test func leavesASelectionThatReachesOutsideTheBlock() {
        let markdown = "Notes\n\(Self.reference)\nMore"
        let spanning = NSRange(location: 0, length: ("Notes\n\(Self.reference)" as NSString).length)
        #expect(MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: spanning, in: markdown) == nil)
    }

    @Test func leavesASelectionInsideAFencedCodeBlock() {
        // Code fences and tables un-render while the caret is in them, so their characters are
        // visible source and a selection there is real.
        let markdown = "Intro\n```\nlet x = 1\n```\nOutro"
        let codeStart = ("Intro\n" as NSString).length
        let codeLength = ("```\nlet x = 1\n```" as NSString).length
        #expect(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(
                for: NSRange(location: codeStart, length: codeLength),
                in: markdown
            ) == nil
        )
    }

    @Test func collapsesASelectionInsideADivider() throws {
        let markdown = "Above\n---\nBelow"
        let dividerRange = NSRange(location: ("Above\n" as NSString).length, length: 3)
        let collapsed = try #require(
            MarkdownRenderedBlockDeletionSupport.collapsedSelection(for: dividerRange, in: markdown)
        )
        #expect(collapsed == NSRange(location: NSMaxRange(dividerRange), length: 0))
    }
}
