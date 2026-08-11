import Foundation
import Testing
@testable import Cadence

struct MarkdownRenderedBlockDeletionSupportTests {
    @Test func expandsPartialImageSelectionToWholeImageBlockAndFollowingNewline() {
        let imageID = "11111111-1111-1111-1111-111111111111"
        let markdown = "Before\n![Sketch](cadence-image://\(imageID))\nAfter"
        let markerLocation = ("Before\n![" as NSString).length

        let range = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: markerLocation, length: 1)
        )

        #expect(range == NSRange(location: 7, length: 64))
    }

    @Test func expandsTaskEmbedSelectionToWholeTaskBlock() {
        let taskID = "22222222-2222-2222-2222-222222222222"
        let markdown = "Before\n[[task:\(taskID)|Ship iOS notes]]\nAfter"
        let titleLocation = (markdown as NSString).range(of: "Ship").location

        let range = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: titleLocation, length: 2)
        )

        #expect(range == NSRange(location: 7, length: 61))
    }

    @Test func includesPrecedingNewlineWhenRenderedBlockIsAtDocumentEnd() {
        let imageID = "11111111-1111-1111-1111-111111111111"
        let markdown = "Before\n![Sketch](cadence-image://\(imageID))"
        let imageLocation = (markdown as NSString).range(of: "cadence-image").location

        let range = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: imageLocation, length: 1)
        )

        #expect(range == NSRange(location: 6, length: 64))
    }

    @Test func ignoresInlineReferencesAndImages() {
        let imageID = "11111111-1111-1111-1111-111111111111"
        let markdown = "Before ![Sketch](cadence-image://\(imageID)) after"
        let imageLocation = (markdown as NSString).range(of: "cadence-image").location

        let range = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: imageLocation, length: 1)
        )

        #expect(range == nil)
    }

    @Test func expandsCodeBlockSelectionToWholeFencedBlock() throws {
        let markdown = """
        Before
        ```swift
        let mode = "live"
        print(mode)
        ```
        After
        """
        let probeLocation = (markdown as NSString).range(of: "print").location

        let range = try #require(MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: probeLocation, length: 1)
        ))

        #expect((markdown as NSString).substring(with: range) == """
        ```swift
        let mode = "live"
        print(mode)
        ```

        """)
    }

    @Test func expandsTableSelectionToWholeTableBlock() throws {
        let markdown = """
        Before
        | Area | Status |
        | --- | --- |
        | iOS | Live |
        | Mac | Stable |
        After
        """
        let probeLocation = (markdown as NSString).range(of: "Live").location

        let range = try #require(MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: probeLocation, length: 1)
        ))

        #expect((markdown as NSString).substring(with: range) == """
        | Area | Status |
        | --- | --- |
        | iOS | Live |
        | Mac | Stable |

        """)
    }

    @Test func expandsDividerSelectionToWholeDividerLine() throws {
        let markdown = """
        Before
        * * *
        After
        """
        let probeLocation = (markdown as NSString).range(of: "* * *").location

        let range = try #require(MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
            in: markdown,
            selection: NSRange(location: probeLocation, length: 1)
        ))

        #expect((markdown as NSString).substring(with: range) == "* * *\n")
    }

    @Test func findsRenderedCodeBlockAtTappedLocation() throws {
        let markdown = """
        Before
        ```swift
        let mode = "live"
        print(mode)
        ```
        After
        """
        let probeLocation = (markdown as NSString).range(of: "mode").location

        let block = try #require(MarkdownRenderedBlockDeletionSupport.renderedBlock(
            atUTF16Location: probeLocation,
            in: markdown
        ))

        #expect(block.kind == .code)
        #expect((markdown as NSString).substring(with: block.storageRange) == """
        ```swift
        let mode = "live"
        print(mode)
        ```
        """)
    }

    @Test func findsRenderedTableBlockAtTappedLocation() throws {
        let markdown = """
        Before
        | Area | Status |
        | --- | --- |
        | iOS | Live |
        | Mac | Stable |
        After
        """
        let probeLocation = (markdown as NSString).range(of: "Stable").location

        let block = try #require(MarkdownRenderedBlockDeletionSupport.renderedBlock(
            atUTF16Location: probeLocation,
            in: markdown
        ))

        #expect(block.kind == .table)
        #expect((markdown as NSString).substring(with: block.storageRange) == """
        | Area | Status |
        | --- | --- |
        | iOS | Live |
        | Mac | Stable |
        """)
    }

    @Test func findsRenderedTaskBlockAtTappedLocation() throws {
        let taskID = "22222222-2222-2222-2222-222222222222"
        let markdown = "Before\n[[task:\(taskID)|Ship iOS notes]]\nAfter"
        let probeLocation = (markdown as NSString).range(of: "Ship").location

        let block = try #require(MarkdownRenderedBlockDeletionSupport.renderedBlock(
            atUTF16Location: probeLocation,
            in: markdown
        ))

        #expect(block.kind == .task)
        #expect((markdown as NSString).substring(with: block.storageRange) == "[[task:\(taskID)|Ship iOS notes]]")
    }

    /// The macOS editor finds its blocks from `NSTextStorage` attributes rather than from the
    /// markdown source, so it cannot use `expandedDeletionRange(in:selection:)` — but it shares
    /// this expansion rule instead of carrying a second copy of it.
    @Test func expandsAKnownBlockRangeOverExactlyOneAdjacentNewline() {
        let markdown = "Before\nblock\nAfter"
        let blockRange = NSRange(location: 7, length: 5)

        #expect(
            MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: blockRange, in: markdown)
                == NSRange(location: 7, length: 6)
        )

        // No newline after the last line, so the one in front of it is taken instead.
        let trailing = "Before\nblock"
        #expect(
            MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: blockRange, in: trailing)
                == NSRange(location: 6, length: 6)
        )

        // An empty range describes no block, so there is nothing to swallow a newline for.
        #expect(
            MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
                for: NSRange(location: 7, length: 0),
                in: markdown
            ) == NSRange(location: 7, length: 0)
        )
    }

    @Test func renderedBlockLookupIgnoresInlineImages() {
        let imageID = "11111111-1111-1111-1111-111111111111"
        let markdown = "Before ![Sketch](cadence-image://\(imageID)) after"
        let probeLocation = (markdown as NSString).range(of: "cadence-image").location

        let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
            atUTF16Location: probeLocation,
            in: markdown
        )

        #expect(block == nil)
    }
}
