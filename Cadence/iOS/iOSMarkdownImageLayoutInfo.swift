#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownImageLayoutInfo {
    let id: UUID
    let altText: String
    let image: UIImage?
    let displayWidth: CGFloat
    let pixelSize: CGSize

    private var caption: String {
        altText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every rect this block is drawn from and hit-tested against, from the one shared arithmetic.
    ///
    /// This type used to compute its own `fittedImageSize`, and that is where the squash lived: it
    /// ended in `height: min(max(96, width * aspect), 520)`, a floor and a ceiling applied to the
    /// height with the width left alone. `MarkdownImageBlockLayout` derives the height from the
    /// stored pixel aspect and nothing else, and brings the width down with it if the safety
    /// ceiling is ever reached.
    func layout(maxWidth: CGFloat) -> MarkdownImageBlockLayout {
        MarkdownImageBlockLayout.make(
            displayWidth: displayWidth,
            pixelSize: pixelSize,
            maxWidth: Self.availableWidth(maxWidth: maxWidth),
            hasCaption: !caption.isEmpty
        )
    }

    /// How much width the text column can actually give a picture. Kept separate from the sizing
    /// itself so the shared function stays a pure "width + aspect → box".
    static func availableWidth(maxWidth: CGFloat) -> CGFloat {
        max(MarkdownImageAssetService.minDisplayWidth, min(maxWidth - 24, 760))
    }

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let layout = layout(maxWidth: maxWidth)
        let imageRect = layout.imageRect

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: layout.canvasSize, format: format).image { context in
            let rect = CGRect(origin: .zero, size: layout.canvasSize)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 14)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.46).setFill()
            path.fill()
            UIColor(Theme.borderSubtle).withAlphaComponent(0.62).setStroke()
            path.lineWidth = 1
            path.stroke()

            if let image {
                context.cgContext.saveGState()
                UIBezierPath(roundedRect: imageRect, cornerRadius: 10).addClip()
                image.draw(in: imageRect)
                context.cgContext.restoreGState()
            } else {
                drawMissingImage(in: imageRect)
            }

            drawResizeHandle(in: layout.handleRect)

            guard !caption.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor(Theme.dim)
            ]
            NSString(string: caption).draw(in: layout.captionRect, withAttributes: attributes)
        }
    }

    /// The grip a finger drags to resize. Drawn at the picture's trailing-bottom corner, echoing
    /// the two diagonal strokes the macOS editor paints in the same place.
    private func drawResizeHandle(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor(Theme.bg).withAlphaComponent(0.82).setFill()
        path.fill()
        UIColor(Theme.borderStrong).withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()

        let grip = UIBezierPath()
        grip.lineWidth = 1.6
        grip.lineCapStyle = .round
        grip.move(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 8))
        grip.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 7))
        grip.move(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 8))
        grip.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 12))
        UIColor(Theme.blue).setStroke()
        grip.stroke()
    }

    private func drawMissingImage(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        UIColor(Theme.surface).withAlphaComponent(0.84).setFill()
        path.fill()
        UIColor(Theme.borderSubtle).withAlphaComponent(0.56).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let icon = UIImage(systemName: "photo", withConfiguration: iconConfig)?
            .withTintColor(UIColor(Theme.dim), renderingMode: .alwaysOriginal)
        let iconSize = icon?.size ?? CGSize(width: 24, height: 24)
        icon?.draw(at: CGPoint(x: rect.midX - iconSize.width / 2, y: rect.midY - iconSize.height - 4))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor(Theme.dim)
        ]
        NSString(string: "Missing image").draw(
            in: CGRect(x: rect.minX + 12, y: rect.midY + 8, width: rect.width - 24, height: 18),
            withAttributes: attributes
        )
    }
}
#endif
