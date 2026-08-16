#if os(iOS)
import Testing
import UIKit

@testable import Cadence

struct iOSMarkdownStylingSupportTests {
    @Test func liveInlineCodePreservesLiteralMarkdownInsideCode() {
        let markdown = "`**not bold** [raw](https://example.com) #tag`"
        let styled = iOSMarkdownStyler.attributedString(for: markdown)

        #expect(isHidden(at: 0, in: styled))
        #expect(isHidden(at: (markdown as NSString).length - 1, in: styled))
        #expect(!isHidden(at: 1, in: styled))
        #expect(!isHidden(at: 2, in: styled))
        #expect(!isHidden(at: 14, in: styled))
        #expect(styled.attribute(.link, at: 16, effectiveRange: nil) == nil)
        #expect(styled.attribute(.cadenceMarkdownInlineCode, at: 4, effectiveRange: nil) as? Bool == true)
    }

    @Test func liveEmphasisCanWrapInlineCodeWithoutConsumingCodeMarkers() {
        let markdown = "**Review `API` today**"
        let styled = iOSMarkdownStyler.attributedString(for: markdown)

        #expect(isHidden(at: 0, in: styled))
        #expect(isHidden(at: 1, in: styled))
        #expect(isHidden(at: 9, in: styled))
        #expect(isHidden(at: 13, in: styled))
        #expect(isHidden(at: (markdown as NSString).length - 2, in: styled))
        #expect(isHidden(at: (markdown as NSString).length - 1, in: styled))
        #expect(styled.attribute(.cadenceMarkdownInlineCode, at: 10, effectiveRange: nil) as? Bool == true)
    }

    private func isHidden(at location: Int, in styled: NSAttributedString) -> Bool {
        (styled.attribute(.cadenceMarkdownHidden, at: location, effectiveRange: nil) as? Bool) == true
    }
}
#endif
