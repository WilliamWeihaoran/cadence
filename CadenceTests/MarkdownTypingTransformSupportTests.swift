import Foundation
import Testing

@testable import Cadence

struct MarkdownTypingTransformSupportTests {
    @Test func normalizesTypedBulletShortcuts() throws {
        let mutation = try #require(MarkdownTypingTransformSupport.mutation(in: "- ", cursor: 2))

        #expect(mutation.text == "• ")
        #expect(mutation.replacementRange == NSRange(location: 0, length: 2))
        #expect(mutation.replacement == "• ")
        #expect(mutation.selection == NSRange(location: 2, length: 0))
    }

    @Test func normalizesTypedChecklistShortcuts() throws {
        let todo = try #require(MarkdownTypingTransformSupport.mutation(in: "[ ] ", cursor: 4))
        let done = try #require(MarkdownTypingTransformSupport.mutation(in: "[x] ", cursor: 4))
        let compact = try #require(MarkdownTypingTransformSupport.mutation(in: "[] ", cursor: 3))

        #expect(todo.text == "○ ")
        #expect(done.text == "✓ ")
        #expect(compact.text == "○ ")
    }

    @Test func remapsTypedOrderedMarkerForIndentationLevel() throws {
        let text = "    1. "
        let mutation = try #require(MarkdownTypingTransformSupport.mutation(in: text, cursor: (text as NSString).length))

        #expect(mutation.text == "    a. ")
        #expect(mutation.selection == NSRange(location: ("    a. " as NSString).length, length: 0))
    }

    @Test func preservesTypedOrderedMarkerIndex() throws {
        let text = "        4. "
        let mutation = try #require(MarkdownTypingTransformSupport.mutation(in: text, cursor: (text as NSString).length))

        #expect(mutation.text == "        iv. ")
    }

    @Test func appliesTypedSlashCommandExpansion() throws {
        let text = "Notes\n/todo "
        let mutation = try #require(MarkdownTypingTransformSupport.mutation(in: text, cursor: (text as NSString).length))

        #expect(mutation.text == "Notes\n○ ")
        #expect(mutation.selection == NSRange(location: ("Notes\n○ " as NSString).length, length: 0))
    }

    @Test func ignoresPlainInlineSlashText() {
        let text = "https://example.com/path "

        #expect(MarkdownTypingTransformSupport.mutation(in: text, cursor: (text as NSString).length) == nil)
    }
}
