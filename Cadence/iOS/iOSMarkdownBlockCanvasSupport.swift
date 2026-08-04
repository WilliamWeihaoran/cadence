#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownQuoteMarkerLayoutInfo {
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

struct iOSMarkdownCheckboxLayoutInfo {
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

struct iOSMarkdownDividerLayoutInfo {
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

struct iOSMarkdownLiveCodeBlockLayoutInfo {
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

struct iOSMarkdownLiveTableLayoutInfo {
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
#endif
