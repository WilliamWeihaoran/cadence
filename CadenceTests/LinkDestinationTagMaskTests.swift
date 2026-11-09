import Foundation
import Testing
@testable import Cadence

/// [[T-14783]]: a link destination or bare URL holding balanced parentheses is masked whole, so
/// its `#fragment` is not swept into a tag the user never created. The mask stopped at the first
/// `)`, leaving `#History)` of a Wikipedia link as prose. Same grammar `MarkdownLinkSupport` took
/// in [[T-14781]]: one level of balanced parentheses, an unopened `)` still ends the URL.
struct LinkDestinationTagMaskTests {
    private func names(_ content: String) -> [String] {
        MarkdownMetadataParser.inlineTagNames(in: content)
    }

    @Test func aLinkDestinationWithParenthesesAndAFragmentMintsNoTag() {
        #expect(names("[History](https://en.wikipedia.org/wiki/Swift_(programming_language)#History)") == [])
        #expect(names("Read [it](https://x.org/a_(b)#Frag) first #real") == ["real"],
                "a real tag after the link still parses")
    }

    @Test func aBareURLWithParenthesesAndAFragmentMintsNoTag() {
        #expect(names("see https://en.wikipedia.org/wiki/Swift_(programming_language)#History ok") == [])
    }

    @Test func anUnopenedParenthesisStillEndsTheMask() {
        #expect(names("[a](b) (c) #todo") == ["todo"])
        #expect(names("(see https://x.com) #todo") == ["todo"])
        #expect(names("plain #work and [l](https://x.com/#frag)") == ["work"], "non-vacuity: plain prose still tags")
    }
}
