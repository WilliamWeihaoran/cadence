#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Three Mac rows that drew a long title as one unbreakable line ([[T-18341]], [[T-18342]],
/// [[T-18343]]). The runs below are a real seam; the rest pins the view modifiers that do the
/// wrapping, because a SwiftUI layout has no unit seam. None of it was seen on screen.
@MainActor
struct CadenceMacLongTitleLayoutTests {

    // MARK: T-18341 — the title field's previews wrap with the field

    @Test func thePriorityPreviewIsTheFieldsTextInOneRunOfWords() throws {
        let typed = "Rewrite the onboarding checklist for new contractors before the quarterly review !!"
        let segments = try #require(TaskTitleSupport.priorityShortcutSegments(in: typed))
        let runs = TaskTitleEntryField.priorityShortcutPreviewRuns(segments)

        #expect(runs.map(\.text).joined() == typed)
        #expect(runs.map(\.isMarker) == [false, true])
    }

    @Test func bothMarksAreRunsOfTheirOwnAroundThePlainTitle() throws {
        let segments = try #require(TaskTitleSupport.priorityShortcutSegments(in: "!! ship it !!!"))
        #expect(TaskTitleEntryField.priorityShortcutPreviewRuns(segments) == [
            .init(text: "!!", isMarker: true),
            .init(text: " ship it", isMarker: false),
            .init(text: " !!!", isMarker: true),
        ])

        let leading = try #require(TaskTitleSupport.priorityShortcutSegments(in: "! call mom"))
        #expect(TaskTitleEntryField.priorityShortcutPreviewRuns(leading) == [
            .init(text: "!", isMarker: true),
            .init(text: " call mom", isMarker: false),
        ])
    }

    /// The field wraps at its host's `lineLimit` (`1...3` in the board composer), and each preview
    /// drawn over it now does too. Before, all three were `.lineLimit(1).fixedSize()`.
    @Test func everyTitlePreviewWrapsToTheFieldsLineLimit() throws {
        let source = try Self.source("Cadence/macOS/Views/TaskTitleEntryField.swift")
        #expect(!source.contains(".lineLimit(1)"))

        let priority = try Self.body(of: "private var priorityShortcutPreview: some View {", in: source)
        #expect(priority.contains(".lineLimit(lineLimit)"))
        #expect(priority.contains(".fixedSize(horizontal: false, vertical: true)"))

        let title = try Self.body(of: "private var inlineShortcutPreviewTitle: some View {", in: source)
        #expect(title.contains(".lineLimit(lineLimit)"))
        #expect(title.contains(".fixedSize(horizontal: false, vertical: true)"))
        for preview in ["private var tildePreview: some View {", "private var tagPreview: some View {"] {
            #expect(try Self.body(of: preview, in: source).contains("inlineShortcutPreviewTitle"))
        }
    }

    // MARK: T-18342 — the embed popover's Time row shows the time

    @Test func theTimeRowDrawsTheTimeOutsideTheHiddenStepperLabel() throws {
        let source = try Self.source("Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift")
        let row = try Self.body(of: "private var scheduledTimeControls: some View {", in: source)
        let visible = try #require(row.range(of: "Text(scheduledTimeLabel)"))
        let stepper = try #require(row.range(of: "Stepper("))
        #expect(visible.lowerBound < stepper.lowerBound)
    }

    // MARK: T-18343 — the "Start with" template row wraps

    @Test func theTemplateRowWrapsAndItsNamesCanTruncate() throws {
        let source = try Self.source("Cadence/macOS/Views/NoteEditorAccessoryViews.swift")
        let placeholder = try Self.body(of: "struct NoteEmptyBodyPlaceholder: View {", in: source)
        #expect(placeholder.contains("CadenceWrappingHStack("))

        let button = try Self.body(of: "private struct NoteTemplateTextButton: View {", in: source)
        #expect(button.contains(".lineLimit(1)"))
        #expect(!button.contains(".fixedSize()"))
    }

    // MARK: helpers

    private static func source(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The text from `opener` to its matching close brace.
    private static func body(of opener: String, in source: String) throws -> String {
        let start = try #require(source.range(of: opener))
        var depth = 0
        var index = start.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        Issue.record("no closing brace for \(opener)")
        return ""
    }
}
#endif
