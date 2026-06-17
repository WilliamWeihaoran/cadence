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
}

private extension NSRange {
    func toOptional() -> NSRange? {
        location == NSNotFound ? nil : self
    }
}
