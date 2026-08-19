import CoreGraphics

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

    /// Where a list line's content starts — the `headIndent` of every list paragraph, and also the
    /// `firstLineHeadIndent` of a checklist line, whose marker is hidden and drawn back into the
    /// gutter this leaves.
    static func contentIndent(level: Int, markerWidth: Int) -> CGFloat {
        markerIndent(level: level) + CGFloat(markerWidth) * markerCharacterWidth + contentGap
    }
}
