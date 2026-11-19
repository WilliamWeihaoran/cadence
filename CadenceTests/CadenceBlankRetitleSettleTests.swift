import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-18457]] / [[T-18458]]: a title field typed straight into the model settles at its flush
/// points.** The Mac note editor's title field and both platforms' saved-subtask rows bind the
/// model per keystroke, so a cleared field used to be stored as `""` and read "Untitled" (or
/// "Event Note") everywhere, a blank every create and sibling rename path refuses. At Return, focus
/// loss and close each now settles through `CadenceTitleNormalization.settledRetitle`: a blank
/// title restores the one the edit opened with, anything else is stored trimmed. The rule is
/// behavioural here; the view wiring around it has no seam and is pinned from source.
struct CadenceBlankRetitleSettleTests {
    // MARK: - The shared rule

    @Test func aBlankDraftRestoresTheOpeningTitleAndAnythingElseIsTrimmed() {
        for blank in ["", "   ", "\n", " \t\n "] {
            #expect(CadenceTitleNormalization.settledRetitle(blank, openedWith: "Groceries") == "Groceries")
        }
        #expect(CadenceTitleNormalization.settledRetitle("  Weekly shop \n", openedWith: "Groceries") == "Weekly shop")
        #expect(CadenceTitleNormalization.settledRetitle("Weekly shop", openedWith: "Groceries") == "Weekly shop")
    }

    // MARK: - T-18457: the Mac note title field

    private func savedListNote(title: String) throws -> (ModelContainer, ModelContext, Note) {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let note = Note(kind: .list, title: title)
        note.content = "# \(title)\nMilk\n"
        context.insert(note)
        try context.save()
        return (container, context, note)
    }

    /// The defect: the field cleared, so `rename` left `""` and an empty `# ` heading. Settling puts
    /// the title and the heading back, and answers that it wrote.
    @Test func aClearedNoteTitleSettlesBackToTheTitleItOpenedWith() throws {
        let (_, _, note) = try savedListNote(title: "Groceries")
        MarkdownNoteTitleSync.rename(note, to: "")
        #expect(note.title == "", "non-vacuity: the keystroke path stores the blank")
        #expect(note.content.hasPrefix("# \n"))

        #expect(MarkdownNoteTitleSync.settleTitleEdit(note, openedWith: "Groceries"))
        #expect(note.title == "Groceries")
        #expect(note.content == "# Groceries\nMilk\n")
        #expect(note.displayTitle == "Groceries")
    }

    @Test func aWhitespaceOrPaddedNoteTitleSettlesTrimmed() throws {
        let (_, _, note) = try savedListNote(title: "Groceries")
        MarkdownNoteTitleSync.rename(note, to: "   ")
        #expect(MarkdownNoteTitleSync.settleTitleEdit(note, openedWith: "Groceries"))
        #expect(note.title == "Groceries")

        MarkdownNoteTitleSync.rename(note, to: "  Weekly shop ")
        #expect(MarkdownNoteTitleSync.settleTitleEdit(note, openedWith: "Groceries"))
        #expect(note.title == "Weekly shop")
        #expect(note.content == "# Weekly shop\nMilk\n")
    }

    @Test func aCleanNoteRetitleIsLeftAsTyped() throws {
        let (_, _, note) = try savedListNote(title: "Groceries")
        MarkdownNoteTitleSync.rename(note, to: "Weekly shop")
        #expect(!MarkdownNoteTitleSync.settleTitleEdit(note, openedWith: "Groceries"))
        #expect(note.title == "Weekly shop")
    }

    /// The pane's wiring: the first keystroke records the opening title; Return, leaving the field,
    /// the pane going and a note switch all settle; the quit flush settles before it commits.
    @Test func theNoteEditorPaneSettlesTheTitleAtEveryFlushPoint() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift"))
        let binding = try #require(CadenceSourceScan.declarationBody("private var titleBinding", in: source))
        let record = try #require(binding.range(of: "pendingTitleEdit ?? PendingTitleEdit(note: note, openedWith: note.title)"))
        let rename = try #require(binding.range(of: "MarkdownNoteTitleSync.rename(note, to: $0)"))
        #expect(record.lowerBound < rename.lowerBound, "the opening title is read after the keystroke renamed it")
        #expect(binding.contains("registerTitleQuitCommit(edit)"))
        let quitBody = try #require(CadenceSourceScan.functionBody(named: "registerTitleQuitCommit", in: source))
        let quit = try #require(quitBody.range(of: "MarkdownEditorTerminationFlush.shared.register(titleTerminationFlushID) {"))
        let quitClosure = String(quitBody[quit.upperBound...])
        let quitSettle = try #require(quitClosure.range(of: "MarkdownNoteTitleSync.settleTitleEdit(edit.note, openedWith: edit.openedWith)"))
        let quitCommit = try #require(quitClosure.range(of: "CadencePendingChangePersistence.commitTypedContent(in: modelContext)"))
        #expect(quitSettle.lowerBound < quitCommit.lowerBound)

        #expect(source.contains(".onSubmit { flushTitleEdit() }"))
        let blur = try #require(CadenceSourceScan.declarationBody(".onChange(of: isTitleFieldFocused)", in: source))
        #expect(blur.contains("flushTitleEdit()"))
        let disappear = try #require(CadenceSourceScan.declarationBody(".onDisappear", in: source))
        #expect(disappear.contains("commitSettledTitleEdit()"))
        let noteSwitch = try #require(CadenceSourceScan.declarationBody(".onChange(of: note.id)", in: source))
        #expect(noteSwitch.contains("commitSettledTitleEdit()"))

        let flush = try #require(CadenceSourceScan.functionBody(named: "flushTitleEdit", in: source))
        let landBody = try #require(flush.range(of: "flushPendingEditorContent()"))
        let settle = try #require(flush.range(of: "commitSettledTitleEdit()"))
        #expect(landBody.lowerBound < settle.lowerBound, "the body buffer must land before the heading is restored")

        let commit = try #require(CadenceSourceScan.functionBody(named: "commitSettledTitleEdit", in: source))
        #expect(commit.contains("MarkdownNoteTitleSync.settleTitleEdit(edit.note, openedWith: edit.openedWith)"))
        #expect(commit.contains("editorContent = edit.note.content"))
        #expect(commit.contains("CadencePendingChangePersistence.commitTypedContent(in: modelContext)"))
        // A settled edit's quit closure holds its note; the plain commit replaces it before any
        // early return, so a switched-away note deleted later is never read at Cmd-Q.
        let replace = try #require(commit.range(of: "MarkdownEditorTerminationFlush.shared.registerCommit(titleTerminationFlushID, in: modelContext)"))
        let firstSettle = try #require(commit.range(of: "MarkdownNoteTitleSync.settleTitleEdit("))
        #expect(replace.lowerBound < firstSettle.lowerBound)
        let disappearAt = try #require(source.range(of: ".onDisappear {"))
        let tail = String(source[disappearAt.upperBound...].prefix(600))
        let settleAt = try #require(tail.range(of: "commitSettledTitleEdit()"))
        let unregisterAt = try #require(tail.range(of: "MarkdownEditorTerminationFlush.shared.unregister(titleTerminationFlushID)"))
        #expect(settleAt.lowerBound < unregisterAt.lowerBound, "the re-registered quit commit would outlive the pane")
    }

    // MARK: - T-18458: saved subtask retitles, both platforms

    private func savedSubtask(title: String) throws -> (ModelContainer, ModelContext, Subtask) {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let subtask = Subtask(title: title)
        context.insert(subtask)
        try context.save()
        return (container, context, subtask)
    }

    @Test func aClearedSubtaskTitleSettlesBackToTheTitleItOpenedWith() throws {
        let (container, context, subtask) = try savedSubtask(title: "Book flight")
        for blank in ["", "  ", "\n"] {
            subtask.title = blank
            #expect(CadenceTaskMutationSupport.settleSubtaskRetitle(subtask, openedWith: "Book flight"))
            #expect(subtask.title == "Book flight")
        }
        try context.save()
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).map(\.title) == ["Book flight"])
    }

    @Test func aPaddedSubtaskTitleSettlesTrimmedAndACleanOneIsLeftAlone() throws {
        let (_, _, subtask) = try savedSubtask(title: "Book flight")
        subtask.title = "  Book flight to Lisbon \n"
        #expect(CadenceTaskMutationSupport.settleSubtaskRetitle(subtask, openedWith: "Book flight"))
        #expect(subtask.title == "Book flight to Lisbon")
        #expect(!CadenceTaskMutationSupport.settleSubtaskRetitle(subtask, openedWith: "Book flight"))
        #expect(subtask.title == "Book flight to Lisbon")
    }

    /// Both rows: the first focused keystroke records the opening title, and Return, leaving the
    /// field and the row going settle through the one shared helper.
    @Test(arguments: [
        ("Cadence/macOS/Views/TasksPanelSupportViews.swift", "struct SubtaskRow: View", ".onSubmit { settleTitleEdit() }"),
        ("Cadence/iOS/iOSTaskDetailComponents.swift", "struct iOSSubtaskRow: View", ".onSubmit(settleTitleEdit)"),
    ])
    func bothSubtaskRowsSettleTheirTitleThroughTheSharedRule(path: String, declaration: String, submit: String) throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        let row = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(path)")
        #expect(row.contains(".focused($isTitleFocused)"), "\(path)")
        #expect(row.contains(submit), "\(path)")
        #expect(row.contains("if isTitleFocused, titleAtEditStart == nil { titleAtEditStart = previous }"), "\(path)")
        let blur = try #require(CadenceSourceScan.declarationBody(".onChange(of: isTitleFocused)", in: row), "\(path)")
        #expect(blur.contains("if !isFocused { settleTitleEdit() }"), "\(path)")
        #expect(row.contains(".onDisappear"), "\(path)")
        let settle = try #require(CadenceSourceScan.functionBody(named: "settleTitleEdit", in: row), "\(path)")
        #expect(settle.contains("CadenceTaskMutationSupport.settleSubtaskRetitle(subtask, openedWith: openedWith)"), "\(path)")
        #expect(settle.contains("guard !subtask.isDeleted, subtask.modelContext != nil else { return }"), "\(path)")
    }
}
