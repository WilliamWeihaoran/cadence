#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

enum MarkdownEditorMetrics {
    static let textInset: CGFloat = 20
    static let lineFragmentPadding: CGFloat = 5
    static let firstTextColumnInset: CGFloat = textInset + lineFragmentPadding
}

struct MarkdownEditor: View {
    @Binding var text: String
    var showsToolbar = true
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    var onOpenNoteReference: (UUID?, String) -> Void = { _, _ in }
    var onOpenTaskReference: (UUID?, String) -> Void = { _, _ in }
    var onCreateEmbeddedTask: (String) -> MarkdownReferenceSuggestion? = { _ in nil }
    var onToggleEmbeddedTask: (UUID) -> Void = { _ in }
    var onOpenEmbeddedTask: (UUID) -> Void = { _ in }
    var onTextViewChanged: (CadenceTextView) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @State private var textView: CadenceTextView?

    @MainActor private var noteSuggestions: [MarkdownReferenceSuggestion] {
        referenceNotes
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            .map(MarkdownReferenceSuggestion.note)
    }

    @MainActor private var taskSuggestions: [MarkdownReferenceSuggestion] {
        referenceTasks
            .filter { !$0.isCancelled }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map(MarkdownReferenceSuggestion.task)
    }

    @MainActor private var referenceSuggestions: [MarkdownReferenceSuggestion] {
        noteSuggestions + taskSuggestions
    }

    @MainActor private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(uniqueKeysWithValues: referenceTasks.map { ($0.id, MarkdownTaskEmbedRenderInfo.task($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                MarkdownEditorToolbar(
                    textView: textView,
                    noteSuggestions: noteSuggestions,
                    taskSuggestions: taskSuggestions,
                    onChooseImages: chooseImages
                )
            }

            MarkdownEditorView(
                text: $text,
                imageAssets: imageAssets,
                onCreateImages: createAssets,
                onResizeImage: resizeImage,
                onChooseImages: chooseImages,
                referenceSuggestions: referenceSuggestions,
                taskEmbedInfos: taskEmbedInfos,
                onOpenReference: openReference,
                onCreateEmbeddedTask: onCreateEmbeddedTask,
                onToggleEmbeddedTask: onToggleEmbeddedTask,
                onOpenEmbeddedTask: onOpenEmbeddedTask,
                onTextViewChanged: {
                    textView = $0
                    onTextViewChanged($0)
                }
            )
        }
    }

    private func createAssets(images: [NSImage], urls: [URL]) -> [MarkdownImageAsset] {
        var assets = MarkdownImageAssetService.createAssets(fromFileURLs: urls, in: modelContext)
        assets.append(contentsOf: images.compactMap {
            MarkdownImageAssetService.createAsset(from: $0, in: modelContext)
        })
        try? modelContext.save()
        return assets
    }

    private func resizeImage(id: UUID, width: CGFloat) {
        MarkdownImageAssetService.setDisplayWidth(width, for: id, in: imageAssets)
        try? modelContext.save()
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let assets = createAssets(images: [], urls: panel.urls)
            insertAssets(assets)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func insertAssets(_ assets: [MarkdownImageAsset]) {
        guard !assets.isEmpty else { return }
        if let textView {
            textView.insertMarkdownImages(assets)
        } else {
            let markdown = assets.map { MarkdownImageAssetService.markdown(for: $0) }.joined(separator: "\n\n")
            text += text.hasSuffix("\n") || text.isEmpty ? markdown + "\n" : "\n\n\(markdown)\n"
        }
    }

    private func openReference(_ target: MarkdownReferenceTarget) {
        switch target.kind {
        case .note:
            onOpenNoteReference(target.id, target.title)
        case .task:
            onOpenTaskReference(target.id, target.title)
        }
    }
}

private struct MarkdownEditorToolbar: View {
    let textView: CadenceTextView?
    let noteSuggestions: [MarkdownReferenceSuggestion]
    let taskSuggestions: [MarkdownReferenceSuggestion]
    let onChooseImages: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                MarkdownToolbarTextButton(title: "H1", help: "Heading 1") {
                    textView?.performMarkdownFormatCommand(.heading(1))
                }
                MarkdownToolbarTextButton(title: "H2", help: "Heading 2") {
                    textView?.performMarkdownFormatCommand(.heading(2))
                }
                toolbarDivider
                MarkdownToolbarButton(systemName: "bold", help: "Bold") {
                    textView?.performMarkdownFormatCommand(.bold)
                }
                MarkdownToolbarButton(systemName: "italic", help: "Italic") {
                    textView?.performMarkdownFormatCommand(.italic)
                }
                MarkdownToolbarButton(systemName: "strikethrough", help: "Strikethrough") {
                    textView?.performMarkdownFormatCommand(.strikethrough)
                }
                MarkdownToolbarButton(systemName: "highlighter", help: "Highlight") {
                    textView?.performMarkdownFormatCommand(.highlight)
                }
                MarkdownToolbarButton(systemName: "chevron.left.forwardslash.chevron.right", help: "Inline code") {
                    textView?.performMarkdownFormatCommand(.inlineCode)
                }
                toolbarDivider
                MarkdownToolbarButton(systemName: "link", help: "Link") {
                    textView?.performMarkdownFormatCommand(.link)
                }
                MarkdownReferenceMenuButton(
                    systemName: "text.badge.plus",
                    help: "Note link",
                    emptyTitle: "Blank Note Link",
                    suggestions: noteSuggestions,
                    blankAction: { textView?.performMarkdownFormatCommand(.noteLink) },
                    selectAction: { textView?.insertMarkdownReference($0.markdown) }
                )
                MarkdownReferenceMenuButton(
                    systemName: "checkmark.circle",
                    help: "Task reference",
                    emptyTitle: "Blank Task Reference",
                    suggestions: taskSuggestions,
                    blankAction: { textView?.performMarkdownFormatCommand(.taskReference) },
                    selectAction: { textView?.insertMarkdownReference($0.markdown) }
                )
                toolbarDivider
                MarkdownToolbarButton(systemName: "list.bullet", help: "Bulleted list") {
                    textView?.performMarkdownFormatCommand(.unorderedList)
                }
                MarkdownToolbarButton(systemName: "list.number", help: "Numbered list") {
                    textView?.performMarkdownFormatCommand(.orderedList)
                }
                MarkdownToolbarButton(systemName: "checklist", help: "Checklist") {
                    textView?.performMarkdownFormatCommand(.todoList)
                }
                MarkdownToolbarButton(systemName: "text.quote", help: "Quote") {
                    textView?.performMarkdownFormatCommand(.quote)
                }
                toolbarDivider
                MarkdownToolbarButton(systemName: "curlybraces.square", help: "Code block") {
                    textView?.performMarkdownFormatCommand(.codeBlock)
                }
                MarkdownToolbarButton(systemName: "minus", help: "Divider") {
                    textView?.performMarkdownFormatCommand(.divider)
                }
                MarkdownToolbarButton(systemName: "photo", help: "Image") {
                    onChooseImages()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(Theme.surfaceElevated)
        .overlay(alignment: .bottom) {
            Divider().background(Theme.borderSubtle)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}

private struct MarkdownReferenceMenuButton: View {
    let systemName: String
    let help: String
    let emptyTitle: String
    let suggestions: [MarkdownReferenceSuggestion]
    let blankAction: () -> Void
    let selectAction: (MarkdownReferenceSuggestion) -> Void

    var body: some View {
        Menu {
            if suggestions.isEmpty {
                Button(emptyTitle, action: blankAction)
            } else {
                Button(emptyTitle, action: blankAction)
                Divider()
                ForEach(suggestions.prefix(12)) { suggestion in
                    Button {
                        selectAction(suggestion)
                    } label: {
                        Text(suggestion.title)
                    }
                }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .cadenceHoverHighlight(cornerRadius: 7, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .help(help)
    }
}

private struct MarkdownToolbarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .cadenceHoverHighlight(cornerRadius: 7, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .help(help)
    }
}

private struct MarkdownToolbarTextButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 30, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .cadenceHoverHighlight(cornerRadius: 7, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .help(help)
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var imageAssets: [MarkdownImageAsset] = []
    var onCreateImages: ([NSImage], [URL]) -> [MarkdownImageAsset] = { _, _ in [] }
    var onResizeImage: (UUID, CGFloat) -> Void = { _, _ in }
    var onChooseImages: () -> Void = {}
    var referenceSuggestions: [MarkdownReferenceSuggestion] = []
    var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var onOpenReference: (MarkdownReferenceTarget) -> Void = { _ in }
    var onCreateEmbeddedTask: (String) -> MarkdownReferenceSuggestion? = { _ in nil }
    var onToggleEmbeddedTask: (UUID) -> Void = { _ in }
    var onOpenEmbeddedTask: (UUID) -> Void = { _ in }
    var onTextViewChanged: (CadenceTextView) -> Void = { _ in }

    func makeNSView(context: NSViewRepresentableContext<MarkdownEditorView>) -> NSScrollView {
        let scrollView = MarkdownEditorScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#0f1117")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CadenceTextView(frame: NSRect(origin: .zero, size: CGSize(width: contentSize.width, height: 0)),
                                       textContainer: textContainer)
        textView.frame = NSRect(origin: .zero, size: CGSize(width: contentSize.width, height: 0))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                        height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true       // must be true to preserve custom attributes
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = NSColor(hex: "#0f1117")
        textView.insertionPointColor = NSColor(hex: "#4a9eff")
        textView.textContainerInset = NSSize(
            width: MarkdownEditorMetrics.textInset,
            height: MarkdownEditorMetrics.textInset
        )
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        configure(textView, context: context)

        scrollView.documentView = textView
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.update(parent: self)
        if let cadenceTextView = textView as? CadenceTextView {
            configure(cadenceTextView, context: context)
        }
        let displayText = MarkdownListSupport.normalizedMarkdownListPrefixes(in: text)
        if textView.string != displayText {
            let sel = textView.selectedRange()
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                textView.string = displayText
                MarkdownStylist.apply(to: textView)
            }
            let safe = NSRange(location: min(sel.location, (displayText as NSString).length), length: 0)
            textView.setSelectedRange(safe)
        } else {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: textView)
            }
        }
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
    }

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(parent: self)
    }

    private func configure(_ textView: CadenceTextView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        textView.markdownImageAssets = Dictionary(
            uniqueKeysWithValues: imageAssets.compactMap { asset in
                MarkdownImageAssetService.renderAsset(for: asset.id, in: imageAssets).map { (asset.id, $0) }
            }
        )
        if textView.markdownTaskEmbeds != taskEmbedInfos {
            textView.markdownTaskEmbedRects.removeAll()
            textView.markdownTaskEmbeds = taskEmbedInfos
        }
        textView.referenceSuggestions = referenceSuggestions
        textView.onOpenMarkdownReference = onOpenReference
        textView.onCreateEmbeddedMarkdownTask = onCreateEmbeddedTask
        textView.onToggleEmbeddedMarkdownTask = onToggleEmbeddedTask
        textView.onOpenEmbeddedMarkdownTask = onOpenEmbeddedTask
        textView.onCreateMarkdownImages = onCreateImages
        textView.onResizeMarkdownImage = onResizeImage
        textView.registerForDraggedTypes([.fileURL, .tiff, .png])
        DispatchQueue.main.async {
            onTextViewChanged(textView)
        }
    }
}

private final class MarkdownEditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        MarkdownEditorScrollSupport.refreshLayout(in: self)
    }
}

enum MarkdownEditorScrollSupport {
    static func preservingScrollPosition(in scrollView: NSScrollView, _ updates: () -> Void) {
        let clipView = scrollView.contentView
        let originalOrigin = clipView.bounds.origin
        updates()
        restoreScrollPosition(originalOrigin, in: scrollView)
    }

    static func refreshLayout(in scrollView: NSScrollView) {
        preservingScrollPosition(in: scrollView) {
            refreshLayoutWithoutRestoringScroll(in: scrollView)
        }
    }

    private static func refreshLayoutWithoutRestoringScroll(in scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let contentSize = scrollView.contentSize
        let targetWidth = max(1, contentSize.width)
        let currentSize = textView.frame.size

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)

        if abs(currentSize.width - targetWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: targetWidth, height: max(currentSize.height, contentSize.height)))
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let targetHeight = max(
            contentSize.height,
            ceil(usedRect.maxY + textView.textContainerInset.height * 2 + 1)
        )

        let updatedSize = textView.frame.size
        if abs(updatedSize.height - targetHeight) > 0.5 || abs(updatedSize.width - targetWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        }
    }

    private static func restoreScrollPosition(_ origin: NSPoint, in scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let restoredOrigin = NSPoint(
            x: min(max(origin.x, 0), maxX),
            y: min(max(origin.y, 0), maxY)
        )

        guard abs(clipView.bounds.origin.x - restoredOrigin.x) > 0.5 ||
                abs(clipView.bounds.origin.y - restoredOrigin.y) > 0.5 else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            clipView.scroll(to: restoredOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}
#endif
