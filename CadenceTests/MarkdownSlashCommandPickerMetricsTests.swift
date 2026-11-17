#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-7231]]: the Mac `/` picker's token column must hold every token it shows on one line.
@MainActor
struct MarkdownSlashCommandPickerMetricsTests {
    /// The built-in table plus every note template the editor appends, which is the list
    /// `MarkdownEditorView` hands the picker.
    private var everyCommand: [MarkdownSlashCommand] {
        MarkdownSlashCommand.all
            + MarkdownSlashCommand.templateCommands(for: NoteTemplateLibrary.editableTemplates(overridesRaw: ""))
    }

    @Test func theTokenColumnHoldsEveryBuiltInAndTemplateToken() {
        let commands = everyCommand
        let column = MarkdownSlashCommandPickerMetrics.tokenColumnWidth(for: commands)
        for command in commands {
            let token = MarkdownSlashCommandPickerMetrics.token(for: command)
            #expect(
                MarkdownSlashCommandPickerMetrics.tokenWidth(token) <= column,
                "\(token) is wider than the column it is drawn in"
            )
        }
    }

    /// The fixed column this replaced was too narrow for at least one shipped token; if this
    /// stops holding, the test above is no longer exercising a widened column.
    @Test func atLeastOneShippedTokenIsWiderThanTheOldFixedColumn() {
        let widest = everyCommand
            .map { MarkdownSlashCommandPickerMetrics.tokenWidth(MarkdownSlashCommandPickerMetrics.token(for: $0)) }
            .max() ?? 0
        #expect(widest > MarkdownSlashCommandPickerMetrics.minimumTokenColumnWidth)
    }

    /// The popover widens by exactly what the column did, so the title column keeps its room.
    @Test func thePickerGrowsByWhatTheColumnGrew() {
        let commands = everyCommand
        let columnGrowth = MarkdownSlashCommandPickerMetrics.tokenColumnWidth(for: commands)
            - MarkdownSlashCommandPickerMetrics.minimumTokenColumnWidth
        let pickerGrowth = MarkdownSlashCommandPickerMetrics.pickerWidth(for: commands)
            - MarkdownSlashCommandPickerMetrics.minimumPickerWidth
        #expect(columnGrowth > 0)
        #expect(pickerGrowth == columnGrowth)
    }

    /// A short list keeps the old floor rather than shrinking the picker.
    @Test func aListOfShortTokensKeepsTheFloor() throws {
        let short = try #require(MarkdownSlashCommand.all.first { $0.id == "h1" })
        #expect(
            MarkdownSlashCommandPickerMetrics.tokenColumnWidth(for: [short])
                == MarkdownSlashCommandPickerMetrics.minimumTokenColumnWidth
        )
        #expect(
            MarkdownSlashCommandPickerMetrics.pickerWidth(for: [short])
                == MarkdownSlashCommandPickerMetrics.minimumPickerWidth
        )
    }

    /// [[T-7233]]: a bare `/` hands the picker more commands than it shows at once, and every
    /// list longer than the cap is exactly as tall as the cap -- the popover stops growing.
    @Test func aBareSlashListIsCappedAtTheVisibleRowLimit() {
        let limit = MarkdownSlashCommandPickerMetrics.visibleRowLimit
        let count = everyCommand.count
        #expect(count > limit, "non-vacuity: a bare `/` lists more rows than the cap")
        #expect((8...10).contains(limit), "the keeper's call was a cap of about 8-10 rows")
        #expect(MarkdownSlashCommandPickerMetrics.visibleRowCount(forRowCount: count) == limit)
        #expect(
            MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: count)
                == MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: limit)
        )
        #expect(
            MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: limit + 1)
                == MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: limit),
            "a list one longer than the cap is no taller than the cap"
        )
    }

    /// A list that fits is sized to its rows, not padded out to the cap.
    @Test func aShortListIsAsTallAsItsRows() {
        let limit = MarkdownSlashCommandPickerMetrics.visibleRowLimit
        #expect(MarkdownSlashCommandPickerMetrics.visibleRowCount(forRowCount: 3) == 3)
        #expect(
            MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: 3)
                < MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: limit)
        )
        #expect(
            MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: 2)
                < MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: 3)
        )
    }

    /// The view draws the capped height and keeps the keyboard highlight scrolled into view.
    @Test func thePickerScrollsAtTheCapAndFollowsTheHighlight() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift")
        let body = try #require(CadenceSourceScan.declarationBody(
            "private struct MarkdownSlashCommandPickerView: View", in: source))
        let compact = body.filter { !$0.isWhitespace }
        #expect(compact.contains("ScrollView(.vertical)"), "the rows past the cap must scroll")
        #expect(compact.contains(".frame(height:MarkdownSlashCommandPickerMetrics.listHeight(forRowCount:commands.count))"),
                "the list must be drawn at the capped height")
        #expect(compact.contains(".frame(height:MarkdownSlashCommandPickerMetrics.rowHeight)"),
                "each row must be the height the cap arithmetic assumes")
        #expect(compact.contains(".onChange(of:highlightedIndex){_,_inscrollToHighlighted(proxy)}"),
                "an arrow-key move must scroll the highlighted row into view")
        #expect(compact.contains("proxy.scrollTo(commands[highlightedIndex].id)"))
        #expect(compact.contains(".id(command.id)"), "scrollTo needs each row tagged with the id it scrolls to")
    }

    /// **[[T-9463]].** The `/`, `[[` and `#` popovers' rows filled `Color.clear` everywhere but the
    /// highlighted row and gave the row no content shape, so a click on an unhighlighted row's
    /// padding or the empty run beside its title hit nothing. Every row now wears the one shared
    /// plate, and the plate is the hit shape. (Source-read: SwiftUI's hit testing is not
    /// observable from a hosted view here; not seen on screen.)
    @Test func everyCompletionPopoverRowIsHitAcrossItsWholePlate() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift"))
        let plate = try #require(CadenceSourceScan.declarationBody(
            "private struct MarkdownPickerRowPlate: ViewModifier", in: source)).filter { !$0.isWhitespace }
        #expect(plate.contains(".background(shape.fill("), "non-vacuity: the plate draws the highlight fill")
        #expect(plate.contains(".contentShape(shape)"), "the row plate is not the row's hit shape")
        let pickers = [
            ("private struct MarkdownSlashCommandPickerView: View", 1),
            ("private struct MarkdownReferencePickerView: View", 1),
            ("private struct MarkdownTagPickerView: View", 2),
        ]
        for (declaration, rows) in pickers {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            #expect(
                body.components(separatedBy: ".modifier(MarkdownPickerRowPlate(isHighlighted:").count - 1 == rows,
                "\(declaration) does not draw its \(rows) row kind(s) on the shared plate"
            )
            #expect(!body.contains(": Color.clear"), "\(declaration) paints its own clear row fill again")
        }
    }

    /// **[[T-18395]].** A narrowed query puts the keyboard highlight back on the first row, so Return
    /// applies the row the user sees first; the same query (a re-render) keeps the row moved to.
    @Test func aChangedQueryPutsTheHighlightBackOnTheFirstRow() {
        // Down twice on `#`, then `work` typed: the list narrows and the third row must not stay lit.
        #expect(MarkdownPickerHighlight.index(current: 2, previousQuery: "", query: "work", count: 3) == 0)
        #expect(MarkdownPickerHighlight.index(current: 2, previousQuery: "wor", query: "work", count: 5) == 0)
        // A fresh open has no previous query.
        #expect(MarkdownPickerHighlight.index(current: 4, previousQuery: nil, query: "", count: 9) == 0)
        // Same query: the row is kept, and only clamped when the list shrank under it.
        #expect(MarkdownPickerHighlight.index(current: 2, previousQuery: "work", query: "work", count: 3) == 2)
        #expect(MarkdownPickerHighlight.index(current: 5, previousQuery: "work", query: "work", count: 3) == 2)
        #expect(MarkdownPickerHighlight.index(current: 1, previousQuery: "work", query: "work", count: 0) == 0)
    }

    /// The three controllers are AppKit popovers with no seam to drive from here, so each `update`
    /// is read from source: it asks the shared rule, with the PREVIOUS context's query (read before
    /// `self.context` is replaced), and no longer only clamps.
    @Test func everyCompletionPopoverResetsItsHighlightThroughTheSharedRule() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift"))
        let controllers = [
            "final class MarkdownSlashCommandPickerController",
            "final class MarkdownReferencePickerController",
            "final class MarkdownTagPickerController",
        ]
        for declaration in controllers {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            let update = try #require(CadenceSourceScan.declarationBody("func update(", in: body))
                .filter { !$0.isWhitespace }
            let rule = try #require(update.range(of: "highlightedIndex=MarkdownPickerHighlight.index(current:highlightedIndex,previousQuery:self.context?.query,query:context.query,"),
                                    "\(declaration).update does not reset its highlight through the shared rule")
            let replaced = try #require(update.range(of: "self.context=context"))
            #expect(rule.lowerBound < replaced.lowerBound, "\(declaration) reads the previous query after replacing it")
            #expect(!update.contains("highlightedIndex=min(highlightedIndex"), "\(declaration) only clamps again")
        }
    }
}
#endif
