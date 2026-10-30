import Foundation
import Testing
@testable import Cadence

/// **What the note editor's two typing menus offer — the `/` commands and the `[[` notes.**
///
/// [[T-8581]]: iOS's `/` strip took the first eight matches, so a bare `/` never reached Table,
/// Highlight, Image or seven more. [[T-8582]]: iOS's `[[` strip and Insert Note Link sheet offered
/// the note being edited, whose link every reader of it then dropped.
///
/// Both answers are shared, pure `Services/` functions and are tested here as behaviour. The iOS
/// call sites are inside a SwiftUI view this macOS target does not compile, so the second half of
/// each test is a source scan that the call site reads the shared answer and adds nothing to it.
struct MarkdownEditorOfferedChoicesTests {
    private static let surfacePath = "Cadence/iOS/iOSMarkdownEditingSurface.swift"

    // MARK: - T-8581

    @Test func aBareSlashOffersEveryCommandInMenuOrder() {
        let all = MarkdownSlashCommand.all
        // Non-vacuity: more commands than the eight the strip used to keep, so "every command"
        // and "the first eight" are different answers here.
        #expect(all.count > 8)

        let offered = MarkdownSlashCommand.matching(all, query: "")
        #expect(offered.map(\.id) == all.map(\.id))
        #expect(offered.map(\.id).contains("table"), "a bare / still cannot reach /table")
    }

    @Test func aQueryOffersEveryMatchAndOnlyMatches() {
        let all = MarkdownSlashCommand.all
        // "e" is in most ids or titles; the count it matches must be more than eight for the
        // relation below to argue anything about a cap.
        let offered = MarkdownSlashCommand.matching(all, query: "e")
        let expected = all.filter {
            $0.id.localizedCaseInsensitiveContains("e") || $0.title.localizedCaseInsensitiveContains("e")
        }
        #expect(expected.count > 8)
        #expect(offered.map(\.id) == expected.map(\.id))

        #expect(MarkdownSlashCommand.matching(all, query: "TABLE").map(\.id) == ["table"])
        #expect(MarkdownSlashCommand.matching(all, query: "zzzz-none").isEmpty)
    }

    @Test func theIOSSlashStripReadsTheSharedFilterWithNoCap() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.surfacePath))
        let choices = try #require(
            CadenceSourceScan.functionBody(named: "slashCommandChoices", in: code),
            "slashCommandChoices() could not be read; the assertions below would be measuring nothing"
        )
        #expect(choices.contains("MarkdownSlashCommand.matching(offered, query: context.query)"))
        #expect(choices.contains(".prefix(") == false, "the iOS / strip caps its commands again")
        #expect(choices.contains("localizedCaseInsensitiveContains") == false, "the iOS / strip re-spells the filter")
    }

    // MARK: - T-8582

    @Test func theNoteBeingEditedIsNeverOfferedAsALinkTarget() {
        let editing = Note(kind: .permanent, title: "Editing")
        let peerA = Note(kind: .permanent, title: "Peer A")
        let peerB = Note(kind: .meeting, title: "Peer B")
        let notes = [peerA, editing, peerB]

        let linkable = MarkdownReferenceCompletionSupport.linkableNotes(notes, excludingNoteID: editing.id)
        #expect(linkable.map(\.id) == [peerA.id, peerB.id], "the edited note is offered, or a peer was dropped or reordered")

        // A host with no note of its own (a task's notes, a template) excludes nothing.
        #expect(MarkdownReferenceCompletionSupport.linkableNotes(notes, excludingNoteID: nil).map(\.id) == notes.map(\.id))
    }

    @Test func theIOSLinkOffersReadTheLinkableNotesNotTheWholeQuery() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.surfacePath))
        #expect(code.contains(
            "MarkdownReferenceCompletionSupport.linkableNotes(referenceNotes, excludingNoteID: editingNote?.id)"
        ))

        let choices = try #require(
            CadenceSourceScan.functionBody(named: "referenceCompletionChoices", in: code),
            "referenceCompletionChoices() could not be read"
        )
        #expect(choices.contains(".candidateNotes(from: linkableNotes, query: context.query)"))
        #expect(choices.contains("candidateNotes(from: referenceNotes") == false, "the [[ strip offers the edited note again")

        let toolbar = try #require(
            CadenceSourceScan.functionBody(named: "applyToolbarCommand", in: code),
            "applyToolbarCommand() could not be read"
        )
        #expect(toolbar.contains("case .noteLink where !linkableNotes.isEmpty:"))

        // The Insert Note Link sheet, presented from `body`.
        #expect(code.contains("kind: kind,\n                notes: linkableNotes,"))
        #expect(code.contains("kind: kind,\n                notes: referenceNotes,") == false)
    }
}
