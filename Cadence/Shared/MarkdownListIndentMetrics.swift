import CoreGraphics
import CoreText
import Foundation

/// The single definition of markdown list indentation.
///
/// Both markdown editors lay list paragraphs out with the same two numbers — where the marker
/// starts, and where the content (and every wrapped line) starts — and until T-130 each spelled
/// the arithmetic itself: `MarkdownStylist.listMarkerIndent`/`listContentIndent` in
/// `macOS/Editor/MarkdownEditorSupport.swift` and `iOSMarkdownStyler.listParagraphStyle` in
/// `iOS/iOSMarkdownStylingSupport.swift`. Two copies of a layout constant drift silently: the
/// symptom is list indentation that differs by a few points on one platform only, which no
/// compiler, test or diff reader flags.
///
/// This lives in `Shared/` rather than beside either editor for two reasons. It is used by
/// *both* platforms, so `macOS/Editor/` (where the AppKit-typed rect math of
/// `MarkdownEditorDecorationGeometry` correctly stays) would put it out of iOS's reach, and
/// `iOS/` is invisible to the macOS-built test target. It is pure `CGFloat` arithmetic with no
/// AppKit or UIKit in it, so `Shared/` costs nothing and `CadenceTests` can pin it.
nonisolated enum MarkdownListIndentMetrics {
    /// Horizontal step added per nesting level.
    static let levelUnit: CGFloat = 12

    /// Gap between the text container's leading edge and the marker itself.
    static let markerInset: CGFloat = 8

    /// Approximate rendered width of one marker character, used to reserve room for markers of
    /// different lengths (`-` vs `10.`) without measuring the glyphs.
    static let markerCharacterWidth: CGFloat = 5.5

    /// Gap between the end of the marker and the start of the content.
    static let contentGap: CGFloat = 8

    /// Where a list line's marker starts — the `firstLineHeadIndent` of a normal list paragraph.
    static func markerIndent(level: Int) -> CGFloat {
        CGFloat(level) * levelUnit + markerInset
    }

    /// Where a GitHub checklist line's content starts — both indents of a `- [ ] ` paragraph, whose
    /// whole prefix is hidden and whose box is drawn back into the gutter this leaves.
    ///
    /// This is an ESTIMATE of a marker's width (5.5pt a character plus a gap), which is fine where
    /// the marker is not text at all. It is wrong as the wrap column of a line whose marker IS
    /// visible text: [[T-12263]] measured a legacy `○ ` checklist wrapping 6pt left of its own
    /// first line on iOS (5pt on macOS), and bullets and numbers missing by a few points the other
    /// way. Those lines hang with `hangingIndent(firstLineHeadIndent:prefix:)` instead.
    static func contentIndent(level: Int, markerWidth: Int) -> CGFloat {
        markerIndent(level: level) + CGFloat(markerWidth) * markerCharacterWidth + contentGap
    }

    /// The `headIndent` of a list line whose marker is visible text — bullet, number, or legacy
    /// `○`/`✓` checklist — so that its wrapped lines start exactly where its first line's text does.
    ///
    /// `prefix` is the line's source from its first character up to the start of its content, AS
    /// STYLED: the marker's font and kern and any leading indentation. Its typeset width is what
    /// pushes the first line's text across from `firstLineHeadIndent`, so adding it back is the
    /// first line's text column by construction — at any Dynamic Type size and for any marker,
    /// rather than for the marker sizes the old per-character estimate happened to fit.
    ///
    /// CoreText rather than UIKit/AppKit measuring, so this stays platform-free in `Shared/`: both
    /// `UIFont` and `NSFont` are toll-free bridged to `CTFont`, and `.font`/`.kern` are CoreText's
    /// own attribute names. Pinned against real TextKit layout on both editors by
    /// `MarkdownListHangingIndentTests`.
    static func hangingIndent(firstLineHeadIndent: CGFloat, prefix: NSAttributedString) -> CGFloat {
        guard prefix.length > 0 else { return firstLineHeadIndent }
        let line = CTLineCreateWithAttributedString(prefix as CFAttributedString)
        return firstLineHeadIndent + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
