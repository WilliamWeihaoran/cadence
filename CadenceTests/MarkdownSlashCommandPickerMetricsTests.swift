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
}
#endif
