#if os(iOS)
import SwiftUI
import UIKit

/// What a touch on a task-embed card resolves to.
///
/// There is deliberately **no `.title`**. It existed briefly, opening an inline field over the
/// card's title, and it split the card into two things a finger could not tell apart: the title
/// renamed, everywhere else opened the task. The Mac can afford that split because a hover
/// highlight announces the title as a control before you commit to pressing it; touch gets no such
/// warning. So the two checkboxes stay — they are drawn as controls and read as controls — and
/// everything else on the card is one action, `.card`, which opens the task. Renaming happens in
/// the task sheet, where every other field of a task is edited.
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
        return CadenceTaskEmbedSubtaskRow.checkboxHit(
            at: point,
            in: subtaskRow(width: width).items,
            slopX: Self.subtaskTouchSlopX,
            slopY: Self.subtaskTouchSlopY
        )
    }

    /// [[T-9273]]: a fingertip on a 10pt glyph. The target is the glyph grown to a 32pt-tall,
    /// 26pt-wide touch box — the title beside it stays the card's (it opens the task).
    static let subtaskTouchSlopX: CGFloat = 8
    static let subtaskTouchSlopY: CGFloat = 11
    static let subtaskRowMinX: CGFloat = 44 + 38
    static let subtaskRowY: CGFloat = 66
    static let subtaskRowHeight: CGFloat = 16

    /// The shared row geometry (`CadenceTaskEmbedSubtaskRow`), measured in this card's 10pt font.
    func subtaskRow(width: CGFloat) -> CadenceTaskEmbedSubtaskRowLayout {
        CadenceTaskEmbedSubtaskRow.layout(
            task.visibleSubtasks,
            fallbackTitle: TaskTitleSupport.defaultCompactDisplayTitle,
            minX: Self.subtaskRowMinX,
            maxX: width - 12,
            rowY: Self.subtaskRowY,
            rowHeight: Self.subtaskRowHeight
        ) { title, _ in
            ceil(NSString(string: title).size(withAttributes: smallTextAttributes).width)
        }
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
        // [[T-9320]]: one 22pt line, truncated as the Mac card's title is — not word-wrapped
        // with the second line clipped away.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: task.isDone ? UIColor(Theme.dim) : UIColor(Theme.text),
            .paragraphStyle: Self.truncatingParagraph
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

    /// [[T-9271]]: the row is `CadenceTaskEmbedTouchChips`', shared with Focus's read-only copy of
    /// this card; only the measuring is this file's.
    private var chips: [(title: String, tint: UIColor, width: CGFloat)] {
        CadenceTaskEmbedTouchChips.chips(for: task).map { chip in
            let width = min(150, max(44, ceil(chip.title.size(withAttributes: chipAttributes).width) + 16))
            return (chip.title, UIColor(chip.tint), width)
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
        attributes[.paragraphStyle] = Self.truncatingParagraph
        NSString(string: title).draw(
            in: rect.insetBy(dx: 8, dy: 2),
            withAttributes: attributes
        )
    }

    private func drawSubtasks(width: CGFloat) {
        guard task.hasSubtasks else { return }
        let summary = "\(task.completedSubtaskCount)/\(task.subtaskTotalCount)"
        drawSmallText(summary, color: UIColor(Theme.dim), rect: CGRect(x: 44, y: Self.subtaskRowY, width: 34, height: 16))

        let row = subtaskRow(width: width)
        for item in row.items {
            drawSubtaskMark(in: item.checkbox, isDone: item.isDone)
            drawSubtaskTitle(item.label, isDone: item.isDone, rect: item.text)
        }
        // Counts what the row could not place as well as what was never offered to it: on a
        // 393pt phone the third subtask often does not fit, and leaving it uncounted lost it.
        let unplaced = task.subtaskTotalCount - row.items.count
        if unplaced > 0, width - row.trailingX > 34 {
            drawSmallText(
                "+\(unplaced)",
                color: UIColor(Theme.dim),
                rect: CGRect(x: row.trailingX, y: Self.subtaskRowY, width: 34, height: 16)
            )
        }
    }

    /// `drawStatusMark`'s vocabulary at subtask size, drawn as the Focus copy of this card draws
    /// it (`circle` / `checkmark.circle.fill`): an open subtask is a dim ring, a done one a filled
    /// green disc with the tick knocked out.
    private func drawSubtaskMark(in rect: CGRect, isDone: Bool) {
        let circle = UIBezierPath(ovalIn: rect)
        if isDone {
            UIColor(Theme.green).setFill()
            circle.fill()
            let points = CadenceTaskEmbedSubtaskRow.checkPoints(in: rect)
            let check = UIBezierPath()
            check.move(to: points[0])
            points.dropFirst().forEach { check.addLine(to: $0) }
            UIColor(Theme.bg).setStroke()
            check.lineWidth = 1.35
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        } else {
            UIColor(Theme.dim).withAlphaComponent(0.84).setStroke()
            circle.lineWidth = 1.2
            circle.stroke()
        }
    }

    private static var truncatingParagraph: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func drawSubtaskTitle(_ title: String, isDone: Bool, rect: CGRect) {
        var attributes = smallTextAttributes
        attributes[.foregroundColor] = isDone ? UIColor(Theme.dim) : UIColor(Theme.muted)
        attributes[.paragraphStyle] = Self.truncatingParagraph
        if isDone {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = UIColor(Theme.dim)
        }
        NSString(string: title).draw(in: rect, withAttributes: attributes)
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
#endif
