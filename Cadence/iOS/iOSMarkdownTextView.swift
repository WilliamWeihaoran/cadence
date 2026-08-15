#if os(iOS)
import SwiftUI
import UIKit

/// The "Done" bar that sits above the keyboard while a markdown editor is being typed into.
///
/// It is a UIKit `inputAccessoryView` rather than SwiftUI's `ToolbarItemGroup(placement: .keyboard)`
/// because the editor's first responder is a `UITextView` inside a `UIViewRepresentable`. SwiftUI
/// drives keyboard-placement toolbars off its *own* focus system, so when the UIKit text view holds
/// first responder SwiftUI sees no focused view and renders nothing — seven of those toolbar groups
/// were declared across the iOS markdown surfaces and not one of them ever appeared. Worse, on the
/// screens that also carry a plain SwiftUI `TextField` (Today's capture bar, the task editor's tag
/// and subtask fields) the group *did* render for that field, showing a "Done" whose action only
/// ever unfocused the markdown editor — a button that appeared and did nothing.
///
/// Attaching the bar to the text view itself puts it where it was always meant to be: visible
/// exactly when the editor is being typed into, and on every surface that embeds the editor, from
/// one implementation.
final class iOSMarkdownKeyboardAccessoryView: UIView {
    /// Touch floor; also the bar's height, matching the system's own keyboard accessory bars.
    private static let barHeight: CGFloat = 44

    private let onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.barHeight))
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor(Theme.surfaceElevated)

        let hairline = UIView()
        hairline.backgroundColor = UIColor(Theme.borderSubtle)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.setTitleColor(UIColor(Theme.blue), for: .normal)
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            doneButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.barHeight),
            doneButton.heightAnchor.constraint(equalToConstant: Self.barHeight)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight)
    }

    @objc private func handleDone() {
        onDone()
    }
}

final class iOSMarkdownTextView: UITextView {
    var formatCommandHandler: ((MarkdownFormatCommand) -> Void)?
    var indentationCommandHandler: ((Bool) -> Void)?
    var imagePasteHandler: (([UIImage]) -> Bool)?
    var layoutInvalidationHandler: (() -> Void)?
    private var lastMarkdownLayoutSize: CGSize = .zero

    override var keyCommands: [UIKeyCommand]? {
        [
            command("b", [.command], "Bold", #selector(applyBoldCommand)),
            command("i", [.command], "Italic", #selector(applyItalicCommand)),
            command("e", [.command], "Inline Code", #selector(applyInlineCodeCommand)),
            command("k", [.command], "Link", #selector(applyLinkCommand)),
            command("x", [.command, .shift], "Strikethrough", #selector(applyStrikethroughCommand)),
            command("h", [.command, .shift], "Highlight", #selector(applyHighlightCommand)),
            command("0", [.command, .alternate], "Paragraph", #selector(applyParagraphCommand)),
            command("1", [.command, .alternate], "Heading 1", #selector(applyHeading1Command)),
            command("2", [.command, .alternate], "Heading 2", #selector(applyHeading2Command)),
            command("3", [.command, .alternate], "Heading 3", #selector(applyHeading3Command)),
            command("4", [.command, .alternate], "Heading 4", #selector(applyHeading4Command)),
            command("5", [.command, .alternate], "Heading 5", #selector(applyHeading5Command)),
            command("6", [.command, .alternate], "Heading 6", #selector(applyHeading6Command)),
            command("7", [.command, .shift], "Ordered List", #selector(applyOrderedListCommand)),
            command("8", [.command, .shift], "Bulleted List", #selector(applyUnorderedListCommand)),
            command("9", [.command, .shift], "Quote", #selector(applyQuoteCommand)),
            command("t", [.command, .shift], "Checklist", #selector(applyChecklistCommand)),
            command("c", [.command, .alternate], "Code Block", #selector(applyCodeBlockCommand)),
            command("d", [.command, .alternate], "Divider", #selector(applyDividerCommand)),
            command("n", [.command, .alternate], "Note Link", #selector(applyNoteLinkCommand)),
            command("r", [.command, .alternate], "Task Reference", #selector(applyTaskReferenceCommand)),
            command("\t", [], "Indent List", #selector(indentListCommand)),
            command("\t", [.shift], "Outdent List", #selector(outdentListCommand))
        ] + (super.keyCommands ?? [])
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
}
#endif
