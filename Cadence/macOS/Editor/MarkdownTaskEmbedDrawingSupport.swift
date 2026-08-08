#if os(macOS)
import AppKit

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
    }

    private struct ChipRect {
        let field: MarkdownTaskEmbedField
        let rect: NSRect
    }

    static func cardRect(
        forLineRect lineRect: NSRect,
        textContainerWidth: CGFloat,
        task: MarkdownTaskEmbedRenderInfo
    ) -> NSRect {
        let maxWidth = max(160, textContainerWidth - 16)
        let width = min(maxWidth, preferredCardWidth(for: task, maxWidth: maxWidth))
        return NSRect(
            x: lineRect.minX + 8,
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

    static func subtaskHit(
        at point: NSPoint,
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> MarkdownTaskEmbedSubtaskHitTarget? {
        MarkdownTaskEmbedSubtaskHitTesting.hit(at: point, in: subtaskRects(task: task, cardRect: cardRect))
    }

    static func drawCard(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect, checkboxRect: NSRect, hoveredTarget: MarkdownTaskEmbedHitTarget?) {
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
        let stripColor = task.isMissing ? MarkdownStylist.dimColor : priorityColor(task.priorityRaw, fallback: task.containerColorHex)
        stripColor.withAlphaComponent(task.isMissing ? 0.48 : 0.9).setFill()
        NSBezierPath(roundedRect: stripRect, xRadius: 2, yRadius: 2).fill()

        drawCheckbox(task: task, rect: checkboxRect, isHovered: hoveredTarget == .checkbox)

        let chips = displayChips(for: task)
        let layout = fieldRects(task: task, cardRect: cardRect, chips: chips)
        drawTitle(task: task, in: layout.title, isHovered: hoveredTarget == .field(.title))
        for chipRect in layout.chips {
            guard let chip = chips.first(where: { $0.field == chipRect.field }) else { continue }
            drawChip(label: chip.label, color: chip.color, rect: chipRect.rect, isHovered: hoveredTarget == .field(chipRect.field))
        }
        drawSubtasks(task: task, cardRect: cardRect, hoveredTarget: hoveredTarget)
    }

    private static func drawCheckbox(task: MarkdownTaskEmbedRenderInfo, rect: NSRect, isHovered: Bool) {
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

        var chipRects: [ChipRect] = []
        var x = contentMinX
        let y = cardRect.minY + 38
        for chip in chips {
            let width = min(max(42, chip.label.size(withAttributes: chipAttributes).width + 18), 128)
            guard x + width <= contentMaxX else { break }
            let rect = NSRect(x: x, y: y, width: width, height: 20)
            chipRects.append(ChipRect(field: chip.field, rect: rect))
            x = rect.maxX + 6
        }
        return (titleRect, chipRects)
    }

    private static func isOverdue(_ task: MarkdownTaskEmbedRenderInfo) -> Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    private static func isOverdo(_ task: MarkdownTaskEmbedRenderInfo) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    private static func isDoToday(_ task: MarkdownTaskEmbedRenderInfo) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    private static func displayChips(for task: MarkdownTaskEmbedRenderInfo) -> [Chip] {
        if task.isMissing {
            return [Chip(label: "Missing", color: MarkdownStylist.redColor, field: .status)]
        }

        var chips: [Chip] = []
        let statusColor: NSColor
        switch TaskStatus(rawValue: task.statusRaw) ?? .todo {
        case .todo:
            statusColor = MarkdownStylist.dimColor
        case .inProgress:
            statusColor = MarkdownStylist.blueColor
        case .done:
            statusColor = MarkdownStylist.greenColor
        case .cancelled:
            statusColor = MarkdownStylist.dimColor
        }

        if (TaskStatus(rawValue: task.statusRaw) ?? .todo) != .todo {
            chips.append(Chip(label: statusLabel(task.statusRaw), color: statusColor, field: .status))
        }
        if (TaskPriority(rawValue: task.priorityRaw) ?? .none) != .none {
            chips.append(Chip(
                label: priorityLabel(task.priorityRaw),
                color: priorityColor(task.priorityRaw, fallback: task.containerColorHex),
                field: .priority
            ))
        }

        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        chips.append(Chip(
            label: container.isEmpty ? "Inbox" : container,
            color: container.isEmpty ? MarkdownStylist.dimColor : NSColor(hex: task.containerColorHex),
            field: .container
        ))

        let section = task.sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !section.isEmpty, section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame {
            chips.append(Chip(label: section, color: MarkdownStylist.dimColor, field: .section))
        }

        let scheduledColor: NSColor = isOverdo(task)
            ? MarkdownStylist.redColor
            : (isDoToday(task) ? MarkdownStylist.highlightFillColor : MarkdownStylist.dimColor)
        chips.append(Chip(label: scheduledLabel(for: task), color: scheduledColor, field: .scheduledDate))
        let dueColor: NSColor = isOverdue(task) ? MarkdownStylist.redColor : MarkdownStylist.dimColor
        chips.append(Chip(label: dueLabel(for: task), color: dueColor, field: .dueDate))
        chips.append(Chip(label: estimateLabel(for: task), color: MarkdownStylist.blueColor, field: .estimate))

        if let recurrence = TaskRecurrenceRule(rawValue: task.recurrenceRaw), recurrence != .none {
            chips.append(Chip(label: recurrence.shortLabel, color: MarkdownStylist.greenColor, field: .recurrence))
        }
        return chips
    }

    private static func preferredCardWidth(for task: MarkdownTaskEmbedRenderInfo, maxWidth: CGFloat) -> CGFloat {
        let checkboxAndPadding: CGFloat = 60
        let titleWidth = min(
            max(140, task.title.size(withAttributes: titleMeasureAttributes).width + 8),
            240
        )
        let chips = displayChips(for: task)
        let chipWidths = chips
            .prefix(task.hasSubtasks ? 4 : 5)
            .map { min(max(42, $0.label.size(withAttributes: chipAttributes).width + 18), 128) }
            .reduce(CGFloat(0), +)
        let chipGaps = CGFloat(max(0, min(chips.count, task.hasSubtasks ? 4 : 5) - 1)) * 6
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

        if task.hiddenSubtaskCount > 0, let overflowRect = rects.first(where: { $0.subtaskID == nil }) {
            drawOverflowChip(count: task.hiddenSubtaskCount, rect: overflowRect.full)
        }
    }

    private static func subtaskRects(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> [MarkdownTaskEmbedSubtaskHitRect] {
        guard task.hasSubtasks else { return [] }
        let contentMinX = cardRect.minX + 59
        let contentMaxX = cardRect.maxX - 12
        let rowY = cardRect.minY + 70
        let rowHeight: CGFloat = 18
        var x = contentMinX
        var rects: [MarkdownTaskEmbedSubtaskHitRect] = []

        for subtask in task.visibleSubtasks {
            let title = subtask.title.isEmpty ? "Untitled subtask" : subtask.title
            let titleWidth = title.size(withAttributes: subtaskAttributes(done: subtask.isDone)).width
            let width = min(max(58, titleWidth + 28), 150)
            guard x + width <= contentMaxX else { break }

            let full = NSRect(x: x, y: rowY, width: width, height: rowHeight)
            let checkbox = NSRect(x: full.minX + 3, y: full.midY - 5, width: 10, height: 10)
            let text = NSRect(x: checkbox.maxX + 5, y: full.minY + 1, width: max(16, full.width - 21), height: rowHeight - 2)
            rects.append(.subtask(id: subtask.id, checkbox: checkbox, text: text, full: full))
            x = full.maxX + 6
        }

        if task.hiddenSubtaskCount > 0 {
            let label = "+\(task.hiddenSubtaskCount) more"
            let width = min(max(48, label.size(withAttributes: subtaskMetaAttributes).width + 16), 84)
            if x + width <= contentMaxX {
                let full = NSRect(x: x, y: rowY, width: width, height: rowHeight)
                rects.append(.overflow(text: full.insetBy(dx: 6, dy: 2), full: full))
            }
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
        ("+\(count) more" as NSString).draw(in: rect.insetBy(dx: 6, dy: 3), withAttributes: subtaskMetaAttributes)
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
            check.move(to: NSPoint(x: checkboxRect.minX + 2.4, y: checkboxRect.midY + 0.4))
            check.line(to: NSPoint(x: checkboxRect.minX + 4.7, y: checkboxRect.maxY - 3))
            check.line(to: NSPoint(x: checkboxRect.maxX - 2.2, y: checkboxRect.minY + 3))
            check.stroke()
        }

        let title = subtask.title.isEmpty ? "Untitled subtask" : subtask.title
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

    private static func priorityColor(_ raw: String, fallback: String) -> NSColor {
        switch TaskPriority(rawValue: raw) ?? .none {
        case .high:
            return MarkdownStylist.redColor
        case .medium:
            return MarkdownStylist.highlightFillColor
        case .low:
            return MarkdownStylist.blueColor
        case .none:
            return NSColor(hex: fallback)
        }
    }

    private static func statusLabel(_ raw: String) -> String {
        switch TaskStatus(rawValue: raw) ?? .todo {
        case .todo:
            return "Todo"
        case .inProgress:
            return "In progress"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        }
    }

    private static func priorityLabel(_ raw: String) -> String {
        let priority = TaskPriority(rawValue: raw) ?? .none
        return priority == .none ? "No priority" : priority.label
    }

    private static func scheduledLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        guard !task.scheduledDate.isEmpty else { return "No do date" }
        let date = DateFormatters.relativeDate(from: task.scheduledDate)
        guard task.scheduledStartMin >= 0 else { return "Do \(date)" }
        return "\(date) \(TimeFormatters.timeString(from: task.scheduledStartMin))"
    }

    private static func dueLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        task.dueDate.isEmpty ? "No due date" : "Due \(DateFormatters.relativeDate(from: task.dueDate))"
    }

    private static func estimateLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        if task.actualMinutes > 0 {
            return TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        }
        return task.estimatedMinutes > 0 ? durationLabel(task.estimatedMinutes) : "No estimate"
    }

    /// Same chip can show either this or `TimeFormatters.durationLabel` depending on whether
    /// actual minutes are logged, so both have to come from the shared formatter — otherwise
    /// one control flips between "1h 30m/2h" and "1.5h".
    private static func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "-" }
        return CadenceTaskPresentationSupport.estimateLabel(minutes: minutes)
    }
}
#endif
