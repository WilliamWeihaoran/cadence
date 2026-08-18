#if os(macOS)
import AppKit

// MARK: - Suggestion & Hit-Rect Types

struct MarkdownReferenceTarget: Hashable {
    let kind: MarkdownReferenceKind
    let id: UUID?
    let title: String
}

struct MarkdownReferenceSuggestion: Identifiable, Hashable {
    let kind: MarkdownReferenceKind
    let targetID: UUID
    let title: String
    let subtitle: String
    let markdown: String

    var id: String {
        "\(kind)-\(targetID.uuidString)"
    }

    static func note(_ note: Note) -> MarkdownReferenceSuggestion {
        MarkdownReferenceSuggestion(
            kind: .note,
            targetID: note.id,
            title: note.displayTitle,
            subtitle: note.kind.rawValue.capitalized,
            markdown: NoteReferenceParser.noteReferenceMarkdown(for: note)
        )
    }

    static func task(_ task: AppTask) -> MarkdownReferenceSuggestion {
        MarkdownReferenceSuggestion(
            kind: .task,
            targetID: task.id,
            title: TaskTitleSupport.displayTitle(task.title),
            subtitle: task.containerName.isEmpty ? task.status.rawValue.capitalized : task.containerName,
            markdown: NoteReferenceParser.taskReferenceMarkdown(for: task)
        )
    }
}

struct MarkdownTagSuggestion: Identifiable, Hashable {
    let name: String
    let slug: String
    let desc: String
    let colorHex: String
    let isArchived: Bool

    var id: String { slug }

    static func tag(_ tag: Tag) -> MarkdownTagSuggestion {
        MarkdownTagSuggestion(
            name: tag.name,
            slug: tag.slug,
            desc: tag.desc,
            colorHex: tag.colorHex,
            isArchived: tag.isArchived
        )
    }
}

struct MarkdownImageLayoutInfo {
    let id: UUID
    let altText: String
    let image: NSImage?
    let displayWidth: CGFloat
    let pixelSize: CGSize

    func fittedSize(maxWidth: CGFloat) -> CGSize {
        let width = min(max(1, displayWidth), max(1, maxWidth))
        let aspect = pixelSize.height / max(pixelSize.width, 1)
        return CGSize(width: width, height: max(60, width * aspect))
    }
}

struct MarkdownTaskEmbedHitRects {
    let card: NSRect
    let checkbox: NSRect
}

struct MarkdownTaskEmbedSubtaskHitRect: Hashable {
    let subtaskID: UUID?
    let checkbox: NSRect?
    let text: NSRect
    let full: NSRect

    static func subtask(id: UUID, checkbox: NSRect, text: NSRect, full: NSRect) -> MarkdownTaskEmbedSubtaskHitRect {
        MarkdownTaskEmbedSubtaskHitRect(subtaskID: id, checkbox: checkbox, text: text, full: full)
    }

    static func overflow(text: NSRect, full: NSRect) -> MarkdownTaskEmbedSubtaskHitRect {
        MarkdownTaskEmbedSubtaskHitRect(subtaskID: nil, checkbox: nil, text: text, full: full)
    }
}

enum MarkdownTaskEmbedSubtaskHitTarget: Hashable {
    case checkbox(UUID)
    case openInspector
}

enum MarkdownTaskEmbedSubtaskHitTesting {
    static func hit(
        at point: NSPoint,
        in rects: [MarkdownTaskEmbedSubtaskHitRect],
        checkboxPadding: CGFloat = 4
    ) -> MarkdownTaskEmbedSubtaskHitTarget? {
        for rect in rects {
            if let subtaskID = rect.subtaskID,
               let checkbox = rect.checkbox,
               checkbox.insetBy(dx: -checkboxPadding, dy: -checkboxPadding).contains(point) {
                return .checkbox(subtaskID)
            }

            if rect.text.insetBy(dx: -3, dy: -3).contains(point) {
                return .openInspector
            }
        }

        return nil
    }
}

// MARK: - Checklist Box

/// Geometry and drawing for the box that stands in for a hidden `- [x] ` prefix.
///
/// Kept out of `CadenceLayoutManager` so the draw pass and the click hit test measure the box the
/// same way — the box is not a glyph, so nothing else can keep them agreeing. Shaped to match the
/// circle the iOS styler renders and the `○` / `✓` glyph the legacy syntax still draws as text.
nonisolated enum MarkdownChecklistBoxDrawing {
    static let boxSize: CGFloat = 14
    /// Gap between the box and the text that follows it.
    static let contentGap: CGFloat = 5

    /// `prefixRect` is the bounding rect of the hidden prefix, which sits at the content indent with
    /// almost no width — so the box is measured backwards from its leading edge into the gutter.
    static func boxRect(prefixRect: NSRect) -> NSRect {
        NSRect(
            x: prefixRect.minX - boxSize - contentGap,
            y: prefixRect.midY - (boxSize / 2),
            width: boxSize,
            height: boxSize
        )
    }

    /// Drawn in the text view's flipped coordinate space, so the check descends before it rises.
    static func draw(in rect: NSRect, isDone: Bool) {
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.9, dy: 0.9))
        if isDone {
            MarkdownStylist.greenColor.withAlphaComponent(0.22).setFill()
            circle.fill()
        }
        (isDone ? MarkdownStylist.greenColor : MarkdownStylist.dimColor).setStroke()
        circle.lineWidth = 1.8
        circle.stroke()

        guard isDone else { return }
        let check = NSBezierPath()
        check.move(to: NSPoint(x: rect.minX + 3.4, y: rect.midY - 0.1))
        check.line(to: NSPoint(x: rect.minX + 5.6, y: rect.midY + 2.3))
        check.line(to: NSPoint(x: rect.minX + 10.4, y: rect.midY - 2.8))
        MarkdownStylist.greenColor.setStroke()
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }
}

// MARK: - MarkdownStylist

enum MarkdownStylist {
    // Palette values come from `Theme` so the AppKit editor cannot drift from the rest of the app.
    nonisolated static let bgColor        = Theme.nsBg
    nonisolated static let textColor      = Theme.nsText
    nonisolated static let mutedColor     = Theme.nsMuted
    nonisolated static let dimColor       = Theme.nsDim
    nonisolated static let codeBackground = Theme.nsSurfaceElevated
    nonisolated static let blueColor      = Theme.nsBlue
    nonisolated static let greenColor     = Theme.nsGreen
    nonisolated static let redColor       = Theme.nsRed

    // Extended neutral ramp — see `Theme`'s "Extended neutral ramp" section. These stops sit
    // *between* the four core Theme surfaces (or below `bg`) for jobs the four-stop ramp cannot
    // express: inline strokes that must stay visible at low alpha, recessed wells, and
    // hover/selection lifts inside drawn cards. They used to be private hex literals declared
    // here, which let the editor silently drift from the palette; they now resolve from `Theme`
    // like every other color in the app.
    /// Recessed well, one step *below* the page background (unchecked checkbox interiors).
    nonisolated static let recessColor    = Theme.nsSurfaceRecessed
    /// Hover lift for a drawn card whose resting fill is `Theme.surface`.
    nonisolated static let surfaceHover   = Theme.nsSurfaceHover
    /// Hover/selection highlight behind drawn text inside a card.
    nonisolated static let highlightSurface = Theme.nsSurfaceHighlight
    /// Border one step above `Theme.borderSubtle`, for hairlines drawn at partial alpha.
    nonisolated static let borderColor    = Theme.nsBorder
    /// Emphasized border: hovered cards, table delimiters, code fences.
    nonisolated static let codeBorder     = Theme.nsBorderStrong
    /// Standalone horizontal rules (`---`), which carry no other affordance.
    nonisolated static let ruleColor      = Theme.nsRule

    // Semantic (non-palette) highlight colors — deliberately unchanged by the neutral repaint.
    nonisolated static let highlightFillColor = Theme.nsMarkerHighlightFill
    nonisolated static let highlightBorderColor = Theme.nsMarkerHighlightBorder
    nonisolated static let highlightTextColor = Theme.nsMarkerHighlightText

    static let baseFont   = NSFont.systemFont(ofSize: 14)
    static let monoFont   = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor
    ]

    // MARK: - Cached Regexes

    private static let boldItalicRegex = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*")
    private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
    private static let strikethroughRegex = try! NSRegularExpression(pattern: "~~(.+?)~~")
    private static let highlightRegex = try! NSRegularExpression(pattern: "==(.+?)==")
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`([^`\n]+)`")
    private static let wikiLinkRegex = try! NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#)
    private static let wikiLinkDisplayPrefixRegex = try! NSRegularExpression(pattern: #"^\s*(?:task|note):(?:[^\|\]]*\|)?"#, options: [.caseInsensitive])
    private static let codeFenceRegex = try! NSRegularExpression(pattern: #"(?s)```([^\n`]*)\n(.*?)\n?```"#)
    private static let tablePipeRegex = try! NSRegularExpression(pattern: #"\|"#)

    static func apply(to textView: NSTextView) {
        let cadenceTextView = textView as? CadenceTextView
        let imageAssets = cadenceTextView?.markdownImageAssets ?? [:]
        let taskEmbeds = cadenceTextView?.markdownTaskEmbeds ?? [:]
        cadenceTextView?.markdownTaskEmbedRects.removeAll()
        apply(to: textView, imageAssets: imageAssets, taskEmbeds: taskEmbeds)
    }

    static func apply(
        to textView: NSTextView,
        imageAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    ) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: storage.length)
        let tableStyles = MarkdownTableParser.rowStyles(in: text)

        storage.beginEditing()

        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: baseParagraphStyle
        ], range: fullRange)

        var pos = 0
        for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
            let len = (line as NSString).length
            applyLine(
                storage: storage,
                line: line,
                lineRange: NSRange(location: pos, length: len),
                lineStart: pos,
                tableRowStyle: tableStyles[lineIndex],
                imageAssets: imageAssets,
                taskEmbeds: taskEmbeds,
                textView: textView
            )
            pos += len + 1
        }

        applyInline(storage: storage, text: nsText,
                    regex: boldItalicRegex, markerLen: 3,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                        s.addAttribute(.font, value: NSFontManager.shared.convert(italic, toHaveTrait: .boldFontMask), range: range)
                    })
        applyInline(storage: storage, text: nsText,
                    regex: boldRegex, markerLen: 2,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: existing.pointSize), range: range)
                    })
        applyInline(storage: storage, text: nsText,
                    regex: italicRegex, markerLen: 1,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                        s.addAttribute(.font, value: italic, range: range)
                    })
        applyCode(storage, text: nsText)
        applyInline(storage: storage, text: nsText,
                    regex: strikethroughRegex, markerLen: 2,
                    contentStyle: { range, s in
                        s.addAttribute(.foregroundColor, value: dimColor, range: range)
                        s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    })
        applyInline(storage: storage, text: nsText,
                    regex: highlightRegex, markerLen: 2,
                    contentStyle: { range, s in
                        s.addAttributes([
                            .cadenceMarkdownHighlight: true,
                            .foregroundColor: highlightTextColor
                        ], range: range)
                    })
        applyLinks(storage, text: nsText)
        applyWikiLinks(storage, text: nsText)
        applyCodeFences(storage, text: nsText)
        // Last, so no earlier pass can style the block back into view.
        applyFrontmatter(storage, text: text)

        storage.endEditing()
    }

    /// Renders a note's YAML frontmatter at zero height.
    ///
    /// The block is kept in `note.content` for portability with other markdown tools, but Cadence
    /// never shows it: `title`/`status` are not read back anywhere, and tags are edited through the
    /// note header's `Tag` chips, which mirror themselves into the block. Reuses the same
    /// `cadenceMarkdownHidden` machinery as inline syntax markers rather than adding a second
    /// hiding mechanism, and additionally tags the run with `cadenceMarkdownFrontmatter` so
    /// `MarkdownHiddenRangeSupport` can apply the stricter block caret rule to it.
    private static func applyFrontmatter(_ storage: NSTextStorage, text: String) {
        guard let parsed = MarkdownMetadataParser.hiddenFrontmatterRange(in: text) else { return }
        let range = NSIntersectionRange(parsed, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }

        // The `---` fences are also this editor's divider syntax, so `applyLine` has already tagged
        // both of them `cadenceMarkdownDivider`. `hide` only shrinks glyphs; `drawDividerRules`
        // paints from the attribute alone and does not care whether the run is visible, so the
        // attribute has to come off or the block leaves two ~160pt rules behind — drawn against the
        // 0.1pt line boxes collapsed below, i.e. straight through the note's first visible line.
        storage.removeAttribute(.cadenceMarkdownDivider, range: range)
        hide(storage, range)
        storage.addAttribute(.cadenceMarkdownFrontmatter, value: true, range: range)

        // `hide` shrinks the glyphs but each newline still opens a line box, so the block would
        // leave a few points of dead space above the first paragraph without this.
        let collapsed = NSMutableParagraphStyle()
        collapsed.lineSpacing = 0
        collapsed.paragraphSpacing = 0
        collapsed.paragraphSpacingBefore = 0
        collapsed.minimumLineHeight = 0.1
        collapsed.maximumLineHeight = 0.1
        storage.addAttribute(.paragraphStyle, value: collapsed, range: range)
    }

    // MARK: - Line Dispatch

    private static func applyLine(
        storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        lineStart: Int,
        tableRowStyle: MarkdownTableRowStyle?,
        imageAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo],
        textView: NSTextView
    ) {
        if let embed = standaloneTaskEmbed(in: line, taskEmbeds: taskEmbeds) {
            applyTaskEmbedBlock(storage: storage, lineRange: lineRange, embed: embed)
            return
        }

        if let image = standaloneImage(in: line, imageAssets: imageAssets) {
            applyImageBlock(storage: storage, lineRange: lineRange, image: image, textView: textView)
            return
        }

        if let tableRowStyle {
            applyTableRow(storage: storage, line: line, lineRange: lineRange, lineStart: lineStart, style: tableRowStyle)
        } else if line.hasPrefix("###### ") {
            heading(storage, lineRange, lineStart, prefixLen: 7, size: 15)
        } else if line.hasPrefix("##### ") {
            heading(storage, lineRange, lineStart, prefixLen: 6, size: 17)
        } else if line.hasPrefix("#### ") {
            heading(storage, lineRange, lineStart, prefixLen: 5, size: 19)
        } else if line.hasPrefix("### ") {
            heading(storage, lineRange, lineStart, prefixLen: 4, size: 22)
        } else if line.hasPrefix("## ") {
            heading(storage, lineRange, lineStart, prefixLen: 3, size: 26)
        } else if line.hasPrefix("# ") {
            heading(storage, lineRange, lineStart, prefixLen: 2, size: 30)
        } else if let quote = blockquoteMatch(in: line) {
            let paragraph = NSMutableParagraphStyle()
            let levelInset = CGFloat(max(quote.depth - 1, 0)) * 12
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 18 + levelInset
            paragraph.headIndent = 18 + levelInset
            paragraph.paragraphSpacingBefore = 4
            paragraph.paragraphSpacing = 4

            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
            // Extend by one character (the trailing newline, when present) so consecutive
            // same-depth quote lines form one contiguous attribute run — enumerateAttribute
            // otherwise sees the un-tagged newline as a gap and draws each line as its own
            // separate rounded block instead of one continuous quote.
            let depthRange = NSRange(
                location: lineRange.location,
                length: min(lineRange.length + 1, storage.length - lineRange.location)
            )
            storage.addAttribute(.cadenceMarkdownQuoteDepth, value: quote.depth, range: depthRange)
            hide(storage, NSRange(location: lineStart + quote.indentation.count, length: quote.prefix.count - quote.indentation.count))

            let restStart = lineStart + quote.prefix.count
            let rest = NSRange(location: restStart, length: max(0, lineRange.length - quote.prefix.count))
            if rest.length > 0 {
                storage.addAttribute(.foregroundColor, value: mutedColor, range: rest)
                let existing = storage.attribute(.font, at: rest.location, effectiveRange: nil) as? NSFont ?? baseFont
                let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italic, range: rest)
            }
        } else if let list = MarkdownListSupport.lineInfo(in: line) {
            applyListLine(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
        } else if isDividerLine(line) {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.cadenceMarkdownDivider, value: true, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
            storage.addAttribute(.cadenceMarkdownHidden, value: true, range: lineRange)
        }
    }

    /// Every list line goes through `MarkdownListSupport.lineInfo`, which is the same matcher the
    /// iOS styler reads and the one with test coverage. This file used to carry a private marker
    /// table (`["• ", "◦ ", … "✓ ", "● "]`) that matched `- ` before it ever consulted
    /// `MarkdownChecklistSupport`, so `- [x] done` styled as a dash bullet with a literal `[x]`
    /// sitting after it.
    private static func applyListLine(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        switch list.kind {
        case .ordered:
            applyOrderedListLine(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
        case .todo, .done:
            if list.checklistSyntax == .github {
                applyCheckboxListLine(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
            } else {
                applyLegacyChecklistLine(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
            }
        case .bullet, .dash, .plus:
            applyBulletListLine(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
        }
    }

    private static func applyOrderedListLine(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        let ps = listStyle(for: list.visualLevel, markerWidth: list.markerWidth)
        storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
        let markerRange = absoluteRange(list.markerRange, lineStart: lineStart, lineRange: lineRange)
        guard markerRange.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: textColor, range: markerRange)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: markerRange)
        addListMarkerSpacing(storage, markerRange: markerRange)
    }

    private static func applyBulletListLine(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        let ps = listStyle(for: list.visualLevel, markerWidth: list.markerWidth)
        storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
        let markerRange = absoluteRange(list.markerRange, lineStart: lineStart, lineRange: lineRange)
        guard markerRange.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: textColor, range: markerRange)
        if ["•", "*", "◦", "▪"].contains(list.marker) {
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: list.marker == "▪" ? 14 : 20), range: markerRange)
        }
        addListMarkerSpacing(storage, markerRange: markerRange)
    }

    /// Cadence's own `○` / `●` / `✓` glyph: one visible character, styled in place. Existing notes
    /// are full of these, so they keep rendering exactly as they did.
    private static func applyLegacyChecklistLine(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        let ps = listStyle(for: list.visualLevel, markerWidth: list.markerWidth)
        storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
        let markerRange = absoluteRange(list.markerRange, lineStart: lineStart, lineRange: lineRange)
        guard markerRange.length > 0 else { return }

        let checked = list.kind == .done
        storage.addAttribute(.foregroundColor, value: checked ? greenColor : dimColor, range: markerRange)
        storage.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: checked ? 16 : 18, weight: checked ? .bold : .regular),
            range: markerRange
        )
        addListMarkerSpacing(storage, markerRange: markerRange)
        guard checked else { return }
        strikeThroughCompletedContent(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
    }

    /// GitHub syntax (`- [x] `): the whole six-character prefix is hidden and a box is drawn in the
    /// gutter the paragraph style reserves, the same way the quote bar and divider rule are drawn.
    /// The text is left exactly as written so it survives a round trip out to any other tool.
    private static func applyCheckboxListLine(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        storage.addAttribute(.paragraphStyle, value: checkboxListStyle(for: list.visualLevel), range: lineRange)

        // The indentation goes with it: the prefix lays out at the content indent with next to no
        // width, so leaving the leading spaces visible would push the first line's text right of
        // where its own wrapped lines land.
        let prefixRange = absoluteRange(list.prefixRange, lineStart: lineStart, lineRange: lineRange)
        guard prefixRange.length > 0 else { return }
        hide(storage, prefixRange)
        storage.addAttribute(.cadenceMarkdownChecklistBox, value: list.kind == .done, range: prefixRange)

        guard list.kind == .done else { return }
        strikeThroughCompletedContent(storage: storage, lineRange: lineRange, lineStart: lineStart, list: list)
    }

    private static func strikeThroughCompletedContent(
        storage: NSTextStorage,
        lineRange: NSRange,
        lineStart: Int,
        list: MarkdownListLineInfo
    ) {
        let contentRange = absoluteRange(list.contentRange, lineStart: lineStart, lineRange: lineRange)
        guard contentRange.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: dimColor, range: contentRange)
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
    }

    /// A line-relative range from `MarkdownListSupport`, moved into document coordinates and
    /// clipped to the line it came from.
    private static func absoluteRange(_ range: NSRange, lineStart: Int, lineRange: NSRange) -> NSRange {
        NSIntersectionRange(NSRange(location: lineStart + range.location, length: range.length), lineRange)
    }

    private static func applyTableRow(
        storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        lineStart: Int,
        style: MarkdownTableRowStyle
    ) {
        guard lineRange.length > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 14
        paragraph.headIndent = 14
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacingBefore = style.isHeader ? 8 : 0
        paragraph.paragraphSpacing = style.isDelimiter ? 2 : 0

        storage.addAttributes([
            .paragraphStyle: paragraph,
            .cadenceMarkdownTableRow: style,
            .font: style.isHeader ? NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold) : monoFont,
            .foregroundColor: style.isDelimiter ? dimColor : textColor
        ], range: lineRange)

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        tablePipeRegex.enumerateMatches(in: line, range: fullRange) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: blueColor.withAlphaComponent(0.72), range: NSRange(location: lineStart + match.range.location, length: match.range.length))
        }
    }

    private static func standaloneImage(
        in line: String,
        imageAssets: [UUID: MarkdownImageRenderAsset]
    ) -> MarkdownImageLayoutInfo? {
        guard let reference = MarkdownBlockSupport.standaloneImageReference(in: line) else { return nil }

        let asset = imageAssets[reference.id]
        return MarkdownImageLayoutInfo(
            id: reference.id,
            altText: reference.altText,
            image: asset?.image,
            displayWidth: asset?.displayWidth ?? MarkdownImageAssetService.defaultDisplayWidth,
            pixelSize: asset?.pixelSize ?? CGSize(width: 640, height: 360)
        )
    }

    private static func standaloneTaskEmbed(
        in line: String,
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    ) -> MarkdownTaskEmbedLayoutInfo? {
        guard let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: line) else {
            return nil
        }
        let task = taskEmbeds[reference.id] ?? MarkdownTaskEmbedRenderInfo.missing(reference: reference)
        return MarkdownTaskEmbedLayoutInfo(task: task)
    }

    private static func applyTaskEmbedBlock(
        storage: NSTextStorage,
        lineRange: NSRange,
        embed: MarkdownTaskEmbedLayoutInfo
    ) {
        guard lineRange.length > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = embed.task.paragraphLineHeight
        paragraph.maximumLineHeight = embed.task.paragraphLineHeight
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.cadenceMarkdownTaskEmbed, value: embed, range: lineRange)
        hide(storage, lineRange)
    }

    private static func applyImageBlock(
        storage: NSTextStorage,
        lineRange: NSRange,
        image: MarkdownImageLayoutInfo,
        textView: NSTextView
    ) {
        guard lineRange.length > 0 else { return }
        // Same width the draw pass measures with, from the same helper: the reserved line height
        // below is derived from it, so if the two ever disagreed the image would overflow the
        // fragment it was given and a partial redraw could clip it.
        let contentWidth = MarkdownDecorationGeometry.imageContentWidth(
            viewWidth: textView.bounds.width,
            textContainerInsetWidth: textView.textContainerInset.width
        )
        let imageSize = image.fittedSize(maxWidth: contentWidth)
        let lineHeight = MarkdownDecorationGeometry.imageLineHeight(for: imageSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 2

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: lineRange)
        storage.addAttribute(.cadenceMarkdownImage, value: image, range: lineRange)
    }

    private static func blockquoteMatch(in line: String) -> (indentation: String, prefix: String, depth: Int)? {
        let nsLine = line as NSString
        guard let quote = MarkdownQuoteSupport.lineInfo(in: line) else { return nil }
        let prefix = nsLine.substring(with: quote.prefixRange)
        let indentation = String(prefix.prefix { $0 == " " || $0 == "\t" })
        return (indentation, prefix, quote.depth)
    }

    private static func isDividerLine(_ line: String) -> Bool {
        MarkdownBlockSupport.isDividerLine(line)
    }

    private static func heading(_ storage: NSTextStorage, _ lineRange: NSRange, _ lineStart: Int, prefixLen: Int, size: CGFloat) {
        let markerRange = NSRange(location: lineStart, length: min(prefixLen, lineRange.length))
        let contentLength = max(0, lineRange.length - prefixLen)
        let contentRange = NSRange(location: lineStart + prefixLen, length: contentLength)
        let content = contentLength > 0 ? (storage.string as NSString).substring(with: contentRange) : ""
        let hasVisibleContent = !content.trimmingCharacters(in: .whitespaces).isEmpty

        guard hasVisibleContent else {
            storage.addAttribute(.font, value: baseFont, range: lineRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: markerRange)
            storage.addAttribute(.paragraphStyle, value: baseParagraphStyle, range: lineRange)
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        hide(storage, markerRange)
    }

    private static func applyInline(
        storage: NSTextStorage,
        text: NSString,
        regex: NSRegularExpression,
        markerLen: Int,
        contentStyle: (NSRange, NSTextStorage) -> Void
    ) {
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length > markerLen * 2 else { return }
            let full = m.range
            let open = NSRange(location: full.location, length: markerLen)
            let close = NSRange(location: full.location + full.length - markerLen, length: markerLen)
            let content = NSRange(location: full.location + markerLen, length: full.length - markerLen * 2)
            contentStyle(content, storage)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func applyCode(_ storage: NSTextStorage, text: NSString) {
        inlineCodeRegex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length >= 3 else { return }
            let full = m.range
            let open = NSRange(location: full.location, length: 1)
            let close = NSRange(location: full.location + full.length - 1, length: 1)
            let content = NSRange(location: full.location + 1, length: full.length - 2)
            // Scale relative to whatever's already on this range (e.g. a heading's bold
            // font, already applied by this point) instead of a flat size, so inline code
            // inside a heading isn't a tiny, misaligned-looking pill next to huge text —
            // matches how the bold/italic passes above already read the ambient font.
            let existingFont = storage.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont ?? baseFont
            let codeFont = NSFont.monospacedSystemFont(ofSize: existingFont.pointSize * (monoFont.pointSize / baseFont.pointSize), weight: .regular)
            storage.addAttribute(.font, value: codeFont, range: content)
            storage.addAttribute(.foregroundColor, value: greenColor, range: content)
            storage.addAttribute(.cadenceMarkdownInlineCode, value: true, range: content)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func applyLinks(_ storage: NSTextStorage, text: NSString) {
        for link in MarkdownLinkSupport.linkRanges(in: text as String) {
            let labelRange = link.labelRange
            let urlRange = link.urlRange
            let fullRange = link.fullRange
            storage.addAttribute(.foregroundColor, value: blueColor, range: labelRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: urlRange)
            storage.addAttribute(.font, value: monoFont, range: urlRange)

            let hiddenRanges = [
                NSRange(location: fullRange.location, length: 1),
                NSRange(location: labelRange.location + labelRange.length, length: 2),
                NSRange(location: urlRange.location + urlRange.length, length: 1)
            ]
            hiddenRanges.forEach { hide(storage, $0) }
        }
    }

    private static func applyWikiLinks(_ storage: NSTextStorage, text: NSString) {
        wikiLinkRegex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            guard labelRange.location != NSNotFound else { return }
            if storage.attribute(.cadenceMarkdownTaskEmbed, at: fullRange.location, effectiveRange: nil) is MarkdownTaskEmbedLayoutInfo {
                return
            }

            let label = text.substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = wikiLinkKind(for: label)
            let displayRange = wikiLinkDisplayRange(label: text.substring(with: labelRange), labelRange: labelRange)

            storage.addAttribute(.foregroundColor, value: kind == .task ? greenColor : blueColor, range: displayRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: displayRange)
            storage.addAttribute(.cadenceMarkdownReference, value: wikiLinkTarget(for: label), range: displayRange)
            if kind == .task {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: displayRange)
            }

            hide(storage, NSRange(location: fullRange.location, length: 2))
            hide(storage, NSRange(location: fullRange.location + fullRange.length - 2, length: 2))
            if displayRange.location > labelRange.location {
                hide(storage, NSRange(location: labelRange.location, length: displayRange.location - labelRange.location))
            }
        }
    }

    private enum WikiLinkKind {
        case note
        case task
    }

    private static func wikiLinkKind(for label: String) -> WikiLinkKind {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("task:") ? .task : .note
    }

    private static func wikiLinkDisplayRange(label: String, labelRange: NSRange) -> NSRange {
        let nsLabel = label as NSString
        let fullRange = NSRange(location: 0, length: nsLabel.length)
        guard let match = wikiLinkDisplayPrefixRegex.firstMatch(in: label, range: fullRange) else {
            return labelRange
        }

        let displayLocation = labelRange.location + match.range.length
        let displayLength = max(0, labelRange.length - match.range.length)
        guard displayLength > 0 else { return labelRange }
        return NSRange(location: displayLocation, length: displayLength)
    }

    private static func wikiLinkTarget(for label: String) -> MarkdownReferenceTarget {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("task:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return MarkdownReferenceTarget(kind: .task, id: UUID(uuidString: idText), title: title)
            }
            return MarkdownReferenceTarget(kind: .task, id: UUID(uuidString: payload), title: payload)
        }

        if lowercased.hasPrefix("note:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: idText), title: title)
            }
            return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: payload), title: payload)
        }

        return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: trimmed), title: trimmed)
    }

    private static func applyCodeFences(_ storage: NSTextStorage, text: NSString) {
        codeFenceRegex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let fullRange = match.range(at: 0)
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 14
            paragraph.headIndent = 14
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 6

            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: greenColor,
                .paragraphStyle: paragraph,
                .cadenceMarkdownCodeBlock: true
            ], range: codeRange)

            if languageRange.location != NSNotFound, languageRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: dimColor, range: languageRange)
                storage.addAttribute(.font, value: monoFont, range: languageRange)
            }

            let snippet = text.substring(with: fullRange)
            guard let firstFenceRange = snippet.range(of: "```"),
                  let lastFenceRange = snippet.range(of: "```", options: .backwards) else { return }

            let firstFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: firstFenceRange.lowerBound)
            let lastFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: lastFenceRange.lowerBound)
            hide(storage, NSRange(location: firstFenceLocation, length: 3))
            hide(storage, NSRange(location: lastFenceLocation, length: 3))
        }
    }

    private static func hide(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: range)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.removeAttribute(.kern, range: range)
    }

    static let baseParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }()

    private static func listStyle(for level: Int, markerWidth: Int) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = listMarkerIndent(for: level)
        ps.headIndent = listContentIndent(for: level, markerWidth: markerWidth)
        ps.lineSpacing = 4
        return ps
    }

    /// A GitHub-syntax checklist line hides its whole prefix, so — unlike a marker that is a real
    /// visible glyph — the first line has nothing to push its text across and must start at the
    /// same indent its wrapped lines do. The box is drawn back into the gutter that leaves.
    private static func checkboxListStyle(for level: Int) -> NSParagraphStyle {
        let indent = listContentIndent(for: level, markerWidth: 2)
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = indent
        ps.headIndent = indent
        ps.lineSpacing = 4
        return ps
    }

    private static func listMarkerIndent(for level: Int) -> CGFloat {
        CGFloat(level) * 12 + 8
    }

    private static func listContentIndent(for level: Int, markerWidth: Int) -> CGFloat {
        listMarkerIndent(for: level) + CGFloat(Double(markerWidth) * 5.5) + 8
    }

    private static func addListMarkerSpacing(_ storage: NSTextStorage, markerRange: NSRange) {
        guard markerRange.length > 0 else { return }
        storage.addAttribute(.kern, value: 4.0, range: markerRange)
    }
}

// MARK: - Color Utilities

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
