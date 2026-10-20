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

/// **The panel's hosting controller, and the two things a view hung inside a `UITextView` does
/// not get for free** ([[T-3243]]).
///
/// *Escape.* The Mac panel cancels on `onExitCommand`; a `UIHostingController` has no equivalent
/// until someone gives it one. It sits in the responder chain above every control the panel draws
/// (a view's next responder is its own view controller), so one `UIKeyCommand` here answers
/// Escape from anywhere inside the panel. Escape with the caret back in the note text is the text
/// view's own (`iOSMarkdownTextView.inlineTaskPanelCancelHandler`) — the Mac rule is that the key
/// works from either side.
///
/// *Keyboard avoidance.* SwiftUI's reaches the note's editor, never a subview of its `UITextView`,
/// so focusing the panel's title or notes field raised the keyboard straight over Save and Cancel
/// with nothing scrolling them clear. Observed on `Cadence-iPadPro11` before this. The geometry is
/// `CadenceTaskInlinePanelReservation.keyboardRevealOffset`; what is left here is reading UIKit's
/// rects and moving the note.
final class iOSMarkdownInlineTaskPanelHost: UIHostingController<iOSMarkdownInlineTaskPanelFrame> {
    /// Escape, pressed with focus inside the panel. Set by the editor to the panel's close.
    var onCancelKey: (() -> Void)?

    /// The note the panel hangs in — the scroll view the keyboard fix drives, and the one the
    /// controller's detach reaches back through to drop its Escape handler.
    weak var noteTextView: UITextView?

    /// The keyboard's frame in screen coordinates, `nil` once it has gone. Read from the
    /// notification rather than `keyboardLayoutGuide`, because the guide tracks a view's own
    /// layout and this view is positioned by frame inside a scroll view's content.
    private var keyboardFrameInScreen: CGRect?

    /// The bottom inset this host added to the note for the keyboard, so it can take exactly that
    /// much off again.
    private var addedBottomInset: CGFloat = 0

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelFromKeyCommand))]
            + (super.keyCommands ?? [])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        // A move between two of the panel's own fields raises no new keyboard, and the second
        // field can be the one under it.
        center.addObserver(
            self,
            selector: #selector(editingDidBegin),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(editingDidBegin),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
    }

    @objc private func cancelFromKeyCommand() {
        onCancelKey?()
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        keyboardFrameInScreen = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        scheduleKeyboardReveal()
    }

    @objc private func keyboardWillHide() {
        keyboardFrameInScreen = nil
        releaseKeyboardInset()
    }

    @objc private func editingDidBegin() {
        scheduleKeyboardReveal()
    }

    /// Next runloop: the notification arrives before the field is first responder and before the
    /// panel has laid out around it, and both are what the reveal measures.
    private func scheduleKeyboardReveal() {
        DispatchQueue.main.async { [weak self] in
            self?.revealFocusedFieldAboveKeyboard()
        }
    }

    private func revealFocusedFieldAboveKeyboard() {
        guard let textView = noteTextView,
              view.superview === textView,
              !view.isHidden,
              textView.window != nil else { return }
        guard let focused = Self.firstResponder(in: view) else {
            // The caret went back to the note text, which scrolls itself.
            releaseKeyboardInset()
            return
        }

        // What the keyboard is sitting on, in the note's own coordinates. `from: nil` is the text
        // view's window, which is the space the notification's rect is in.
        let keyboardTop = keyboardFrameInScreen.map { textView.convert($0, from: nil).minY }
        applyKeyboardInset(max(0, textView.bounds.maxY - (keyboardTop ?? textView.bounds.maxY)), to: textView)

        let inset = textView.adjustedContentInset
        let visible = textView.bounds.inset(
            by: UIEdgeInsets(top: inset.top, left: 0, bottom: inset.bottom, right: 0)
        )
        let delta = CadenceTaskInlinePanelReservation.keyboardRevealOffset(
            focusedRect: textView.convert(focused.bounds, from: focused),
            panelFrame: view.frame,
            visibleRect: visible
        )
        guard abs(delta) > 0.5 else { return }
        let lowest = max(-inset.top, textView.contentSize.height + inset.bottom - textView.bounds.height)
        let offset = min(max(textView.contentOffset.y + delta, -inset.top), lowest)
        guard abs(offset - textView.contentOffset.y) > 0.5 else { return }
        textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: offset), animated: true)
    }

    /// **Why the note is given a bottom inset and not just a bigger offset.** The keyboard takes
    /// visible height without adding content, so a panel near the end of a note has nowhere to
    /// scroll to: the offset the reveal wants is past the end, and the note springs back. The
    /// inset is the keyboard's overlap, added here and taken off again by `releaseKeyboardInset`,
    /// so every one of these is reversed.
    private func applyKeyboardInset(_ wanted: CGFloat, to textView: UITextView) {
        let change = wanted - addedBottomInset
        guard abs(change) > 0.5 else { return }
        textView.contentInset.bottom += change
        textView.verticalScrollIndicatorInsets.bottom += change
        addedBottomInset = wanted
    }

    /// Gives back whatever `applyKeyboardInset` took. Safe to call when it took nothing, and
    /// called on the way out as well as when the keyboard goes, so the note is never left inset.
    func releaseKeyboardInset() {
        guard let textView = noteTextView else {
            addedBottomInset = 0
            return
        }
        applyKeyboardInset(0, to: textView)
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}

extension iOSMarkdownEditor.Coordinator {
    static func makeInlineTaskPanelController() -> CadenceTaskInlinePanelController<iOSMarkdownInlineTaskPanelHost> {
        CadenceTaskInlinePanelController { host in
            host.releaseKeyboardInset()
            (host.noteTextView as? iOSMarkdownTextView)?.inlineTaskPanelCancelHandler = nil
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
        let close: () -> Void = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.closeInlineTaskPanel(in: textView)
        }
        guard let content = makeContent(taskID, close) else { return false }

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
            host.noteTextView = textView
            host.onCancelKey = close
            host.view.backgroundColor = .clear
            host.view.accessibilityIdentifier = iOSMarkdownInlineTaskPanel.accessibilityIdentifier
            let height = iOSMarkdownInlineTaskPanelFrame.idealHeight(of: content, width: width)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            textView.addSubview(host.view)
            if let markdownTextView = textView as? iOSMarkdownTextView {
                markdownTextView.inlineTaskPanelView = host.view
                // Escape from the note text, once there is a panel for it to cancel.
                markdownTextView.inlineTaskPanelCancelHandler = close
            }
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
