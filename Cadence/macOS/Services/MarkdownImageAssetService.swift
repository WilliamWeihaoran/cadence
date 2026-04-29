#if os(macOS)
import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct MarkdownImageReference: Equatable {
    let id: UUID
    let altText: String
    let range: NSRange
}

struct MarkdownImageRenderAsset {
    let id: UUID
    let image: NSImage
    let displayWidth: CGFloat
    let pixelSize: CGSize
}

enum MarkdownImageAssetService {
    static let urlScheme = "cadence-image"
    static let maxLongEdge: CGFloat = 2400
    static let defaultDisplayWidth: CGFloat = 520
    static let minDisplayWidth: CGFloat = 120
    static let maxDisplayWidth: CGFloat = 1200

    static func markdown(for asset: MarkdownImageAsset) -> String {
        "![\(escapedAltText(asset.altText))](\(urlScheme)://\(asset.id.uuidString))"
    }

    static func references(in text: String) -> [MarkdownImageReference] {
        let nsText = text as NSString
        guard nsText.length > 0,
              let regex = try? NSRegularExpression(pattern: #"(?m)^!\[([^\]\n]*)\]\(cadence-image://([0-9A-Fa-f-]{36})\)\s*$"#)
        else { return [] }

        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let id = UUID(uuidString: nsText.substring(with: match.range(at: 2)))
            else { return nil }
            return MarkdownImageReference(
                id: id,
                altText: nsText.substring(with: match.range(at: 1)),
                range: match.range
            )
        }
    }

    static func referencedIDs(in text: String) -> Set<UUID> {
        Set(references(in: text).map(\.id))
    }

    static func unreferencedAssets(allAssets: [MarkdownImageAsset], markdownTexts: [String]) -> [MarkdownImageAsset] {
        let referenced = markdownTexts.reduce(into: Set<UUID>()) { result, text in
            result.formUnion(referencedIDs(in: text))
        }
        return allAssets.filter { !referenced.contains($0.id) }
    }

    @discardableResult
    static func createAsset(
        from image: NSImage,
        originalFilename: String = "",
        altText: String = "",
        in modelContext: ModelContext
    ) -> MarkdownImageAsset? {
        guard let normalized = normalizedImageData(from: image) else { return nil }
        let displayWidth = min(defaultDisplayWidth, normalized.pixelSize.width)
        let asset = MarkdownImageAsset(
            data: normalized.data,
            mimeType: normalized.mimeType,
            originalFilename: originalFilename,
            altText: altText,
            pixelWidth: Int(normalized.pixelSize.width.rounded()),
            pixelHeight: Int(normalized.pixelSize.height.rounded()),
            displayWidth: Double(max(minDisplayWidth, displayWidth))
        )
        modelContext.insert(asset)
        return asset
    }

    static func createAssets(fromFileURLs urls: [URL], in modelContext: ModelContext) -> [MarkdownImageAsset] {
        urls.compactMap { url in
            guard isImageFile(url), let image = NSImage(contentsOf: url) else { return nil }
            return createAsset(from: image, originalFilename: url.lastPathComponent, altText: suggestedAltText(for: url), in: modelContext)
        }
    }

    static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return pasteboard.readObjects(forClasses: classes, options: options) as? [URL] ?? []
    }

    static func images(from pasteboard: NSPasteboard) -> [NSImage] {
        pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
    }

    static func renderAsset(for id: UUID, in assets: [MarkdownImageAsset]) -> MarkdownImageRenderAsset? {
        guard let asset = assets.first(where: { $0.id == id }),
              let image = NSImage(data: asset.data)
        else { return nil }
        return MarkdownImageRenderAsset(
            id: asset.id,
            image: image,
            displayWidth: CGFloat(asset.displayWidth),
            pixelSize: CGSize(width: max(asset.pixelWidth, 1), height: max(asset.pixelHeight, 1))
        )
    }

    static func setDisplayWidth(_ width: CGFloat, for id: UUID, in assets: [MarkdownImageAsset]) {
        guard let asset = assets.first(where: { $0.id == id }) else { return }
        let clamped = min(max(width, minDisplayWidth), maxDisplayWidth)
        asset.displayWidth = Double(clamped)
        asset.updatedAt = Date()
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return NSImage(contentsOf: url) != nil
        }
        return type.conforms(to: .image)
    }

    private static func suggestedAltText(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }

    private static func escapedAltText(_ value: String) -> String {
        value.replacingOccurrences(of: "]", with: "\\]")
    }

    private static func normalizedImageData(from image: NSImage) -> (data: Data, mimeType: String, pixelSize: CGSize)? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sourceSize = CGSize(width: source.width, height: source.height)
        let scale = min(1, maxLongEdge / max(sourceSize.width, sourceSize.height))
        let outputSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let outputImage: NSImage
        if scale < 1 {
            outputImage = NSImage(size: outputSize)
            outputImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(origin: .zero, size: outputSize), from: .zero, operation: .copy, fraction: 1)
            outputImage.unlockFocus()
        } else {
            outputImage = image
        }

        guard let tiffData = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }

        let hasAlpha = bitmap.hasAlpha
        if hasAlpha,
           let png = bitmap.representation(using: .png, properties: [:]) {
            return (png, "image/png", outputSize)
        }
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            return nil
        }
        return (jpeg, "image/jpeg", outputSize)
    }
}
#endif
