import Foundation
import Testing
@testable import Cadence

struct MarkdownLinkSupportTests {
    @Test func findsRegularMarkdownLinksButIgnoresImages() {
        let markdown = "Read [Docs](https://example.com) and keep ![Sketch](https://example.com/image.png)."

        let links = MarkdownLinkSupport.linkRanges(in: markdown)

        #expect(links.count == 1)
        #expect(links.first?.label == "Docs")
        #expect(links.first?.urlString == "https://example.com")
    }

    @Test func returnsURLWhenLocationIsInsideVisibleLabel() throws {
        let markdown = "Open [Docs](https://example.com) today."
        let labelLocation = try #require((markdown as NSString).range(of: "Docs").toOptional()?.location)

        let url = MarkdownLinkSupport.linkURL(atUTF16Location: labelLocation, in: markdown)

        #expect(url?.absoluteString == "https://example.com")
    }

    @Test func optionallyReturnsURLWhenLocationIsInsideHiddenSyntax() throws {
        let markdown = "Open [Docs](https://example.com) today."
        let urlLocation = try #require((markdown as NSString).range(of: "https://example.com").toOptional()?.location)

        let hiddenSyntaxURL = MarkdownLinkSupport.linkURL(
            atUTF16Location: urlLocation,
            in: markdown,
            includesHiddenSyntax: true
        )
        let visibleURL = MarkdownLinkSupport.linkURL(atUTF16Location: urlLocation, in: markdown)

        #expect(hiddenSyntaxURL?.absoluteString == "https://example.com")
        #expect(visibleURL == nil)
    }

    // MARK: - Parentheses in the destination (T-14781)

    /// The destination ended at the first `)`, so a Wikipedia link opened
    /// `…/Swift_(programming_language` -- a different page -- and drew a stray `)` after the label.
    @Test func aBalancedParenthesisInTheDestinationStaysInTheURL() throws {
        let destination = "https://en.wikipedia.org/wiki/Swift_(programming_language)"
        let markdown = "Read [Swift](\(destination)) first."

        let link = try #require(MarkdownLinkSupport.linkRanges(in: markdown).first)

        #expect(MarkdownLinkSupport.linkRanges(in: markdown).count == 1)
        #expect(link.label == "Swift")
        #expect(link.urlString == destination)
        #expect(link.url?.absoluteString == destination)
        // The whole link, closing `)` included, is the match -- nothing of it is left as prose.
        #expect((markdown as NSString).substring(with: link.fullRange) == "[Swift](\(destination))")
    }

    /// The label is what a click lands on, so the URL it opens is the one a reader sees.
    @Test func clickingTheLabelOfAParenthesisedLinkOpensTheWholeURL() throws {
        let destination = "https://en.wikipedia.org/wiki/Mercury_(planet)#Orbit"
        let markdown = "See [Mercury](\(destination))."
        let labelLocation = try #require((markdown as NSString).range(of: "Mercury").toOptional()?.location)

        let url = MarkdownLinkSupport.linkURL(atUTF16Location: labelLocation, in: markdown)

        #expect(url?.absoluteString == destination)
    }

    /// A `)` that opened nothing still ends the link: a parenthetical straight after a link, and a
    /// link inside a parenthetical, are prose around a plain destination -- the cases the old
    /// pattern already got right and the balanced one must not swallow.
    @Test func anUnopenedParenthesisStillEndsTheLink() {
        let after = MarkdownLinkSupport.linkRanges(in: "[a](https://a.example) (see also)")
        #expect(after.map(\.urlString) == ["https://a.example"])

        let inside = MarkdownLinkSupport.linkRanges(in: "(compare [b](https://b.example))")
        #expect(inside.map(\.urlString) == ["https://b.example"])

        let two = MarkdownLinkSupport.linkRanges(in: "[x](https://x.example/(1)) and [y](https://y.example)")
        #expect(two.map(\.urlString) == ["https://x.example/(1)", "https://y.example"])
    }

    /// The hidden runs are still exactly the link's brackets when the destination nests a pair.
    @Test func theHiddenRunsOfAParenthesisedLinkAreStillItsBrackets() throws {
        let markdown = "see [the page](https://example.com/a_(b)) now"
        let nsMarkdown = markdown as NSString
        let link = try #require(MarkdownLinkSupport.linkRanges(in: markdown).first)

        let hidden = MarkdownInlineMarkerRanges
            .hiddenRanges(forLink: link.fullRange, label: link.labelRange, url: link.urlRange)
            .map { nsMarkdown.substring(with: $0) }
        #expect(hidden == ["[", "](", ")"])
    }
}

private extension NSRange {
    func toOptional() -> NSRange? {
        location == NSNotFound ? nil : self
    }
}
