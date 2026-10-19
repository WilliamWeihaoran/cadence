#if os(iOS)
import SwiftData
import SwiftUI
import UIKit

/// **The task panel, opened in the note's own text flow on iOS** ([[T-1481]], iOS half).
///
/// A tap on an embedded task's card used to open the full inspector sheet. With a content factory
/// handed to `iOSMarkdownEditor(inlineTaskPanelContent:)`, the same tap opens the shared
/// `CadenceTaskInlinePanel` directly under the card instead, and the note reflows around it.
///
/// Where it sits and when it goes are decided in `CadenceTaskInlinePanelReservation` and
/// `CadenceTaskInlinePanelController` (platform-neutral, measured on macOS); this file only hangs
/// a `UIHostingController`'s view inside the `UITextView`. Nothing enters the text storage, so
/// undo, selection and copy see the note exactly as before.
///
/// On an iPhone the panel plus the keyboard fills the screen much as the sheet did: the win is one
/// code path for both platforms, not a visible difference.
typealias iOSMarkdownInlineTaskPanelContent = (_ taskID: UUID, _ close: @escaping () -> Void) -> AnyView?

enum iOSMarkdownInlineTaskPanel {
    static let accessibilityIdentifier = "markdown.inlineTaskPanel"

    /// The one view a note host hands the editor for `task`: the shared panel, carded, on the
    /// host's model context.
    static func content(
        for task: AppTask,
        in modelContext: ModelContext,
        close: @escaping () -> Void,
        onSaved: @escaping (AppTask) -> Void = { _ in }
    ) -> AnyView {
        AnyView(
            CadenceTaskInlinePanel(task: task, onClose: close, onSaved: onSaved)
                .cadenceCard(cornerRadius: Theme.radiusPanel)
                .modelContext(modelContext)
        )
    }
}

/// The hosted root: the panel at the width the note gives it, reporting its height back so the
/// reservation follows it as rows expand and collapse.
struct iOSMarkdownInlineTaskPanelFrame: View {
    var width: CGFloat
    let content: AnyView
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                onHeightChange(height)
            }
            // Top-aligned, so a panel that has just grown extends downward for the one pass before
            // its host catches up, rather than centring in a frame that is too short.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The height the panel wants at `width`, measured before it is laid out in the note — the
    /// root above fills whatever frame it is given, so it cannot be asked itself.
    static func idealHeight(of content: AnyView, width: CGFloat) -> CGFloat {
        let probe = UIHostingController(
            rootView: content.frame(width: width).fixedSize(horizontal: false, vertical: true)
        )
        let size = probe.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return ceil(size.height)
    }
}

typealias iOSMarkdownInlineTaskPanelHost = UIHostingController<iOSMarkdownInlineTaskPanelFrame>

extension iOSMarkdownEditor.Coordinator {
    static func makeInlineTaskPanelController() -> CadenceTaskInlinePanelController<iOSMarkdownInlineTaskPanelHost> {
        CadenceTaskInlinePanelController { host in
            host.view.removeFromSuperview()
        }
    }

    /// Opens the panel under `taskID`'s card. `false` when the host had no panel to give for it
    /// (the task is gone), so the caller can fall back to the inspector.
    func presentInlineTaskPanel(
        taskID: UUID,
        in textView: UITextView,
        makeContent: iOSMarkdownInlineTaskPanelContent
    ) -> Bool {
        if inlineTaskPanel.openTaskID == taskID { return true }
        guard let content = makeContent(taskID, { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.closeInlineTaskPanel(in: textView)
        }) else { return false }

        let width = CadenceTaskInlinePanelReservation.panelWidth(contentWidth: textView.markdownContentWidth)
        inlineTaskPanel.present(taskID: taskID) {
            let host = iOSMarkdownInlineTaskPanelHost(
                rootView: iOSMarkdownInlineTaskPanelFrame(
                    width: width,
                    content: content,
                    onHeightChange: { [weak self, weak textView] height in
                        // Reported from inside SwiftUI's layout pass; restyling the note from there
                        // would re-enter it.
                        DispatchQueue.main.async {
                            guard let self, let textView else { return }
                            self.updateInlineTaskPanelHeight(height, for: taskID, in: textView)
                        }
                    }
                )
            )
            host.view.backgroundColor = .clear
            host.view.accessibilityIdentifier = iOSMarkdownInlineTaskPanel.accessibilityIdentifier
            let height = iOSMarkdownInlineTaskPanelFrame.idealHeight(of: content, width: width)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            textView.addSubview(host.view)
            (textView as? iOSMarkdownTextView)?.inlineTaskPanelView = host.view
            return (host, height)
        }
        restyleForInlineTaskPanel(textView)
        revealInlineTaskPanel(in: textView)
        return true
    }

    /// Closes the panel and gives the note its space back. Safe to call when nothing is open.
    func closeInlineTaskPanel(in textView: UITextView) {
        guard inlineTaskPanel.close() else { return }
        restyleForInlineTaskPanel(textView)
    }

    func updateInlineTaskPanelHeight(_ height: CGFloat, for taskID: UUID, in textView: UITextView) {
        guard inlineTaskPanel.updateHeight(height, for: taskID) else { return }
        restyleForInlineTaskPanel(textView)
    }

    /// Called from `applyMarkdownStyle` straight after the styled string lands: reserves the open
    /// panel's room in the embed's paragraph and keeps the card centred where it was.
    func applyInlineTaskPanelReservation(to storage: NSTextStorage) {
        guard let taskID = inlineTaskPanel.openTaskID,
              let spacing = inlineTaskPanel.applyReservation(to: storage),
              let location = CadenceTaskInlinePanelReservation.embedLocation(for: taskID, in: storage),
              let canvas = storage.attribute(.cadenceMarkdownBlockCanvas, at: location, effectiveRange: nil)
                as? iOSMarkdownBlockCanvas else { return }
        storage.addAttribute(
            .cadenceMarkdownBlockCanvas,
            value: iOSMarkdownBlockCanvas(
                image: canvas.image,
                isBlock: canvas.isBlock,
                yOffset: CadenceTaskInlinePanelReservation.centredCanvasOffset(canvas.yOffset, reservedSpacing: spacing),
                leadingInset: canvas.leadingInset
            ),
            range: NSRange(location: location, length: 1)
        )
    }

    /// Lays the hosted panel over the space its embed reserved. Run after every styling pass.
    func positionInlineTaskPanel(in textView: UITextView) {
        guard let host = inlineTaskPanel.host, let height = inlineTaskPanel.session?.height else { return }
        guard let card = inlineTaskPanelCardRect(in: textView) else {
            host.view.isHidden = true
            return
        }
        let contentWidth = textView.markdownContentWidth
        let frame = CadenceTaskInlinePanelReservation.panelFrame(
            cardRect: card,
            contentWidth: contentWidth,
            height: height
        ).integral
        if host.rootView.width != frame.width {
            host.rootView.width = frame.width
        }
        if host.view.frame != frame {
            host.view.frame = frame
        }
        host.view.isHidden = false
    }

    // MARK: - Private

    private func restyleForInlineTaskPanel(_ textView: UITextView) {
        let selection = textView.selectedRange
        applyMarkdownStyle(to: textView, text: textView.text ?? "")
        textView.selectedRange = clamped(selection, in: textView.textStorage)
    }

    /// The card and the panel on screen, and the card alone if both do not fit — the panel is
    /// about that task, so the task stays visible.
    private func revealInlineTaskPanel(in textView: UITextView) {
        guard let card = inlineTaskPanelCardRect(in: textView),
              let panel = inlineTaskPanel.host?.view.frame else { return }
        let both = card.union(panel)
        let visibleHeight = textView.bounds.height - textView.adjustedContentInset.top - textView.adjustedContentInset.bottom
        textView.scrollRectToVisible(both.height <= visibleHeight ? both : card, animated: true)
    }

    /// The open embed's card, in text-view coordinates — the rect the canvas is painted into.
    private func inlineTaskPanelCardRect(in textView: UITextView) -> CGRect? {
        guard let taskID = inlineTaskPanel.openTaskID else { return nil }
        let storage = textView.textStorage
        guard let location = CadenceTaskInlinePanelReservation.embedLocation(for: taskID, in: storage),
              location < storage.length,
              let canvas = storage.attribute(.cadenceMarkdownBlockCanvas, at: location, effectiveRange: nil)
                as? iOSMarkdownBlockCanvas else { return nil }
        let layoutManager = textView.layoutManager
        layoutManager.ensureLayout(for: textView.textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return iOSMarkdownBlockCanvas.blockRect(
            inLineFragment: fragment,
            size: canvas.image.size,
            leadingInset: canvas.leadingInset,
            yOffset: canvas.yOffset
        )
        .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
    }
}
#endif
