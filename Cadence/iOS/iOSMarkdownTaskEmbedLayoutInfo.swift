#if os(iOS)
import SwiftUI
import UIKit

enum iOSMarkdownTaskEmbedHitTarget {
    case checkbox
    case subtaskCheckbox(UUID)
    /// The title line. Mirrors macOS's `.field(.title)`, which is what opens the inline rename
    /// editor there; iOS had no equivalent, so a card's title could not be changed once written.
    case title
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

        if titleRect(width: width).contains(point) {
            return .title
        }

        return .card
    }

    /// The rect the title is drawn into — the tap target for renaming, and the frame the inline
    /// editor takes. One definition, read by `drawTitle` and by `hitTarget`, so the text you tap is
    /// the text you get to edit.
    func titleRect(maxWidth: CGFloat) -> CGRect {
        titleRect(width: renderedWidth(maxWidth: maxWidth))
    }

    private func titleRect(width: CGFloat) -> CGRect {
        CGRect(x: 44, y: 12, width: max(60, width - 58), height: 22)
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
            drawTitle(in: titleRect(width: width))
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
#endif
