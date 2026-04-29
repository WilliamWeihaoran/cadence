#if os(macOS)
import AppKit
import UniformTypeIdentifiers

enum DocumentExportService {
    static func exportMarkdown(_ doc: Document) {
        let title = doc.title
        let content = doc.content
        exportMarkdown(title: title, content: content)
    }

    static func exportMarkdown(_ note: Note) {
        let title = note.displayTitle
        let content = note.content
        exportMarkdown(title: title, content: content)
    }

    static func exportPDF(_ doc: Document, imageAssets: [MarkdownImageAsset] = []) {
        let title = doc.title
        let content = doc.content
        exportPDF(title: title, content: content, imageAssets: imageAssets)
    }

    static func exportPDF(_ note: Note, imageAssets: [MarkdownImageAsset] = []) {
        let title = note.displayTitle
        let content = note.content
        exportPDF(title: title, content: content, imageAssets: imageAssets)
    }

    private static func exportMarkdown(title: String, content: String) {
        Task { @MainActor in
            presentSavePanel(suggestedName: suggestedName(title: title, pathExtension: "md"), contentType: .plainText) { url in
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func exportPDF(title: String, content: String, imageAssets: [MarkdownImageAsset]) {
        Task { @MainActor in
            presentSavePanel(suggestedName: suggestedName(title: title, pathExtension: "pdf"), contentType: .pdf) { url in
                guard let pdfData = renderedPDFData(content: content, imageAssets: imageAssets) else { return }
                try? pdfData.write(to: url)
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
    private static func renderedPDFData(content: String, imageAssets: [MarkdownImageAsset]) -> Data? {
        let pageWidth: CGFloat = 612
        let horizontalInset: CGFloat = 42
        let verticalInset: CGFloat = 42
        let contentWidth = pageWidth - (horizontalInset * 2)
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
        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.string = renderedContent
        MarkdownStylist.apply(to: textView)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = max(ceil(usedRect.height + (verticalInset * 2)), 240)
        textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: documentHeight)

        return textView.dataWithPDF(inside: textView.bounds)
    }
}
#endif
