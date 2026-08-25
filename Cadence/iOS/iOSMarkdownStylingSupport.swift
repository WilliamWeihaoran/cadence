#if os(iOS)
import SwiftUI
import UIKit

enum iOSMarkdownStyler {
    static var baseFont: UIFont { .preferredFont(forTextStyle: .body) }
    static var monoFont: UIFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }

    static var baseTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: UIColor(Theme.text),
            .paragraphStyle: baseParagraphStyle
        ]
    }

    private static var baseParagraphStyle: NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 5
        return paragraph
    }

    static func attributedString(
        for markdown: String,
        revealedBlockRange: NSRange? = nil,
        imageAssets: [MarkdownImageAsset] = [],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 560
    ) -> NSAttributedString {
        let storage = NSMutableAttributedString(string: markdown)
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            return NSAttributedString(string: "", attributes: baseTypingAttributes)
        }

        storage.setAttributes(baseTypingAttributes, range: fullRange)
        let renderAssets = Dictionary(uniqueKeysWithValues: imageAssets.compactMap { asset in
            MarkdownImageAssetService.renderAsset(for: asset.id, in: imageAssets).map { (asset.id, $0) }
        })

        let lines = MarkdownSourceLines.texts(in: markdown)
        let lineRecords = MarkdownSourceLines.lines(in: markdown)
        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        let codeBlocks = MarkdownBlockSupport.fencedCodeBlocks(in: markdown)
        let codeLineIndexes = Set(codeBlocks.flatMap { Array($0.lineIndexes) })
        let inlineExclusionRanges = MarkdownStyleRanges.inlineStyleExclusionRanges(
            lineRecords: lineRecords,
            tableRows: tableRows,
            codeBlocks: codeBlocks
        )
        for lineRecord in lineRecords {
            styleLine(
                storage,
                line: lineRecord.text,
                lineIndex: lineRecord.index,
                range: lineRecord.range,
                tableRows: tableRows,
                codeLineIndexes: codeLineIndexes,
                imageAssets: renderAssets,
                taskEmbeds: taskEmbeds,
                contentWidth: contentWidth
            )
        }

        applyLiveCodeBlocks(
            storage,
            codeBlocks: codeBlocks,
            lineRecords: lineRecords,
            contentWidth: contentWidth,
            revealedBlockRange: revealedBlockRange
        )
        applyLiveTableBlocks(
            storage,
            lines: lines,
            lineRecords: lineRecords,
            tableRows: tableRows,
            contentWidth: contentWidth,
            revealedBlockRange: revealedBlockRange
        )

        styleInline(
            storage,
            markdown: markdown,
            excludedRanges: inlineExclusionRanges
        )
        // Last, so no earlier pass can style the block back into view — the same ordering
        // macOS's styler uses, and for the same reason.
        applyFrontmatter(storage, markdown: markdown)
        return storage
    }

    /// Renders a note's YAML frontmatter at zero height, as macOS's editor already does.
    ///
    /// The block is kept in `note.content` for portability, but nothing in Cadence reads
    /// `title`/`status` back and tags round-trip through the note header's `Tag` chips, so showing
    /// it in the body is noise. iOS was the only surface still showing it — a note tagged on the
    /// Mac arrived here with three lines of raw YAML above its first heading.
    ///
    /// Two details this needs that an inline marker does not:
    ///
    /// - The `---` fences are also this editor's divider syntax, so `applyDividerBlock` has already
    ///   hung a rule canvas on each of them. `hide` only shrinks glyphs; the layout manager paints
    ///   a `cadenceMarkdownBlockCanvas` regardless, so the attribute has to come off or the block
    ///   leaves two rules behind — drawn against the *collapsed* line boxes, which puts them on top
    ///   of the note's first visible line rather than anywhere near the fences.
    ///
    ///   This removed `.attachment` until now. That was the right key when the canvases were
    ///   `NSTextAttachment`s, and it became a no-op the moment `drawCanvas` replaced them
    ///   (`f1c55ea`) — nothing sets `.attachment` any more. Nobody noticed because before that
    ///   commit the canvases did not draw at all, so a stale removal and a working one looked
    ///   identical.
    /// - `hide` leaves each newline opening a line box, so the collapsed paragraph style is what
    ///   actually reclaims the vertical space.
    ///
    /// Tagging the run with `cadenceMarkdownFrontmatter` is what makes the caret behave: the
    /// editor already routes selection through `MarkdownHiddenRangeSupport.snappedCaretLocation`,
    /// which pushes the caret past a frontmatter *block* unconditionally rather than treating its
    /// leading edge as a resting place. That code path existed on iOS and simply had nothing to
    /// find.
    ///
    /// Unconditional now. It used to run only in live mode, because the raw `Edit` mode showed the
    /// file as written and left its caret un-snapped, so hiding a block there would have stranded the
    /// caret inside text it could not see. Live is the only mode, the caret is always snapped, and
    /// frontmatter is therefore hidden on every surface that shows a note.
    private static func applyFrontmatter(_ storage: NSMutableAttributedString, markdown: String) {
        guard let parsed = MarkdownMetadataParser.hiddenFrontmatterRange(in: markdown) else { return }
        let range = NSIntersectionRange(parsed, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }

        storage.removeAttribute(.cadenceMarkdownBlockCanvas, range: range)
        hide(storage, range)
        storage.addAttribute(.cadenceMarkdownFrontmatter, value: true, range: range)

        let collapsed = NSMutableParagraphStyle()
        collapsed.lineSpacing = 0
        collapsed.paragraphSpacing = 0
        collapsed.paragraphSpacingBefore = 0
        collapsed.minimumLineHeight = 0.1
        collapsed.maximumLineHeight = 0.1
        storage.addAttribute(.paragraphStyle, value: collapsed, range: range)
    }

    private static func styleLine(
        _ storage: NSMutableAttributedString,
        line: String,
        lineIndex: Int,
        range: NSRange,
        tableRows: [Int: MarkdownTableRowStyle],
        codeLineIndexes: Set<Int>,
        imageAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo],
        contentWidth: CGFloat
    ) {
        guard range.length > 0 else { return }

        if codeLineIndexes.contains(lineIndex) {
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.muted),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.42)
            ], range: range)
            return
        }

        if let image = standaloneImage(in: line, imageAssets: imageAssets) {
            applyImageBlock(storage, lineRange: range, image: image, contentWidth: contentWidth)
            return
        }

        if let task = standaloneTaskEmbed(in: line, taskEmbeds: taskEmbeds) {
            applyTaskEmbedBlock(storage, lineRange: range, task: task, contentWidth: contentWidth)
            return
        }

        if let heading = headingMatch(in: line) {
            let size = MarkdownHeadingRamp.size(level: heading.level, surface: .mobile, bodyPointSize: baseFont.pointSize)
            storage.addAttributes([
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor(Theme.text)
            ], range: range)
            if MarkdownStyleRanges.hasVisibleHeadingContent(in: line, markerRange: heading.markerRange) {
                hide(storage, heading.markerRange.shifted(by: range.location))
            } else {
                storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: heading.markerRange.shifted(by: range.location))
            }
            return
        }

        if tableRows[lineIndex] != nil {
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.muted),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.24)
            ], range: range)
            return
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if isDivider(trimmed) {
            applyDividerBlock(storage, lineRange: range, contentWidth: contentWidth)
            return
        }

        if let quote = quoteMatch(in: line) {
            applyQuoteLine(
                storage,
                lineRange: range,
                lineStart: range.location,
                quote: quote
            )
            return
        }

        if let list = listMatch(in: line) {
            applyListLine(
                storage,
                lineRange: range,
                lineStart: range.location,
                list: list
            )
        }
    }

    static func font(at location: Int, in storage: NSAttributedString) -> UIFont {
        guard storage.length > 0 else { return baseFont }
        let clampedLocation = min(max(0, location), storage.length - 1)
        return storage.attribute(.font, at: clampedLocation, effectiveRange: nil) as? UIFont ?? baseFont
    }

    static func boldFont(at location: Int, in storage: NSAttributedString) -> UIFont {
        let current = font(at: location, in: storage)
        return UIFont.systemFont(ofSize: current.pointSize, weight: .bold)
    }

    static func italicFont(from font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return UIFont.italicSystemFont(ofSize: font.pointSize)
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// Hides a run and hangs a pre-rendered canvas over it for the layout manager to paint.
    ///
    /// This replaced seven near-identical blocks that each built an `NSTextAttachment`, set its
    /// `bounds`, hung it on the run's **first character**, and hid only the characters after it.
    /// None of them drew: TextKit makes an attachment glyph only where the text holds `U+FFFC`, so
    /// setting `.attachment` on a `|`, a backtick or a `-` painted nothing and left that character
    /// visible. See `iOSMarkdownBlockCanvas` for the full account and why inserting real attachment
    /// characters was not the way out.
    ///
    /// The whole run is hidden now, including its first character — there is no longer anything the
    /// image needs to sit on, and that stray glyph was the only part of a table you could see.
    static func drawCanvas(
        _ storage: NSMutableAttributedString,
        _ canvas: UIImage,
        over range: NSRange,
        isBlock: Bool,
        yOffset: CGFloat,
        leadingInset: CGFloat = 0
    ) {
        guard range.length > 0 else { return }
        hide(storage, range)
        storage.addAttribute(
            .cadenceMarkdownBlockCanvas,
            value: iOSMarkdownBlockCanvas(
                image: canvas,
                isBlock: isBlock,
                yOffset: yOffset,
                leadingInset: leadingInset
            ),
            range: NSRange(location: range.location, length: 1)
        )
    }

    static func hide(_ storage: NSMutableAttributedString, _ range: NSRange) {
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard safeRange.length > 0 else { return }
        storage.addAttributes([
            .cadenceMarkdownHidden: true,
            .font: UIFont.systemFont(ofSize: 0.1),
            .foregroundColor: UIColor.clear,
            .kern: -0.08
        ], range: safeRange)
    }
}
#endif
