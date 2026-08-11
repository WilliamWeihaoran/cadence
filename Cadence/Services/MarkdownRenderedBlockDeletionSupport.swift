import Foundation

enum MarkdownRenderedBlockKind: Equatable {
    case image
    case task
    case code
    case table
    case divider
}

struct MarkdownRenderedBlock: Equatable {
    let kind: MarkdownRenderedBlockKind
    let storageRange: NSRange
    let deletionRange: NSRange
}

enum MarkdownRenderedBlockDeletionSupport {
    static func expandedDeletionRange(
        in markdown: String,
        selection: NSRange
    ) -> NSRange? {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return nil }
        let safeSelection = clamped(selection, length: nsMarkdown.length)
        let candidates = renderedBlockRanges(in: markdown)

        if safeSelection.length > 0 {
            return candidates.first { NSIntersectionRange($0.storageRange, safeSelection).length > 0 }?.deletionRange
        }

        let probeLocations = [safeSelection.location, safeSelection.location - 1, safeSelection.location + 1]
        return candidates.first { candidate in
            probeLocations.contains { probe in
                probe >= 0 && probe < nsMarkdown.length && NSLocationInRange(probe, candidate.storageRange)
            }
        }?.deletionRange
    }

    static func renderedBlock(
        atUTF16Location location: Int,
        in markdown: String
    ) -> MarkdownRenderedBlock? {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), max(0, nsMarkdown.length - 1))
        return renderedBlockRanges(in: markdown).first { block in
            NSLocationInRange(safeLocation, block.storageRange)
        }
    }

    static func renderedBlockRanges(in markdown: String) -> [MarkdownRenderedBlock] {
        var ranges = MarkdownImageAssetService.references(in: markdown).map { reference in
            MarkdownRenderedBlock(
                kind: .image,
                storageRange: reference.range,
                deletionRange: expandedDeletionRange(for: reference.range, in: markdown)
            )
        }

        let nsMarkdown = markdown as NSString
        let lineRecords = lineRecords(in: markdown)

        for lineRecord in lineRecords {
            let line = nsMarkdown.substring(with: lineRecord.contentRange)
            if let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: line, lineStart: lineRecord.contentRange.location) {
                ranges.append(MarkdownRenderedBlock(
                    kind: .task,
                    storageRange: reference.range,
                    deletionRange: expandedDeletionRange(for: reference.range, in: markdown)
                ))
            }
        }

        for block in MarkdownBlockSupport.fencedCodeBlocks(in: markdown) {
            guard let range = contentRange(
                from: block.startLineIndex,
                through: block.endLineIndex,
                in: lineRecords
            ) else { continue }
            ranges.append(MarkdownRenderedBlock(
                kind: .code,
                storageRange: range,
                deletionRange: expandedDeletionRange(for: range, in: markdown)
            ))
        }

        ranges.append(contentsOf: tableBlockRanges(in: markdown, lineRecords: lineRecords))

        for lineRecord in lineRecords {
            let line = nsMarkdown.substring(with: lineRecord.contentRange)
            guard MarkdownBlockSupport.isDividerLine(line) else { continue }
            ranges.append(MarkdownRenderedBlock(
                kind: .divider,
                storageRange: lineRecord.contentRange,
                deletionRange: expandedDeletionRange(for: lineRecord.contentRange, in: markdown)
            ))
        }

        return ranges.sorted { $0.storageRange.location < $1.storageRange.location }
    }

    private static func tableBlockRanges(
        in markdown: String,
        lineRecords: [RenderedMarkdownLineRecord]
    ) -> [MarkdownRenderedBlock] {
        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        guard !tableRows.isEmpty else { return [] }

        var output: [MarkdownRenderedBlock] = []
        var lineIndex = 0
        while lineIndex < lineRecords.count {
            guard let style = tableRows[lineIndex], style.isHeader else {
                lineIndex += 1
                continue
            }

            var endLineIndex = lineIndex
            var cursor = lineIndex + 1
            while cursor < lineRecords.count, tableRows[cursor] != nil {
                endLineIndex = cursor
                cursor += 1
            }

            if let range = contentRange(from: lineIndex, through: endLineIndex, in: lineRecords) {
                output.append(MarkdownRenderedBlock(
                    kind: .table,
                    storageRange: range,
                    deletionRange: expandedDeletionRange(for: range, in: markdown)
                ))
            }

            lineIndex = max(cursor, lineIndex + 1)
        }

        return output
    }

    private static func lineRecords(in markdown: String) -> [RenderedMarkdownLineRecord] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return [] }

        var records: [RenderedMarkdownLineRecord] = []
        var lineStart = 0
        var lineIndex = 0
        while lineStart < nsMarkdown.length {
            let lineRange = nsMarkdown.lineRange(for: NSRange(location: lineStart, length: 0))
            var contentsEnd = 0
            nsMarkdown.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: lineRange)
            let contentRange = NSRange(location: lineRange.location, length: max(0, contentsEnd - lineRange.location))
            records.append(RenderedMarkdownLineRecord(index: lineIndex, lineRange: lineRange, contentRange: contentRange))

            let nextLineStart = NSMaxRange(lineRange)
            guard nextLineStart > lineStart else { break }
            lineStart = nextLineStart
            lineIndex += 1
        }

        return records
    }

    private static func contentRange(
        from startLineIndex: Int,
        through endLineIndex: Int,
        in lineRecords: [RenderedMarkdownLineRecord]
    ) -> NSRange? {
        guard let start = lineRecords.first(where: { $0.index == startLineIndex }),
              let end = lineRecords.first(where: { $0.index == endLineIndex }) else {
            return nil
        }

        let startLocation = start.contentRange.location
        let endLocation = NSMaxRange(end.contentRange)
        guard endLocation > startLocation else { return nil }
        return NSRange(location: startLocation, length: endLocation - startLocation)
    }

    /// Grows a rendered block's range to swallow one adjacent newline, so deleting the block does
    /// not leave the blank line it occupied behind.
    ///
    /// Internal because the macOS editor finds its blocks from `NSTextStorage` attributes rather
    /// than from the markdown source, so it cannot use `expandedDeletionRange(in:selection:)` —
    /// but the expansion rule itself must be the same one, not a second copy of it.
    static func expandedDeletionRange(for range: NSRange, in markdown: String) -> NSRange {
        let nsMarkdown = markdown as NSString
        var deletionRange = NSIntersectionRange(range, NSRange(location: 0, length: nsMarkdown.length))
        guard deletionRange.length > 0 else { return deletionRange }

        let after = NSMaxRange(deletionRange)
        if after < nsMarkdown.length,
           nsMarkdown.substring(with: NSRange(location: after, length: 1)) == "\n" {
            deletionRange.length += 1
        } else if deletionRange.location > 0,
                  nsMarkdown.substring(with: NSRange(location: deletionRange.location - 1, length: 1)) == "\n" {
            deletionRange.location -= 1
            deletionRange.length += 1
        }

        return deletionRange
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let rangeEnd = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: max(0, rangeEnd - location))
    }
}

private struct RenderedMarkdownLineRecord {
    let index: Int
    let lineRange: NSRange
    let contentRange: NSRange
}
