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
        let nsText = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let inlineCodeRanges = regexRanges(#"`([^`\n]+?)`"#, in: markdown)

        applyRegex(#"\*\*\*(.+?)\*\*\*"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

        applyRegex(#"___(.+?)___"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

        applyRegex(#"\*\*(.+?)\*\*"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

        applyRegex(#"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

        applyRegex(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

        applyRegex(#"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#, in: markdown) { match in
            guard shouldStyleInline(match.range(at: 0), excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)
            hideMarkers(around: content, in: match, storage: storage, if: hidesMarkdownMarkers)
        }

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

        applyRegex(#"!\[([^\]\n]*)\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#, in: markdown) { match in
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

        applyRegex(#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#, in: markdown) { match in
            guard shouldStyleInline(match.range, excluding: excludedRanges, protecting: inlineCodeRanges) else { return }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.greenLight),
                .backgroundColor: UIColor(Theme.green).withAlphaComponent(0.10)
            ], range: match.range)
        }

        if !rendersCodeBlockAttachments {
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
            theme: ThemeManager.shared.selectedTheme.rawValue,
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

private struct iOSMarkdownQuoteMarkerLayoutInfo {
    let depth: Int

    func renderedMarker() -> UIImage {
        let width = CGFloat(8 + max(0, depth - 1) * 4)
        let size = CGSize(width: width, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for index in 0..<max(1, depth) {
                let x = CGFloat(index * 4)
                let path = UIBezierPath(roundedRect: CGRect(x: x, y: 1, width: 3, height: 16), cornerRadius: 1.5)
                UIColor(Theme.blue).withAlphaComponent(index == 0 ? 0.78 : 0.38).setFill()
                path.fill()
            }
        }
    }
}

private struct iOSMarkdownCheckboxLayoutInfo {
    let isDone: Bool

    func renderedMarker() -> UIImage {
        let size = CGSize(width: 18, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(x: 2.5, y: 2.5, width: 13, height: 13)
            let circle = UIBezierPath(ovalIn: rect)
            (isDone ? UIColor(Theme.green).withAlphaComponent(0.22) : UIColor.clear).setFill()
            circle.fill()
            (isDone ? UIColor(Theme.green) : UIColor(Theme.dim)).setStroke()
            circle.lineWidth = 1.8
            circle.stroke()

            guard isDone else { return }
            let check = UIBezierPath()
            check.move(to: CGPoint(x: 6, y: 9.5))
            check.addLine(to: CGPoint(x: 8.2, y: 11.7))
            check.addLine(to: CGPoint(x: 12.6, y: 6.6))
            UIColor(Theme.green).setStroke()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }
    }
}

private struct iOSMarkdownDividerLayoutInfo {
    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let width = min(max(180, maxWidth - 24), 760)
        let size = CGSize(width: width, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let y = size.height / 2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 2, y: y))
            path.addLine(to: CGPoint(x: size.width - 2, y: y))
            UIColor(Theme.borderSubtle).withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.stroke()
        }
    }
}

private struct iOSMarkdownLiveCodeBlockLayoutInfo {
    let language: String?
    let text: String
    let isClosed: Bool

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let width = min(max(260, maxWidth - 22), 760)
        let lines = visibleLines
        let lineHeight: CGFloat = 18
        let headerHeight: CGFloat = language == nil && isClosed ? 0 : 24
        let overflowHeight: CGFloat = overflowCount > 0 ? 22 : 0
        let height = max(68, 24 + headerHeight + CGFloat(lines.count) * lineHeight + overflowHeight)
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 13)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.58).setFill()
            path.fill()
            UIColor(Theme.borderSubtle).withAlphaComponent(0.62).setStroke()
            path.lineWidth = 1
            path.stroke()

            var y = rect.minY + 12
            if headerHeight > 0 {
                drawHeader(in: CGRect(x: rect.minX + 12, y: y, width: rect.width - 24, height: 18))
                y += headerHeight
            }

            for line in lines {
                drawCodeLine(line, in: CGRect(x: rect.minX + 14, y: y, width: rect.width - 28, height: lineHeight))
                y += lineHeight
            }

            if overflowCount > 0 {
                drawOverflow(in: CGRect(x: rect.minX + 14, y: y + 2, width: rect.width - 28, height: 16))
            }
        }
    }

    private var visibleLines: [String] {
        let rawLines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        return Array(rawLines.prefix(12))
    }

    private var overflowCount: Int {
        max(0, (text.isEmpty ? 1 : text.components(separatedBy: "\n").count) - visibleLines.count)
    }

    private func drawHeader(in rect: CGRect) {
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = trimmedLanguage.isEmpty ? (isClosed ? "Code" : "Unclosed code block") : trimmedLanguage
        let tint = isClosed ? UIColor(Theme.amber) : UIColor(Theme.red)
        let chipWidth = min(rect.width, max(58, ceil(label.size(withAttributes: headerAttributes(tint: tint)).width) + 18))
        let chipRect = CGRect(x: rect.minX, y: rect.minY, width: chipWidth, height: rect.height)
        let path = UIBezierPath(roundedRect: chipRect, cornerRadius: 7)
        tint.withAlphaComponent(0.13).setFill()
        path.fill()
        tint.withAlphaComponent(0.24).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSString(string: label).draw(in: chipRect.insetBy(dx: 9, dy: 2), withAttributes: headerAttributes(tint: tint))
    }

    private func drawCodeLine(_ line: String, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor(Theme.muted),
            .paragraphStyle: paragraph
        ]
        NSString(string: line.isEmpty ? " " : line).draw(in: rect, withAttributes: attributes)
    }

    private func drawOverflow(in rect: CGRect) {
        let text = "+ \(overflowCount) more line\(overflowCount == 1 ? "" : "s")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor(Theme.dim)
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func headerAttributes(tint: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: tint
        ]
    }
}

private struct iOSMarkdownLiveTableLayoutInfo {
    let headers: [String]
    let rows: [[String]]

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let columnCount = max(1, headers.count)
        let availableWidth = max(260, min(maxWidth - 22, 760))
        let width = min(max(CGFloat(columnCount) * 132, 280), availableWidth)
        let visibleRows = Array(rows.prefix(8))
        let overflowCount = max(0, rows.count - visibleRows.count)
        let headerHeight: CGFloat = 38
        let rowHeight: CGFloat = 35
        let footerHeight: CGFloat = overflowCount > 0 ? 30 : 0
        let verticalPadding: CGFloat = 10
        let height = verticalPadding * 2 + headerHeight + CGFloat(visibleRows.count) * rowHeight + footerHeight
        let size = CGSize(width: width, height: max(72, height))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 13)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.54).setFill()
            path.fill()
            UIColor(Theme.borderSubtle).withAlphaComponent(0.68).setStroke()
            path.lineWidth = 1
            path.stroke()

            let contentRect = rect.insetBy(dx: 12, dy: verticalPadding)
            let columnWidth = contentRect.width / CGFloat(columnCount)
            drawHeader(in: contentRect, columnWidth: columnWidth)

            var rowY = contentRect.minY + headerHeight
            for (index, row) in visibleRows.enumerated() {
                drawRow(
                    row,
                    index: index,
                    rect: CGRect(x: contentRect.minX, y: rowY, width: contentRect.width, height: rowHeight),
                    columnWidth: columnWidth
                )
                rowY += rowHeight
            }

            if overflowCount > 0 {
                drawOverflow(
                    overflowCount,
                    rect: CGRect(x: contentRect.minX, y: rowY + 3, width: contentRect.width, height: 20)
                )
            }
        }
    }

    private func drawHeader(in rect: CGRect, columnWidth: CGFloat) {
        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 32)
        let headerPath = UIBezierPath(roundedRect: headerRect, cornerRadius: 9)
        UIColor(Theme.blue).withAlphaComponent(0.13).setFill()
        headerPath.fill()

        for column in headers.indices {
            let cellRect = CGRect(
                x: rect.minX + CGFloat(column) * columnWidth,
                y: rect.minY,
                width: columnWidth,
                height: 32
            ).insetBy(dx: 9, dy: 7)
            drawText(headers[column], in: cellRect, color: UIColor(Theme.blueLight), weight: .semibold)
        }
    }

    private func drawRow(_ row: [String], index: Int, rect: CGRect, columnWidth: CGFloat) {
        if index.isMultiple(of: 2) {
            let fillRect = rect.insetBy(dx: 0, dy: 2)
            let path = UIBezierPath(roundedRect: fillRect, cornerRadius: 8)
            UIColor(Theme.surface).withAlphaComponent(0.34).setFill()
            path.fill()
        }

        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
        separator.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        UIColor(Theme.borderSubtle).withAlphaComponent(0.24).setStroke()
        separator.lineWidth = 1
        separator.stroke()

        for column in 0..<max(1, headers.count) {
            let text = row.indices.contains(column) ? row[column] : ""
            let cellRect = CGRect(
                x: rect.minX + CGFloat(column) * columnWidth,
                y: rect.minY,
                width: columnWidth,
                height: rect.height
            ).insetBy(dx: 9, dy: 8)
            drawText(text, in: cellRect, color: UIColor(Theme.text), weight: .regular)
        }
    }

    private func drawOverflow(_ count: Int, rect: CGRect) {
        let text = "+ \(count) more row\(count == 1 ? "" : "s")"
        drawText(text, in: rect.insetBy(dx: 8, dy: 2), color: UIColor(Theme.dim), weight: .medium, size: 11)
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        color: UIColor,
        weight: UIFont.Weight,
        size: CGFloat = 12
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text.isEmpty ? " " : text).draw(in: rect, withAttributes: attributes)
    }
}

enum iOSMarkdownTaskEmbedHitTarget {
    case checkbox
    case subtaskCheckbox(UUID)
    case card
}

struct iOSMarkdownTaskEmbedLayoutInfo {
    let task: MarkdownTaskEmbedRenderInfo

    func renderedSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: renderedWidth(maxWidth: maxWidth), height: task.cardHeight)
    }

    func hitTarget(at point: CGPoint, maxWidth: CGFloat) -> iOSMarkdownTaskEmbedHitTarget {
        let width = renderedWidth(maxWidth: maxWidth)
        let statusRect = CGRect(x: 12, y: 16, width: 22, height: 22).insetBy(dx: -9, dy: -9)
        if statusRect.contains(point) {
            return .checkbox
        }

        if let subtaskID = subtaskCheckboxHit(at: point, width: width) {
            return .subtaskCheckbox(subtaskID)
        }

        return .card
    }

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let width = renderedWidth(maxWidth: maxWidth)
        let size = renderedSize(maxWidth: maxWidth)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 13)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.58).setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            drawStatusMark(in: CGRect(x: 12, y: 16, width: 22, height: 22))
            drawTitle(in: CGRect(x: 44, y: 12, width: width - 58, height: 22))
            drawMetadata(width: width)
            drawSubtasks(width: width)
        }
    }

    private func renderedWidth(maxWidth: CGFloat) -> CGFloat {
        min(max(260, maxWidth - 22), MarkdownTaskEmbedRenderInfo.maxCardWidth)
    }

    private func subtaskCheckboxHit(at point: CGPoint, width: CGFloat) -> UUID? {
        guard task.hasSubtasks else { return nil }
        var x: CGFloat = 44 + 38
        let y: CGFloat = 66

        for subtask in task.visibleSubtasks {
            let title = subtask.title.isEmpty ? "Untitled" : subtask.title
            let prefix = subtask.isDone ? "[x] " : "[ ] "
            let text = prefix + title
            let available = max(0, width - x - 12)
            guard available > 54 else { break }

            let itemWidth = min(160, max(54, ceil(text.size(withAttributes: smallTextAttributes).width) + 6))
            let checkboxRect = CGRect(
                x: x - 4,
                y: y - 8,
                width: min(34, max(0, available)),
                height: 32
            )
            if checkboxRect.contains(point) {
                return subtask.id
            }
            x += itemWidth + 7
        }
        return nil
    }

    private var borderColor: UIColor {
        if task.isMissing { return UIColor(Theme.red).withAlphaComponent(0.42) }
        if task.isDone { return UIColor(Theme.green).withAlphaComponent(0.32) }
        return UIColor(Theme.borderSubtle).withAlphaComponent(0.68)
    }

    private func drawStatusMark(in rect: CGRect) {
        let circle = UIBezierPath(ovalIn: rect)
        UIColor.clear.setFill()
        circle.fill()
        (task.isDone ? UIColor(Theme.green) : UIColor(Theme.dim).withAlphaComponent(0.84)).setStroke()
        circle.lineWidth = 2
        circle.stroke()

        guard task.isDone else { return }
        let check = UIBezierPath()
        check.move(to: CGPoint(x: rect.minX + 6, y: rect.midY + 1))
        check.addLine(to: CGPoint(x: rect.minX + 10, y: rect.midY + 5))
        check.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.midY - 6))
        UIColor(Theme.green).setStroke()
        check.lineWidth = 2.2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }

    private func drawTitle(in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: task.isDone ? UIColor(Theme.dim) : UIColor(Theme.text)
        ]
        NSString(string: task.title).draw(in: rect, withAttributes: attributes)
    }

    private func drawMetadata(width: CGFloat) {
        var x: CGFloat = 44
        let y: CGFloat = 38
        for chip in chips {
            let chipWidth = min(chip.width, max(58, width - x - 12))
            guard chipWidth > 36 else { break }
            drawChip(chip.title, tint: chip.tint, rect: CGRect(x: x, y: y, width: chipWidth, height: 18))
            x += chipWidth + 6
            if x > width - 54 { break }
        }
    }

    private var chips: [(title: String, tint: UIColor, width: CGFloat)] {
        var values: [(String, UIColor)] = []
        let status = TaskStatus(rawValue: task.statusRaw) ?? (task.isDone ? .done : .todo)
        values.append((task.isMissing ? "Missing" : status.label, task.isDone ? UIColor(Theme.green) : UIColor(Theme.blue)))

        if let priority = TaskPriority(rawValue: task.priorityRaw), priority != .none {
            values.append((priority.label, priorityTint(priority)))
        }
        if task.estimatedMinutes > 0 {
            values.append((TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes), UIColor(Theme.amber)))
        }
        if !task.scheduledDate.isEmpty {
            let date = DateFormatters.relativeDate(from: task.scheduledDate)
            let time = task.scheduledStartMin >= 0 ? " \(TimeFormatters.timeString(from: task.scheduledStartMin))" : ""
            values.append(("Do \(date)\(time)", UIColor(Theme.blue)))
        }
        if !task.dueDate.isEmpty {
            values.append(("Due \(DateFormatters.relativeDate(from: task.dueDate))", UIColor(Theme.red)))
        }
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append((task.containerName, UIColor(Theme.muted)))
        }

        return values.map { title, tint in
            let width = min(150, max(44, ceil(title.size(withAttributes: chipAttributes).width) + 16))
            return (title, tint, width)
        }
    }

    private func priorityTint(_ priority: TaskPriority) -> UIColor {
        switch priority {
        case .high: return UIColor(Theme.red)
        case .medium: return UIColor(Theme.amber)
        case .low: return UIColor(Theme.green)
        case .none: return UIColor(Theme.dim)
        }
    }

    private var chipAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor(Theme.text)
        ]
    }

    private func drawChip(_ title: String, tint: UIColor, rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        tint.withAlphaComponent(0.14).setFill()
        path.fill()
        tint.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()

        var attributes = chipAttributes
        attributes[.foregroundColor] = tint
        NSString(string: title).draw(
            in: rect.insetBy(dx: 8, dy: 2),
            withAttributes: attributes
        )
    }

    private func drawSubtasks(width: CGFloat) {
        guard task.hasSubtasks else { return }
        var x: CGFloat = 44
        let y: CGFloat = 66
        let summary = "\(task.completedSubtaskCount)/\(task.subtaskTotalCount)"
        drawSmallText(summary, color: UIColor(Theme.dim), rect: CGRect(x: x, y: y, width: 34, height: 16))
        x += 38

        for subtask in task.visibleSubtasks {
            let title = subtask.title.isEmpty ? "Untitled" : subtask.title
            let prefix = subtask.isDone ? "[x] " : "[ ] "
            let text = prefix + title
            let available = max(0, width - x - 12)
            guard available > 54 else { break }
            let itemWidth = min(160, max(54, ceil(text.size(withAttributes: smallTextAttributes).width) + 6))
            drawSmallText(
                text,
                color: subtask.isDone ? UIColor(Theme.green) : UIColor(Theme.muted),
                rect: CGRect(x: x, y: y, width: min(itemWidth, available), height: 16)
            )
            x += itemWidth + 7
        }
        if task.hiddenSubtaskCount > 0, width - x > 34 {
            drawSmallText("+\(task.hiddenSubtaskCount)", color: UIColor(Theme.dim), rect: CGRect(x: x, y: y, width: 34, height: 16))
        }
    }

    private var smallTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor(Theme.muted)
        ]
    }

    private func drawSmallText(_ text: String, color: UIColor, rect: CGRect) {
        var attributes = smallTextAttributes
        attributes[.foregroundColor] = color
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }
}

private struct iOSMarkdownImageLayoutInfo {
    let id: UUID
    let altText: String
    let image: UIImage?
    let displayWidth: CGFloat
    let pixelSize: CGSize

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let imageSize = fittedImageSize(maxWidth: maxWidth)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 10
        let caption = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionHeight: CGFloat = caption.isEmpty ? 0 : 24
        let canvasSize = CGSize(
            width: imageSize.width + horizontalPadding * 2,
            height: imageSize.height + verticalPadding * 2 + captionHeight
        )

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 14)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.46).setFill()
            path.fill()
            UIColor(Theme.borderSubtle).withAlphaComponent(0.62).setStroke()
            path.lineWidth = 1
            path.stroke()

            let imageRect = CGRect(
                x: horizontalPadding,
                y: verticalPadding,
                width: imageSize.width,
                height: imageSize.height
            )
            if let image {
                UIBezierPath(roundedRect: imageRect, cornerRadius: 10).addClip()
                image.draw(in: imageRect)
                context.cgContext.resetClip()
            } else {
                drawMissingImage(in: imageRect)
            }

            guard !caption.isEmpty else { return }
            let captionRect = CGRect(
                x: horizontalPadding + 2,
                y: imageRect.maxY + 7,
                width: imageSize.width - 4,
                height: 17
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor(Theme.dim)
            ]
            NSString(string: caption).draw(in: captionRect, withAttributes: attributes)
        }
    }

    private func fittedImageSize(maxWidth: CGFloat) -> CGSize {
        let availableWidth = max(160, min(maxWidth - 24, 760))
        let width = min(max(160, displayWidth), availableWidth)
        let aspect = pixelSize.height / max(pixelSize.width, 1)
        let height = max(96, width * aspect)
        return CGSize(width: width, height: min(height, 520))
    }

    private func drawMissingImage(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        UIColor(Theme.surface).withAlphaComponent(0.84).setFill()
        path.fill()
        UIColor(Theme.borderSubtle).withAlphaComponent(0.56).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let icon = UIImage(systemName: "photo", withConfiguration: iconConfig)?
            .withTintColor(UIColor(Theme.dim), renderingMode: .alwaysOriginal)
        let iconSize = icon?.size ?? CGSize(width: 24, height: 24)
        icon?.draw(at: CGPoint(x: rect.midX - iconSize.width / 2, y: rect.midY - iconSize.height - 4))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor(Theme.dim)
        ]
        NSString(string: "Missing image").draw(
            in: CGRect(x: rect.minX + 12, y: rect.midY + 8, width: rect.width - 24, height: 18),
            withAttributes: attributes
        )
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
