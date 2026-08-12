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

    // Continuation-on-Return is asserted in `MarkdownLineBreakSupportTests`, against the path the
    // editor runs. It used to be asserted here too, against a `MarkdownQuoteSupport.continuation`
    // nothing called — which is how that copy came to disagree with the editor unnoticed.
}
