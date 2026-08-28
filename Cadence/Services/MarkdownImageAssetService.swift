import Foundation
import CoreGraphics
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

nonisolated struct MarkdownImageReference: Equatable {
    let id: UUID
    let altText: String
    let range: NSRange
}

#if os(macOS)
nonisolated struct MarkdownImageRenderAsset {
    let id: UUID
    let image: NSImage
    let displayWidth: CGFloat
    let pixelSize: CGSize
}
#elseif os(iOS)
nonisolated struct MarkdownImageRenderAsset {
    let id: UUID
    let image: UIImage
    let displayWidth: CGFloat
    let pixelSize: CGSize
}
#endif

/// The geometry of one rendered image block — the padded card, the picture inside it, its caption,
/// and its resize handle — in card-local coordinates with the origin at the card's top-left.
///
/// Cross-platform and outside every `#if`, so the arithmetic is reachable from the macOS-built test
/// target even though the only renderer that draws from it today lives under `Cadence/iOS/`.
/// `iOSMarkdownImageLayoutInfo` draws this and hit-tests against it, so the handle a finger lands on
/// is the handle that was painted — the same arrangement `iOSMarkdownBlockCanvas.blockRect` already
/// gives the task-embed card.
nonisolated struct MarkdownImageBlockLayout: Equatable {
    /// The picture, inside the card.
    let imageRect: CGRect
    /// The caption line under the picture. Zero-height when there is no caption.
    let captionRect: CGRect
    /// The whole card, which is what the paragraph style has to reserve height for.
    let canvasSize: CGSize
    /// The grip that is drawn, at the picture's trailing-bottom corner.
    let handleRect: CGRect
    /// What a **finger** has to land in to start a resize.
    ///
    /// A cursor is a point and can hit an 18pt grip; a fingertip cannot, so this is grown to the
    /// 44pt platform floor around the grip's centre. It is allowed to extend past the card's own
    /// bounds — it is measured against the card's origin, not clipped to it — which is what keeps
    /// the target honest on a picture only 120pt wide.
    let handleHitRect: CGRect

    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 10
    static let captionGap: CGFloat = 7
    static let captionTextHeight: CGFloat = 17
    /// Total vertical space a caption adds under the picture.
    static let captionBlockHeight: CGFloat = 24
    static let handleSize: CGFloat = 26
    static let handleInset: CGFloat = 6
    /// Apple's minimum comfortable touch target.
    static let minimumTouchSize: CGFloat = 44

    static func make(
        displayWidth: CGFloat,
        pixelSize: CGSize,
        maxWidth: CGFloat,
        hasCaption: Bool
    ) -> MarkdownImageBlockLayout {
        let imageSize = MarkdownImageAssetService.fittedSize(
            displayWidth: displayWidth,
            pixelSize: pixelSize,
            maxWidth: maxWidth
        )
        let imageRect = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: imageSize.width,
            height: imageSize.height
        )
        let captionRect = hasCaption
            ? CGRect(
                x: horizontalPadding + 2,
                y: imageRect.maxY + captionGap,
                width: max(1, imageSize.width - 4),
                height: captionTextHeight
              )
            : CGRect(x: horizontalPadding, y: imageRect.maxY, width: imageSize.width, height: 0)
        let canvasSize = CGSize(
            width: imageSize.width + horizontalPadding * 2,
            height: imageSize.height + verticalPadding * 2 + (hasCaption ? captionBlockHeight : 0)
        )
        let handleRect = CGRect(
            x: imageRect.maxX - handleSize - handleInset,
            y: imageRect.maxY - handleSize - handleInset,
            width: handleSize,
            height: handleSize
        )
        let hitSize = max(minimumTouchSize, handleSize)
        let handleHitRect = CGRect(
            x: handleRect.midX - hitSize / 2,
            y: handleRect.midY - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
        return MarkdownImageBlockLayout(
            imageRect: imageRect,
            captionRect: captionRect,
            canvasSize: canvasSize,
            handleRect: handleRect,
            handleHitRect: handleHitRect
        )
    }

    /// Whether a touch at `point` (card-local) starts a resize rather than anything else.
    func isResizeHandle(localPoint point: CGPoint) -> Bool {
        handleHitRect.contains(point)
    }
}

nonisolated enum MarkdownImageAssetService {
    /// Alt text is escaped on write, so the reader has to accept `\]` and `\\` inside the label.
    /// A pattern that stops at the first `]` cannot match a reference whose alt text contains one
    /// — and an unmatched reference reads as an orphaned asset, which is what deletes the image.
    ///
    /// The trailing `\\?` is not decoration. Alt text written *before* any escaping existed can end
    /// in a lone backslash (`![photo\](…)`), and without it the `\\.` branch swallows the closing
    /// `]`, leaving nothing to end the label — so the reference goes unmatched and the image gets
    /// collected, which is the exact failure this pattern was widened to prevent. Such a label is
    /// genuinely ambiguous with an escaped `]`, and it resolves as the latter; reading the caption
    /// slightly wrong is survivable, deleting the image is not.
    static let altTextPattern = #"(?:[^\]\n\\]|\\.)*\\?"#

    /// One `![alt](cadence-image://<uuid>)`, **wherever it sits**: group 1 is the alt text, group 2
    /// the id. `MarkdownInlineMarkerRanges.inlineImageReferencePattern` is this same string rather
    /// than a second spelling of it — the styler and the lifecycle sweep have to agree on what a
    /// reference *is*, even though they disagree about which ones become blocks.
    static let referencePattern = #"!\[("# + altTextPattern + #")\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#

    private static let anyReferenceRegex = try! NSRegularExpression(pattern: referencePattern)

    /// The same reference, alone on its line — the block form, and nothing else.
    private static let standaloneReferenceRegex = try! NSRegularExpression(pattern: #"(?m)^"# + referencePattern + #"\s*$"#)

    static let urlScheme = "cadence-image"
    static let maxLongEdge: CGFloat = 2400
    static let defaultDisplayWidth: CGFloat = 520
    static let minDisplayWidth: CGFloat = 120
    static let maxDisplayWidth: CGFloat = 1200

    /// Ceiling on a rendered image's height. A safety bound on the canvas a renderer has to
    /// allocate for a pathologically tall picture, **not** a design cap: it is above anything a
    /// real photo reaches at any width this app allows (`maxDisplayWidth` × a 9:16 portrait aspect
    /// is 2,133), and when it does bite `fittedSize` narrows the width to match instead of
    /// flattening the height. See the note on `fittedSize`.
    static let maxRenderedHeight: CGFloat = 2400

    /// The aspect used when an asset has no usable pixel size — 16:9, matching the placeholder
    /// `standaloneImage` already substitutes for an asset it cannot find at all.
    static let fallbackAspectRatio: CGFloat = 360.0 / 640.0

    // MARK: - Rendered geometry

    /// Height ÷ width, from the stored pixel size.
    ///
    /// `MarkdownImageAsset.pixelWidth`/`pixelHeight` are `Int`s defaulting to **0** — the default
    /// exists because CloudKit requires one, and a record that reaches this device without those
    /// fields (an older build's row, a partial sync) arrives holding it. Reading `max(_, 1)` on
    /// each, as `renderAsset` used to, turns that into a 1×1 pixel size and renders the picture as
    /// a **square**. So a degenerate size resolves to `fallbackAspectRatio` here, and `renderAsset`
    /// separately prefers the decoded image's own dimensions over a missing stored size — the
    /// bitmap always knows its shape even when the row does not.
    static func aspectRatio(pixelSize: CGSize) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0,
              pixelSize.width.isFinite, pixelSize.height.isFinite
        else { return fallbackAspectRatio }
        return pixelSize.height / pixelSize.width
    }

    /// The pixel size a render should use: the stored one when it is usable, the decoded bitmap's
    /// own dimensions when it is not.
    static func resolvedPixelSize(storedWidth: Int, storedHeight: Int, decoded: CGSize) -> CGSize {
        if storedWidth > 0, storedHeight > 0 {
            return CGSize(width: CGFloat(storedWidth), height: CGFloat(storedHeight))
        }
        guard decoded.width > 0, decoded.height > 0, decoded.width.isFinite, decoded.height.isFinite else {
            return .zero
        }
        return decoded
    }

    /// **The one definition of how a stored width plus a stored aspect become a rendered box.**
    /// Every render path on both platforms goes through it, so the shape on iOS is the shape on
    /// macOS.
    ///
    /// Width is the only dimension anyone stores; height follows from the aspect, always. That
    /// invariant is the whole fix. The iOS renderer used to end its sizing with
    /// `CGSize(width: width, height: min(max(96, width * aspect), 520))` — a floor and a ceiling
    /// applied to the *height alone*, leaving the width untouched. Both break the aspect by
    /// construction, and the ceiling is what the user saw: a portrait phone screenshot
    /// (1170 × 2532, aspect 2.164) laid out at 326pt wide wants 705pt of height and was drawn at
    /// 520 — the same picture squashed to 74% of its height. "Sometimes" was the ceiling only
    /// biting images taller than the cap, and "a bit" was how close a 16:9 portrait (579pt wanted,
    /// 520 drawn, 90%) comes to clearing it.
    ///
    /// When the height ceiling *is* reached the width comes down with it, so the box shrinks along
    /// its diagonal rather than flattening. That can take the width under `minDisplayWidth`; a
    /// bound that would otherwise be violated loses to the aspect deliberately, because a
    /// too-narrow image still looks like itself and a squashed one does not.
    static func fittedSize(
        displayWidth: CGFloat,
        pixelSize: CGSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat = maxRenderedHeight
    ) -> CGSize {
        let aspect = aspectRatio(pixelSize: pixelSize)
        let available = max(1, maxWidth.isFinite ? maxWidth : maxRenderedHeight)
        let requested = displayWidth.isFinite ? displayWidth : defaultDisplayWidth
        var width = max(1, min(max(requested, minDisplayWidth), available))
        var height = width * aspect

        let ceiling = max(1, maxHeight)
        if height > ceiling {
            width *= ceiling / height
            height = ceiling
        }
        return CGSize(width: width, height: height)
    }

    /// The bounds a persisted display width lives inside. `setDisplayWidth` writes through it and
    /// every platform's drag handler resolves through it, so there is one minimum and one maximum.
    static func clampedDisplayWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultDisplayWidth }
        return min(max(width, minDisplayWidth), maxDisplayWidth)
    }

    /// What a resize drag resolves to: the width the drag started at, plus how far it has travelled
    /// horizontally, clamped. Dragging the trailing handle right widens; left narrows.
    ///
    /// Shared so the macOS mouse drag and the iOS pan agree on the result without either owning a
    /// second clamp — and so both ends of the clamp are testable without a text view.
    static func resolvedDisplayWidth(startWidth: CGFloat, translation: CGFloat) -> CGFloat {
        clampedDisplayWidth(startWidth + (translation.isFinite ? translation : 0))
    }

    static func markdown(for asset: MarkdownImageAsset) -> String {
        "![\(escapedAltText(asset.altText))](\(urlScheme)://\(asset.id.uuidString))"
    }

    // MARK: - Two questions, two predicates
    //
    // T-350: rendering and lifecycle used to share one predicate, and it was the rendering one.
    //
    // `standaloneReferences` answers *does this render as an image block* — a reference alone on
    // its line. Deliberately narrow: an inline `![x](cadence-image://…)` inside a sentence stays
    // paragraph text, and widening this would turn a word into a card.
    //
    // `allReferences` answers *does this text reference this asset at all*, which is the only safe
    // question for asset lifecycle and export. Asking the rendering question there let a note or
    // list delete collect an asset a surviving note still showed: the note displayed the image
    // inline, the sweep did not count it, and the bytes went. Only reachable by hand-editing an
    // image into a sentence — paste and photo insertion both write standalone blocks — but the
    // loss is permanent and unrecoverable, so the lifecycle side errs toward keeping. Over-counting
    // a reference defers garbage; under-counting one deletes a picture.

    /// The references that render as image blocks.
    static func standaloneReferences(in text: String) -> [MarkdownImageReference] {
        references(in: text, matching: standaloneReferenceRegex)
    }

    /// Every image reference in the text, inline ones included.
    static func allReferences(in text: String) -> [MarkdownImageReference] {
        references(in: text, matching: anyReferenceRegex)
    }

    private static func references(in text: String, matching regex: NSRegularExpression) -> [MarkdownImageReference] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let id = UUID(uuidString: nsText.substring(with: match.range(at: 2)))
            else { return nil }
            return MarkdownImageReference(
                id: id,
                altText: unescapedAltText(nsText.substring(with: match.range(at: 1))),
                range: match.range
            )
        }
    }

    /// The assets a renderer has to decode: block references only. Not a lifecycle answer.
    static func standaloneReferencedIDs(in text: String) -> Set<UUID> {
        Set(standaloneReferences(in: text).map(\.id))
    }

    /// The assets this text keeps alive. Every reference form counts.
    static func referencedIDs(in text: String) -> Set<UUID> {
        Set(allReferences(in: text).map(\.id))
    }

    static func unreferencedAssets(allAssets: [MarkdownImageAsset], markdownTexts: [String]) -> [MarkdownImageAsset] {
        let referenced = markdownTexts.reduce(into: Set<UUID>()) { result, text in
            result.formUnion(referencedIDs(in: text))
        }
        return allAssets.filter { !referenced.contains($0.id) }
    }

#if os(macOS)
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

    /// The pasteboard types an image can arrive on — the type-level statement of what the two
    /// readers above can actually accept, so that AppKit can be told about it *before* any of this
    /// runs.
    ///
    /// **This is the list whose absence made pasting an image do nothing.** `NSTextView` decides
    /// whether **Paste** is applicable at all by intersecting the pasteboard's types with its own
    /// `readablePasteboardTypes`, and that list carries no image type unless `importsGraphics` is
    /// set. Measured on macOS 26, the default is RTF, RTFD, HTML, the URL family, string,
    /// filenames, colour, font and ruler — and nothing else. A screenshot and a browser image are
    /// image-*only* pasteboards, so the intersection is empty, `validateUserInterfaceItem` answers
    /// **false** for `paste:`, the menu item is disabled and Cmd-V is never dispatched. A
    /// `paste(_:)` override cannot help: the command never arrives. That is also why the same image
    /// **dragged** in always worked, and why a file copied in **Finder** pasted fine — a Finder copy
    /// carries `NSFilenamesPboardType`, which is in the default list, and a drag registers its own
    /// types.
    ///
    /// Widening `readablePasteboardTypes` is deliberately the fix rather than `importsGraphics =
    /// true`. Turning that on would *also* let `super.paste(_:)` build an `NSTextAttachment` on any
    /// path where the editor's own handler declines — an invisible U+FFFC in a text storage whose
    /// whole invariant is that it holds markdown source and nothing else.
    ///
    /// `NSImage.imageTypes` is the source rather than a hand-written `[.tiff, .png]`, so the offer
    /// and the read agree by construction: every format `readObjects(forClasses: [NSImage.self])`
    /// can decode is a format the menu item is enabled for, HEIC and WebP included.
    static var readableImagePasteboardTypes: [NSPasteboard.PasteboardType] {
        NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) } + [.fileURL]
    }
#elseif os(iOS)
    @discardableResult
    static func createAsset(
        from image: UIImage,
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

    @discardableResult
    static func createAsset(
        fromImageData data: Data,
        originalFilename: String = "",
        altText: String = "",
        in modelContext: ModelContext
    ) -> MarkdownImageAsset? {
        guard let image = UIImage(data: data) else { return nil }
        return createAsset(from: image, originalFilename: originalFilename, altText: altText, in: modelContext)
    }
#endif

    static func renderAsset(for id: UUID, in assets: [MarkdownImageAsset]) -> MarkdownImageRenderAsset? {
        guard let asset = assets.first(where: { $0.id == id }) else { return nil }
#if os(macOS)
        guard let image = NSImage(data: asset.data) else { return nil }
#elseif os(iOS)
        guard let image = UIImage(data: asset.data) else { return nil }
#else
        return nil
#endif
        return MarkdownImageRenderAsset(
            id: asset.id,
            image: image,
            displayWidth: CGFloat(asset.displayWidth),
            // Not `max(asset.pixelWidth, 1)`. A row that never recorded its pixel size — the `0`
            // default, which CloudKit hands back for a field an older build did not write — became
            // a 1×1 aspect there, i.e. a square. The decoded bitmap is the better authority when
            // the row has nothing: it cannot be wrong about its own shape.
            pixelSize: resolvedPixelSize(
                storedWidth: asset.pixelWidth,
                storedHeight: asset.pixelHeight,
                decoded: decodedPixelSize(of: image)
            )
        )
    }

    static func setDisplayWidth(_ width: CGFloat, for id: UUID, in assets: [MarkdownImageAsset]) {
        guard let asset = assets.first(where: { $0.id == id }) else { return }
        asset.displayWidth = Double(clampedDisplayWidth(width))
        asset.updatedAt = Date()
    }

#if os(macOS)
    private static func decodedPixelSize(of image: NSImage) -> CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cgImage.width > 0, cgImage.height > 0 {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }
#elseif os(iOS)
    private static func decodedPixelSize(of image: UIImage) -> CGSize {
        if let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
#endif

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
#if os(macOS)
            return NSImage(contentsOf: url) != nil
#else
            return false
#endif
        }
        return type.conforms(to: .image)
    }

    private static func suggestedAltText(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }

    private static func escapedAltText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    /// Undoes `escapedAltText`. A backslash before anything else is left alone, so alt text that
    /// predates the escaping (a raw `C:\path`) still reads back the way it was written.
    static func unescapedAltText(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            guard character == "\\", let next = pending, next == "\\" || next == "]" else {
                result.append(character)
                continue
            }
            result.append(next)
            pending = iterator.next()
        }
        return result
    }

#if os(macOS)
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
#elseif os(iOS)
    private static func normalizedImageData(from image: UIImage) -> (data: Data, mimeType: String, pixelSize: CGSize)? {
        guard let source = image.cgImage else { return nil }
        let sourceSize = CGSize(width: source.width, height: source.height)
        let scale = min(1, maxLongEdge / max(sourceSize.width, sourceSize.height))
        let outputSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let outputImage: UIImage
        if scale < 1 {
            let renderer = UIGraphicsImageRenderer(size: outputSize)
            outputImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        } else {
            outputImage = image
        }

        if hasAlpha(source), let png = outputImage.pngData() {
            return (png, "image/png", outputSize)
        }
        guard let jpeg = outputImage.jpegData(compressionQuality: 0.88) else {
            return nil
        }
        return (jpeg, "image/jpeg", outputSize)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
#endif
}
