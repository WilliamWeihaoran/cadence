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

    @Test func ignoresSelectedText() {
        let mutation = MarkdownBackspaceSupport.listPrefixMutation(
            in: "• item",
            selection: NSRange(location: 0, length: 2)
        )

        #expect(mutation == nil)
    }
}
