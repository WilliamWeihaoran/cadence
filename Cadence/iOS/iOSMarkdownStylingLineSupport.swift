#if os(iOS)
import SwiftUI
import UIKit

/// **Line-level styling: quotes, list markers, checkboxes, and heading type.**
///
/// One source line at a time, driven by `styleLine` in `iOSMarkdownStylingSupport.swift`. Every
/// matcher here is a thin read of a `Markdown*Support` service — what a line *is* was never decided
/// on this side of the boundary, and the two small value types at the foot of the file exist only to
/// carry that answer into the drawing code in the shape it wants it.
extension iOSMarkdownStyler {
    static func applyQuoteLine(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        lineStart: Int,
        quote: iOSMarkdownQuoteMatch
    ) {
        let levelInset = CGFloat(max(quote.depth - 1, 0)) * 12
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.firstLineHeadIndent = 18 + levelInset
        paragraph.headIndent = 18 + levelInset
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttributes([
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor(Theme.muted),
            .font: italicFont(from: baseFont)
        ], range: lineRange)

        applyQuoteAttachment(storage, markerRange: quote.prefixRange.shifted(by: lineStart), depth: quote.depth)
    }

    private static func applyQuoteAttachment(
        _ storage: NSMutableAttributedString,
        markerRange: NSRange,
        depth: Int
    ) {
        guard markerRange.length > 0 else { return }
        let canvas = iOSMarkdownQuoteMarkerLayoutInfo(depth: depth).renderedMarker()
        drawCanvas(storage, canvas, over: markerRange, isBlock: false, yOffset: 0)
    }

    private static func applyCheckboxAttachment(
        _ storage: NSMutableAttributedString,
        markerRange: NSRange,
        isDone: Bool
    ) {
        guard markerRange.length > 0 else { return }
        let canvas = iOSMarkdownCheckboxLayoutInfo(isDone: isDone).renderedMarker()
        drawCanvas(storage, canvas, over: markerRange, isBlock: false, yOffset: 0)
    }

    private static func applyCompletedListText(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        contentStart: Int
    ) {
        let contentLocation = lineRange.location + contentStart
        let contentLength = max(0, NSMaxRange(lineRange) - contentLocation)
        guard contentLength > 0 else { return }
        storage.addAttributes([
            .foregroundColor: UIColor(Theme.dim),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ], range: NSRange(location: contentLocation, length: contentLength))
    }

    static func applyListLine(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        lineStart: Int,
        list: iOSMarkdownListMatch
    ) {
        let paragraph = listParagraphStyle(
            for: list.visualLevel,
            markerWidth: list.markerWidth,
            // A checkbox has no visible marker glyph to sit in the first line's indent — the whole
            // `- [x] ` prefix is hidden and the box is painted into the gutter beside it — so the
            // first line has to start at the same column its wrapped lines do. Left at the normal
            // list indent, the hidden prefix put the text 19pt to the left of where the box lands
            // and the two overlapped.
            indentsFirstLineToContent: list.kind.isDrawnCheckbox
        )
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)

        let markerRange = list.markerRange.shifted(by: lineStart)
        switch list.kind {
        case let .ordered(marker):
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.text),
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .kern: 3.5
            ], range: markerRange)
            if marker.hasSuffix(")") {
                storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: markerRange)
            }

        case let .bullet(marker):
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.text),
                .font: UIFont.systemFont(ofSize: marker == "•" || marker == "*" ? 20 : 14, weight: .semibold),
                .kern: 4
            ], range: markerRange)

        case let .legacyChecklist(isDone):
            storage.addAttributes([
                .foregroundColor: isDone ? UIColor(Theme.green) : UIColor(Theme.dim),
                .font: UIFont.systemFont(ofSize: isDone ? 16 : 18, weight: isDone ? .bold : .regular),
                .kern: 4
            ], range: markerRange)
            if isDone {
                applyCompletedListText(storage, lineRange: lineRange, contentStart: list.contentStart)
            }

        case let .checkbox(isDone):
            applyCheckboxAttachment(storage, markerRange: markerRange, isDone: isDone)
            if isDone {
                applyCompletedListText(storage, lineRange: lineRange, contentStart: list.contentStart)
            }
        }
    }

    static func headingMatch(in line: String) -> (level: Int, markerRange: NSRange)? {
        guard let heading = MarkdownBlockSupport.headingLineInfo(in: line) else { return nil }
        return (heading.level, heading.markerRange)
    }

    static func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 24
        case 3: return 21
        case 4: return 18
        case 5: return 16
        default: return 15
        }
    }

    static func quoteMatch(in line: String) -> iOSMarkdownQuoteMatch? {
        guard let quote = MarkdownQuoteSupport.lineInfo(in: line) else { return nil }
        return iOSMarkdownQuoteMatch(prefixRange: quote.prefixRange, depth: quote.depth)
    }

    static func listMatch(in line: String) -> iOSMarkdownListMatch? {
        guard let info = MarkdownListSupport.lineInfo(in: line) else { return nil }
        let kind: iOSMarkdownListMatch.Kind
        switch info.kind {
        // Which spelling a checklist uses comes from `checklistSyntax`, not from testing `marker`
        // against a `["○", "●", "✓"]` literal — the same read macOS's `applyListLine` does. The
        // literal happened to agree, but it agreed by listing the legacy glyphs a second time.
        case .todo:
            kind = info.checklistSyntax == .legacy ? .legacyChecklist(isDone: false) : .checkbox(isDone: false)
        case .done:
            kind = info.checklistSyntax == .legacy ? .legacyChecklist(isDone: true) : .checkbox(isDone: true)
        case .ordered:
            kind = .ordered(marker: info.marker)
        case .bullet, .dash, .plus:
            kind = .bullet(marker: info.marker)
        }

        return iOSMarkdownListMatch(
            kind: kind,
            markerRange: info.markerRange,
            contentStart: info.contentStart,
            visualLevel: info.visualLevel,
            markerWidth: info.markerWidth
        )
    }

    private static func listParagraphStyle(
        for level: Int,
        markerWidth: Int,
        indentsFirstLineToContent: Bool = false
    ) -> NSParagraphStyle {
        // Shared with `MarkdownStylist` on macOS via `MarkdownListIndentMetrics` (Shared/). The
        // four constants used to be re-declared here, so list indentation could drift on one
        // platform only — invisible in a diff and nearly invisible on screen.
        let markerIndent = MarkdownListIndentMetrics.markerIndent(level: level)
        let contentIndent = MarkdownListIndentMetrics.contentIndent(level: level, markerWidth: markerWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = indentsFirstLineToContent ? contentIndent : markerIndent
        paragraph.headIndent = contentIndent
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 2
        return paragraph
    }

    static func isDivider(_ line: String) -> Bool {
        MarkdownBlockSupport.isDividerLine(line)
    }
}

struct iOSMarkdownQuoteMatch {
    let prefixRange: NSRange
    let depth: Int
}

struct iOSMarkdownListMatch {
    let kind: Kind
    let markerRange: NSRange
    let contentStart: Int
    let visualLevel: Int
    let markerWidth: Int

    enum Kind {
        case ordered(marker: String)
        case bullet(marker: String)
        case checkbox(isDone: Bool)
        case legacyChecklist(isDone: Bool)

        /// Whether the marker is painted by `iOSMarkdownCheckboxLayoutInfo` rather than being a
        /// glyph the text itself still shows. `legacyChecklist` is the second kind: its `○`/`✓` is
        /// real text, styled in place, so it needs the ordinary list indent.
        var isDrawnCheckbox: Bool {
            if case .checkbox = self { return true }
            return false
        }
    }
}
#endif
