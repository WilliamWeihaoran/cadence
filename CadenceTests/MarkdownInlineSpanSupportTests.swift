import Foundation
import Testing
@testable import Cadence

/// Replaces `iOSMarkdownStylingSupportTests`, which asserted the same two behaviours against a
/// `UIKit` attributed string from inside `#if os(iOS)` — in a test target that builds for macOS.
/// Both tests read as coverage and neither had ever executed. The decisions they described now
/// live in `MarkdownInlineSpanSupport`, which is platform-free, so they run.
@MainActor
struct MarkdownInlineSpanSupportTests {
    @Test func inlineCodePreservesLiteralMarkdownInsideIt() throws {
        let markdown = "`**not bold** [raw](https://example.com) #tag`"
        let spans = MarkdownInlineSpanSupport.spans(in: markdown)

        #expect(spans.count == 1)
        let code = try #require(spans.first)
        #expect(code.kind == .code)
        // Content is everything between the backticks; only the two backticks are hidden.
        #expect(code.contentRange == NSRange(location: 1, length: (markdown as NSString).length - 2))
        #expect(code.markerRanges == [
            NSRange(location: 0, length: 1),
            NSRange(location: (markdown as NSString).length - 1, length: 1)
        ])
    }

    @Test func emphasisWrapsInlineCodeWithoutConsumingItsMarkers() {
        let markdown = "**Review `API` today**"
        let spans = MarkdownInlineSpanSupport.spans(in: markdown)

        #expect(spans.map(\.kind) == [.bold, .code])

        let bold = spans.first { $0.kind == .bold }
        #expect(bold?.contentRange == NSRange(location: 2, length: 18))
        #expect(bold?.markerRanges == [
            NSRange(location: 0, length: 2),
            NSRange(location: 20, length: 2)
        ])

        // The backticks are the code span's own markers, so they are hidden by it — not eaten by
        // the emphasis pass, which would have left `API` styled as prose.
        let code = spans.first { $0.kind == .code }
        #expect(code?.contentRange == NSRange(location: 10, length: 3))
        #expect(code?.markerRanges == [
            NSRange(location: 9, length: 1),
            NSRange(location: 13, length: 1)
        ])
    }

    @Test func emphasisInsideACodeSpanIsNotStyled() {
        // The containment rule: a run swallowed whole by inline code is literal text.
        let spans = MarkdownInlineSpanSupport.spans(in: "`a **b** c`")

        #expect(spans.map(\.kind) == [.code])
    }

    @Test func spansComeBackInApplicationOrderSoBoldItalicWinsOverBold() {
        let spans = MarkdownInlineSpanSupport.spans(in: "***both***")

        // Bold and italic both match `***both***` too; the caller applies in the order given, so
        // bold-italic has to land first or the run ends up merely bold.
        #expect(spans.first?.kind == .boldItalic)
        #expect(spans.first?.contentRange == NSRange(location: 3, length: 4))
    }

    @Test func anExcludedBlockRangeSuppressesEveryOverlappingSpan() {
        let markdown = "| **a** | b |"
        let rowRange = NSRange(location: 0, length: (markdown as NSString).length)

        #expect(MarkdownInlineSpanSupport.spans(in: markdown, excluding: [rowRange]).isEmpty)
        #expect(MarkdownInlineSpanSupport.spans(in: markdown).map(\.kind) == [.bold])
    }

    @Test func underscoreEmphasisDoesNotFireInsideAWord() {
        #expect(MarkdownInlineSpanSupport.spans(in: "snake_case_name").isEmpty)
        #expect(MarkdownInlineSpanSupport.spans(in: "_real_").map(\.kind) == [.italic])
    }

    @Test func markerRangesAreEmptyWhenTheContentFillsTheMatch() {
        let full = NSRange(location: 4, length: 3)
        #expect(MarkdownInlineSpanSupport.markerRanges(fullRange: full, contentRange: full).isEmpty)
    }

    @Test func excludedRangesDisqualifyOnAnyOverlapButProtectedRangesOnlyOnContainment() {
        let candidate = NSRange(location: 5, length: 5)

        #expect(!MarkdownInlineSpanSupport.shouldStyle(candidate, excluding: [NSRange(location: 9, length: 4)]))
        #expect(MarkdownInlineSpanSupport.shouldStyle(
            candidate,
            excluding: [],
            protecting: [NSRange(location: 9, length: 4)]
        ))
        #expect(!MarkdownInlineSpanSupport.shouldStyle(
            candidate,
            excluding: [],
            protecting: [NSRange(location: 0, length: 20)]
        ))
    }

    @Test func spansOverEmojiAndCJKStayInUTF16Units() {
        // The classic mis-ranging: an emoji is two UTF-16 units and one Character. A span measured
        // in Characters would hide the wrong glyphs — and, on a surrogate pair, the wrong half of
        // one.
        let markdown = "🙂 **值得做** 🙂"
        let nsMarkdown = markdown as NSString
        let spans = MarkdownInlineSpanSupport.spans(in: markdown)

        #expect(spans.map(\.kind) == [.bold])
        let bold = spans.first
        #expect(nsMarkdown.substring(with: bold?.contentRange ?? NSRange()) == "值得做")
        #expect((bold?.markerRanges ?? []).map { nsMarkdown.substring(with: $0) } == ["**", "**"])
    }
}
