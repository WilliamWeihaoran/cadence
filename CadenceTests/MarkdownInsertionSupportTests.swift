import Foundation
import Testing
@testable import Cadence

struct MarkdownInsertionSupportTests {
    @Test func blockInsertionAddsTrailingNewlineAtEndOfDocument() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(insertion == "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n")
    }

    @Test func blockInsertionPadsWhenInsertedInsideText() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "Before after",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(insertion == "\n\n![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n\n")
    }

    @Test func blockInsertionDoesNotAddExtraBreaksBesideExistingNewlines() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "Before\n\nAfter",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(insertion == "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n")
    }
}
