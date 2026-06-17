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

    @Test func continuesChecklistLinesWithSharedCanonicalMarker() {
        #expect(MarkdownListSupport.continuation(after: "- [ ] write tests") == "○ ")
        #expect(MarkdownListSupport.continuation(after: "    - [x] done") == "    ○ ")
        #expect(MarkdownListSupport.continuation(after: "✓ shipped") == "○ ")
    }

    @Test func continuesOrderedLinesWithDelimiterAndCaseAwareness() {
        #expect(MarkdownListSupport.continuation(after: "1. first") == "2. ")
        #expect(MarkdownListSupport.continuation(after: "a) alpha") == "b) ")
        #expect(MarkdownListSupport.continuation(after: "IV. roman") == "V. ")
    }

    @Test func lineInfoDescribesGithubChecklistRangesForLiveRendering() throws {
        let info = try #require(MarkdownListSupport.lineInfo(in: "    - [x] shipped"))

        #expect(info.kind == .done)
        #expect(info.indentation == "    ")
        #expect(info.marker == "x")
        #expect(info.markerRange == NSRange(location: 4, length: 6))
        #expect(info.contentRange == NSRange(location: 10, length: 7))
        #expect(info.visualLevel == 1)
        #expect(info.markerWidth == 2)
    }

    @Test func lineInfoDescribesNativeChecklistRangesForLiveRendering() throws {
        let info = try #require(MarkdownListSupport.lineInfo(in: "\t○ draft note"))

        #expect(info.kind == .todo)
        #expect(info.indentation == "\t")
        #expect(info.marker == "○")
        #expect(info.markerRange == NSRange(location: 1, length: 1))
        #expect(info.contentRange == NSRange(location: 3, length: 10))
        #expect(info.visualLevel == 1)
    }

    @Test func lineInfoDescribesOrderedAndBulletMarkersForLiveRendering() throws {
        let ordered = try #require(MarkdownListSupport.lineInfo(in: "    iv. roman"))
        let bullet = try #require(MarkdownListSupport.lineInfo(in: "• bullet"))

        #expect(ordered.kind == .ordered)
        #expect(ordered.marker == "iv.")
        #expect(ordered.markerRange == NSRange(location: 4, length: 3))
        #expect(ordered.contentRange == NSRange(location: 8, length: 5))
        #expect(ordered.visualLevel == 1)
        #expect(ordered.markerWidth == 4)

        #expect(bullet.kind == .bullet)
        #expect(bullet.marker == "•")
        #expect(bullet.markerRange == NSRange(location: 0, length: 1))
        #expect(bullet.contentRange == NSRange(location: 2, length: 6))
        #expect(bullet.visualLevel == 0)
    }

    @Test func orderedMarkerUsesSharedDesktopListCycle() {
        #expect(MarkdownListSupport.orderedMarker(for: 0, index: 3) == "3.")
        #expect(MarkdownListSupport.orderedMarker(for: 1, index: 3) == "c.")
        #expect(MarkdownListSupport.orderedMarker(for: 2, index: 4) == "iv.")
        #expect(MarkdownListSupport.orderedMarker(for: 4, index: 27) == "z.")
    }

    @Test func indentsListLinesAndRemapsOrderedMarkersByLevel() {
        let text = "1. first"
        let result = MarkdownListSupport.adjustedListIndentation(
            in: text,
            selection: NSRange(location: 0, length: 0),
            increase: true
        )

        #expect(result?.text == "    a. first")
        #expect(result?.selection == NSRange(location: ("    a. " as NSString).length, length: 0))
    }

    @Test func outdentsNestedListLinesAndRemapsOrderedMarkersByLevel() {
        let text = "    b. nested"
        let result = MarkdownListSupport.adjustedListIndentation(
            in: text,
            selection: NSRange(location: ("    b. " as NSString).length, length: 0),
            increase: false
        )

        #expect(result?.text == "2. nested")
        #expect(result?.selection == NSRange(location: ("2. " as NSString).length, length: 0))
    }

    @Test func outdentingRootListRemovesTheListMarker() {
        let text = "• item"
        let result = MarkdownListSupport.adjustedListIndentation(
            in: text,
            selection: NSRange(location: ("• " as NSString).length, length: 0),
            increase: false
        )

        #expect(result?.text == "item")
        #expect(result?.selection == NSRange(location: 0, length: 0))
    }

    @Test func indentationIgnoresPlainParagraphSelections() {
        let text = "plain paragraph"
        let result = MarkdownListSupport.adjustedListIndentation(
            in: text,
            selection: NSRange(location: 0, length: 0),
            increase: true
        )

        #expect(result == nil)
    }

    @Test func indentsOnlyListLinesAcrossASelection() {
        let text = "• first\nplain\n2. second"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let result = MarkdownListSupport.adjustedListIndentation(
            in: text,
            selection: selection,
            increase: true
        )

        #expect(result?.text == "    • first\nplain\n    b. second")
        #expect(result?.selection == NSRange(location: 4, length: ((result?.text ?? "") as NSString).length - 4))
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
