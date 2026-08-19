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
        let inlineExclusionRanges = inlineStyleExclusionRanges(
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
            let size = headingSize(for: heading.level)
            storage.addAttributes([
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor(Theme.text)
            ], range: range)
            if hasVisibleHeadingContent(line, markerRange: heading.markerRange) {
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

    private static func applyQuoteLine(
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

    private static func applyListLine(
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

    private static func applyLiveCodeBlocks(
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
            if let revealedBlockRange,
               let blockRange = combinedLineRange(for: block.lineIndexes, recordsByIndex: recordsByIndex),
               NSIntersectionRange(blockRange, revealedBlockRange).length > 0 {
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

    private static func applyLiveTableBlocks(
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
            guard let style = tableRows[cursor], style.isHeader else {
                cursor += 1
                continue
            }

            let headers = MarkdownBlockSupport.tableCells(in: lines[cursor], expectedCount: style.columnCount)
            var rows: [[String]] = []
            var tableLineIndexes: [Int] = [cursor]
            var nextIndex = cursor + 1
            while nextIndex < lines.count, let rowStyle = tableRows[nextIndex] {
                tableLineIndexes.append(nextIndex)
                if !rowStyle.isDelimiter {
                    rows.append(MarkdownBlockSupport.tableCells(in: lines[nextIndex], expectedCount: style.columnCount))
                }
                nextIndex += 1
            }

            guard let firstRecord = lineRecords.first(where: { $0.index == cursor }),
                  firstRecord.range.length > 0,
                  !headers.isEmpty else {
                cursor = max(nextIndex, cursor + 1)
                continue
            }

            // Same reveal rule as a fenced code block: caret inside the table, show its pipes.
            let lastRecord = lineRecords.first { $0.index == tableLineIndexes.last }
            let tableRange = NSRange(
                location: firstRecord.range.location,
                length: NSMaxRange(lastRecord?.range ?? firstRecord.range) - firstRecord.range.location
            )
            if let revealedBlockRange,
               NSIntersectionRange(tableRange, revealedBlockRange).length > 0 {
                cursor = max(nextIndex, cursor + 1)
                continue
            }

            let table = iOSMarkdownLiveTableLayoutInfo(headers: headers, rows: rows, alignments: style.alignments)
            applyTableBlock(storage, lineRange: firstRecord.range, table: table, contentWidth: contentWidth)

            for lineIndex in tableLineIndexes.dropFirst() {
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

    private static func applyDividerBlock(
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

    private static func standaloneImage(
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

    private static func applyImageBlock(
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
    }

    private static func standaloneTaskEmbed(
        in line: String,
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    ) -> MarkdownTaskEmbedRenderInfo? {
        guard let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: line) else {
            return nil
        }
        return taskEmbeds[reference.id] ?? .missing(reference: reference)
    }

    private static func applyTaskEmbedBlock(
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

    private static func inlineStyleExclusionRanges(
        lineRecords: [MarkdownSourceLine],
        tableRows: [Int: MarkdownTableRowStyle],
        codeBlocks: [MarkdownFencedCodeBlock]
    ) -> [NSRange] {
        let recordsByIndex = Dictionary(uniqueKeysWithValues: lineRecords.map { ($0.index, $0) })
        var ranges: [NSRange] = codeBlocks.compactMap { block in
            combinedLineRange(for: block.lineIndexes, recordsByIndex: recordsByIndex)
        }

        ranges += tableRows.keys.compactMap { recordsByIndex[$0]?.range }

        for record in lineRecords {
            let trimmed = record.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if MarkdownBlockSupport.standaloneImageReference(in: record.text) != nil ||
                MarkdownTaskEmbedParser.standaloneTaskReference(in: record.text) != nil ||
                MarkdownBlockSupport.isDividerLine(trimmed) {
                ranges.append(record.range)
            }
        }

        return ranges.filter { $0.length > 0 }
    }

    private static func combinedLineRange(
        for lineIndexes: ClosedRange<Int>,
        recordsByIndex: [Int: MarkdownSourceLine]
    ) -> NSRange? {
        let records = lineIndexes.compactMap { recordsByIndex[$0] }
        guard let first = records.first, let last = records.last else { return nil }
        return NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
    }

    private static func styleInline(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange]
    ) {
        let inlineCodeRanges = MarkdownInlineSpanSupport.codeRanges(in: markdown)

        // Which runs get styled, in what order, and which markers disappear is
        // `MarkdownInlineSpanSupport`'s decision — a platform-free one the macOS test target can
        // actually run. This method is only the drawing half of it.
        for span in MarkdownInlineSpanSupport.spans(in: markdown, excluding: excludedRanges) {
            apply(span, to: storage)
        }

        styleImageLink(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleMarkdownLinks(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleWikiReferences(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleHashtags(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
    }

    private static func apply(_ span: MarkdownInlineSpan, to storage: NSMutableAttributedString) {
        let content = span.contentRange
        switch span.kind {
        case .boldItalic:
            storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)

        case .bold:
            storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)

        case .italic:
            storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)

        case .strikethrough:
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: content)

        case .code:
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.65),
                .cadenceMarkdownInlineCode: true
            ], range: content)

        case .highlight:
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.amber).withAlphaComponent(0.18)
            ], range: content)
        }

        for markerRange in span.markerRanges {
            hide(storage, markerRange)
        }
    }

    private static func styleImageLink(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        applyRegex(#"!\[("# + MarkdownImageAssetService.altTextPattern + #")\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 3 else { return }
            let label = match.range(at: 1)
            let id = match.range(at: 2)
            let full = match.range(at: 0)
            guard full.location != NSNotFound, id.location != NSNotFound else { return }

            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .backgroundColor: UIColor(Theme.blue).withAlphaComponent(0.12),
                .font: UIFont.systemFont(ofSize: font(at: full.location, in: storage).pointSize, weight: .semibold)
            ], range: label.location == NSNotFound || label.length == 0 ? full : label)

            if label.location != NSNotFound, label.length > 0 {
                hide(storage, NSRange(location: full.location, length: max(0, label.location - full.location)))
                hide(storage, NSRange(location: label.location + label.length, length: max(0, id.location - (label.location + label.length))))
                hide(storage, NSRange(location: id.location, length: max(0, NSMaxRange(full) - id.location)))
            } else {
                storage.addAttributes([
                    .foregroundColor: UIColor(Theme.dim),
                    .font: monoFont
                ], range: id)
            }
        }
    }

    private static func styleMarkdownLinks(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for link in MarkdownLinkSupport.linkRanges(in: markdown) {
            guard shouldStyleInline(link.fullRange, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }
            let label = link.labelRange
            let url = link.urlRange
            let full = link.fullRange
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: label)
            if let linkURL = link.url {
                storage.addAttribute(.link, value: linkURL, range: label)
            }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .font: monoFont
            ], range: url)
            hide(storage, NSRange(location: full.location, length: 1))
            hide(storage, NSRange(location: label.location + label.length, length: max(0, url.location - (label.location + label.length))))
            hide(storage, NSRange(location: url.location + url.length, length: max(0, NSMaxRange(full) - (url.location + url.length))))
        }
    }

    private static func styleWikiReferences(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for referenceRange in MarkdownReferenceDisplaySupport.referenceRanges(in: markdown) {
            let full = referenceRange.fullRange
            guard shouldStyleInline(full, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }
            guard full.location != NSNotFound, full.length >= 4 else { continue }
            if storage.attribute(.cadenceMarkdownTaskEmbed, at: full.location, effectiveRange: nil) is MarkdownTaskEmbedLayoutInfo {
                continue
            }

            let reference = referenceRange.display
            let styledRange = referenceRange.displayRange
            let labelLocation = full.location + 2
            let referenceColor = reference.kind == .task ? UIColor(Theme.greenLight) : UIColor(Theme.blueLight)
            let referenceBackground = reference.kind == .task
                ? UIColor(Theme.green).withAlphaComponent(0.10)
                : UIColor(Theme.blue).withAlphaComponent(0.10)
            storage.addAttributes([
                .foregroundColor: referenceColor,
                .backgroundColor: referenceBackground,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: styledRange)
            if let referenceURL = MarkdownReferenceDisplaySupport.url(for: reference.target) {
                storage.addAttribute(.link, value: referenceURL, range: styledRange)
            }
            if reference.kind == .task {
                storage.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: font(at: styledRange.location, in: storage).pointSize, weight: .semibold),
                    range: styledRange
                )
            }
            hide(storage, NSRange(location: full.location, length: 2))
            hide(storage, NSRange(location: NSMaxRange(full) - 2, length: 2))
            if reference.hiddenPrefixUTF16Length > 0 {
                hide(storage, NSRange(location: labelLocation, length: reference.hiddenPrefixUTF16Length))
            }
        }
    }

    private static func styleHashtags(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        applyRegex(#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#, in: markdown) { match in
            guard shouldStyleInline(match.range, excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.greenLight),
                .backgroundColor: UIColor(Theme.green).withAlphaComponent(0.10)
            ], range: match.range)
        }
    }

    private static func shouldStyleInline(
        _ range: NSRange,
        excluding excludedRanges: [NSRange],
        protecting protectedRanges: [NSRange] = []
    ) -> Bool {
        MarkdownInlineSpanSupport.shouldStyle(range, excluding: excludedRanges, protecting: protectedRanges)
    }

    private static func applyRegex(
        _ pattern: String,
        in text: String,
        handler: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            handler(match)
        }
    }

    private static func headingMatch(in line: String) -> (level: Int, markerRange: NSRange)? {
        guard let heading = MarkdownBlockSupport.headingLineInfo(in: line) else { return nil }
        return (heading.level, heading.markerRange)
    }

    private static func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 24
        case 3: return 21
        case 4: return 18
        case 5: return 16
        default: return 15
        }
    }

    private static func hasVisibleHeadingContent(_ line: String, markerRange: NSRange) -> Bool {
        let nsLine = line as NSString
        let contentStart = min(nsLine.length, markerRange.location + markerRange.length)
        let contentLength = max(0, nsLine.length - contentStart)
        guard contentLength > 0 else { return false }
        return !nsLine.substring(with: NSRange(location: contentStart, length: contentLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func quoteMatch(in line: String) -> iOSMarkdownQuoteMatch? {
        guard let quote = MarkdownQuoteSupport.lineInfo(in: line) else { return nil }
        return iOSMarkdownQuoteMatch(prefixRange: quote.prefixRange, depth: quote.depth)
    }

    private static func listMatch(in line: String) -> iOSMarkdownListMatch? {
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

    private static func isDivider(_ line: String) -> Bool {
        MarkdownBlockSupport.isDividerLine(line)
    }

    private static func font(at location: Int, in storage: NSAttributedString) -> UIFont {
        guard storage.length > 0 else { return baseFont }
        let clampedLocation = min(max(0, location), storage.length - 1)
        return storage.attribute(.font, at: clampedLocation, effectiveRange: nil) as? UIFont ?? baseFont
    }

    private static func boldFont(at location: Int, in storage: NSAttributedString) -> UIFont {
        let current = font(at: location, in: storage)
        return UIFont.systemFont(ofSize: current.pointSize, weight: .bold)
    }

    private static func italicFont(from font: UIFont) -> UIFont {
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
    private static func drawCanvas(
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

    private static func hide(_ storage: NSMutableAttributedString, _ range: NSRange) {
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

struct iOSMarkdownStyleSignature: Equatable {
    let theme: String
    /// The code fence or table the caret is currently inside, which the styler leaves un-rendered
    /// so its source can be edited. Part of the signature because moving the caret in or out of one
    /// changes the styling with no text edit to trigger a refresh.
    let revealedBlockRange: NSRange?
    let contentWidthBucket: Int
    let imageAssetRevision: String
    let taskEmbedRevision: String

    static func current(
        revealedBlockRange: NSRange?,
        imageAssets: [MarkdownImageAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 0
    ) -> iOSMarkdownStyleSignature {
        iOSMarkdownStyleSignature(
            theme: "fixed",
            revealedBlockRange: revealedBlockRange,
            contentWidthBucket: Int(max(0, contentWidth).rounded()),
            imageAssetRevision: imageAssets
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.displayWidth)" }
                .joined(separator: "|"),
            taskEmbedRevision: taskEmbeds.values
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map {
                    [
                        $0.id.uuidString,
                        $0.title,
                        $0.statusRaw,
                        $0.priorityRaw,
                        $0.dueDate,
                        $0.scheduledDate,
                        "\($0.scheduledStartMin)",
                        "\($0.estimatedMinutes)",
                        "\($0.actualMinutes)",
                        "\($0.completedSubtaskCount)/\($0.subtaskTotalCount)",
                        "\($0.isDone)",
                        "\($0.isMissing)"
                    ].joined(separator: ":")
                }
                .joined(separator: "|")
        )
    }
}

private struct iOSMarkdownQuoteMatch {
    let prefixRange: NSRange
    let depth: Int
}

private struct iOSMarkdownListMatch {
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

extension UITextView {
    func textRange(from nsRange: NSRange) -> UITextRange? {
        let start = position(from: beginningOfDocument, offset: nsRange.location) ?? beginningOfDocument
        let end = position(from: start, offset: nsRange.length) ?? start
        return textRange(from: start, to: end)
    }
}

private extension NSRange {
    func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
#endif
