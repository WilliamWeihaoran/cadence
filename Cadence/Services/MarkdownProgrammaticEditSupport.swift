import Foundation

/// **A programmatic write into a text view is a *keyboard* write, and UIKit edits around it.**
///
/// `UITextView.replace(_:withText:)` is the only write that registers on the view's own undo
/// manager, which is why every markdown mutation on iOS goes through it rather than assigning
/// `text` or reaching into `textStorage`. Measured on iOS 26.5 (T-221), it is also this:
///
/// ```
/// -[UITextView replaceRange:withText:]
/// -[UITextInputController replaceRange:withText:]
/// -[UITextInputController _replaceRange:withAttributedTextFromKeyboard:…]
/// -[UITextInputController checkSmartPunctuationForWordInRange:]
/// -[UITextInputController _delegateShouldChangeTextInRange:replacementText:]
/// ```
///
/// UIKit treats the replacement as text the keyboard produced, then runs its smart-punctuation
/// pass over the **words either side of the range just written** and offers the delegate
/// substitutions of its own. Committing a cell in a table wrote its row correctly and then let
/// UIKit rewrite the `---` delimiter on the line above into an em dash, twice, at which point the
/// table stopped parsing and dropped to raw source in front of the user.
///
/// **`smartDashesType = .no` does not prevent it.** Both the text view and the hosted cell field
/// set it, and both were set again — with `smartQuotesType`, `smartInsertDeleteType` and
/// `reloadInputViews()` — immediately before the call; the substitution still landed, byte-checked
/// out of the simulator's store. The trait is not the lever, so the delegate is: UIKit *asks*
/// before substituting, and a write that knows exactly what it asked for can tell the difference
/// between its own change and one proposed around it.
///
/// This is that decision, and it lives here rather than in `Cadence/iOS/` because it is a rule
/// about text rather than about UIKit lifecycle — and because `Cadence/iOS/` is entirely inside
/// `#if os(iOS)`, invisible to this repo's macOS-built tests.
nonisolated struct MarkdownProgrammaticEdit: Equatable {
    /// The UTF-16 range handed to `replace(_:withText:)`.
    let range: NSRange
    /// The exact string handed to `replace(_:withText:)`.
    let replacement: String

    init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

nonisolated enum MarkdownProgrammaticEditSupport {
    /// Whether a `shouldChangeTextIn` callback may proceed.
    ///
    /// With no write in flight the editor's own rules apply and every change is the user's, so the
    /// answer is always yes — this must never become a general veto on typing.
    ///
    /// While a write **is** in flight the only acceptable change is that write itself, spelled
    /// exactly as it was asked for. Anything else arriving inside that window came from UIKit, not
    /// from Cadence and not from the user, and refusing it is the difference between a table that
    /// survives a cell commit and one that does not.
    ///
    /// Equality rather than intersection, deliberately. A smart-punctuation proposal can land
    /// *inside* the range being written — a cell whose value is `---` is the obvious case — and an
    /// overlap test would wave that one through while catching the neighbours. What makes a change
    /// ours is that we asked for it, not where it lands.
    static func acceptsDelegateChange(
        range: NSRange,
        replacement: String,
        whileWriting pending: MarkdownProgrammaticEdit?
    ) -> Bool {
        guard let pending else { return true }
        return range == pending.range && replacement == pending.replacement
    }
}
