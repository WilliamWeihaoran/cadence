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

    /// **[[T-18095]]: a rename survives the note's next body commit.** A list note's title follows
    /// its first `# H1`, so a rename that wrote only `title` left `# Groceries` in the body and the
    /// next commit through the shared path read it back, undoing the rename. The rename now rewrites
    /// the heading, and the rest of the body is untouched.
    @Test func aRenameSurvivesTheNextBodyCommit() throws {
        let (container, context, note) = try savedNote(title: "Groceries")
        note.content = "# Groceries\n\n- milk"
        try context.save()

        #expect(try ListNoteRow.commitRename(note, draft: "Weekly shop", in: context) == .saved)
        #expect(note.content == "# Weekly shop\n\n- milk")

        // The next body edit, through the commit path every iOS editor and the shared support use.
        CadenceCoreNoteSupport.update(note, content: note.content + "\n- eggs", in: context)
        try context.save()

        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<Note>()).first)
        #expect(stored.title == "Weekly shop", "the next body commit put the old heading back as the title")
        #expect(stored.content == "# Weekly shop\n\n- milk\n- eggs")
    }

    /// A refused rename puts the rewritten heading back with the title.
    @Test func aRefusedRenamePutsTheHeadingBack() throws {
        let (_, context, note) = try savedNote(title: "Groceries")
        note.content = "# Groceries\n\n- milk"
        try context.save()

        #expect(throws: CommitRefused.self) {
            try ListNoteRow.commitRename(note, draft: "Weekly shop", in: context, commit: { _ in throw CommitRefused() })
        }
        #expect(note.content == "# Groceries\n\n- milk")
    }

    /// The rewrite's edges: only a first-line H1 the read rule would read is rewritten, only for the
    /// kinds that follow it, and an empty name writes the seed shape the read rule ignores.
    @Test func theHeadingRewriteTouchesOnlyAHeadingTheTitleFollows() {
        #expect(MarkdownNoteTitleSync.content("# Old\nbody", renamedTo: " New ", kind: .list) == "# New\nbody")
        #expect(MarkdownNoteTitleSync.content("# Old", renamedTo: "New", kind: .permanent) == "# New")
        #expect(MarkdownNoteTitleSync.content("# New\nbody", renamedTo: "New", kind: .list) == nil)
        #expect(MarkdownNoteTitleSync.content("prose\n# Old", renamedTo: "New", kind: .list) == nil)
        #expect(MarkdownNoteTitleSync.content("## Old", renamedTo: "New", kind: .list) == nil)
        #expect(MarkdownNoteTitleSync.content("# Old", renamedTo: "New", kind: .meeting) == nil)
        #expect(MarkdownNoteTitleSync.content("# Old\n", renamedTo: "", kind: .list) == "# \n")
        #expect(MarkdownNoteTitleSync.title(from: "# \n", kind: .list, currentTitle: "") == nil)
    }

    /// `NoteEditorPane`'s title field renames through the same helper, after landing any armed body
    /// commit (which holds the old heading). The view has no seam, so this is pinned from source.
    @Test func theEditorTitleFieldRenamesTheHeadingToo() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = CadenceSourceScan.codeOnly(try String(
            contentsOf: root.appendingPathComponent("Cadence/macOS/Views/NoteEditorPane.swift"),
            encoding: .utf8
        ))
        let binding = try #require(CadenceSourceScan.declarationBody("private var titleBinding: Binding<String>", in: source))
        #expect(!binding.contains("note.title = $0"))
        let flush = try #require(binding.range(of: "if pendingFallbackContentSyncTask != nil { flushPendingEditorContent() }"))
        let rename = try #require(binding.range(of: "MarkdownNoteTitleSync.rename(note, to: $0)"))
        #expect(flush.lowerBound < rename.lowerBound)
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

    /// **[[T-18356]] (a): the rename field is labelled.** It was `TextField("", ...)`, so an untitled
    /// note's row became a blank box with nothing for VoiceOver to name it by. It now carries the
    /// placeholder the editor's own title field uses, as its accessibility label too.
    @Test func theRenameFieldHasAPlaceholderAndAnAccessibilityLabel() throws {
        #expect(NoteFolderListRow.renameFieldLabel == "Note title")
        let shared = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceNoteFolderSupport.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("struct NoteFolderListRow: View", in: shared))
        #expect(!row.contains("TextField(\"\""), "the rename field has no placeholder again")
        #expect(row.contains("TextField(Self.renameFieldLabel, text: editingTitle)"))
        #expect(row.contains(".accessibilityLabel(Self.renameFieldLabel)"))

        let editor = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift"))
        #expect(editor.contains("TextField(\"\(NoteFolderListRow.renameFieldLabel)\", text: titleBinding)"),
                "the row's rename field and the editor's title field name the same thing two ways")
    }

    /// **[[T-18356]] (b): a refused blank Return says why.** The field stays open, as [[T-18082]]
    /// decided, and the row now says the note needs a title; leaving the field drops the draft and
    /// closes on the stored name, so it says nothing, and neither does a rename that went through.
    @Test func aRefusedBlankReturnSaysTheNoteNeedsATitle() throws {
        #expect(ListNoteRow.renameNotice(after: .refusedBlank, leavingField: false) == ListNoteRow.blankTitleNotice)
        #expect(ListNoteRow.blankTitleNotice == "A note needs a title.")
        #expect(ListNoteRow.renameNotice(after: .refusedBlank, leavingField: true) == nil)
        for leaving in [false, true] {
            #expect(ListNoteRow.renameNotice(after: .saved, leavingField: leaving) == nil)
            #expect(ListNoteRow.renameNotice(after: .unchanged, leavingField: leaving) == nil)
        }

        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesListSupportViews.swift"))
        let finish = try #require(CadenceSourceScan.declarationBody("private func finishRename(leavingField: Bool)", in: source))
        #expect(finish.contains("renameFailureNotice = Self.renameNotice(after: outcome, leavingField: leavingField)"))
    }
}
#endif
