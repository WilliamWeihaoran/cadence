import Foundation
import Testing
@testable import Cadence

struct MarkdownQuoteSupportTests {
    @Test func parsesIndentedNestedQuoteLines() throws {
        let quote = try #require(MarkdownQuoteSupport.lineInfo(in: "    >>   Nested thought  "))

        #expect(quote.depth == 2)
        #expect(quote.content == "Nested thought")
        #expect(quote.prefixRange == NSRange(location: 0, length: 9))
        #expect(quote.contentRange == NSRange(location: 9, length: 14))
    }

    @Test func ignoresPlainGreaterThanSymbolsInsideText() {
        #expect(MarkdownQuoteSupport.lineInfo(in: "Score 3 > 2") == nil)
    }

    @Test func allowsEmptyQuoteMarkerForLiveStyling() throws {
        let quote = try #require(MarkdownQuoteSupport.lineInfo(in: ">   "))

        #expect(quote.depth == 1)
        #expect(quote.content.isEmpty)
    }

    @Test func continuesNonEmptyQuoteLines() {
        #expect(MarkdownQuoteSupport.continuation(after: "> Keep going") == "> ")
        #expect(MarkdownQuoteSupport.continuation(after: "  >> Nested") == "  >> ")
    }

    @Test func continuesListsInsideQuoteLines() {
        #expect(MarkdownQuoteSupport.continuation(after: "> - item") == "> • ")
        #expect(MarkdownQuoteSupport.continuation(after: "> 1. first") == "> 2. ")
        #expect(MarkdownQuoteSupport.continuation(after: "> - [ ] task") == "> ○ ")
    }

    @Test func doesNotContinueEmptyQuoteMarkers() {
        #expect(MarkdownQuoteSupport.continuation(after: "> ") == nil)
        #expect(MarkdownQuoteSupport.continuation(after: "Plain text") == nil)
    }
}
