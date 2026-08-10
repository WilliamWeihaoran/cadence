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

    @Test func leavesSentenceOpeningAbbreviationsAlone() {
        // "a."/"b." lettered lists are a single letter; a whole word before the period is prose.
        #expect(MarkdownTypingTransformSupport.mutation(in: "Mr. ", cursor: 4) == nil)
        #expect(MarkdownTypingTransformSupport.mutation(in: "Dr. ", cursor: 4) == nil)
        #expect(MarkdownTypingTransformSupport.mutation(in: "Fig. ", cursor: 5) == nil)
        #expect(MarkdownTypingTransformSupport.mutation(in: "Note. ", cursor: 6) == nil)
        #expect(MarkdownTypingTransformSupport.mutation(in: "vs. ", cursor: 4) == nil)
    }

    @Test func typedSingleLetterMarkersUseTheirAlphabetPosition() throws {
        // "c"/"m" are also roman numerals, but a lone letter opening a list is the 3rd/13th item,
        // not 100/1000. "i." is the exception: nobody opens a lettered list at its 9th letter.
        let c = try #require(MarkdownTypingTransformSupport.mutation(in: "c. ", cursor: 3))
        let m = try #require(MarkdownTypingTransformSupport.mutation(in: "m. ", cursor: 3))
        let roman = try #require(MarkdownTypingTransformSupport.mutation(in: "iv. ", cursor: 4))
        let outline = try #require(MarkdownTypingTransformSupport.mutation(in: "I. ", cursor: 3))

        #expect(c.text == "3. ")
        #expect(m.text == "13. ")
        #expect(roman.text == "4. ")
        #expect(outline.text == "1. ")
    }

    @Test func typedMarkerReadsTheRunItIsJoining() throws {
        // Typed after "4.", "V." is the fifth item, not the twenty-second.
        let text = "4. four\nV. "
        let mutation = try #require(MarkdownTypingTransformSupport.mutation(in: text, cursor: (text as NSString).length))

        #expect(mutation.text == "4. four\n5. ")
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
