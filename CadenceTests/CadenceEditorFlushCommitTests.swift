import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-4971: **the macOS text editors wrote the model while typing and never committed**, not even
/// at their focus-loss flush. The typing rode the context's autosave, and any unrelated
/// `rollback()` in the app's single `ModelContext` took it with it ([[T-322]]'s cost).
///
/// Keeper's call: commit at the existing flush points (focus loss, `flushPendingEditorContent`,
/// `persistEditorContentIfNeeded`) — not per keystroke, and no new debounce. Every site commits
/// through one helper, `CadencePendingChangePersistence.commitTypedContent`, so the behaviour is
/// proved once on the helper and each site is pinned to call it.
///
/// Every store here is an in-memory container built by the test; success is read from a **second**
/// `ModelContext`, because only the store answers whether the text would survive.
@MainActor
struct CadenceEditorFlushCommitTests {

    private struct CommitRefused: Error {}

    private func storedTask(id: UUID, in container: ModelContainer) throws -> AppTask? {
        let reader = ModelContext(container)
        return try reader.fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })).first
    }

    private func storedNote(id: UUID, in container: ModelContainer) throws -> Note? {
        let reader = ModelContext(container)
        return try reader.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - The helper's behaviour

    /// The bug itself: typed notes, flushed, then an unrelated `rollback()` on the same context.
    @Test func typedTaskNotesReachTheStoreAndSurviveAnUnrelatedRollback() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let task = AppTask(title: "Draft the brief")
        editing.insert(task)
        try editing.save()

        task.notes = "typed at the flush"
        #expect(CadencePendingChangePersistence.commitTypedContent(in: editing))

        #expect(try storedTask(id: task.id, in: container)?.notes == "typed at the flush")
        editing.rollback()
        #expect(try storedTask(id: task.id, in: container)?.notes == "typed at the flush")
    }

    /// The Notes page's two typed fields, body and title, through the same door.
    @Test func typedNoteContentAndTitleReachTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let note = Note(kind: .list, title: "Old", content: "old body")
        editing.insert(note)
        try editing.save()

        note.title = "New title"
        note.content = "new body"
        #expect(CadencePendingChangePersistence.commitTypedContent(in: editing))

        let stored = try #require(try storedNote(id: note.id, in: container))
        #expect(stored.title == "New title")
        #expect(stored.content == "new body")
    }

    /// A refusal is reported and is **not** undone: undoing would overwrite the text under the
    /// caret. The typed text stays pending in the editing context for the next flush.
    @Test func aRefusedFlushLeavesTheTypedTextPendingRatherThanUndoingIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let task = AppTask(title: "Draft the brief")
        editing.insert(task)
        try editing.save()

        task.notes = "typed, then refused"
        let committed = CadencePendingChangePersistence.commitTypedContent(in: editing) { _ in
            throw CommitRefused()
        }

        #expect(!committed)
        #expect(task.notes == "typed, then refused")
        #expect(editing.hasChanges)
        #expect(try storedTask(id: task.id, in: container)?.notes == "")
    }

    /// A focus loss with nothing typed writes nothing.
    @Test func aFlushWithNothingPendingDoesNotCommit() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        var commits = 0
        let answered = CadencePendingChangePersistence.commitTypedContent(in: editing) { _ in commits += 1 }
        #expect(answered)
        #expect(commits == 0)
    }

    // MARK: - Every flush point reaches it

    static let commitCall = "CadencePendingChangePersistence.commitTypedContent(in: modelContext)"

    /// Each editor's `persistEditorContentIfNeeded` — reached from both the existing debounced
    /// fallback sync and the focus-loss flush — commits. One file per editor named in T-4971.
    @Test(arguments: [
        "Cadence/macOS/Views/NoteEditorPane.swift",
        "Cadence/macOS/Views/ListNotesSupportViews.swift",
        "Cadence/macOS/Views/FocusNotesPanel.swift",
        "Cadence/macOS/Views/TaskInspectorContentSupportViews.swift",
    ])
    func everyEditorsPersistCommits(path: String) throws {
        let source = try CadenceSourceScan.sourceFile(path)
        let body = try #require(CadenceSourceScan.functionBody(named: "persistEditorContentIfNeeded", in: source))
        #expect(body.contains(Self.commitCall), "\(path)'s persistEditorContentIfNeeded does not commit")
    }

    /// The note title is typed straight into the model and has no persist of its own, so the pane's
    /// flush commits too, and leaving the title field (or pressing Return) is a flush.
    @Test func theNoteTitleIsCommittedAtItsOwnFlushPoints() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift")
        let flush = try #require(CadenceSourceScan.functionBody(named: "flushPendingEditorContent", in: source))
        #expect(flush.contains(Self.commitCall))

        let onTitleBlur = try #require(
            CadenceSourceScan.declarationBody(".onChange(of: isTitleFieldFocused)", in: source)
        )
        #expect(onTitleBlur.contains("flushPendingEditorContent()"))
        #expect(CadenceSourceScan.codeOnly(source).contains(".focused($isTitleFieldFocused)"))
        #expect(CadenceSourceScan.codeOnly(source).contains(".onSubmit { flushPendingEditorContent() }"))
    }

    /// Not per keystroke: the title binding's setter writes the model and does not commit.
    @Test func theTitleBindingDoesNotCommitPerKeystroke() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift")
        let binding = try #require(CadenceSourceScan.declarationBody("private var titleBinding", in: source))
        #expect(binding.contains("note.title = $0"))
        #expect(!binding.contains("commitTypedContent"))
        #expect(!binding.contains("save()"))
    }
}
