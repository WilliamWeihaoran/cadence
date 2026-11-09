import Foundation
import Testing

@testable import Cadence

struct MarkdownBackspaceSupportTests {
    @Test func removesBulletPrefixWhenCaretIsAfterMarker() throws {
        let markdown = "• item"

        let mutation = try #require(MarkdownBackspaceSupport.listPrefixMutation(
            in: markdown,
            selection: NSRange(location: ("• " as NSString).length, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 0, length: 2))
        #expect(mutation.replacement == "")
        #expect(mutation.selection == NSRange(location: 0, length: 0))
    }

    @Test func removesChecklistPrefixWhenCaretIsAfterMarker() throws {
        let markdown = "- [x] done"

        let mutation = try #require(MarkdownBackspaceSupport.listPrefixMutation(
            in: markdown,
            selection: NSRange(location: ("- [x] " as NSString).length, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 0, length: 6))
        #expect(mutation.selection == NSRange(location: 0, length: 0))
    }

    @Test func removesEmptyListPrefixWhenCaretIsAfterTrailingWhitespace() throws {
        let markdown = "Before\n•   \nAfter"
        let caret = ("Before\n•   " as NSString).length

        let mutation = try #require(MarkdownBackspaceSupport.listPrefixMutation(
            in: markdown,
            selection: NSRange(location: caret, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 7, length: 2))
        #expect(mutation.selection == NSRange(location: 7, length: 0))
    }

    @Test func removesPartialEmptyListPrefixWhenCaretIsInsidePrefix() throws {
        let markdown = "    • "
        let caret = ("    " as NSString).length

        let mutation = try #require(MarkdownBackspaceSupport.listPrefixMutation(
            in: markdown,
            selection: NSRange(location: caret, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 0, length: 4))
        #expect(mutation.selection == NSRange(location: 0, length: 0))
    }

    @Test func ignoresNonEmptyListWhenCaretIsInContent() {
        let markdown = "• item"

        let mutation = MarkdownBackspaceSupport.listPrefixMutation(
            in: markdown,
            selection: NSRange(location: (markdown as NSString).length, length: 0)
        )

        #expect(mutation == nil)
    }

    /// [[T-14713]]: Backspace on the empty line after the note's final newline, below an empty
    /// bullet, is an ordinary Backspace (it removes that newline). The probe was clamped to
    /// `length - 1`, the previous line's newline, so it read the empty bullet above, deleted its
    /// "• " and jumped the caret to 0.
    @Test func backspaceOnTheEmptyFinalLineLeavesTheBulletAboveAlone() throws {
        let afterFinalNewline = MarkdownBackspaceSupport.listPrefixMutation(
            in: "• \n",
            selection: NSRange(location: 3, length: 0)
        )
        #expect(afterFinalNewline == nil)

        // The neighbouring case keeps firing: an empty bullet that IS the last line, with no
        // newline after it, still loses its marker.
        let unterminated = try #require(MarkdownBackspaceSupport.listPrefixMutation(
            in: "• ",
            selection: NSRange(location: 2, length: 0)
        ))
        #expect(unterminated.replacementRange == NSRange(location: 0, length: 2))
        #expect(unterminated.selection == NSRange(location: 0, length: 0))
    }

    @Test func ignoresSelectedText() {
        let mutation = MarkdownBackspaceSupport.listPrefixMutation(
            in: "• item",
            selection: NSRange(location: 0, length: 2)
        )

        #expect(mutation == nil)
    }

    /// [[T-14722]]: UIKit proposes a Backspace as the character it deletes, `(n-1, 1)`, with the
    /// caret still at `n`. That proposal is a Backspace from the caret at `n`; nothing else is.
    @Test func aSingleCharacterBackwardProposalIsTheBackspaceFromTheCaretAfterIt() {
        let caret = MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: NSRange(location: 1, length: 1),
            replacement: "",
            currentSelection: NSRange(location: 2, length: 0)
        )
        #expect(caret == NSRange(location: 2, length: 0))

        // A forward delete proposes the character AFTER the caret: caret at the proposal's start.
        #expect(MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: NSRange(location: 2, length: 1),
            replacement: "",
            currentSelection: NSRange(location: 2, length: 0)
        ) == nil)
        // Deleting a selection is not a Backspace from a caret.
        #expect(MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: NSRange(location: 0, length: 2),
            replacement: "",
            currentSelection: NSRange(location: 0, length: 2)
        ) == nil)
        #expect(MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: NSRange(location: 1, length: 1),
            replacement: "",
            currentSelection: NSRange(location: 1, length: 1)
        ) == nil)
        // Typing over a character is not a deletion.
        #expect(MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: NSRange(location: 1, length: 1),
            replacement: "x",
            currentSelection: NSRange(location: 2, length: 0)
        ) == nil)
    }

    /// [[T-14722]], end to end on the shared half: the proposal UIKit sends for Backspace right
    /// after an empty bullet's marker reaches the list-prefix rule as the caret, and the whole
    /// marker goes, as it does from the Mac's `deleteBackward:`. The raw proposal alone is refused,
    /// which is the defect the translation exists for.
    @Test func backspaceProposedAfterAnEmptyBulletsMarkerRemovesTheWholeMarker() throws {
        let markdown = "- first\n- "
        let caretLocation = (markdown as NSString).length
        let proposal = NSRange(location: caretLocation - 1, length: 1)
        #expect(
            MarkdownBackspaceSupport.listPrefixMutation(in: markdown, selection: proposal) == nil,
            "non-vacuity: the raw proposal is a range, which the caret rule refuses"
        )

        let caret = try #require(MarkdownBackspaceSupport.backspaceCaret(
            forProposedDeletion: proposal,
            replacement: "",
            currentSelection: NSRange(location: caretLocation, length: 0)
        ))
        let mutation = try #require(MarkdownBackspaceSupport.listPrefixMutation(in: markdown, selection: caret))
        #expect(mutation.replacementRange == NSRange(location: ("- first\n" as NSString).length, length: 2))
        #expect(mutation.selection == NSRange(location: ("- first\n" as NSString).length, length: 0))
    }
}
