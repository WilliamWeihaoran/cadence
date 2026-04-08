#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: NSViewRepresentableContext<MarkdownEditorView>) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#0f1117")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CadenceTextView()
        let contentSize = scrollView.contentSize
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            MarkdownStylist.apply(to: textView)
            let safe = NSRange(location: min(sel.location, (text as NSString).length), length: 0)
            textView.setSelectedRange(safe)
        }
    }

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(parent: self)
    }
}
#endif
