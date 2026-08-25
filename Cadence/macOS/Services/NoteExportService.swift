#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// The macOS half of note export: an `NSSavePanel` and a PDF drawn by the live editor.
///
/// **`NoteExportFormat` and `NotePDFRenderOptions` used to be declared here**, inside this file's
/// `#if os(macOS)`, along with the filename rule and the live-title resolution. They are
/// `Cadence/Services/CadenceNoteExportSupport.swift` now, because iOS necessarily gets a second PDF
/// renderer (T-194) and two renderers deciding their own page width and their own margins are two
/// documents. This file keeps only what genuinely needs AppKit — and it does need it: the PDF is
/// produced by running `MarkdownStylist.apply` over an offscreen `NSTextView` and asking it for
/// `dataWithPDF`. That is not a guard to lift; it is a mechanism iOS has to rebuild.
enum NoteExportService {
    /// Writes the note out, with every `[[task:UUID|Title]]` embed named by its **live** task.
    ///
    /// `embeddedTasks` is what makes that possible, and it does two jobs. The markdown file gets the
    /// resolved text, so an export does not carry a title the task was renamed out of months ago.
    /// The PDF gets the same text *and* the render infos: the PDF is produced by running the live
    /// editor styling over an offscreen text view, and a text view with no `markdownTaskEmbeds` map
    /// draws every embed through `MarkdownTaskEmbedRenderInfo.missing(reference:)` — so before this,
    /// exporting a note turned every task card in it into a "missing task" card carrying the stale
    /// cached title.
    static func export(
        _ note: Note,
        as format: NoteExportFormat,
        imageAssets: [MarkdownImageAsset] = [],
        embeddedTasks: [AppTask] = []
    ) {
        let title = note.displayTitle
        let content = NoteExportSupport.resolvedContent(note.content, embeddedTasks: embeddedTasks)
        let taskEmbeds = NoteExportSupport.taskEmbedRenderInfos(for: embeddedTasks)
        presentSavePanelOnMainQueue(
            suggestedName: NoteExportSupport.suggestedFilename(title: title, format: format),
            contentType: format.contentType
        ) { url in
            switch format {
            case .markdown:
                try? content.write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                guard let pdfData = renderedPDFData(
                    content: content,
                    imageAssets: imageAssets,
                    taskEmbeds: taskEmbeds
                ) else { return }
                try? pdfData.write(to: url)
            }
        }
    }

    @MainActor
    private static func presentSavePanelOnMainQueue(
        suggestedName: String,
        contentType: UTType,
        onSave: @MainActor @escaping (URL) -> Void
    ) {
        DispatchQueue.main.async {
            presentSavePanel(suggestedName: suggestedName, contentType: contentType) { url in
                onSave(url)
            }
        }
    }

    @MainActor
    private static func presentSavePanel(
        suggestedName: String,
        contentType: UTType,
        onSave: @MainActor @escaping (URL) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName

        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                onSave(url)
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            panel.begin(completionHandler: save)
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

        let textStorage = NSTextStorage(string: renderedContent)
        let layoutManager = CadenceLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CadenceTextView(frame: .zero, textContainer: textContainer)
        textView.markdownImageAssets = Dictionary(
            uniqueKeysWithValues: imageAssets.compactMap { asset in
                MarkdownImageAssetService.renderAsset(for: asset.id, in: imageAssets).map { (asset.id, $0) }
            }
        )
        textView.markdownTaskEmbeds = taskEmbeds
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        // Deliberately dark: the PDF is rendered by running the *live* editor styling
        // (`MarkdownStylist.apply`) over an offscreen text view, so the glyphs come out in the
        // app's light-on-dark palette. A light page here would render near-white text on white.
        // Keep it matched to the app background rather than paper-white.
        textView.backgroundColor = Theme.nsBg
        textView.textContainerInset = NSSize(width: options.horizontalInset, height: options.verticalInset)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.string = renderedContent
        MarkdownStylist.apply(to: textView)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = options.documentHeight(forContentHeight: usedRect.height)
        textView.frame = NSRect(x: 0, y: 0, width: options.pageWidth, height: documentHeight)

        return textView.dataWithPDF(inside: textView.bounds)
    }
}
#endif
