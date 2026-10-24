#if os(iOS)
import UIKit

final class iOSMarkdownTextView: UITextView {
    var formatCommandHandler: ((MarkdownFormatCommand) -> Void)?
    var indentationCommandHandler: ((Bool) -> Void)?
    var imagePasteHandler: (([UIImage]) -> Bool)?
    var layoutInvalidationHandler: (() -> Void)?
    /// The host's `iOSMarkdownEditingSurface.allowsImageInsertion`, threaded down so the *edit
    /// menu* answer matches the one every other image door already gives (T-504).
    ///
    /// Spelled exactly as `CadenceTextView.allowsMarkdownImageInsertion` is on macOS, because the
    /// two views close the identical door and a reader who has met one should recognise the other.
    /// Read by `canPerformAction(_:withSender:)` below.
    var allowsMarkdownImageInsertion = true
    private var lastMarkdownLayoutSize: CGSize = .zero

    /// TextKit 1, built explicitly — **this is what makes rendered blocks visible at all.**
    ///
    /// `UITextView()` gives you a TextKit 2 view on iOS 16 and later, and TextKit 2 draws an
    /// `NSTextAttachment` only where the text actually contains the attachment character U+FFFC.
    /// Every rendered block in this editor works the other way round: it hangs an attachment on the
    /// block's *first existing character* and hides the rest of the run
    /// (`iOSMarkdownStyler.applyLiveTableBlocks` and its siblings in
    /// `iOSMarkdownStylingBlockSupport.swift`). Under TextKit 2 none of
    /// those images drew. Tables, fenced code blocks and dividers all rendered as a tall empty gap
    /// with one stray `|`, backtick or hyphen where the block should have been — the paragraph
    /// style reserved the canvas's height, and nothing was ever painted into it.
    ///
    /// The rest of the editor assumes TextKit 1 anyway: hit-testing and the marker rects in
    /// `iOSMarkdownEditor` go through `textView.layoutManager`, which is TextKit 1 only. Touching
    /// that property forces UIKit to fall back — silently, mid-session, on whichever gesture gets
    /// there first. Deciding it here instead of tripping over it later is the whole point.
    init() {
        let storage = NSTextStorage()
        let layoutManager = iOSMarkdownBlockCanvasLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("iOSMarkdownTextView is created in code, never from a nib")
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            command("b", [.command], MarkdownFormatCommandTitle.sentenceCase(for: .bold), #selector(applyBoldCommand)),
            command("i", [.command], MarkdownFormatCommandTitle.sentenceCase(for: .italic), #selector(applyItalicCommand)),
            command("e", [.command], MarkdownFormatCommandTitle.sentenceCase(for: .inlineCode), #selector(applyInlineCodeCommand)),
            // T-5882: Cmd+Shift+K, matching macOS. The clash that moved it is the Mac's (Cmd+K is
            // Search there), but one note editor with two different link shortcuts is worse than a
            // key left unbound on iOS, so both tables moved together.
            command("k", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .link), #selector(applyLinkCommand)),
            command("x", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .strikethrough), #selector(applyStrikethroughCommand)),
            command("h", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .highlight), #selector(applyHighlightCommand)),
            command("0", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .paragraph), #selector(applyParagraphCommand)),
            command("1", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(1)), #selector(applyHeading1Command)),
            command("2", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(2)), #selector(applyHeading2Command)),
            command("3", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(3)), #selector(applyHeading3Command)),
            command("4", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(4)), #selector(applyHeading4Command)),
            command("5", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(5)), #selector(applyHeading5Command)),
            command("6", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .heading(6)), #selector(applyHeading6Command)),
            command("7", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .orderedList), #selector(applyOrderedListCommand)),
            command("8", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .unorderedList), #selector(applyUnorderedListCommand)),
            command("9", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .quote), #selector(applyQuoteCommand)),
            command("t", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .todoList), #selector(applyChecklistCommand)),
            command("c", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .codeBlock), #selector(applyCodeBlockCommand)),
            command("d", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .divider), #selector(applyDividerCommand)),
            command("n", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .noteLink), #selector(applyNoteLinkCommand)),
            command("r", [.command, .alternate], MarkdownFormatCommandTitle.sentenceCase(for: .taskReference), #selector(applyTaskReferenceCommand)),
            // No `MarkdownFormatCommand` case: these drive `indentationCommandHandler`, not
            // `apply(_:)`, so there is nothing in the shared table to read. Sentence case by hand.
            command("\t", [], "Indent list", #selector(indentListCommand)),
            command("\t", [.shift], "Outdent list", #selector(outdentListCommand))
        ]
            + inlineTaskPanelKeyCommands
            + (super.keyCommands ?? [])
    }

    private var inlineTaskPanelKeyCommands: [UIKeyCommand] {
        guard inlineTaskPanelCancelHandler != nil, inlineTaskPanelView != nil else { return [] }
        return [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelInlineTaskPanel))]
    }

    @objc private func cancelInlineTaskPanel() {
        inlineTaskPanelCancelHandler?()
    }

    private func command(
        _ input: String,
        _ modifiers: UIKeyModifierFlags,
        _ discoverabilityTitle: String,
        _ action: Selector
    ) -> UIKeyCommand {
        UIKeyCommand(
            title: discoverabilityTitle,
            image: nil,
            action: action,
            input: input,
            modifierFlags: modifiers,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: discoverabilityTitle,
            attributes: [],
            state: .off
        )
    }

    @objc private func applyBoldCommand() { apply(.bold) }
    @objc private func applyItalicCommand() { apply(.italic) }
    @objc private func applyInlineCodeCommand() { apply(.inlineCode) }
    @objc private func applyLinkCommand() { apply(.link) }
    @objc private func applyStrikethroughCommand() { apply(.strikethrough) }
    @objc private func applyHighlightCommand() { apply(.highlight) }
    @objc private func applyParagraphCommand() { apply(.paragraph) }
    @objc private func applyHeading1Command() { apply(.heading(1)) }
    @objc private func applyHeading2Command() { apply(.heading(2)) }
    @objc private func applyHeading3Command() { apply(.heading(3)) }
    @objc private func applyHeading4Command() { apply(.heading(4)) }
    @objc private func applyHeading5Command() { apply(.heading(5)) }
    @objc private func applyHeading6Command() { apply(.heading(6)) }
    @objc private func applyOrderedListCommand() { apply(.orderedList) }
    @objc private func applyUnorderedListCommand() { apply(.unorderedList) }
    @objc private func applyQuoteCommand() { apply(.quote) }
    @objc private func applyChecklistCommand() { apply(.todoList) }
    @objc private func applyCodeBlockCommand() { apply(.codeBlock) }
    @objc private func applyDividerCommand() { apply(.divider) }
    @objc private func applyNoteLinkCommand() { apply(.noteLink) }
    @objc private func applyTaskReferenceCommand() { apply(.taskReference) }
    @objc private func indentListCommand() { indentationCommandHandler?(true) }
    @objc private func outdentListCommand() { indentationCommandHandler?(false) }

    /// Offers **Paste** when the pasteboard holds nothing but an image.
    ///
    /// The macOS twin of this is `CadenceTextView.readablePasteboardTypes`, and it is the same
    /// defect on both platforms: the command is validated before it is dispatched, so a `paste(_:)`
    /// override is unreachable for a payload the stock view does not consider pasteable.
    /// `UITextView` answers no for an image on an editor whose `allowsEditingTextAttributes` is
    /// false — which `iOSMarkdownEditor` sets deliberately, because this storage holds markdown
    /// source and not attributed rich text — so the item never appears in the edit menu and Cmd-V
    /// on a hardware keyboard does nothing.
    ///
    /// `hasImages` and not `.images`: reading the pasteboard's contents raises the system's
    /// "pasted from" banner, and asking whether a menu item should be enabled must not do that.
    ///
    /// **`allowsMarkdownImageInsertion` comes before the pasteboard (T-504).** The widening was
    /// unconditional, so at a host that refuses images — the note template, the event-edit sheet,
    /// quick create in event mode — **Paste** was enabled over a copied image and did nothing:
    /// `createPastedImageAssets` returned `[]`, `paste(_:)` fell through to `super.paste`, and
    /// `super` declines an image on a view whose `allowsEditingTextAttributes` is false. That is
    /// the same defect T-478 fixed on the drag cursor, one door along. The flag is tested first
    /// because it is a local `Bool` and `hasImages` is not: a refusing host must not raise the
    /// banner to answer a question it has already answered.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)),
           isEditable,
           allowsMarkdownImageInsertion,
           UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if let images = UIPasteboard.general.images,
           !images.isEmpty,
           imagePasteHandler?(images) == true {
            return
        }
        super.paste(sender)
    }

    private func apply(_ command: MarkdownFormatCommand) {
        formatCommandHandler?(command)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        guard abs(size.width - lastMarkdownLayoutSize.width) >= 1 ||
            abs(size.height - lastMarkdownLayoutSize.height) >= 1 else {
            return
        }

        lastMarkdownLayoutSize = size
        layoutInvalidationHandler?()
    }

    /// The inline task panel's hosted view while one is open ([[T-1481]]); set by
    /// `iOSMarkdownInlineTaskPanelSupport`, and gone with the view.
    weak var inlineTaskPanelView: UIView?

    /// **Escape, with the caret back in the note text and a panel still open** ([[T-3243]]).
    ///
    /// The Mac cancels the inline task panel on Escape from either side — the panel's own focus
    /// (`onExitCommand`) or the note text (`CadenceTextView.cancelInlineTaskPanel`). iOS had
    /// neither. The panel's side is `iOSMarkdownInlineTaskPanelHost`; this is the note's. Set
    /// alongside `inlineTaskPanelView` when a panel opens, and cleared when it closes, so Escape
    /// is offered only while there is something for it to cancel.
    var inlineTaskPanelCancelHandler: (() -> Void)?

    /// **A touch on the inline task panel belongs to the panel.** Every recognizer attached to the
    /// text view — its own selection and caret taps, and the coordinator's reference, block and
    /// table taps — also sees touches that land in a subview, so without this a tap on a panel
    /// control would drop a caret into the hidden markdown behind it and raise the keyboard. Only
    /// the scroll pan still begins there, so the note scrolls under a finger resting on the panel.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view === self,
           gestureRecognizer !== panGestureRecognizer,
           let panel = inlineTaskPanelView,
           panel.superview === self,
           !panel.isHidden,
           panel.frame.contains(gestureRecognizer.location(in: self)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// Bridges an `NSRange` in the storage to the `UITextRange` every `UITextInput` mutation wants.
///
/// Clamps by falling back to `beginningOfDocument` / `start` rather than trapping: the ranges
/// handed in come from parsers reading the *previous* text, so a stale one has to degenerate
/// rather than crash.
extension UITextView {
    func textRange(from nsRange: NSRange) -> UITextRange? {
        let start = position(from: beginningOfDocument, offset: nsRange.location) ?? beginningOfDocument
        let end = position(from: start, offset: nsRange.length) ?? start
        return textRange(from: start, to: end)
    }
}
#endif
