import Foundation
import Testing
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import Cadence

/// [[T-12263]]: a wrapped list item must hang its continuation lines under its OWN first line's
/// text, on both editors.
///
/// The iOS sighting was a checklist made with the format row's checklist button, which writes
/// Cadence's legacy `○ ` (`MarkdownFormatCommandSupport`), not GitHub `- [ ] `. A legacy marker is a
/// real, visible glyph styled at 18pt with 4pt of kern, so the first line's text starts at
/// `markerIndent + (width of the styled prefix)`; the wrapped lines started at
/// `MarkdownListIndentMetrics.contentIndent`, which ESTIMATES the prefix as 5.5pt per character.
/// For `○ ` that estimate is ~6pt short, which is exactly the sighting. Bullets and numbers used the
/// same estimate and missed by a few points the other way.
///
/// These tests lay the styled text out through the real TextKit stack each editor uses and
/// compare the two x positions TextKit itself produced. They assert a RELATION (the continuation
/// starts where the first line's text starts), never a pinned point figure, so they hold at any
/// Dynamic Type size and on either Xcode.
struct MarkdownListHangingIndentTests {

    /// Every visible-marker spelling an editor can produce, plus the GitHub checkbox whose hidden
    /// prefix already hung correctly (kept so a fix to the others cannot regress it).
    static let wrappedItems: [String] = [
        "○ Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "✓ Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "• Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "- Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "1. Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "10. Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "  ○ Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here.",
        "- [ ] Paragraph under the fixture image. Sighting run by phonesee1352 with enough words to wrap twice over here."
    ]

    /// Sub-point slack for the two TextKit glyph positions; the defect was 4-6pt.
    static let tolerance: CGFloat = 0.5

    struct Columns {
        let firstLineText: CGFloat
        let continuation: CGFloat
        let lineCount: Int
    }

    /// The x where the first line's content starts and where the second line starts, both read off
    /// the layout manager — the numbers a screenshot would show, minus the view's inset.
    static func columns(layoutManager: NSLayoutManager, contentStart: Int) -> Columns {
        let firstGlyph = layoutManager.glyphIndexForCharacter(at: contentStart)
        let firstFragment = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
        let firstX = firstFragment.minX + layoutManager.location(forGlyphAt: firstGlyph).x

        var lineStarts: [Int] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, _, _, range, _ in
            lineStarts.append(range.location)
        }
        let second = lineStarts.count > 1 ? lineStarts[1] : firstGlyph
        let secondFragment = layoutManager.lineFragmentRect(forGlyphAt: second, effectiveRange: nil)
        let continuationX = secondFragment.minX + layoutManager.location(forGlyphAt: second).x
        return Columns(firstLineText: firstX, continuation: continuationX, lineCount: lineStarts.count)
    }

    #if os(iOS)
    @MainActor
    @Test(arguments: wrappedItems)
    func theIOSEditorHangsAWrappedListItemUnderItsOwnText(_ markdown: String) throws {
        let info = try #require(MarkdownListSupport.lineInfo(in: markdown))
        let styled = iOSMarkdownStyler.attributedString(for: markdown, contentWidth: 300)
        let storage = NSTextStorage(attributedString: styled)
        // The editor's own stack: `iOSMarkdownTextView` builds TextKit 1 with this layout manager
        // and a 2pt line-fragment padding.
        let layoutManager = iOSMarkdownBlockCanvasLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 2
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let columns = Self.columns(layoutManager: layoutManager, contentStart: info.contentStart)
        #expect(columns.lineCount > 1, "\(markdown.prefix(6)) must wrap for the test to mean anything")
        #expect(
            abs(columns.continuation - columns.firstLineText) <= Self.tolerance,
            "\(markdown.prefix(6)): first line text at \(columns.firstLineText), continuation at \(columns.continuation)"
        )
    }

    /// Non-parameterised sibling (T-3212): proves the scope ran and pins the sighting's own case —
    /// the legacy `○ ` the iOS format row writes.
    @MainActor
    @Test func theFormatRowChecklistHangsUnderItsText() throws {
        try theIOSEditorHangsAWrappedListItemUnderItsOwnText(Self.wrappedItems[0])
    }
    #endif

    #if os(macOS)
    @MainActor
    @Test(arguments: wrappedItems)
    func theMacEditorHangsAWrappedListItemUnderItsOwnText(_ markdown: String) throws {
        let info = try #require(MarkdownListSupport.lineInfo(in: markdown))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        textView.string = markdown
        MarkdownStylist.apply(to: textView)
        let layoutManager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)

        let columns = Self.columns(layoutManager: layoutManager, contentStart: info.contentStart)
        #expect(columns.lineCount > 1, "\(markdown.prefix(6)) must wrap for the test to mean anything")
        #expect(
            abs(columns.continuation - columns.firstLineText) <= Self.tolerance,
            "\(markdown.prefix(6)): first line text at \(columns.firstLineText), continuation at \(columns.continuation)"
        )
    }

    /// Non-parameterised sibling (T-3212).
    @MainActor
    @Test func theMacLegacyChecklistHangsUnderItsText() throws {
        try theMacEditorHangsAWrappedListItemUnderItsOwnText(Self.wrappedItems[0])
    }
    #endif
}
