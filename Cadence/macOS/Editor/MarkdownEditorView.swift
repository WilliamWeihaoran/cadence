#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

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
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes

        scrollView.documentView = textView
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let displayText = MarkdownListSupport.normalizedMarkdownListPrefixes(in: text)
        if textView.string != displayText {
            let sel = textView.selectedRange()
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                textView.string = displayText
                MarkdownStylist.apply(to: textView)
            }
            let safe = NSRange(location: min(sel.location, (displayText as NSString).length), length: 0)
            textView.setSelectedRange(safe)
        }
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
    }

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(parent: self)
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
