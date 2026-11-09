#if os(macOS)
import AppKit
import SwiftUI

enum MarkdownTaskEmbedHitTarget: Equatable {
    case checkbox
    case subtaskCheckbox(UUID)
    case subtaskText
    case field(MarkdownTaskEmbedField)
    case card
}

struct MarkdownTaskEmbedHover: Equatable {
    let id: UUID
    let target: MarkdownTaskEmbedHitTarget
}

enum MarkdownTaskEmbedDrawing {
    private struct Chip {
        let label: String
        let color: NSColor
        let field: MarkdownTaskEmbedField
        /// `CadenceTaskEmbedChipRow.Importance`: lower wins when the card cannot fit every chip.
        let importance: Int
    }

    private struct ChipRect {
        let field: MarkdownTaskEmbedField
        let rect: NSRect
    }

    /// How far in from each edge of the text container the card is drawn. Read by
    /// `MarkdownInlineTaskPanelLayout`, so the panel that opens under the card is the width of the
    /// card rather than of a second, nearly identical rule ([[T-3243]]).
    static let cardHorizontalInset: CGFloat = 8

    static func cardRect(
        forLineRect lineRect: NSRect,
        textContainerWidth: CGFloat,
        task: MarkdownTaskEmbedRenderInfo
    ) -> NSRect {
        let maxWidth = max(160, textContainerWidth - cardHorizontalInset * 2)
        let width = min(maxWidth, preferredCardWidth(for: task, maxWidth: maxWidth))
        return NSRect(
            x: lineRect.minX + cardHorizontalInset,
            y: lineRect.minY + 6,
            width: width,
            height: task.cardHeight
        )
    }

    static func checkboxRect(in cardRect: NSRect) -> NSRect {
        NSRect(x: cardRect.minX + 15, y: cardRect.midY - 9, width: 18, height: 18)
    }

    static func fieldHit(at point: NSPoint, task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) -> MarkdownTaskEmbedField? {
        let layout = fieldRects(task: task, cardRect: cardRect, chips: displayChips(for: task))
        if layout.title.insetBy(dx: -3, dy: -3).contains(point) {
            return .title
        }
        return layout.chips.first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) })?.field
    }

    static func titleRect(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) -> NSRect {
        fieldRects(task: task, cardRect: cardRect, chips: displayChips(for: task)).title
    }

    /// Chip layout drops metadata that does not fit, so callers need a way to ask which fields
    /// actually made it onto the card instead of assuming every chip is there.
    static func chipRects(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) -> [(field: MarkdownTaskEmbedField, rect: NSRect)] {
        fieldRects(task: task, cardRect: cardRect, chips: displayChips(for: task))
            .chips
            .map { (field: $0.field, rect: $0.rect) }
    }

    static func subtaskHit(
        at point: NSPoint,
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> MarkdownTaskEmbedSubtaskHitTarget? {
        MarkdownTaskEmbedSubtaskHitTesting.hit(at: point, in: subtaskRects(task: task, cardRect: cardRect))
    }

    /// `pendingFill` is the card circle's running deferral ([[T-8395]]), read from
    /// `TaskCompletionAnimationManager` by the text view at draw time: the snapshot `task` is the
    /// status before the deferred write, and is rebuilt when it lands.
    static func drawCard(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect,
        checkboxRect: NSRect,
        hoveredTarget: MarkdownTaskEmbedHitTarget?,
        pendingFill: CadenceTaskEmbedPendingFill? = nil
    ) {
        let isHovered = hoveredTarget != nil
        let radius: CGFloat = 11
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        (isHovered ? MarkdownStylist.surfaceHover : Theme.nsSurface)
            .withAlphaComponent(0.98)
            .setFill()
        cardPath.fill()

        (isHovered ? MarkdownStylist.codeBorder : MarkdownStylist.borderColor)
            .withAlphaComponent(isHovered ? 0.62 : 0.82)
            .setStroke()
        cardPath.lineWidth = isHovered ? 1.0 : 0.9
        cardPath.stroke()

        let stripRect = NSRect(x: cardRect.minX, y: cardRect.minY + 5, width: 4, height: cardRect.height - 10)
        let stripColor = task.isMissing ? MarkdownStylist.dimColor : stripColor(for: task)
        stripColor.withAlphaComponent(task.isMissing ? 0.48 : 0.9).setFill()
        NSBezierPath(roundedRect: stripRect, xRadius: 2, yRadius: 2).fill()

        drawCheckbox(task: task, rect: checkboxRect, isHovered: hoveredTarget == .checkbox, pendingFill: pendingFill)

        let chips = displayChips(for: task)
        let layout = fieldRects(task: task, cardRect: cardRect, chips: chips)
        drawTitle(task: task, in: layout.title, isHovered: hoveredTarget == .field(.title))
        for chipRect in layout.chips {
            guard let chip = chips.first(where: { $0.field == chipRect.field }) else { continue }
            drawChip(label: chip.label, color: chip.color, rect: chipRect.rect, isHovered: hoveredTarget == .field(chipRect.field))
        }
        drawSubtasks(task: task, cardRect: cardRect, hoveredTarget: hoveredTarget)
    }

    private static func drawCheckbox(
        task: MarkdownTaskEmbedRenderInfo,
        rect: NSRect,
        isHovered: Bool,
        pendingFill: CadenceTaskEmbedPendingFill?
    ) {
        let path = NSBezierPath(ovalIn: rect)
        let done = task.isDone
        if task.isMissing {
            MarkdownStylist.recessColor.withAlphaComponent(0.76).setFill()
            path.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.38).setStroke()
        } else if done {
            MarkdownStylist.greenColor.withAlphaComponent(0.95).setFill()
            path.fill()
            MarkdownStylist.greenColor.setStroke()
        } else {
            MarkdownStylist.recessColor.withAlphaComponent(0.94).setFill()
            path.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.75).setStroke()
        }
        path.lineWidth = 1.4
        path.stroke()

        if let pendingFill, !task.isMissing, let context = NSGraphicsContext.current?.cgContext {
            let tint = pendingFill.kind == .completing ? MarkdownStylist.greenColor : MarkdownStylist.dimColor
            pendingFill.draw(
                in: rect,
                tint: tint.cgColor,
                reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                context: context
            )
        }

        if isHovered {
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 1.4
            MarkdownStylist.blueColor.withAlphaComponent(0.65).setStroke()
            ring.stroke()
        }

        guard done else { return }
        Theme.nsBg.setStroke()
        let check = NSBezierPath()
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: rect.minX + 4.6, y: rect.midY + 0.8))
        check.line(to: NSPoint(x: rect.minX + 8, y: rect.maxY - 5))
        check.line(to: NSPoint(x: rect.maxX - 4.8, y: rect.minY + 5))
        check.stroke()
    }

    private static func drawTitle(task: MarkdownTaskEmbedRenderInfo, in rect: NSRect, isHovered: Bool) {
        if isHovered {
            MarkdownStylist.highlightSurface.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleColor: NSColor = task.isDone || task.isCancelled || task.isMissing ? MarkdownStylist.dimColor : MarkdownStylist.textColor
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: titleColor,
            .paragraphStyle: paragraph
        ]
        if isHovered {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if task.isDone || task.isCancelled {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        (task.title as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func fieldRects(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect,
        chips: [Chip]
    ) -> (title: NSRect, chips: [ChipRect]) {
        let contentMinX = checkboxRect(in: cardRect).maxX + 12
        let contentMaxX = cardRect.maxX - 12
        let titleRect = NSRect(
            x: contentMinX,
            y: cardRect.minY + 10,
            width: max(60, contentMaxX - contentMinX),
            height: 19
        )

        let widths = chips.map { chipWidth($0) }
        let kept = keptChipIndices(chips: chips, widths: widths, available: max(0, contentMaxX - contentMinX))

        var chipRects: [ChipRect] = []
        var x = contentMinX
        let y = cardRect.minY + 38
        for index in kept {
            let width = min(widths[index], contentMaxX - x)
            guard width > 0 else { break }
            let rect = NSRect(x: x, y: y, width: width, height: 20)
            chipRects.append(ChipRect(field: chips[index].field, rect: rect))
            x = rect.maxX + 6
        }
        return (titleRect, chipRects)
    }

    /// Picks which chips survive a narrow card by importance, then hands the survivors back in
    /// display order -- the rule `CadenceTaskEmbedChipRow.keptIndices` shared with the iOS card.
    /// Both drawing and hit testing go through here, so a chip is never visible without being
    /// clickable or clickable without being visible.
    private static func keptChipIndices(chips: [Chip], widths: [CGFloat], available: CGFloat) -> [Int] {
        CadenceTaskEmbedChipRow.keptIndices(importances: chips.map(\.importance), widths: widths, available: available, gap: 6)
    }

    private static func chipWidth(_ chip: Chip) -> CGFloat {
        min(max(42, chip.label.size(withAttributes: chipAttributes).width + 18), 128)
    }

    /// [[T-14324]]: the row -- order, words, hues, importance -- is `CadenceTaskEmbedChipRow`'s,
    /// shared with the iOS card under [[T-8201]]. What is this card's own is the placeholder an
    /// empty Do, Due or estimate draws: its chips are click targets that edit the field under a
    /// pointer, so an empty field still needs one; the iOS card is a single touch target and
    /// leaves the chip out.
    private static func displayChips(for task: MarkdownTaskEmbedRenderInfo) -> [Chip] {
        CadenceTaskEmbedChipRow.slots(for: task).map { slot in
            Chip(
                label: slot.title ?? placeholder(for: slot.field),
                color: nsColor(for: slot.tone),
                field: slot.field,
                importance: slot.importance
            )
        }
    }

    /// Every chip the card offers before width drops any, as (field, words): the seam the
    /// cross-platform row test reads, since the drawing itself cannot be unit-painted.
    static func offeredChips(for task: MarkdownTaskEmbedRenderInfo) -> [(field: MarkdownTaskEmbedField, label: String)] {
        displayChips(for: task).map { ($0.field, $0.label) }
    }

    /// The card's left strip: the priority chip's hue, or the list's colour when there is none.
    private static func stripColor(for task: MarkdownTaskEmbedRenderInfo) -> NSColor {
        let priority = TaskPriority(rawValue: task.priorityRaw) ?? .none
        return priority == .none ? NSColor(hex: task.containerColorHex) : nsColor(for: .priority(priority))
    }

    /// The empty field's name on its click target.
    private static func placeholder(for field: MarkdownTaskEmbedField) -> String {
        switch field {
        case .scheduledDate: return "No do date"
        case .dueDate: return "No due date"
        case .estimate: return "No estimate"
        default: return ""
        }
    }

    /// The shared tone's `Color`, resolved into sRGB for AppKit drawing as `Theme`'s own bridges do.
    private static func nsColor(for tone: CadenceTaskEmbedChipTone) -> NSColor {
        let resolved = NSColor(tone.color)
        return resolved.usingColorSpace(.sRGB) ?? resolved
    }

    private static func preferredCardWidth(for task: MarkdownTaskEmbedRenderInfo, maxWidth: CGFloat) -> CGFloat {
        let checkboxAndPadding: CGFloat = 60
        let titleWidth = min(
            max(140, task.title.size(withAttributes: titleMeasureAttributes).width + 8),
            240
        )
        let chips = displayChips(for: task)
        // Budget the most important chips, not the first few in display order — otherwise the
        // card is sized for metadata the layout is willing to drop and starves the due chip.
        let budget = task.hasSubtasks ? 4 : 5
        let budgeted = CadenceTaskEmbedChipRow.rankedIndices(importances: chips.map(\.importance)).prefix(budget)
        let chipWidths = budgeted
            .map { chipWidth(chips[$0]) }
            .reduce(CGFloat(0), +)
        let chipGaps = CGFloat(max(0, budgeted.count - 1)) * 6
        let subtaskAllowance: CGFloat = task.hasSubtasks ? 90 : 0
        let preferred = checkboxAndPadding + max(titleWidth, chipWidths + chipGaps) + subtaskAllowance + 24
        return min(max(320, preferred), min(maxWidth, MarkdownTaskEmbedRenderInfo.maxCardWidth))
    }

    private static func drawChip(label: String, color: NSColor, rect: NSRect, isHovered: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        color.withAlphaComponent(isHovered ? 0.22 : 0.13).setFill()
        path.fill()
        color.withAlphaComponent(isHovered ? 0.6 : 0.38).setStroke()
        path.lineWidth = isHovered ? 1.0 : 0.7
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs = chipAttributes
        attrs[.paragraphStyle] = paragraph
        (label as NSString).draw(in: rect.insetBy(dx: 6, dy: 3), withAttributes: attrs)
    }

    private static func drawSubtasks(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect, hoveredTarget: MarkdownTaskEmbedHitTarget?) {
        guard task.hasSubtasks else { return }
        let rects = subtaskRects(task: task, cardRect: cardRect)
        guard !rects.isEmpty else { return }

        let separatorY = cardRect.minY + 64
        MarkdownStylist.borderColor.withAlphaComponent(0.42).setStroke()
        let separator = NSBezierPath()
        separator.lineWidth = 0.6
        separator.move(to: NSPoint(x: cardRect.minX + 15, y: separatorY))
        separator.line(to: NSPoint(x: cardRect.maxX - 12, y: separatorY))
        separator.stroke()

        let progressRect = NSRect(x: cardRect.minX + 15, y: cardRect.minY + 70, width: 36, height: 18)
        drawProgressChip(label: "\(task.completedSubtaskCount)/\(task.subtaskTotalCount)", rect: progressRect)

        for subtask in task.visibleSubtasks {
            guard let rect = rects.first(where: { $0.subtaskID == subtask.id }) else { continue }
            let isHovered = hoveredTarget == .subtaskCheckbox(subtask.id)
            drawSubtask(subtask, checkboxRect: rect.checkbox ?? .zero, textRect: rect.text, isHovered: isHovered)
        }

        if let overflow = subtaskRow(task: task, cardRect: cardRect).overflow {
            drawOverflowChip(count: overflow.count, rect: overflow.full)
        }
    }

    /// [[T-9322]]: the `+N` chip counts every subtask the row did not draw — past the third, and
    /// any of the first three the card was too narrow for — as the iOS card has since [[T-9273]].
    /// Nil when every subtask is on the row.
    static func subtaskOverflowCount(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) -> Int? {
        subtaskRow(task: task, cardRect: cardRect).overflow?.count
    }

    private static func subtaskRow(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> (row: CadenceTaskEmbedSubtaskRowLayout, overflow: (count: Int, full: CGRect)?) {
        // [[T-9273]]: the row's geometry is shared with the iOS card.
        CadenceTaskEmbedSubtaskRow.layoutWithOverflow(
            task.visibleSubtasks,
            totalCount: task.subtaskTotalCount,
            // [[T-10186]]: "Untitled", as the iOS card and every other subtask row say it.
            fallbackTitle: TaskTitleSupport.defaultCompactDisplayTitle,
            minX: cardRect.minX + 59,
            maxX: cardRect.maxX - 12,
            rowY: cardRect.minY + 70,
            rowHeight: 18,
            overflowWidth: { count in
                let label = CadenceTaskSurfaceOptions.moreLabel(hidden: count)
                return min(max(48, label.size(withAttributes: subtaskMetaAttributes).width + 16), 84)
            }
        ) { title, isDone in
            title.size(withAttributes: subtaskAttributes(done: isDone)).width
        }
    }

    static func subtaskRects(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> [MarkdownTaskEmbedSubtaskHitRect] {
        guard task.hasSubtasks else { return [] }
        let layout = subtaskRow(task: task, cardRect: cardRect)
        var rects: [MarkdownTaskEmbedSubtaskHitRect] = layout.row.items.map {
            .subtask(id: $0.subtaskID, checkbox: $0.checkbox, text: $0.text, full: $0.full)
        }
        if let overflow = layout.overflow {
            rects.append(.overflow(text: overflow.full.insetBy(dx: 6, dy: 2), full: overflow.full))
        }
        return rects
    }

    private static func drawProgressChip(label: String, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        MarkdownStylist.blueColor.withAlphaComponent(0.12).setFill()
        path.fill()
        MarkdownStylist.blueColor.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        (label as NSString).draw(in: rect.insetBy(dx: 5, dy: 3), withAttributes: subtaskMetaAttributes)
    }

    private static func drawOverflowChip(count: Int, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        Theme.nsBorderSubtle.withAlphaComponent(0.72).setFill()
        path.fill()
        MarkdownStylist.codeBorder.withAlphaComponent(0.52).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        (CadenceTaskSurfaceOptions.moreLabel(hidden: count) as NSString).draw(in: rect.insetBy(dx: 6, dy: 3), withAttributes: subtaskMetaAttributes)
    }

    private static func drawSubtask(
        _ subtask: MarkdownTaskEmbedSubtaskRenderInfo,
        checkboxRect: NSRect,
        textRect: NSRect,
        isHovered: Bool
    ) {
        let checkboxPath = NSBezierPath(ovalIn: checkboxRect)
        if subtask.isDone {
            MarkdownStylist.greenColor.withAlphaComponent(0.88).setFill()
            checkboxPath.fill()
            MarkdownStylist.greenColor.withAlphaComponent(0.9).setStroke()
        } else {
            MarkdownStylist.recessColor.withAlphaComponent(0.84).setFill()
            checkboxPath.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.62).setStroke()
        }
        checkboxPath.lineWidth = 1
        checkboxPath.stroke()

        if isHovered {
            let ring = NSBezierPath(ovalIn: checkboxRect.insetBy(dx: -2.5, dy: -2.5))
            ring.lineWidth = 1.2
            MarkdownStylist.blueColor.withAlphaComponent(0.65).setStroke()
            ring.stroke()
        }

        if subtask.isDone {
            Theme.nsBg.setStroke()
            let check = NSBezierPath()
            check.lineWidth = 1.35
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            let points = CadenceTaskEmbedSubtaskRow.checkPoints(in: checkboxRect)
            check.move(to: points[0])
            points.dropFirst().forEach { check.line(to: $0) }
            check.stroke()
        }

        let title = TaskTitleSupport.displayTitle(subtask.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle)
        (title as NSString).draw(in: textRect, withAttributes: subtaskAttributes(done: subtask.isDone))
    }

    private static let chipAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: MarkdownStylist.dimColor
    ]

    private static let titleMeasureAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
    ]

    private static let subtaskMetaAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
        .foregroundColor: MarkdownStylist.dimColor
    ]

    private static func subtaskAttributes(done: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: done ? MarkdownStylist.dimColor.withAlphaComponent(0.72) : MarkdownStylist.textColor.withAlphaComponent(0.86),
            .paragraphStyle: paragraph
        ]
        if done {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }
}
#endif
