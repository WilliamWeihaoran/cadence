#if os(macOS)
import AppKit
import UniformTypeIdentifiers

enum NoteExportFormat {
    case markdown
    case pdf

    var pathExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return .plainText
        case .pdf: return .pdf
        }
    }
}

struct NotePDFRenderOptions {
    var pageWidth: CGFloat = 612
    var horizontalInset: CGFloat = 42
    var verticalInset: CGFloat = 42
    var minimumHeight: CGFloat = 240

    nonisolated init(
        pageWidth: CGFloat = 612,
        horizontalInset: CGFloat = 42,
        verticalInset: CGFloat = 42,
        minimumHeight: CGFloat = 240
    ) {
        self.pageWidth = pageWidth
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.minimumHeight = minimumHeight
    }
}

enum NoteExportService {
    static func export(_ note: Note, as format: NoteExportFormat, imageAssets: [MarkdownImageAsset] = []) {
        let title = note.displayTitle
        let content = note.content
        presentSavePanelOnMainQueue(
            suggestedName: suggestedName(title: title, pathExtension: format.pathExtension),
            contentType: format.contentType
        ) { url in
            switch format {
            case .markdown:
                try? content.write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                guard let pdfData = renderedPDFData(content: content, imageAssets: imageAssets) else { return }
                try? pdfData.write(to: url)
            }
        }
    }

    static func exportMarkdown(_ note: Note) {
        export(note, as: .markdown)
    }

    static func exportPDF(_ note: Note, imageAssets: [MarkdownImageAsset] = []) {
        export(note, as: .pdf, imageAssets: imageAssets)
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

    private static func suggestedName(title: String, pathExtension: String) -> String {
        let baseName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (baseName.isEmpty ? "Untitled Note" : baseName) + ".\(pathExtension)"
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
        options: NotePDFRenderOptions = NotePDFRenderOptions()
    ) -> Data? {
        let contentWidth = options.pageWidth - (options.horizontalInset * 2)
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
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(hex: "#0f1117")
        textView.textContainerInset = NSSize(width: options.horizontalInset, height: options.verticalInset)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.string = renderedContent
        MarkdownStylist.apply(to: textView)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = max(ceil(usedRect.height + (options.verticalInset * 2)), options.minimumHeight)
        textView.frame = NSRect(x: 0, y: 0, width: options.pageWidth, height: documentHeight)

        return textView.dataWithPDF(inside: textView.bounds)
    }
}
#endif
