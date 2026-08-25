#if os(iOS)
import SwiftUI
import UIKit

/// **Block-level styling: fenced code, tables, dividers, images and task-embed cards.**
///
/// Each pass swaps a run of source for one pre-rendered canvas (`drawCanvas`) and collapses the
/// lines the canvas replaced (`collapseLine`), with two exceptions that stay as source: a **fenced
/// code block** the caret is currently inside (`MarkdownStyleRanges.isRevealed`), and a table whose
/// source the reader has explicitly asked for. A table is the one block that does **not** reveal by
/// caret position — see `applyLiveTableBlocks` — and it is the one block that does not go through
/// `drawCanvas` either, because it draws itself in vectors.
///
/// Where a block *starts and ends* is not decided here — `MarkdownTableParser.tableBlock` groups a
/// table's lines and `MarkdownBlockSupport.fencedCodeBlocks` groups a fence's, both in `Services/`
/// where they are covered. This file only paints.
extension iOSMarkdownStyler {
    static func applyLiveCodeBlocks(
        _ storage: NSMutableAttributedString,
        codeBlocks: [MarkdownFencedCodeBlock],
        lineRecords: [MarkdownSourceLine],
        contentWidth: CGFloat,
        revealedBlockRange: NSRange?
    ) {
        guard !codeBlocks.isEmpty else { return }
        let recordsByIndex = Dictionary(uniqueKeysWithValues: lineRecords.map { ($0.index, $0) })

        for block in codeBlocks {
            guard let firstRecord = recordsByIndex[block.startLineIndex],
                  firstRecord.range.length > 0 else {
                continue
            }

            // The caret is inside this fence, so show its source instead of the canvas. `styleLine`
            // has already mono-styled every line of the block, so skipping is all it takes.
            if let blockRange = MarkdownStyleRanges.combinedLineRange(for: block.lineIndexes, recordsByIndex: recordsByIndex),
               MarkdownStyleRanges.isRevealed(blockRange, by: revealedBlockRange) {
                continue
            }

            applyCodeBlock(
                storage,
                lineRange: firstRecord.range,
                block: iOSMarkdownLiveCodeBlockLayoutInfo(
                    language: block.language,
                    text: block.content,
                    isClosed: block.isClosed
                ),
                contentWidth: contentWidth
            )

            for lineIndex in block.lineIndexes where lineIndex != block.startLineIndex {
                guard let record = recordsByIndex[lineIndex] else { continue }
                collapseLine(storage, lineRange: record.range)
            }
        }
    }

    private static func applyCodeBlock(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        block: iOSMarkdownLiveCodeBlockLayoutInfo,
        contentWidth: CGFloat
    ) {
        guard lineRange.length > 0 else { return }

        let canvas = block.renderedBlock(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = canvas.size.height + 14
        paragraph.maximumLineHeight = canvas.size.height + 14
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 6

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        drawCanvas(storage, canvas, over: lineRange, isBlock: true, yOffset: 0)
    }

    /// Renders every table as one editable grid, and hides the pipes it was spelled with.
    ///
    /// **The source stays in the storage, untouched — only its glyphs are collapsed.** That single
    /// choice is what lets a hosted cell field exist at all: a selection spanning the table still
    /// covers the markdown, copying it still yields pipes, and a committed cell is an ordinary
    /// text-view edit on the view's own undo stack rather than a rewrite of the whole note.
    ///
    /// **There is no caret-reveal here any more, and its absence is T-221.** A table used to
    /// un-render the moment the caret landed inside it, which meant editing a table on this
    /// platform meant typing pipes — the complaint the ticket opened with. The raw source is now
    /// reachable only by the explicit **Show Table Source** command, whose anchors arrive in
    /// `tableSourceAnchors`; a table named there falls back to the banded per-row styling
    /// `styleLine` has always drawn. Fenced code blocks are unchanged and still reveal by caret.
    static func applyLiveTableBlocks(
        _ storage: NSMutableAttributedString,
        markdown: String,
        contentWidth: CGFloat,
        tableSourceAnchors: Set<Int>
    ) {
        let documentRange = NSRange(location: 0, length: storage.length)
        guard documentRange.length > 0 else { return }

        // `MarkdownTableEditor.grids` walks `MarkdownTableParser`, which is the same walk
        // `MarkdownPreviewParser` and the macOS grid use — so where a table starts and stops is
        // still decided in exactly one place.
        for grid in MarkdownTableEditor.grids(in: markdown) {
            guard grid.columnCount > 0, grid.rowCount > 0 else { continue }
            guard !tableSourceAnchors.contains(grid.storageRange.location) else { continue }
            let range = NSIntersectionRange(grid.storageRange, documentRange)
            guard range.length > 0 else { continue }

            // `styleLine` has already given every row of this table the banded source treatment,
            // which is the *other* spelling of the same table. The background band would otherwise
            // paint a stripe through the grid drawn over it.
            storage.removeAttribute(.backgroundColor, range: range)
            hide(storage, range)

            let collapsed = NSMutableParagraphStyle()
            collapsed.lineSpacing = 0
            collapsed.paragraphSpacing = 0
            collapsed.paragraphSpacingBefore = 0
            collapsed.minimumLineHeight = 0.1
            collapsed.maximumLineHeight = 0.1
            storage.addAttribute(.paragraphStyle, value: collapsed, range: range)

            let headerLine = NSIntersectionRange(grid.rowLineRanges[0], documentRange)
            guard headerLine.length > 0 else { continue }

            let info = iOSMarkdownTableRenderInfo.make(grid: grid, containerWidth: contentWidth)
            let reserved = MarkdownTableMetrics.reservedLineHeight(
                rowCount: grid.rowCount,
                rowHeight: iOSMarkdownTableGridMetrics.rowHeight
            )
            let canvas = NSMutableParagraphStyle()
            canvas.lineSpacing = 0
            canvas.minimumLineHeight = reserved
            canvas.maximumLineHeight = reserved
            canvas.lineBreakMode = .byClipping
            canvas.paragraphSpacingBefore = 8
            canvas.paragraphSpacing = 6
            storage.addAttribute(.paragraphStyle, value: canvas, range: headerLine)
            storage.addAttribute(
                .cadenceMarkdownTable,
                value: info,
                range: NSRange(location: headerLine.location, length: 1)
            )
        }
    }

    static func applyDividerBlock(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        contentWidth: CGFloat
    ) {
        guard lineRange.length > 0 else { return }

        let canvas = iOSMarkdownDividerLayoutInfo().renderedBlock(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = canvas.size.height + 10
        paragraph.maximumLineHeight = canvas.size.height + 10
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 6
        paragraph.paragraphSpacing = 6

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        drawCanvas(storage, canvas, over: lineRange, isBlock: true, yOffset: 0)
    }

    /// Collapses one source line of a block whose canvas is drawn on the block's *first* line.
    ///
    /// **The range has to include the line's terminating newline.** A paragraph style governs the
    /// paragraph its characters sit in, and the newline is the last character of that paragraph —
    /// so a collapse applied to the content alone leaves the `\n` carrying the base 17pt style. For
    /// a line that has content, the first character's collapsed style still wins and the mistake is
    /// invisible. For a **blank** line it is the only character there is, and the blank line stays
    /// at full height: a fenced code block with a blank line in the middle drew its canvas and then
    /// a stack of empty rows underneath it, one per blank line, which is exactly what a rendered
    /// code block is supposed to have replaced.
    private static func collapseLine(_ storage: NSMutableAttributedString, lineRange: NSRange) {
        let withTerminator = NSIntersectionRange(
            NSRange(location: lineRange.location, length: lineRange.length + 1),
            NSRange(location: 0, length: storage.length)
        )
        guard withTerminator.length > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 0.1
        paragraph.maximumLineHeight = 0.1
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        hide(storage, withTerminator)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: withTerminator)
    }

    static func standaloneImage(
        in line: String,
        imageAssets: [UUID: MarkdownImageRenderAsset]
    ) -> iOSMarkdownImageLayoutInfo? {
        guard let reference = MarkdownBlockSupport.standaloneImageReference(in: line) else { return nil }

        let asset = imageAssets[reference.id]
        return iOSMarkdownImageLayoutInfo(
            id: reference.id,
            altText: reference.altText,
            image: asset?.image,
            displayWidth: asset?.displayWidth ?? MarkdownImageAssetService.defaultDisplayWidth,
            pixelSize: asset?.pixelSize ?? CGSize(width: 640, height: 360)
        )
    }

    static func applyImageBlock(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        image: iOSMarkdownImageLayoutInfo,
        contentWidth: CGFloat
    ) {
        guard lineRange.length > 0 else { return }

        let canvas = image.renderedBlock(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = canvas.size.height + 14
        paragraph.maximumLineHeight = canvas.size.height + 14
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 6

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        drawCanvas(storage, canvas, over: lineRange, isBlock: true, yOffset: 0)
        // Marks the block so the editor's resize pan can find the image under a touch, the same way
        // `.cadenceMarkdownTaskEmbed` below lets it find a card. One character is enough: the hit
        // test reads the block canvas from the same location and measures against the rect the
        // canvas was painted into.
        storage.addAttribute(
            .cadenceMarkdownImage,
            value: image,
            range: NSRange(location: lineRange.location, length: 1)
        )
    }

    static func standaloneTaskEmbed(
        in line: String,
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    ) -> MarkdownTaskEmbedRenderInfo? {
        guard let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: line) else {
            return nil
        }
        return taskEmbeds[reference.id] ?? .missing(reference: reference)
    }

    static func applyTaskEmbedBlock(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        task: MarkdownTaskEmbedRenderInfo,
        contentWidth: CGFloat
    ) {
        guard lineRange.length > 0 else { return }

        let canvas = iOSMarkdownTaskEmbedLayoutInfo(task: task).renderedBlock(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = canvas.size.height + 12
        paragraph.maximumLineHeight = canvas.size.height + 12
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 7
        paragraph.paragraphSpacing = 5

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        drawCanvas(storage, canvas, over: lineRange, isBlock: true, yOffset: 0)
        storage.addAttribute(
            .cadenceMarkdownTaskEmbed,
            value: MarkdownTaskEmbedLayoutInfo(task: task),
            range: NSRange(location: lineRange.location, length: 1)
        )
    }
}
#endif
