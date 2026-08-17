import Foundation
import Testing
@testable import Cadence

@MainActor
struct MarkdownSlashCommandMutationSupportTests {
    @Test func todoCommandUsesCanonicalCadenceChecklistMarker() throws {
        let command = try #require(MarkdownSlashCommand.all.first { $0.id == "todo" })
        let context = MarkdownSlashCommandContext(
            range: NSRange(location: 0, length: 5),
            indentation: "",
            query: "todo",
            cursorLocation: 5
        )

        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)

        #expect(mutation.replacementRange == NSRange(location: 0, length: 5))
        #expect(mutation.replacement == "○ ")
        #expect(mutation.selection == NSRange(location: 2, length: 0))
        #expect(mutation.followUp == .none)
    }

    @Test func indentedCommandPreservesIndentationAndCaretOffset() throws {
        let command = try #require(MarkdownSlashCommand.all.first { $0.id == "bullet" })
        let context = MarkdownSlashCommandContext(
            range: NSRange(location: 8, length: 12),
            indentation: "    ",
            query: "bullet",
            cursorLocation: 20
        )

        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)

        #expect(mutation.replacement == "    • ")
        #expect(mutation.selection == NSRange(location: 14, length: 0))
    }

    @Test func imageCommandClearsTokenBeforeOpeningPicker() throws {
        let command = try #require(MarkdownSlashCommand.all.first { $0.id == "image" })
        let context = MarkdownSlashCommandContext(
            range: NSRange(location: 4, length: 10),
            indentation: "  ",
            query: "image",
            cursorLocation: 14
        )

        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)

        #expect(mutation.replacement == "  ")
        #expect(mutation.selection == NSRange(location: 6, length: 0))
        #expect(mutation.followUp == .chooseImage)
    }

    @Test func typedSpaceCompletionUsesSameMutation() throws {
        let text = "Intro\n    /todo " as NSString
        let mutation = try #require(MarkdownSlashCommandMutationSupport.typedMutation(
            in: text,
            cursor: text.length
        ))

        #expect(mutation.replacementRange == NSRange(location: 6, length: 10))
        #expect(mutation.replacement == "    ○ ")
        #expect(mutation.selection == NSRange(location: 12, length: 0))
    }

    @Test func typedSpaceCompletionIgnoresPickerCommands() {
        let text = "/image " as NSString

        #expect(MarkdownSlashCommandMutationSupport.typedMutation(in: text, cursor: text.length) == nil)
    }
}
