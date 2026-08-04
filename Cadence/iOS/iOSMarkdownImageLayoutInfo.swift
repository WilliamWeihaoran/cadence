#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownImageLayoutInfo {
    let id: UUID
    let altText: String
    let image: UIImage?
    let displayWidth: CGFloat
    let pixelSize: CGSize

    func renderedBlock(maxWidth: CGFloat) -> UIImage {
        let imageSize = fittedImageSize(maxWidth: maxWidth)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 10
        let caption = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionHeight: CGFloat = caption.isEmpty ? 0 : 24
        let canvasSize = CGSize(
            width: imageSize.width + horizontalPadding * 2,
            height: imageSize.height + verticalPadding * 2 + captionHeight
        )

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 14)
            UIColor(Theme.surfaceElevated).withAlphaComponent(0.46).setFill()
            path.fill()
            UIColor(Theme.borderSubtle).withAlphaComponent(0.62).setStroke()
            path.lineWidth = 1
            path.stroke()

            let imageRect = CGRect(
                x: horizontalPadding,
                y: verticalPadding,
                width: imageSize.width,
                height: imageSize.height
            )
            if let image {
                UIBezierPath(roundedRect: imageRect, cornerRadius: 10).addClip()
                image.draw(in: imageRect)
                context.cgContext.resetClip()
            } else {
                drawMissingImage(in: imageRect)
            }

            guard !caption.isEmpty else { return }
            let captionRect = CGRect(
                x: horizontalPadding + 2,
                y: imageRect.maxY + 7,
                width: imageSize.width - 4,
                height: 17
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor(Theme.dim)
            ]
            NSString(string: caption).draw(in: captionRect, withAttributes: attributes)
        }
    }

    private func fittedImageSize(maxWidth: CGFloat) -> CGSize {
        let availableWidth = max(160, min(maxWidth - 24, 760))
        let width = min(max(160, displayWidth), availableWidth)
        let aspect = pixelSize.height / max(pixelSize.width, 1)
        let height = max(96, width * aspect)
        return CGSize(width: width, height: min(height, 520))
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
