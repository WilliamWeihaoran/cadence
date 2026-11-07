import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

struct MarkdownQuoteSupportTests {
    @Test func parsesIndentedNestedQuoteLines() throws {
        let quote = try #require(MarkdownQuoteSupport.lineInfo(in: "    >>   Nested thought  "))

        #expect(quote.depth == 2)
        #expect(quote.content == "Nested thought")
        #expect(quote.prefixRange == NSRange(location: 0, length: 9))
        #expect(quote.contentRange == NSRange(location: 9, length: 14))
    }

    @Test func ignoresPlainGreaterThanSymbolsInsideText() {
        #expect(MarkdownQuoteSupport.lineInfo(in: "Score 3 > 2") == nil)
    }

    @Test func allowsEmptyQuoteMarkerForLiveStyling() throws {
        let quote = try #require(MarkdownQuoteSupport.lineInfo(in: ">   "))

        #expect(quote.depth == 1)
        #expect(quote.content.isEmpty)
    }

    // Continuation-on-Return is asserted in `MarkdownLineBreakSupportTests`, against the path the
    // editor runs. It used to be asserted here too, against a `MarkdownQuoteSupport.continuation`
    // nothing called — which is how that copy came to disagree with the editor unnoticed.

    // MARK: - A list or checklist inside a quote ([[T-12282]])

    @Test func readsAQuotedTaskItemInWholeLineCoordinates() throws {
        let line = "> - [ ] todo item"
        let quoted = try #require(MarkdownQuoteSupport.listLineInfo(in: line))

        #expect(quoted.quote.depth == 1)
        #expect(quoted.list.kind == .todo)
        #expect(quoted.list.checklistSyntax == .github)
        // The list's own prefix starts AFTER `> ` and never swallows the quote prefix.
        #expect(quoted.list.prefixRange == NSRange(location: 2, length: 6))
        #expect(quoted.list.markerRange == NSRange(location: 2, length: 6))
        #expect((line as NSString).substring(from: quoted.list.contentStart) == "todo item")

        let done = try #require(MarkdownQuoteSupport.listLineInfo(in: ">> - [x] shipped"))
        #expect(done.quote.depth == 2)
        #expect(done.list.kind == .done)
        #expect(done.list.prefixRange.location == 3)
    }

    @Test func readsQuotedBulletsOrderedAndLegacyItems() throws {
        let bullet = try #require(MarkdownQuoteSupport.listLineInfo(in: "> - point"))
        #expect(bullet.list.kind == .bullet)
        #expect(bullet.list.markerRange == NSRange(location: 2, length: 1))

        let ordered = try #require(MarkdownQuoteSupport.listLineInfo(in: "> 1. step"))
        #expect(ordered.list.kind == .ordered)
        #expect(ordered.list.markerRange == NSRange(location: 2, length: 2))

        let legacy = try #require(MarkdownQuoteSupport.listLineInfo(in: "> ○ legacy"))
        #expect(legacy.list.checklistSyntax == .legacy)
        #expect(legacy.list.markerRange == NSRange(location: 2, length: 1))

        // An empty, just-continued box is still a box: Return writes exactly this line.
        let fresh = try #require(MarkdownQuoteSupport.listLineInfo(in: "> - [ ] "))
        #expect(fresh.list.kind == .todo)
    }

    @Test func aPlainQuoteOrAnUnquotedListIsNotAQuotedList() {
        #expect(MarkdownQuoteSupport.listLineInfo(in: "> just a quote") == nil)
        #expect(MarkdownQuoteSupport.listLineInfo(in: ">") == nil)
        #expect(MarkdownQuoteSupport.listLineInfo(in: "- [ ] not quoted") == nil)
        #expect(MarkdownQuoteSupport.listLineInfo(in: "Score 3 > - 2") == nil)
    }

    /// The tap and the toggle read the same line the styler draws a box on, and flip the state
    /// character after the quote prefix, not a character of the prefix itself.
    @Test func aQuotedTaskItemTogglesAtTheMarkerAfterThePrefix() throws {
        let info = try #require(MarkdownChecklistSupport.quotableLineInfo(in: "> - [ ] todo"))
        #expect(info.syntax == .github)
        #expect(info.markerRange == NSRange(location: 2, length: 6))
        #expect(info.stateRange == NSRange(location: 5, length: 1))
        #expect(info.content == "todo")

        #expect(MarkdownChecklistSupport.toggledLine("> - [ ] todo") == "> - [x] todo")
        #expect(MarkdownChecklistSupport.toggledLine(">> - [x] done") == ">> - [ ] done")
        #expect(MarkdownChecklistSupport.toggledLine("> ○ legacy") == "> ● legacy")
        #expect(MarkdownChecklistSupport.toggledText("> a quote\n> - [ ] todo", lineIndex: 1) == "> a quote\n> - [x] todo")
        #expect(MarkdownChecklistSupport.toggledLine("> just a quote") == nil)

        // `lineInfo(in:)` stays unquoted: `MarkdownListSupport.lineInfo` builds on it.
        #expect(MarkdownChecklistSupport.lineInfo(in: "> - [ ] todo") == nil)
    }

    /// Return-continuation and styling must agree about every quoted line: continuation carries a
    /// list marker onto the next line exactly when the styler reads the line as a list item.
    @Test func continuationAndStylingAgreeAboutQuotedListLines() throws {
        let lines = [
            "> - [ ] todo item", "> - [x] done", "> - point", "> 1. step", "> ○ legacy",
            ">> - [ ] nested", "> plain quote", "> -not a list", "> [ ] no bullet"
        ]
        var listCount = 0
        for line in lines {
            let mutation = try #require(MarkdownLineBreakSupport.mutation(
                in: line,
                selection: NSRange(location: (line as NSString).length, length: 0)
            ))
            let quote = try #require(MarkdownQuoteSupport.lineInfo(in: line))
            let quotePrefix = (line as NSString).substring(with: quote.prefixRange)
            let continuesAList = mutation.replacement != "\n" + quotePrefix
            let styledAsList = MarkdownQuoteSupport.listLineInfo(in: line) != nil
            #expect(continuesAList == styledAsList, "\(line)")
            if styledAsList { listCount += 1 }
        }
        #expect(listCount == 6, "non-vacuity: both sides of the relation are exercised")
    }

    #if os(macOS)
    /// The macOS stylist itself, not just the helper: a quoted task line keeps its quote rail AND
    /// gets the drawn checkbox over the list prefix after `> `, indented inside the rail.
    @MainActor
    @Test func macOSStylesAQuotedTaskLineAsBothQuoteAndCheckbox() throws {
        let markdown = "> a quote line\n> - [ ] todo item\n> - [x] done item\n> - point"
        let storage = NSTextStorage()
        let layout = CadenceLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: 400, height: 1000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = CadenceTextView(frame: CGRect(x: 0, y: 0, width: 440, height: 600), textContainer: container)
        view.isRichText = true
        view.font = MarkdownStylist.baseFont
        view.typingAttributes = MarkdownStylist.baseAttributes
        view.string = markdown
        MarkdownStylist.apply(to: view)
        let styled = try #require(view.textStorage)
        let text = markdown as NSString

        let todoLine = text.range(of: "> - [ ] todo item")
        let doneLine = text.range(of: "> - [x] done item")
        let bulletLine = text.range(of: "> - point")
        let quoteIndent = MarkdownQuoteSupport.paragraphIndent(depth: 1)

        for line in [todoLine, doneLine] {
            // Still one quote block…
            #expect(styled.attribute(.cadenceMarkdownQuoteDepth, at: line.location, effectiveRange: nil) as? Int == 1)
            // …and the box is drawn over exactly the `- [ ] ` after the hidden `> `.
            #expect(styled.attribute(.cadenceMarkdownChecklistBox, at: line.location, effectiveRange: nil) == nil)
            var boxRange = NSRange(location: NSNotFound, length: 0)
            let box = styled.attribute(.cadenceMarkdownChecklistBox, at: line.location + 2,
                                       longestEffectiveRange: &boxRange, in: line)
            #expect(box is Bool)
            #expect(boxRange == NSRange(location: line.location + 2, length: 6))
            // Indented inside the rail: the quote's own indent plus the checklist's.
            let paragraph = try #require(styled.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle)
            let checkboxIndent = MarkdownListIndentMetrics.contentIndent(level: 0, markerWidth: 2)
            #expect(paragraph.firstLineHeadIndent == quoteIndent + checkboxIndent)
            #expect(paragraph.headIndent == paragraph.firstLineHeadIndent)
        }
        #expect(styled.attribute(.cadenceMarkdownChecklistBox, at: doneLine.location + 2, effectiveRange: nil) as? Bool == true)
        #expect(styled.attribute(.strikethroughStyle, at: doneLine.location + 8, effectiveRange: nil) != nil)
        #expect(styled.attribute(.strikethroughStyle, at: todoLine.location + 8, effectiveRange: nil) == nil)

        // A quoted bullet gets the list's marker spacing, and still no box.
        #expect(styled.attribute(.kern, at: bulletLine.location + 2, effectiveRange: nil) as? Double == 4)
        #expect(styled.attribute(.cadenceMarkdownChecklistBox, at: bulletLine.location + 2, effectiveRange: nil) == nil)

        // The plain quote line above is untouched by any of this.
        let plain = try #require(styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(plain.firstLineHeadIndent == quoteIndent)
    }
    #endif
}
