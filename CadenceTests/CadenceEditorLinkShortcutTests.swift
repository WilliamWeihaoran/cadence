#if os(macOS)
import AppKit
import Testing
@testable import Cadence

/// T-5882. **The markdown editor's insert-link shortcut is Cmd+Shift+K, and plain Cmd+K is not it.**
///
/// Cmd+K is Search app-wide. `RootCommandEventSupport.handleCommandKeyEvent` consumes key code 40
/// from an app-wide local monitor, which runs before `performKeyEquivalent` reaches the editor's
/// text view, so an editor binding on plain Cmd+K cannot fire however it is written here. The owner
/// kept one meaning for Cmd+K and moved the editor's link shortcut; these two cases are what fails
/// if it moves back.
///
/// The events are synthesized against no window and nothing is dispatched — `handle` reads only
/// `charactersIgnoringModifiers` and `modifierFlags`, so no responder sees a key.
@Suite
@MainActor
struct CadenceEditorLinkShortcutTests {
    @Test func commandShiftKWrapsTheSelectionAsALink() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        #expect(MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command, .shift]), in: textView))
        #expect(textView.string == "[alpha](url)")
    }

    @Test func plainCommandKIsNotTheEditorsLinkShortcut() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        // Unhandled, so `performKeyEquivalent` falls through to the responder chain — which is
        // moot in the running app, where the root monitor has already presented Search.
        #expect(!MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command]), in: textView))
        #expect(textView.string == "alpha")
    }

    /// Cmd+Shift+K is free: no other shortcut in the editor's own table takes shifted `k`, and the
    /// case above is the one that claims it.
    @Test func noOtherEditorShortcutClaimsShiftedK() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        _ = MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command, .shift]), in: textView)

        #expect(textView.string.hasPrefix("["))
        #expect(!textView.string.contains("**"))
        #expect(!textView.string.contains("~~"))
    }

    private func keyEvent(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 40
            )
        )
    }
}
#endif
