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

    private var sourceLines: [String] {
        text.isEmpty ? [""] : MarkdownSourceLines.texts(in: text)
    }

    private var truncation: MarkdownRenderedBlockTruncation {
        MarkdownRenderedBlockLimits.codeLineTruncation(ofTotal: sourceLines.count)
    }

    private var visibleLines: [String] {
        Array(sourceLines.prefix(truncation.visibleCount))
    }

    private var overflowCount: Int {
        truncation.overflowCount
    }

    private func drawHeader(in rect: CGRect) {
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = trimmedLanguage.isEmpty ? (isClosed ? "Code" : "Unclosed code block") : trimmedLanguage
        let tint = isClosed ? UIColor(Theme.amber) : UIColor(Theme.red)
        let chipWidth = min(rect.width, max(58, ceil(label.size(withAttributes: headerAttributes(tint: tint)).width) + 18))
        let chipRect = CGRect(x: rect.minX, y: rect.minY, width: chipWidth, height: rect.height)
        let path = UIBezierPath(roundedRect: chipRect, cornerRadius: Theme.radiusControlCompact)
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
        guard let text = truncation.overflowLabel(unit: "line") else { return }
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

// `iOSMarkdownLiveTableLayoutInfo` was here: the raster table canvas, capped at
// `MarkdownRenderedBlockLimits.tableRowLimit` rows with a "+ N more rows" footer. T-221 replaced it
// with `iOSMarkdownTableGridRendering`, which draws the whole table in vectors so every row is one
// you can reach and edit. The cap and its footer went with it; the limit type itself is still read
// by the fenced-code canvas and by `iOSMarkdownPreview`.
#endif
