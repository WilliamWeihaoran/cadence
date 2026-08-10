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
        hidesMarkdownMarkers: Bool = true,
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

        let lines = markdown.components(separatedBy: "\n")
        let lineRecords = lineRecords(in: lines)
        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        let codeBlocks = MarkdownBlockSupport.fencedCodeBlocks(in: markdown)
        let codeLineIndexes = Set(codeBlocks.flatMap { Array($0.lineIndexes) })
        let inlineExclusionRanges = inlineStyleExclusionRanges(
            lineRecords: lineRecords,
            tableRows: tableRows,
            codeBlocks: codeBlocks,
            hidesMarkdownMarkers: hidesMarkdownMarkers
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
                contentWidth: contentWidth,
                hidesMarkdownMarkers: hidesMarkdownMarkers
            )
        }

        if hidesMarkdownMarkers {
            applyLiveCodeBlocks(
                storage,
                codeBlocks: codeBlocks,
                lineRecords: lineRecords,
                contentWidth: contentWidth
            )
            applyLiveTableBlocks(
                storage,
                lines: lines,
                lineRecords: lineRecords,
                tableRows: tableRows,
                contentWidth: contentWidth
            )
        }

        styleInline(
            storage,
            markdown: markdown,
            hidesMarkdownMarkers: hidesMarkdownMarkers,
            excludedRanges: inlineExclusionRanges,
            rendersCodeBlockAttachments: hidesMarkdownMarkers
        )
        return storage
    }

    private static func lineRecords(in lines: [String]) -> [iOSMarkdownLineRecord] {
        var records: [iOSMarkdownLineRecord] = []
        var location = 0
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            records.append(iOSMarkdownLineRecord(index: index, text: line, range: NSRange(location: location, length: length)))
            location += length + 1
        }
        return records
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
        contentWidth: CGFloat,
        hidesMarkdownMarkers: Bool
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

        if hidesMarkdownMarkers,
           let image = standaloneImage(in: line, imageAssets: imageAssets) {
            applyImageBlock(storage, lineRange: range, image: image, contentWidth: contentWidth)
            return
        }

        if hidesMarkdownMarkers,
           let task = standaloneTaskEmbed(in: line, taskEmbeds: taskEmbeds) {
            applyTaskEmbedBlock(storage, lineRange: range, task: task, contentWidth: contentWidth)
            return
        }

        if let heading = headingMatch(in: line) {
            let size = headingSize(for: heading.level)
            storage.addAttributes([
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor(Theme.text)
            ], range: range)
            if hidesMarkdownMarkers && hasVisibleHeadingContent(line, markerRange: heading.markerRange) {
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
            if hidesMarkdownMarkers {
                applyDividerBlock(storage, lineRange: range, contentWidth: contentWidth)
                return
            }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.borderSubtle),
                .font: monoFont
            ], range: range)
            return
        }

        if let quote = quoteMatch(in: line) {
            applyQuoteLine(
                storage,
                lineRange: range,
                lineStart: range.location,
                quote: quote,
                hidesMarkdownMarkers: hidesMarkdownMarkers
            )
            return
        }

        if let list = listMatch(in: line) {
            applyListLine(
                storage,
                lineRange: range,
                lineStart: range.location,
                list: list,
                hidesMarkdownMarkers: hidesMarkdownMarkers
            )
        }
    }

    private static func applyQuoteLine(
        _ storage: NSMutableAttributedString,
        lineRange: NSRange,
        lineStart: Int,
        quote: iOSMarkdownQuoteMatch,
        hidesMarkdownMarkers: Bool
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

        let prefixRange = quote.prefixRange.shifted(by: lineStart)
        if hidesMarkdownMarkers {
            applyQuoteAttachment(storage, markerRange: prefixRange, depth: quote.depth)
        } else {
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.blue), range: prefixRange)
        }
    }

    private static func applyQuoteAttachment(
        _ storage: NSMutableAttributedString,
        markerRange: NSRange,
        depth: Int
    ) {
        guard markerRange.length > 0 else { return }
        let canvas = iOSMarkdownQuoteMarkerLayoutInfo(depth: depth).renderedMarker()
        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -3), size: canvas.size)

        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: markerRange.location, length: 1))
        if markerRange.length > 1 {
            hide(storage, NSRange(location: markerRange.location + 1, length: markerRange.length - 1))
        }
    }

    private static func applyCheckboxAttachment(
        _ storage: NSMutableAttributedString,
        markerRange: NSRange,
        isDone: Bool
    ) {
        guard markerRange.length > 0 else { return }
        let canvas = iOSMarkdownCheckboxLayoutInfo(isDone: isDone).renderedMarker()
        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -3), size: canvas.size)

        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: markerRange.location, length: 1))
        if markerRange.length > 1 {
            hide(storage, NSRange(location: markerRange.location + 1, length: markerRange.length - 1))
        }
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
        list: iOSMarkdownListMatch,
        hidesMarkdownMarkers: Bool
    ) {
        let paragraph = listParagraphStyle(for: list.visualLevel, markerWidth: list.markerWidth)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)

        let markerRange = list.markerRange.shifted(by: lineStart)
        switch list.kind {
        case let .ordered(marker):
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.text),
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .kern: 3.5
            ], range: markerRange)
            if hidesMarkdownMarkers, marker.hasSuffix(")") {
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
            if hidesMarkdownMarkers {
                applyCheckboxAttachment(storage, markerRange: markerRange, isDone: isDone)
            } else {
                storage.addAttributes([
                    .foregroundColor: isDone ? UIColor(Theme.green) : UIColor(Theme.dim),
                    .font: monoFont
                ], range: markerRange)
            }
            if isDone {
                applyCompletedListText(storage, lineRange: lineRange, contentStart: list.contentStart)
            }
        }
    }

    private static func applyLiveCodeBlocks(
        _ storage: NSMutableAttributedString,
        codeBlocks: [MarkdownFencedCodeBlock],
        lineRecords: [iOSMarkdownLineRecord],
        contentWidth: CGFloat
    ) {
        guard !codeBlocks.isEmpty else { return }
        let recordsByIndex = Dictionary(uniqueKeysWithValues: lineRecords.map { ($0.index, $0) })

        for block in codeBlocks {
            guard let firstRecord = recordsByIndex[block.startLineIndex],
                  firstRecord.range.length > 0 else {
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

        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -8), size: canvas.size)

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: lineRange.location, length: 1))
        if lineRange.length > 1 {
            hide(storage, NSRange(location: lineRange.location + 1, length: lineRange.length - 1))
        }
    }

    private static func applyLiveTableBlocks(
        _ storage: NSMutableAttributedString,
        lines: [String],
        lineRecords: [iOSMarkdownLineRecord],
        tableRows: [Int: MarkdownTableRowStyle],
        contentWidth: CGFloat
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

            let table = iOSMarkdownLiveTableLayoutInfo(headers: headers, rows: rows)
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

        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -8), size: canvas.size)

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: lineRange.location, length: 1))
        if lineRange.length > 1 {
            hide(storage, NSRange(location: lineRange.location + 1, length: lineRange.length - 1))
        }
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

        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: canvas.size)

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: lineRange.location, length: 1))
        if lineRange.length > 1 {
            hide(storage, NSRange(location: lineRange.location + 1, length: lineRange.length - 1))
        }
    }

    private static func collapseLine(_ storage: NSMutableAttributedString, lineRange: NSRange) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 0.1
        paragraph.maximumLineHeight = 0.1
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        if lineRange.length > 0 {
            hide(storage, lineRange)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        }
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

        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -8), size: canvas.size)

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: lineRange.location, length: 1))
        if lineRange.length > 1 {
            hide(storage, NSRange(location: lineRange.location + 1, length: lineRange.length - 1))
        }
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

        let attachment = NSTextAttachment()
        attachment.image = canvas
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -7), size: canvas.size)

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: lineRange.location, length: 1))
        storage.addAttribute(
            .cadenceMarkdownTaskEmbed,
            value: MarkdownTaskEmbedLayoutInfo(task: task),
            range: NSRange(location: lineRange.location, length: 1)
        )
        if lineRange.length > 1 {
            hide(storage, NSRange(location: lineRange.location + 1, length: lineRange.length - 1))
        }
    }

    private static func inlineStyleExclusionRanges(
        lineRecords: [iOSMarkdownLineRecord],
        tableRows: [Int: MarkdownTableRowStyle],
        codeBlocks: [MarkdownFencedCodeBlock],
        hidesMarkdownMarkers: Bool
    ) -> [NSRange] {
        let recordsByIndex = Dictionary(uniqueKeysWithValues: lineRecords.map { ($0.index, $0) })
        var ranges: [NSRange] = codeBlocks.compactMap { block in
            combinedLineRange(for: block.lineIndexes, recordsByIndex: recordsByIndex)
        }

        guard hidesMarkdownMarkers else {
            return ranges.filter { $0.length > 0 }
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
        recordsByIndex: [Int: iOSMarkdownLineRecord]
    ) -> NSRange? {
        let records = lineIndexes.compactMap { recordsByIndex[$0] }
        guard let first = records.first, let last = records.last else { return nil }
        return NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
    }

    private static func styleInline(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        rendersCodeBlockAttachments: Bool
    ) {
        let inlineCodeRanges = regexRanges(#"`([^`\n]+?)`"#, in: markdown)

        styleBoldItalic(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleBold(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleItalic(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleStrikethrough(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleInlineCode(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges)
        styleHighlight(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleImageLink(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleMarkdownLinks(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleWikiReferences(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleHashtags(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        if !rendersCodeBlockAttachments {
            styleFallbackCodeBlockText(storage, markdown: markdown, hidesMarkdownMarkers: hidesMarkdownMarkers)
        }
    }

    /// Handles both `***bold italic***` and `___bold italic___`.
    private static func styleBoldItalic(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for pattern in [#"\*\*\*(.+?)\*\*\*"#, #"___(.+?)___"#] {
            applyRegex(pattern, in: markdown) { match in
                guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
                guard match.numberOfRanges >= 2 else { return }
                let content = match.range(at: 1)
                storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)
                hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
            }
        }
    }

    /// Handles both `**bold**` and `__bold__`.
    private static func styleBold(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for pattern in [#"\*\*(.+?)\*\*"#, #"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#] {
            applyRegex(pattern, in: markdown) { match in
                guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
                guard match.numberOfRanges >= 2 else { return }
                let content = match.range(at: 1)
                storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)
                hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
            }
        }
    }

    /// Handles both `*italic*` and `_italic_`.
    private static func styleItalic(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for pattern in [
            #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            #"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#
        ] {
            applyRegex(pattern, in: markdown) { match in
                guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
                guard match.numberOfRanges >= 2 else { return }
                let content = match.range(at: 1)
                storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)
                hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
            }
        }
    }

    private static func styleStrikethrough(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        applyRegex(#"~~(.+?)~~"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }
    }

    private static func styleInlineCode(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange]
    ) {
        applyRegex(#"`([^`\n]+?)`"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.65),
                .cadenceMarkdownInlineCode: true
            ], range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }
    }

    private static func styleHighlight(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        applyRegex(#"==(.+?)=="#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.amber).withAlphaComponent(0.18)
            ], range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }
    }

    private static func styleImageLink(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
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

            if hidesMarkdownMarkers, label.location != NSNotFound, label.length > 0 {
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
        hidesMarkdownMarkers: Bool,
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
            if hidesMarkdownMarkers {
                hide(storage, NSRange(location: full.location, length: 1))
                hide(storage, NSRange(location: label.location + label.length, length: max(0, url.location - (label.location + label.length))))
                hide(storage, NSRange(location: url.location + url.length, length: max(0, NSMaxRange(full) - (url.location + url.length))))
            }
        }
    }

    private static func styleWikiReferences(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool,
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
            if hidesMarkdownMarkers {
                hide(storage, NSRange(location: full.location, length: 2))
                hide(storage, NSRange(location: NSMaxRange(full) - 2, length: 2))
                if reference.hiddenPrefixUTF16Length > 0 {
                    hide(storage, NSRange(location: labelLocation, length: reference.hiddenPrefixUTF16Length))
                }
            } else if reference.hiddenPrefixUTF16Length > 0 {
                storage.addAttributes([
                    .foregroundColor: UIColor(Theme.dim),
                    .font: monoFont
                ], range: NSRange(location: labelLocation, length: reference.hiddenPrefixUTF16Length))
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

    /// Only reached when code-block attachments are disabled (plain-markdown mode); the "live"
    /// path renders fenced code blocks as image attachments via `applyLiveCodeBlocks` instead.
    private static func styleFallbackCodeBlockText(
        _ storage: NSMutableAttributedString,
        markdown: String,
        hidesMarkdownMarkers: Bool
    ) {
        let fullRange = NSRange(location: 0, length: (markdown as NSString).length)
        applyRegex(#"(?s)(```.*?```)"#, in: markdown) { match in
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.muted),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.48)
            ], range: NSIntersectionRange(match.range(at: 1), fullRange))
            guard hidesMarkdownMarkers else { return }
            let full = match.range(at: 1)
            guard full.length >= 6 else { return }
            hide(storage, NSRange(location: full.location, length: 3))
            hide(storage, NSRange(location: NSMaxRange(full) - 3, length: 3))
        }
    }

    private static func shouldStyleInline(
        _ range: NSRange,
        excluding excludedRanges: [NSRange],
        protecting protectedRanges: [NSRange] = []
    ) -> Bool {
        guard range.location != NSNotFound, range.length > 0 else { return false }
        guard !excludedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
            return false
        }
        return !protectedRanges.contains { protected in
            range.location >= protected.location && NSMaxRange(range) <= NSMaxRange(protected)
        }
    }

    private static func regexRanges(_ pattern: String, in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: range).map(\.range)
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
        case .todo:
            kind = ["○", "●", "✓"].contains(info.marker) ? .legacyChecklist(isDone: false) : .checkbox(isDone: false)
        case .done:
            kind = ["○", "●", "✓"].contains(info.marker) ? .legacyChecklist(isDone: true) : .checkbox(isDone: true)
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

    private static func listParagraphStyle(for level: Int, markerWidth: Int) -> NSParagraphStyle {
        let unit: CGFloat = 12
        let markerInset: CGFloat = 8
        let contentGap: CGFloat = 8
        let base = CGFloat(level) * unit
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = base + markerInset
        paragraph.headIndent = base + markerInset + CGFloat(Double(markerWidth) * 5.5) + contentGap
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

    private static func hideMarkers(
        around contentRange: NSRange,
        in match: NSTextCheckingResult,
        storage: NSMutableAttributedString,
        if shouldHide: Bool
    ) {
        guard shouldHide else { return }
        for range in match.markerRanges(contentRange: contentRange) {
            hide(storage, range)
        }
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
    let hidesMarkdownMarkers: Bool
    let contentWidthBucket: Int
    let imageAssetRevision: String
    let taskEmbedRevision: String

    static func current(
        hidesMarkdownMarkers: Bool,
        imageAssets: [MarkdownImageAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 0
    ) -> iOSMarkdownStyleSignature {
        iOSMarkdownStyleSignature(
            theme: "fixed",
            hidesMarkdownMarkers: hidesMarkdownMarkers,
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

private struct iOSMarkdownLineRecord {
    let index: Int
    let text: String
    let range: NSRange
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

private extension NSTextCheckingResult {
    func markerRanges(contentRange: NSRange) -> [NSRange] {
        let opening = NSRange(location: range.location, length: max(0, contentRange.location - range.location))
        let closingStart = contentRange.location + contentRange.length
        let closing = NSRange(location: closingStart, length: max(0, range.location + range.length - closingStart))
        return [opening, closing].filter { $0.length > 0 }
    }
}
#endif
