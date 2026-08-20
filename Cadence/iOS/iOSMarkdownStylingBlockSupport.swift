#if os(iOS)
import SwiftUI
import UIKit

/// **Block-level styling: fenced code, tables, dividers, images and task-embed cards.**
///
/// Each pass swaps a run of source for one pre-rendered canvas (`drawCanvas`) and collapses the
/// lines the canvas replaced (`collapseLine`), with two exceptions that stay as source: a block the
/// caret is currently inside (`MarkdownStyleRanges.isRevealed`), and a table whose header row parses
/// to nothing.
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

    static func applyLiveTableBlocks(
        _ storage: NSMutableAttributedString,
        lines: [String],
        lineRecords: [MarkdownSourceLine],
        tableRows: [Int: MarkdownTableRowStyle],
        contentWidth: CGFloat,
        revealedBlockRange: NSRange?
    ) {
        guard !tableRows.isEmpty else { return }
        var cursor = 0
        while cursor < lines.count {
            // Grouping the table's lines is `MarkdownTableParser.tableBlock`'s job — the same walk
            // `MarkdownPreviewParser` uses, so the canvas and the preview cannot drift apart on
            // where a table ends.
            guard let block = MarkdownTableParser.tableBlock(startingAt: cursor, lines: lines, tableRows: tableRows) else {
                cursor += 1
                continue
            }
            let nextIndex = block.nextIndex

            guard let firstRecord = lineRecords.first(where: { $0.index == cursor }),
                  firstRecord.range.length > 0,
                  !block.headers.isEmpty else {
                cursor = max(nextIndex, cursor + 1)
                continue
            }

            // Same reveal rule as a fenced code block: caret inside the table, show its pipes.
            let lastRecord = lineRecords.first { $0.index == block.lineIndexes.last }
            let tableRange = NSRange(
                location: firstRecord.range.location,
                length: NSMaxRange(lastRecord?.range ?? firstRecord.range) - firstRecord.range.location
            )
            if MarkdownStyleRanges.isRevealed(tableRange, by: revealedBlockRange) {
                cursor = max(nextIndex, cursor + 1)
                continue
            }

            let table = iOSMarkdownLiveTableLayoutInfo(
                headers: block.headers,
                rows: block.rows,
                alignments: block.alignments
            )
            applyTableBlock(storage, lineRange: firstRecord.range, table: table, contentWidth: contentWidth)

            for lineIndex in block.lineIndexes.dropFirst() {
                guard let record = lineRecords.first(where: { $0.index == lineIndex }) else { continue }
                collapseLine(storage, lineRange: record.range)
            }

            cursor = max(nextIndex, cursor + 1)
        }
    }

    private static func applyTableBlock(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        table: iOSMarkdownLiveTableLayoutInfo,
        contentWidth: CGFloat
    ) {
        guard lineRange.length > 0 else { return }

        let canvas = table.renderedBlock(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = canvas.size.height + 14
        paragraph.maximumLineHeight = canvas.size.height + 14
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 6

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        drawCanvas(storage, canvas, over: lineRange, isBlock: true, yOffset: 0)
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
