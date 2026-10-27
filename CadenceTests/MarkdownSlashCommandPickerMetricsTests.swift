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
}
#endif
