#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-18082]]: the Mac list-note row's double-click rename edits a draft.** It used to hand the
/// shared row's `TextField` the live `note.title`, so every keystroke was the stored name: Escape
/// "left the field" with the typed text kept, a cleared field saved as "Untitled", and nothing
/// committed. `ListNoteRow.commitRename` is now the rename's one write; the view wiring around it
/// is pinned from source, because the view has no seam.
struct CadenceListNoteRowRenameTests {
    private struct CommitRefused: Error {}

    private func savedNote(title: String) throws -> (ModelContainer, ModelContext, Note) {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let note = Note(kind: .list, title: title)
        note.updatedAt = Date(timeIntervalSince1970: 1_000)
        context.insert(note)
        try context.save()
        return (container, context, note)
    }

    /// A rename is normalised, stamped and in the store — read through a second context — with
    /// nothing left pending for an unrelated save or rollback to decide.
    @Test func aRenameIsTrimmedStampedAndCommitted() throws {
        let (container, context, note) = try savedNote(title: "Groceries")
        let now = Date(timeIntervalSince1970: 2_000)

        let outcome = try ListNoteRow.commitRename(note, draft: "  Weekly shop \n", in: context, now: now)

        #expect(outcome == .saved)
        #expect(!context.hasChanges, "the rename is still pending after commitRename returned")
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<Note>()).first)
        #expect(stored.title == "Weekly shop")
        #expect(stored.updatedAt == now)
    }

    /// **The defect's second half.** A cleared or whitespace-only field is refused: the note keeps
    /// its name instead of becoming "Untitled", and nothing is written.
    @Test func aBlankDraftIsRefusedAndWritesNothing() throws {
        let (_, context, note) = try savedNote(title: "Groceries")

        for draft in ["", "   ", "\n"] {
            #expect(try ListNoteRow.commitRename(note, draft: draft, in: context) == .refusedBlank)
            #expect(note.title == "Groceries")
            #expect(note.updatedAt == Date(timeIntervalSince1970: 1_000))
            #expect(!context.hasChanges)
        }
    }

    /// Return on an untouched draft closes the field without stamping the note as edited.
    @Test func anUnchangedDraftWritesNothing() throws {
        let (_, context, note) = try savedNote(title: "Groceries")

        #expect(try ListNoteRow.commitRename(note, draft: " Groceries ", in: context) == .unchanged)
        #expect(note.updatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(!context.hasChanges)
    }

    /// A refused commit rethrows with the title and `updatedAt` back on the live note, and leaves an
    /// unrelated pending edit alone — a snapshot undo, not a `rollback()`.
    @Test func aRefusedRenamePutsTheNoteBack() throws {
        let (_, context, note) = try savedNote(title: "Groceries")
        let bystander = Area(name: "Home")
        context.insert(bystander)
        try context.save()
        bystander.name = "Home, being typed"

        #expect(throws: CommitRefused.self) {
            try ListNoteRow.commitRename(note, draft: "Weekly shop", in: context, commit: { _ in throw CommitRefused() })
        }

        #expect(note.title == "Groceries", "the refused rename left the new name on the row")
        #expect(note.updatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(bystander.name == "Home, being typed", "the refused rename discarded unrelated pending work")
    }

    /// The view: the field binds the draft, never the model; both ways out reach `finishRename`;
    /// Escape cancels without a write; the draft is seeded only when a rename starts.
    @Test func theRowEditsADraftAndCommitsThroughTheOneWrite() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(
            contentsOf: root.appendingPathComponent("Cadence/macOS/Views/ListNotesListSupportViews.swift"),
            encoding: .utf8
        )
        let source = CadenceSourceScan.codeOnly(raw)
        let body = try #require(CadenceSourceScan.declarationBody("struct ListNoteRow: View", in: source))

        #expect(!body.contains("$note.title"))
        #expect(body.contains("editingTitle: isEditingTitle ? $draftTitle : nil"))
        #expect(body.contains("onSubmitTitle: { finishRename(leavingField: false) }"))
        #expect(body.contains("onTitleFocusLost: { finishRename(leavingField: true) }"))
        #expect(body.contains(".onExitCommand(perform: cancelRename)"))
        #expect(body.contains("try Self.commitRename(note, draft: draftTitle, in: modelContext)"))
        #expect(body.contains("CadenceInlineFailureNotice(text: renameFailureNotice)"))

        let cancel = try #require(CadenceSourceScan.declarationBody("private func cancelRename()", in: body))
        #expect(!cancel.contains("note."), "Escape must not write the note")
        let begin = try #require(CadenceSourceScan.declarationBody("private func beginRename()", in: body))
        #expect(begin.contains("guard !isEditingTitle else { return }"))
        #expect(begin.contains("draftTitle = note.title"))

        // The shared row reports focus loss rather than leaving the field drawn open.
        let shared = CadenceSourceScan.codeOnly(try String(
            contentsOf: root.appendingPathComponent("Cadence/Shared/CadenceNoteFolderSupport.swift"),
            encoding: .utf8
        ))
        #expect(shared.contains("onTitleFocusLost?()"))
    }
}
#endif
