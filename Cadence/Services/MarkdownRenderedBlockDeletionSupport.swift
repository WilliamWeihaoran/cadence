import Foundation

nonisolated enum MarkdownRenderedBlockKind: Equatable {
    case image
    case task
    case code
    case table
    case divider
}

nonisolated struct MarkdownRenderedBlock: Equatable {
    let kind: MarkdownRenderedBlockKind
    let storageRange: NSRange
    let deletionRange: NSRange
}

nonisolated enum MarkdownRenderedBlockDeletionSupport {
    static func expandedDeletionRange(
        in markdown: String,
        selection: NSRange,
        sourceRevealedRanges: [NSRange] = []
    ) -> NSRange? {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return nil }
        let safeSelection = clamped(selection, length: nsMarkdown.length)
        let candidates = renderedBlockRanges(in: markdown)
            .filter { !isSourceRevealed($0, sourceRevealedRanges) }

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

    /// Block kinds whose source stays hidden no matter where the caret is *and* no matter what the
    /// reader asks for.
    ///
    /// Code fences and tables are absent because both have an escape hatch, and they are not the
    /// same hatch — see `hidesSourceFromSelection` below, which is what callers should be asking.
    private static let alwaysRenderedKinds: Set<MarkdownRenderedBlockKind> = [.image, .task, .divider]

    /// Whether a block is currently showing its own markdown because the reader asked for it.
    ///
    /// The editor's two escape hatches are different shapes and this is the one thing they share.
    /// A fenced code block un-renders while the caret is inside it, so its revealed range is the
    /// caret's block; a table un-renders only on the explicit **Show Table Source** command, so its
    /// revealed range is whichever table the command names. Either way the characters under it are
    /// on screen, and every rule below that exists to protect a reader from editing text they
    /// cannot see has to stand down.
    private static func isSourceRevealed(_ block: MarkdownRenderedBlock, _ sourceRevealedRanges: [NSRange]) -> Bool {
        sourceRevealedRanges.contains { NSIntersectionRange($0, block.storageRange).length > 0 }
    }

    /// Whether a selection lying wholly inside this block is a selection of nothing.
    ///
    /// **`.table` is in this set since T-221's iOS half, and the change is the ticket.** A table
    /// used to un-render whenever the caret landed in it, so a selection there was a selection over
    /// visible pipes and had to be left alone — which is why the stored set above lists only the
    /// three kinds that never show their source. Now that a table is a grid you edit cell by cell,
    /// its characters are hidden like a task embed's, and a drag inside one produces the same
    /// handles-over-a-card nothing this function exists to collapse. `.code` is deliberately still
    /// absent: it is the one block that reveals itself by caret position.
    private static func hidesSourceFromSelection(
        _ block: MarkdownRenderedBlock,
        _ sourceRevealedRanges: [NSRange]
    ) -> Bool {
        guard !isSourceRevealed(block, sourceRevealedRanges) else { return false }
        return alwaysRenderedKinds.contains(block.kind) || block.kind == .table
    }

    /// Collapses a selection that lies entirely inside a block whose characters are never visible.
    ///
    /// Selecting hidden text produces selection UI with nothing under it — on iOS, a full-height
    /// bar and two drag handles down the leading edge of the rendered card — and any typing then
    /// rewrites markdown the user cannot see. A task embed is the sharp case: overtyping its hidden
    /// title edits the `[[task:UUID|Title]]` reference without renaming the task, so the card keeps
    /// showing the old title while the note's source drifts away from it.
    ///
    /// Returns nil for an empty selection (that is `MarkdownHiddenRangeSupport.snappedCaretLocation`'s
    /// job) and for a selection that also covers text outside the block, which is a legitimate
    /// "select this paragraph and the card under it" gesture.
    static func collapsedSelection(
        for selection: NSRange,
        in markdown: String,
        sourceRevealedRanges: [NSRange] = []
    ) -> NSRange? {
        guard selection.length > 0 else { return nil }
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return nil }
        let safeSelection = clamped(selection, length: nsMarkdown.length)
        guard safeSelection.length > 0 else { return nil }

        guard let block = renderedBlockRanges(in: markdown).first(where: { block in
            hidesSourceFromSelection(block, sourceRevealedRanges) &&
                NSIntersectionRange(block.storageRange, safeSelection) == safeSelection
        }) else { return nil }

        return NSRange(location: NSMaxRange(block.storageRange), length: 0)
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
        var ranges = MarkdownImageAssetService.standaloneReferences(in: markdown).map { reference in
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

    /// Line numbering has to be `MarkdownSourceLines`', not `NSString.lineRange(for:)`'.
    ///
    /// The indexes these records are looked up by come from `fencedCodeBlocks` and
    /// `MarkdownTableParser.rowStyles`, which split on `"\n"`. `NSString.lineRange(for:)` also
    /// breaks on U+2028, U+2029 and U+0085, so a note carrying any of those numbered its lines
    /// differently here than in the parsers feeding it — and a rendered block would then be given
    /// the deletion range of some other line.
    private static func lineRecords(in markdown: String) -> [RenderedMarkdownLineRecord] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else { return [] }

        return MarkdownSourceLines.lines(in: markdown).map {
            RenderedMarkdownLineRecord(index: $0.index, contentRange: $0.range)
        }
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
    let contentRange: NSRange
}
