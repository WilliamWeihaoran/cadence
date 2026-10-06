import Foundation
import CoreGraphics

// Kept outside the UIKit boundary so range grouping and rail geometry are executable in tests.
nonisolated struct iOSMarkdownQuoteRailLayout: Equatable {
    let depth: Int
    let range: NSRange

    static func taggedRange(for lineRange: NSRange, storageLength: Int) -> NSRange {
        NSRange(location: lineRange.location,
                length: min(lineRange.length + 1, storageLength - lineRange.location))
    }

    static func runs(in storage: NSAttributedString, intersecting visibleRange: NSRange) -> [Self] {
        let fullRange = NSRange(location: 0, length: storage.length)
        let visible = NSIntersectionRange(fullRange, visibleRange)
        guard visible.length > 0 else { return [] }
        var runs: [Self] = []
        storage.enumerateAttribute(.cadenceMarkdownQuoteDepth, in: visible) { value, range, _ in
            guard let depth = value as? Int, depth > 0,
                  (storage.attribute(.cadenceMarkdownFrontmatter, at: range.location, effectiveRange: nil) as? Bool) != true
            else { return }
            // A dirty rect can start halfway through a block. Recover its full range before
            // measuring, otherwise partial redraws give the rail spurious rounded ends.
            var wholeRange = NSRange(location: 0, length: 0)
            _ = storage.attribute(.cadenceMarkdownQuoteDepth, at: range.location,
                                  longestEffectiveRange: &wholeRange, in: fullRange)
            let run = Self(depth: depth, range: wholeRange)
            if runs.last != run { runs.append(run) }
        }
        return runs
    }

    func barRects(firstFragment: CGRect, lastFragment: CGRect, markerLocation: CGPoint) -> [CGRect] {
        let markerWidth = CGFloat(8 + max(0, depth - 1) * 4)
        let x = max(0, firstFragment.minX + markerLocation.x - markerWidth - 6)
        return (0..<max(1, depth)).map { index in
            CGRect(x: x + CGFloat(index * 4), y: firstFragment.minY + 1,
                   width: 3, height: max(0, lastFragment.maxY - firstFragment.minY - 2))
        }
    }
}

#if os(iOS)
import SwiftUI
import UIKit

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
