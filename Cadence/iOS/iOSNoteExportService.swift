#if os(iOS)
import SwiftUI
import UIKit

/// The iOS half of note export: the bytes, for both formats.
///
/// **This is a second PDF renderer, and it was not avoidable.** macOS produces its PDF by running
/// `MarkdownStylist.apply` over an offscreen `NSTextView` and asking AppKit for `dataWithPDF` —
/// there is no un-guarding that, unlike the seven services lifted out of `#if os(macOS)` before it.
/// So iOS rebuilds the mechanism with the pieces the iOS editor already has, and the whole design
/// constraint is that the two documents must not drift apart:
///
/// - **The page is not this file's decision.** `NotePDFRenderOptions` (page width, insets, the
///   minimum height, and the content width a rendered block is measured against) is shared, in
///   `Cadence/Services/CadenceNoteExportSupport.swift`. So are the filename and the live task-title
///   resolution. Nothing about the page is spelled twice.
/// - **The styling is not this file's decision either.** The attributed string is
///   `iOSMarkdownStyler.attributedString`, the *same* call the editor canvas makes, at the same
///   content width. An export therefore matches what the user was looking at, and a styling fix
///   lands in both without anyone remembering.
/// - **The block canvases need `iOSMarkdownBlockCanvasLayoutManager`.** Tables, fenced code,
///   dividers, images and task-embed cards are not glyphs on iOS: they are pre-rendered images
///   hung on `cadenceMarkdownBlockCanvas` over a hidden run, painted by that layout manager's
///   `drawGlyphs` override. Laying the same storage out through a plain `NSLayoutManager` produces
///   a PDF with tall empty gaps where every table and image should be — the exact failure that
///   attribute exists to fix. This is why the stack is built by hand rather than by taking a
///   `UITextView` off the shelf, and why it is TextKit 1.
///
/// **One tall page, matching macOS.** Drawing straight into the PDF context rather than through
/// `layer.render(in:)` is deliberate: a view hierarchy that is not in a window renders
/// inconsistently, and the layout manager is the thing that knows how to paint this content
/// anyway.
enum iOSNoteExportService {
    /// The bytes for `format`, or `nil` if a PDF could not be rendered.
    ///
    /// Markdown cannot fail: the resolved content is a `String` and UTF-8 encoding of a Swift
    /// string is total.
    @MainActor
    static func exportData(
        for note: Note,
        as format: NoteExportFormat,
        imageAssets: [MarkdownImageAsset] = [],
        embeddedTasks: [AppTask] = []
    ) -> Data? {
        let content = NoteExportSupport.resolvedContent(note.content, embeddedTasks: embeddedTasks)

        switch format {
        case .markdown:
            return Data(content.utf8)
        case .pdf:
            return renderedPDFData(
                content: content,
                imageAssets: imageAssets,
                taskEmbeds: NoteExportSupport.taskEmbedRenderInfos(for: embeddedTasks)
            )
        }
    }

    @MainActor
    static func renderedPDFData(
        content: String,
        imageAssets: [MarkdownImageAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        options: NotePDFRenderOptions = NotePDFRenderOptions()
    ) -> Data? {
        let contentWidth = options.contentWidth
        let renderedContent = MarkdownListSupport.normalizedMarkdownListPrefixes(in: content)

        let styled = iOSMarkdownStyler.attributedString(
            for: renderedContent,
            imageAssets: imageAssets,
            taskEmbeds: taskEmbeds,
            contentWidth: contentWidth
        )

        let textStorage = NSTextStorage(attributedString: styled)
        let layoutManager = iOSMarkdownBlockCanvasLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = options.documentHeight(forContentHeight: usedRect.height)
        let pageRect = CGRect(x: 0, y: 0, width: options.pageWidth, height: documentHeight)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let origin = CGPoint(x: options.horizontalInset, y: options.verticalInset)

        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [kCGPDFContextCreator as String: "Cadence"]

        return UIGraphicsPDFRenderer(bounds: pageRect, format: rendererFormat).pdfData { context in
            context.beginPage()
            // Deliberately dark, for the same reason the macOS renderer paints `Theme.nsBg`: the
            // glyphs come out in the app's light-on-dark palette because they were styled by the
            // live editor styler. A paper-white page here is near-white text on white.
            UIColor(Theme.bg).setFill()
            context.fill(pageRect)

            guard glyphRange.length > 0 else { return }
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }
    }
}
#endif
