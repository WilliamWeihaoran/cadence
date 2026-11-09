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
}
