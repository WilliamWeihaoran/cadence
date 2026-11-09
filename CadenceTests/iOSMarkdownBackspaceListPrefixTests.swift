import Foundation
import SwiftUI
import Testing
@testable import Cadence

// [[T-14722]]: the iOS editor's Backspace list-prefix rule, held by what the delegate DOES.
//
// UIKit asks `textView(_:shouldChangeTextIn:replacementText:)` about a Backspace with the character
// it is about to delete, `(n-1, 1)`, while the caret is still at `n`. The editor used to hand that
// proposal straight to `MarkdownBackspaceSupport.listPrefixMutation`, whose caret guard refused it,
// so Backspace right after an empty bullet's marker deleted one space on iOS and the whole marker
// on the Mac. `MarkdownBackspaceSupportTests` holds the shared translation on both legs; this suite
// drives a real `iOSMarkdownEditor.Coordinator` over a real `iOSMarkdownTextView` with the proposal
// UIKit sends, so the wiring is held by effect. Gated `#if os(iOS)` because none of these types
// exists on the macOS leg.
#if os(iOS)
import UIKit

@Suite @MainActor
struct iOSMarkdownBackspaceListPrefixTests {
    private final class TextBinding {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private struct Fixture {
        let coordinator: iOSMarkdownEditor.Coordinator
        let textView: iOSMarkdownTextView
        let binding: TextBinding
    }

    private func makeFixture(_ markdown: String, caret: Int) -> Fixture {
        let binding = TextBinding(markdown)
        let editor = iOSMarkdownEditor(
            text: Binding(get: { binding.value }, set: { binding.value = $0 }),
            isFocused: .constant(false)
        )
        let coordinator = iOSMarkdownEditor.Coordinator(parent: editor)
        let textView = iOSMarkdownTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        textView.text = markdown
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: caret, length: 0)
        return Fixture(coordinator: coordinator, textView: textView, binding: binding)
    }

    /// Asks the delegate exactly what UIKit asks it for a Backspace with the caret at `caret`.
    private func backspace(on fixture: Fixture, caret: Int) -> Bool {
        fixture.coordinator.textView(
            fixture.textView,
            shouldChangeTextIn: NSRange(location: caret - 1, length: 1),
            replacementText: ""
        )
    }

    @Test func backspaceAfterAnEmptyBulletsMarkerRemovesTheWholeMarker() {
        let markdown = "- first\n- "
        let caret = (markdown as NSString).length
        let fixture = makeFixture(markdown, caret: caret)

        let allowed = backspace(on: fixture, caret: caret)

        #expect(!allowed, "the delegate let UIKit delete one character instead of applying the list-prefix rule")
        #expect(fixture.textView.text == "- first\n")
        #expect(fixture.textView.selectedRange == NSRange(location: ("- first\n" as NSString).length, length: 0))
        #expect(fixture.binding.value == "- first\n", "the host's binding did not receive the edit")
    }

    @Test func backspaceRightAfterAFilledItemsMarkerRemovesTheMarkerAndKeepsTheText() {
        let markdown = "- [ ] buy milk"
        let caret = ("- [ ] " as NSString).length
        let fixture = makeFixture(markdown, caret: caret)

        #expect(!backspace(on: fixture, caret: caret))
        #expect(fixture.textView.text == "buy milk")
        #expect(fixture.textView.selectedRange == NSRange(location: 0, length: 0))
    }

    /// The rule stays narrow: Backspace inside an item's text, and a forward delete over the
    /// marker's last character, are UIKit's to perform.
    @Test func backspaceInsideAnItemsTextAndForwardDeleteAreLeftToUIKit() {
        let markdown = "- first"
        let inText = makeFixture(markdown, caret: 5)
        #expect(backspace(on: inText, caret: 5))
        #expect(inText.textView.text == markdown)

        let forward = makeFixture("- ", caret: 1)
        #expect(forward.coordinator.textView(
            forward.textView,
            shouldChangeTextIn: NSRange(location: 1, length: 1),
            replacementText: ""
        ))
        #expect(forward.textView.text == "- ")
    }
}

#endif
