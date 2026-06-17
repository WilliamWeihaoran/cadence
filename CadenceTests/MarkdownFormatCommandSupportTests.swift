import Foundation
import Testing
@testable import Cadence

struct MarkdownFormatCommandSupportTests {
    @Test func inlineCommandWrapsSelectionAndTogglesExistingMarkers() {
        let wrapped = MarkdownFormatCommandSupport.apply(
            .bold,
            text: "make important",
            selection: NSRange(location: 5, length: 9)
        )

        #expect(wrapped.text == "make **important**")
        #expect(wrapped.selection == NSRange(location: 7, length: 9))

        let unwrapped = MarkdownFormatCommandSupport.apply(
            .bold,
            text: wrapped.text,
            selection: wrapped.selection
        )

        #expect(unwrapped.text == "make important")
        #expect(unwrapped.selection == NSRange(location: 5, length: 9))
    }

    @Test func emptyInlineCommandRemovesSurroundingMarkersAtCursor() {
        let mutation = MarkdownFormatCommandSupport.apply(
            .italic,
            text: "Start ** end",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(mutation.text == "Start  end")
        #expect(mutation.selection == NSRange(location: 6, length: 0))
    }

    @Test func headingCommandTogglesSameLevelAndReplacesDifferentLevel() {
        let heading = MarkdownFormatCommandSupport.apply(
            .heading(2),
            text: "Plan",
            selection: NSRange(location: 0, length: 4)
        )

        #expect(heading.text == "## Plan")

        let changedLevel = MarkdownFormatCommandSupport.apply(
            .heading(3),
            text: heading.text,
            selection: NSRange(location: 0, length: heading.text.count)
        )

        #expect(changedLevel.text == "### Plan")

        let paragraph = MarkdownFormatCommandSupport.apply(
            .heading(3),
            text: changedLevel.text,
            selection: NSRange(location: 0, length: changedLevel.text.count)
        )

        #expect(paragraph.text == "Plan")
    }

    @Test func listCommandsToggleAndConvertExistingListPrefixes() {
        let bullet = MarkdownFormatCommandSupport.apply(
            .unorderedList,
            text: "Alpha\nBeta",
            selection: NSRange(location: 0, length: 10)
        )

        #expect(bullet.text == "• Alpha\n• Beta")

        let todo = MarkdownFormatCommandSupport.apply(
            .todoList,
            text: bullet.text,
            selection: NSRange(location: 0, length: bullet.text.count)
        )

        #expect(todo.text == "○ Alpha\n○ Beta")

        let cleared = MarkdownFormatCommandSupport.apply(
            .todoList,
            text: todo.text,
            selection: NSRange(location: 0, length: todo.text.count)
        )

        #expect(cleared.text == "Alpha\nBeta")
    }

    @Test func lineCommandsPreserveCaretPositionAfterInsertedPrefix() {
        let mutation = MarkdownFormatCommandSupport.apply(
            .unorderedList,
            text: "Write this",
            selection: NSRange(location: 5, length: 0)
        )

        #expect(mutation.text == "• Write this")
        #expect(mutation.selection == NSRange(location: 7, length: 0))
    }

    @Test func lineCommandsDoNotFormatNextLineWhenSelectionEndsAtNewline() {
        let mutation = MarkdownFormatCommandSupport.apply(
            .unorderedList,
            text: "Alpha\nBeta",
            selection: NSRange(location: 0, length: 6)
        )

        #expect(mutation.text == "• Alpha\nBeta")
        #expect(mutation.selection == NSRange(location: 0, length: 8))
    }

    @Test func paragraphCommandClearsBlockPrefixes() {
        let text = "## Title\n• Task\n> Quote"
        let mutation = MarkdownFormatCommandSupport.apply(
            .paragraph,
            text: text,
            selection: NSRange(location: 0, length: text.count)
        )

        #expect(mutation.text == "Title\nTask\nQuote")
    }

    @Test func insertMarkdownCommandReplacesSelectionAndMovesCaretAfterSnippet() {
        let reference = "[[note:11111111-1111-1111-1111-111111111111|Project Notes]]"
        let mutation = MarkdownFormatCommandSupport.apply(
            .insertMarkdown(reference),
            text: "Read this later",
            selection: NSRange(location: 5, length: 4)
        )

        #expect(mutation.text == "Read \(reference) later")
        #expect(mutation.selection == NSRange(location: 5 + (reference as NSString).length, length: 0))
    }

    @Test func replaceMarkdownCommandReplacesExplicitRangeAndMovesCaretAfterSnippet() {
        let reference = "[[note:11111111-1111-1111-1111-111111111111|Project Notes]]"
        let mutation = MarkdownFormatCommandSupport.apply(
            .replaceMarkdown(location: 5, length: 9, markdown: reference),
            text: "Read [[Project later",
            selection: NSRange(location: 20, length: 0)
        )

        #expect(mutation.text == "Read \(reference) later")
        #expect(mutation.selection == NSRange(location: 5 + (reference as NSString).length, length: 0))
    }

    @Test func replaceMarkdownWithCaretUsesExplicitCaretOffset() {
        let mutation = MarkdownFormatCommandSupport.apply(
            .replaceMarkdownWithCaret(location: 5, length: 5, markdown: "****", caretOffset: 2),
            text: "Make /bold",
            selection: NSRange(location: 10, length: 0)
        )

        #expect(mutation.text == "Make ****")
        #expect(mutation.selection == NSRange(location: 7, length: 0))
    }
}
