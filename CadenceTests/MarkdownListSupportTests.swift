#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import Cadence

struct MarkdownListSupportTests {
    @Test func normalizesMarkdownBulletMarkersWithoutMovingEarlierCaret() {
        let text = "caret stays here\n- normalize later"
        let caret = ("caret" as NSString).length

        let result = MarkdownListSupport.normalizedMarkdownListPrefixes(
            in: text,
            selection: NSRange(location: caret, length: 0)
        )

        #expect(result.text == "caret stays here\n• normalize later")
        #expect(result.selection == NSRange(location: caret, length: 0))
    }

    @Test func adjustsCaretForChecklistPrefixShrinkBeforeSelection() {
        let text = "- [ ] first\nstill selected"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let result = MarkdownListSupport.normalizedMarkdownListPrefixes(in: text, selection: selection)

        #expect(result.text == "○ first\nstill selected")
        #expect(result.selection == NSRange(location: (result.text as NSString).length, length: 0))
    }

    @Test func preservesSelectionAcrossMultipleNormalizedLines() {
        let text = "- [x] done\n- [ ] todo\nplain"
        let start = ("- [x] done\n- [ ] " as NSString).length
        let selection = NSRange(location: start, length: ("todo" as NSString).length)

        let result = MarkdownListSupport.normalizedMarkdownListPrefixes(in: text, selection: selection)
        let expectedStart = ("✓ done\n○ " as NSString).length

        #expect(result.text == "✓ done\n○ todo\nplain")
        #expect(result.selection == NSRange(location: expectedStart, length: ("todo" as NSString).length))
    }

    @Test func leavesMarkdownDividersAlone() {
        let text = "---\n***\n___\n- real bullet"
        let result = MarkdownListSupport.normalizedMarkdownListPrefixes(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )

        #expect(result.text == "---\n***\n___\n• real bullet")
    }

    @MainActor @Test func toolbarTodoListUsesCanonicalTodoMarker() {
        let textView = NSTextView()
        textView.string = "write this"
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        #expect(MarkdownKeyboardShortcutSupport.apply(.todoList, in: textView))
        #expect(textView.string == "○ write this")
        #expect(MarkdownListSupport.listPrefixMatch(in: textView.string)?.kind == .todo)
    }

    @MainActor @Test func toolbarTodoListRemovesCanonicalTodoMarker() {
        let textView = NSTextView()
        textView.string = "○ write this"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        #expect(MarkdownKeyboardShortcutSupport.apply(.todoList, in: textView))
        #expect(textView.string == "write this")
    }
}
#endif
