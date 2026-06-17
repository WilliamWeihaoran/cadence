import Testing
@testable import Cadence

struct CadenceTaskPresentationSupportTests {
    @Test func plainPreviewUsesDisplayTextForCadenceReferences() {
        let markdown = """
        ## Plan
        - [ ] Review [[task:22222222-2222-2222-2222-222222222222|Ship iOS notes]]
        See [[note:11111111-1111-1111-1111-111111111111|Project Notes]]
        """

        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Plan Review Ship iOS notes See Project Notes")
    }

    @Test func plainPreviewNormalizesIOSNativeListMarkers() {
        let markdown = """
        • Capture inbox
        ○ Draft note
        ✓ Review note
        """

        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Capture inbox Draft note Review note")
    }

    @Test func markdownPreviewRemovesCommonInlineSyntax() {
        let markdown = """
        # Meeting Notes
        - [x] Ship **live preview**
        See [docs](https://example.com) and `inline code`
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown, limit: 80)

        #expect(preview == "Meeting Notes Ship live preview See docs and inline code")
    }

    @Test func markdownPreviewUsesImageAltTextForInlineImages() {
        let markdown = """
        Capture ![Whiteboard](cadence-image://22222222-2222-2222-2222-222222222222) after standup.
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Capture Whiteboard after standup.")
    }

    @Test func markdownPreviewNormalizesMarkdownInsideLinkLabels() {
        let markdown = """
        Read [**Design** `API`](https://example.com) before planning.
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Read Design API before planning.")
    }

    @Test func markdownPreviewNormalizesNestedInlineMarkdown() {
        let markdown = """
        - [ ] **Review `API` and [docs](https://example.com)**
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Review API and docs")
    }

    @Test func markdownPreviewUsesSharedParserForRichBlocks() {
        let markdown = """
        # _Launch_ Notes
        > Review __copy__ with [[note:11111111-1111-1111-1111-111111111111|Design Notes]]

        ![Screenshot](cadence-image://22222222-2222-2222-2222-222222222222)

        [[task:33333333-3333-3333-3333-333333333333|Finish TestFlight checklist]]

        | Area | Owner |
        | --- | --- |
        | iOS | William |
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Launch Notes Review copy with Design Notes Screenshot Finish TestFlight checklist Area Owner iOS William")
    }

    @Test func markdownPreviewPreservesCodeContentWithoutFenceMarkers() {
        let markdown = """
        Before
        ```swift
        let cadence = "iOS"
        ```
        After
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == #"Before let cadence = "iOS" After"#)
    }
}
