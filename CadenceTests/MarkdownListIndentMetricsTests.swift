import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

/// The one markdown list-indent formula, pinned.
///
/// It used to be written out twice — `MarkdownStylist.listMarkerIndent`/`listContentIndent` on
/// macOS and `iOSMarkdownStyler.listParagraphStyle` on iOS — with no test on either. Two copies of
/// a layout constant fail in the one way nothing catches: they drift by a few points on one
/// platform, which no compiler warns about, no diff reader notices, and no screenshot of a single
/// platform reveals. These tests fix the numbers, and the macOS test below fixes the *wiring*, so
/// a stylist that quietly goes back to spelling its own arithmetic fails here.
struct MarkdownListIndentMetricsTests {

    // MARK: - The numbers themselves

    /// Level 0 is not flush with the text container — every list line starts one marker inset in.
    @Test func theTopLevelMarkerStartsAtTheMarkerInset() {
        #expect(MarkdownListIndentMetrics.markerIndent(level: 0) == 8)
    }

    /// Each nesting level is one fixed step further in, and the step never compounds.
    @Test func eachNestingLevelAddsOneConstantStep() {
        #expect(MarkdownListIndentMetrics.markerIndent(level: 1) == 20)
        #expect(MarkdownListIndentMetrics.markerIndent(level: 2) == 32)
        #expect(MarkdownListIndentMetrics.markerIndent(level: 3) == 44)

        for level in 0..<5 {
            let step = MarkdownListIndentMetrics.markerIndent(level: level + 1)
                - MarkdownListIndentMetrics.markerIndent(level: level)
            #expect(step == MarkdownListIndentMetrics.levelUnit)
        }
    }

    /// Content clears the marker plus a gap, so wrapped lines line up under the text rather than
    /// under the bullet.
    @Test func contentClearsTheMarkerAndOneGap() {
        // "- " — two characters of marker.
        #expect(MarkdownListIndentMetrics.contentIndent(level: 0, markerWidth: 2) == 27)
        // "10. " — a wider marker pushes its own content across without moving the marker.
        #expect(MarkdownListIndentMetrics.contentIndent(level: 0, markerWidth: 4) == 38)
        #expect(MarkdownListIndentMetrics.markerIndent(level: 0) == 8)
    }

    /// A nested list's content indent is its own marker indent plus the same marker allowance —
    /// nesting and marker width are independent, which is what keeps a `1.` and a `10.` at the
    /// same level starting their markers in the same column.
    @Test func nestingAndMarkerWidthAreIndependent() {
        for level in 0..<5 {
            for markerWidth in 1..<7 {
                let content = MarkdownListIndentMetrics.contentIndent(level: level, markerWidth: markerWidth)
                let marker = MarkdownListIndentMetrics.markerIndent(level: level)
                #expect(content > marker)
                #expect(content - marker == CGFloat(markerWidth) * MarkdownListIndentMetrics.markerCharacterWidth
                    + MarkdownListIndentMetrics.contentGap)
            }
        }
    }

    // MARK: - The wiring (macOS)

    #if os(macOS)
    /// The AppKit stylist must *use* the shared metrics, not agree with them by coincidence.
    ///
    /// This runs the real `MarkdownStylist.apply(to:)` over real markdown and reads the paragraph
    /// styles back off the text storage, so re-inlining `level * 12 + 8` into the stylist fails
    /// here even though the inlined value is (today) the same number.
    @MainActor
    @Test func theAppKitStylistLaysListsOutWithTheSharedMetrics() throws {
        let lines = [
            "- alpha",
            "  - beta",
            "    - gamma",
            "1. one",
            "10. ten"
        ]
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.string = lines.joined(separator: "\n")
        MarkdownStylist.apply(to: textView)

        let storage = try #require(textView.textStorage)
        var location = 0
        for line in lines {
            let info = try #require(MarkdownListSupport.lineInfo(in: line), "\(line) should parse as a list line")
            let style = try #require(
                storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
                "\(line) should carry a paragraph style"
            )

            #expect(style.firstLineHeadIndent == MarkdownListIndentMetrics.markerIndent(level: info.visualLevel))
            #expect(style.headIndent == MarkdownListIndentMetrics.contentIndent(
                level: info.visualLevel,
                markerWidth: info.markerWidth
            ))

            location += (line as NSString).length + 1
        }
    }

    /// A GitHub checklist hides its whole `- [ ] ` prefix, so its first line has no marker to sit
    /// beside and must start where its wrapped lines do. That is still the *shared* content
    /// indent — the checkbox is drawn back into the gutter it leaves.
    @MainActor
    @Test func aHiddenChecklistPrefixStartsItsFirstLineAtTheContentIndent() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.string = "- [ ] todo"
        MarkdownStylist.apply(to: textView)

        let storage = try #require(textView.textStorage)
        let style = try #require(
            storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let expected = MarkdownListIndentMetrics.contentIndent(level: 0, markerWidth: 2)

        #expect(style.firstLineHeadIndent == expected)
        #expect(style.headIndent == expected)
    }
    #endif
}
