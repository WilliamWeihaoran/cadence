import Foundation
import Testing
import SwiftUI
#if os(macOS)
import AppKit
#endif

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

        #expect(result?.text == "    ◦ first\nplain\n    b. second")
        #expect(result?.selection == NSRange(location: 4, length: ((result?.text ?? "") as NSString).length - 4))
    }

    @Test func tabIndentationResolvesToTheSameOrderedLevelForToolbarAndTyping() {
        // The toolbar reads the marker straight from the indentation string while typing goes
        // through orderedLevel; when the two disagreed a tab-indented line got "1." from one and
        // "a." from the other.
        #expect(MarkdownListSupport.orderedLevel(forIndentation: "\t") == 1)
        #expect(MarkdownListSupport.orderedMarker(forIndentation: "\t") == "a.")
        #expect(MarkdownListSupport.orderedMarker(forIndentation: "    ") == "a.")
    }

    @Test func proseThatOpensWithAnAbbreviationIsNotAList() {
        #expect(MarkdownListSupport.listPrefixMatch(in: "Mr. Smith called") == nil)
        #expect(MarkdownListSupport.listPrefixMatch(in: "Fig. 3 shows the split") == nil)
        #expect(MarkdownListSupport.continuation(after: "Note. see below") == nil)
        #expect(MarkdownListSupport.listPrefixMatch(in: "a. alpha")?.kind == .ordered)
        #expect(MarkdownListSupport.listPrefixMatch(in: "iv. roman")?.kind == .ordered)
    }

    @Test func letteredListsContinuePastTheLettersThatAreAlsoRomanNumerals() {
        // Level 1 markers are letters, so "c." is the third item; level 2 markers are roman.
        #expect(MarkdownListSupport.continuation(after: "    c. gamma") == "    d. ")
        #expect(MarkdownListSupport.continuation(after: "    x. twentyfourth") == "    y. ")
        #expect(MarkdownListSupport.continuation(after: "        iii. third") == "        iv. ")
    }

    @Test func topLevelSingleLetterMarkersReadAsTheListTheyOpen() {
        // Level 0's own markers are numbers, so neither alphabet is native and the lone letter
        // has to speak for itself: "i." is how a hand-written roman outline starts, every other
        // lone letter is a lettered list.
        #expect(MarkdownListSupport.continuation(after: "i. first") == "ii. ")
        #expect(MarkdownListSupport.continuation(after: "c. gamma") == "d. ")
        #expect(MarkdownListSupport.continuation(after: "I. FIRST") == "II. ")
    }

    @Test func theRunAboveAMarkerSettlesWhichAlphabetItBelongsTo() {
        // "v." is both the 22nd letter and roman 5; only one reading continues the marker above it.
        #expect(MarkdownListSupport.continuation(after: "v. five", precededBy: "iv.") == "vi. ")
        #expect(MarkdownListSupport.continuation(after: "x. ten", precededBy: "ix.") == "xi. ")
        #expect(MarkdownListSupport.continuation(after: "i. ninth", precededBy: "h.") == "j. ")
        #expect(MarkdownListSupport.continuation(after: "        c. hundredth", precededBy: "        xcix.") == "        ci. ")
    }

    // MARK: - Ordered marker renumbering

    @Test func renumbersOrderedMarkersWithinOneRun() {
        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: "3. one\n9. two\n1. three",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "1. one\n2. two\n3. three")
    }

    @Test func restartsOrderedNumberingAfterANonListLine() {
        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: "1. one\n2. two\n\n7. fresh start",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "1. one\n2. two\n\n1. fresh start")
    }

    @Test func nestedOrderedLevelsRestartAndTheOuterLevelResumes() {
        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: "1. one\n    9. sub\n5. two\n    7. sub again",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "1. one\n    a. sub\n2. two\n    a. sub again")
    }

    @Test func aLevelCountIsDroppedOnceTheListSteppedOutPastIt() {
        // Stepping out to level 0 has to discard level 1's count, or the last line resumes it as
        // "b." — a second item of a sublist the level-2 block already ended.
        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: "    5. deep\n9. top\n        3. deeper\n    7. back",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "    a. deep\n1. top\n        i. deeper\n    a. back")
    }

    @Test func keepsTheCaretWhereItSitsWhenAnEarlierMarkerShrinks() {
        let text = "10. one\ntail"
        let caret = ("10. one\nta" as NSString).length

        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: text,
            selection: NSRange(location: caret, length: 0)
        )

        #expect(result.text == "1. one\ntail")
        #expect(result.selection == NSRange(location: ("1. one\nta" as NSString).length, length: 0))
    }

    @Test func clampsTheSelectionWhenNoOrderedMarkerChanges() {
        let text = "1. one\n2. two"

        let result = MarkdownListSupport.normalizedOrderedListMarkers(
            in: text,
            selection: NSRange(location: 999, length: 4)
        )

        #expect(result.text == text)
        #expect(result.selection == NSRange(location: (text as NSString).length, length: 0))
    }

#if os(macOS)
    /// The renumberer runs from `textDidChange`, after NSTextView has already closed the undo
    /// group for the keystroke. Rewriting the document outside the mutation contract left that
    /// record describing text that had moved, so the rewrite has to register its own undo step.
    @MainActor @Test func renumberingRegistersItsOwnUndoStep() throws {
        let textView = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView = textView
        textView.allowsUndo = true
        // Deliberately not installed as the text view's delegate: undoing the renumber would
        // otherwise post another change notification and the renumberer would immediately redo it.
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))

        textView.string = "1. one\n3. two"
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(textView.string == "1. one\n2. two")
        let undoManager = try #require(textView.undoManager)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(textView.string == "1. one\n3. two")
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
#endif
}
