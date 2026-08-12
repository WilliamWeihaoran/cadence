import Foundation
import Testing

@testable import Cadence

struct MarkdownLineBreakSupportTests {
    @Test func continuesBulletListWithExistingMarker() throws {
        let mutation = try #require(MarkdownLineBreakSupport.mutation(
            in: "- first",
            selection: NSRange(location: ("- first" as NSString).length, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 7, length: 0))
        #expect(mutation.replacement == "\n- ")
        #expect(mutation.selection == NSRange(location: 10, length: 0))
    }

    @Test func continuesOrderedAndChecklistLines() throws {
        let ordered = try #require(MarkdownLineBreakSupport.mutation(
            in: "9. item",
            selection: NSRange(location: ("9. item" as NSString).length, length: 0)
        ))
        let checklist = try #require(MarkdownLineBreakSupport.mutation(
            in: "- [x] done",
            selection: NSRange(location: ("- [x] done" as NSString).length, length: 0)
        ))

        #expect(ordered.replacement == "\n10. ")
        // Opens an empty box in the spelling the line above is written in. It used to open `○ `,
        // which left one list written two ways.
        #expect(checklist.replacement == "\n- [ ] ")
    }

    @Test func continuesEachChecklistLineInItsOwnSpelling() throws {
        let legacy = try #require(MarkdownLineBreakSupport.mutation(
            in: "  ✓ shipped",
            selection: NSRange(location: ("  ✓ shipped" as NSString).length, length: 0)
        ))
        let starred = try #require(MarkdownLineBreakSupport.mutation(
            in: "    * [X] done",
            selection: NSRange(location: ("    * [X] done" as NSString).length, length: 0)
        ))

        #expect(legacy.replacement == "\n  ○ ")
        #expect(starred.replacement == "\n    * [ ] ")
    }

    @Test func exitsEmptyListLineInsteadOfContinuingForever() throws {
        let markdown = "Before\n• \nAfter"
        let markerLocation = ("Before\n• " as NSString).length

        let mutation = try #require(MarkdownLineBreakSupport.mutation(
            in: markdown,
            selection: NSRange(location: markerLocation, length: 0)
        ))

        #expect(mutation.replacementRange == NSRange(location: 7, length: 3))
        #expect(mutation.replacement == "\n")
        #expect(mutation.selection == NSRange(location: 8, length: 0))
    }

    @Test func continuesQuoteLinesAndQuotedLists() throws {
        let quote = try #require(MarkdownLineBreakSupport.mutation(
            in: "> Keep going",
            selection: NSRange(location: ("> Keep going" as NSString).length, length: 0)
        ))
        let quotedList = try #require(MarkdownLineBreakSupport.mutation(
            in: "> - item",
            selection: NSRange(location: ("> - item" as NSString).length, length: 0)
        ))

        #expect(quote.replacement == "\n> ")
        #expect(quotedList.replacement == "\n> - ")
    }

    /// Quoted ordered lists advance their marker and quoted checklists open a fresh unchecked box,
    /// exactly as their unquoted forms do. These cases used to live only on a dead
    /// `MarkdownQuoteSupport.continuation`, so the editor was free to disagree — and did.
    @Test func continuesQuotedOrderedListsAndChecklists() throws {
        let nested = try #require(MarkdownLineBreakSupport.mutation(
            in: "  >> Nested",
            selection: NSRange(location: ("  >> Nested" as NSString).length, length: 0)
        ))
        #expect(nested.replacement == "\n  >> ")

        let quotedOrdered = try #require(MarkdownLineBreakSupport.mutation(
            in: "> 1. first",
            selection: NSRange(location: ("> 1. first" as NSString).length, length: 0)
        ))
        #expect(quotedOrdered.replacement == "\n> 2. ")

        let quotedTodo = try #require(MarkdownLineBreakSupport.mutation(
            in: "> - [ ] task",
            selection: NSRange(location: ("> - [ ] task" as NSString).length, length: 0)
        ))
        #expect(quotedTodo.replacement == "\n> - [ ] ")
    }

    @Test func doesNotContinueEmptyQuoteMarkersOrPlainText() {
        #expect(MarkdownLineBreakSupport.mutation(
            in: "> ",
            selection: NSRange(location: ("> " as NSString).length, length: 0)
        ) == nil)
        #expect(MarkdownLineBreakSupport.mutation(
            in: "Plain text",
            selection: NSRange(location: ("Plain text" as NSString).length, length: 0)
        ) == nil)
    }

    @Test func continuesRunsOfMarkersThatAreBothLettersAndRomanNumerals() throws {
        // Pressing return has the whole note to read, so the markers above the caret decide
        // whether a lone "v."/"c." is roman or the 22nd/3rd letter.
        let roman = "i. one\nii. two\niii. three\niv. four\nv. five"
        let lettered = "a. alpha\nb. beta\nc. gamma"

        let continuedRoman = try #require(MarkdownLineBreakSupport.mutation(
            in: roman,
            selection: NSRange(location: (roman as NSString).length, length: 0)
        ))
        let continuedLettered = try #require(MarkdownLineBreakSupport.mutation(
            in: lettered,
            selection: NSRange(location: (lettered as NSString).length, length: 0)
        ))

        #expect(continuedRoman.replacement == "\nvi. ")
        #expect(continuedLettered.replacement == "\nd. ")
    }

    @Test func doesNotContinueEmptyQuoteMarkers() {
        let mutation = MarkdownLineBreakSupport.mutation(
            in: "> ",
            selection: NSRange(location: ("> " as NSString).length, length: 0)
        )

        #expect(mutation == nil)
    }
}
