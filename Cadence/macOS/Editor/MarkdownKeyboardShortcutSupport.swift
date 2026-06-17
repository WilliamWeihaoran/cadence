#if os(macOS)
import AppKit

enum MarkdownKeyboardShortcutSupport {
    static func apply(_ command: MarkdownFormatCommand, in textView: NSTextView) -> Bool {
        let mutation = MarkdownFormatCommandSupport.apply(
            command,
            text: textView.string,
            selection: textView.selectedRange()
        )

        if mutation.text == textView.string {
            textView.setSelectedRange(clamped(mutation.selection, in: textView.string))
            return true
        }

        return replaceText(
            in: textView,
            range: mutation.replacementRange,
            with: mutation.replacement,
            selection: mutation.selection
        )
    }

    static func handle(_ event: NSEvent, in textView: NSTextView) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else { return false }

        var flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        flags.remove(.capsLock)

        switch (characters, flags) {
        case ("b", [.command]):
            return apply(.bold, in: textView)
        case ("i", [.command]):
            return apply(.italic, in: textView)
        case ("e", [.command]):
            return apply(.inlineCode, in: textView)
        case ("k", [.command]):
            return apply(.link, in: textView)
        case ("x", [.command, .shift]):
            return apply(.strikethrough, in: textView)
        case ("h", [.command, .shift]):
            return apply(.highlight, in: textView)
        case ("0", [.command, .option]):
            return apply(.paragraph, in: textView)
        case ("1", [.command, .option]),
             ("2", [.command, .option]),
             ("3", [.command, .option]),
             ("4", [.command, .option]),
             ("5", [.command, .option]),
             ("6", [.command, .option]):
            guard let level = Int(characters) else { return false }
            return apply(.heading(level), in: textView)
        case ("7", [.command, .shift]):
            return apply(.orderedList, in: textView)
        case ("8", [.command, .shift]):
            return apply(.unorderedList, in: textView)
        case ("9", [.command, .shift]):
            return apply(.quote, in: textView)
        case ("t", [.command, .shift]):
            return apply(.todoList, in: textView)
        case ("c", [.command, .option]):
            return apply(.codeBlock, in: textView)
        case ("d", [.command, .option]):
            return apply(.divider, in: textView)
        case ("n", [.command, .option]):
            return apply(.noteLink, in: textView)
        case ("r", [.command, .option]):
            return apply(.taskReference, in: textView)
        default:
            return false
        }
    }

    private static func replaceText(
        in textView: NSTextView,
        range: NSRange,
        with replacement: String,
        selection: NSRange
    ) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(clamped(selection, in: textView.string))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, max(0, length - location)))
    }
}
#endif
