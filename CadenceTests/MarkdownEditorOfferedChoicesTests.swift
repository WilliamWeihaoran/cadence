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

    // MARK: - T-8583, the Mac hosts

    /// **The Mac's core-notes panel offered the note being typed in as a `[[` target** — the
    /// T-8582 residual one platform over. `NoteEditorPane` already filtered itself out; `NotePanel`
    /// handed the editor its whole `@Query`. It hands the shared linkable set now, while the
    /// reference it opens still resolves against every note.
    @Test func theMacNotePanelOffersTheLinkableNotesNotTheWholeQuery() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotePanel.swift"))
        let editor = try #require(
            CadenceSourceScan.functionBody(named: "noteEditor", in: code),
            "noteEditor(for:) could not be read"
        )
        #expect(editor.contains("MarkdownEditor("), "non-vacuity: wrong body read")
        #expect(editor.contains(
            "referenceNotes: MarkdownReferenceCompletionSupport.linkableNotes(referenceNotes, excludingNoteID: note.id),"
        ))
        #expect(!editor.contains("referenceNotes: referenceNotes,"), "the panel offers the edited note again")
        // Opening a reference still reads the whole set.
        #expect(code.contains("TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes)"))
    }

    /// **Why filtering the editor's `referenceNotes` cannot thin out anything but the `[[` menu.**
    /// The Mac editor reads the array in exactly one place — the completion source. The reference
    /// strip and backlinks are each host's own, computed from the full set.
    @Test func theMacEditorReadsItsReferenceNotesOnlyForCompletion() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorView.swift"))
        #expect(code.contains("var referenceNotes: [Note] = []"), "non-vacuity: wrong file read")
        #expect(CadenceSourceScan.matchCount(#"\breferenceNotes\b"#, in: code) == 2)
        #expect(code.contains("MarkdownReferenceCompletionSupport.candidateNotes(from: referenceNotes, query: \"\")"))
    }

    /// **`TaskNoteEditorPane` (`ListNotesSupportViews`) has no note of its own to exclude.** It
    /// edits a task's `notes` string, not a `Note`, so every `Note` in `relatedNotes` is a fair
    /// link target and the T-8583 hypothesis about it does not hold. Pinned so a future host
    /// that starts editing a `Note` there has to revisit it.
    @Test func theMacTaskNotesEditorEditsATaskAndNotANote() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesSupportViews.swift"))
        let pane = try #require(CadenceSourceScan.declarationBody("struct TaskNoteEditorPane: View", in: code))
        #expect(pane.contains("@Bindable var task: AppTask"))
        #expect(pane.contains("get: { loadedTaskID == task.id ? editorContent : task.notes },"))
        #expect(CadenceSourceScan.matchCount(#"(?:var|let) \w+: Note\??\s"#, in: pane) == 0, "the pane holds a Note of its own now")
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

    // MARK: - T-8751, the event editors

    /// **The event editor's Notes field offered its own note as a `[[` target**, on both platforms.
    /// Since [[T-8161]] that field writes the event's `Note` itself, so it is a note host like any
    /// other and the T-8582/T-8583 rule applies. Each host filters at the call site (not
    /// `editingNote:` on iOS, which would also draw the full editor's reference panel here), and a
    /// tapped link still resolves against every note.
    @Test func theMacEventPopoverNotesFieldDoesNotOfferTheEventsOwnNote() throws {
        try expectEventNotesFieldExcludesItsOwnNote(
            path: "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift",
            declaration: "private var notesField: some View",
            opener: "TaskNoteLinkRouting.note(id: id, title: title, in: allNotes)"
        )
    }

    @Test func theIOSEventEditSheetNotesFieldDoesNotOfferTheEventsOwnNote() throws {
        try expectEventNotesFieldExcludesItsOwnNote(
            path: "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            declaration: "private var notesSection: some View",
            opener: "iOSMarkdownReferenceResolver.note(for: target, in: allNotes)"
        )
    }

    private func expectEventNotesFieldExcludesItsOwnNote(path: String, declaration: String, opener: String) throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let field = try #require(CadenceSourceScan.declarationBody(declaration, in: code), "\(declaration) could not be read")
        #expect(field.contains("CadenceEventNotesField("), "non-vacuity: wrong body read")
        #expect(field.contains(
            "referenceNotes: MarkdownReferenceCompletionSupport.linkableNotes(allNotes, excludingNoteID: linkedEventNote?.id),"
        ))
        #expect(!field.contains("referenceNotes: allNotes,"), "the event field offers its own note again")
        #expect(code.contains(opener), "opening a link must still read every note")
    }
}
