#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5120]]: the one live-card embed handler set behind the three macOS task-notes editors.**
///
/// `TaskDetailNotesSection`, `TaskNoteEditorPane` and `FocusNotesPanel` each carried a hand-copied
/// set of `[[task:…]]` card and `[[task]]` link handlers; they now all hold a
/// `TaskNotesEmbedHandlers`. These tests drive that type against a real in-memory store, so the
/// behaviour all three editors share is pinned once, by what it does rather than by how it is
/// spelled. `CadenceMarkdownEditorEmbedWiringTests` still checks each host passes the closures.
@MainActor
struct TaskNotesEmbedHandlersTests {

    private struct CommitRefused: Error {}

    private func context() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    private func seededTask(_ title: String, in modelContext: ModelContext) throws -> AppTask {
        let task = AppTask(title: title)
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    private func scope(_ tasks: [AppTask], owner: AppTask, _ modelContext: ModelContext) -> TaskNotesEmbedScope {
        TaskNotesEmbedScope(referenceTasks: tasks, ownerTask: owner, modelContext: modelContext)
    }

    // MARK: - `[[task]]` links and card bodies

    @Test func aTaskLinkOpensByIDFirstThenByTrimmedCaseInsensitiveTitle() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let beta = try seededTask("Ship the beta", in: modelContext)
        let notes = try seededTask("Write the notes", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        let scope = scope([owner, beta, notes], owner: owner, modelContext)

        // The id wins over a title that names a different task.
        handlers.openTaskReference(id: notes.id, title: "Ship the beta", in: scope)
        #expect(handlers.linkedTaskForPopover?.id == notes.id)

        handlers.openTaskReference(id: nil, title: "  sHIP THE beta \n", in: scope)
        #expect(handlers.linkedTaskForPopover?.id == beta.id)

        // An unknown id falls through to the title; an empty or unknown title changes nothing.
        handlers.openTaskReference(id: UUID(), title: "write the notes", in: scope)
        #expect(handlers.linkedTaskForPopover?.id == notes.id)
        handlers.openTaskReference(id: nil, title: "   ", in: scope)
        handlers.openTaskReference(id: nil, title: "No such task", in: scope)
        #expect(handlers.linkedTaskForPopover?.id == notes.id)
    }

    @Test func clickingACardBodyOpensItsTaskAndAMissingCardDoesNothing() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let embedded = try seededTask("Embedded", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        let callbacks = handlers.callbacks(
            in: scope([owner, embedded], owner: owner, modelContext),
            hoveredTaskManager: .shared,
            hoveredEditableManager: .shared
        )

        // Through the closures the host hands `MarkdownEditor`, so the bundle is pinned too.
        callbacks.openEmbeddedTask(UUID())
        #expect(handlers.linkedTaskForPopover == nil)
        callbacks.openEmbeddedTask(embedded.id)
        #expect(handlers.linkedTaskForPopover?.id == embedded.id)
    }

    /// Without a text view the inline task panel has nowhere to open, so every chip falls back to
    /// the field popover, carrying the chip that was clicked.
    @Test func aFieldChipWithoutATextViewFallsBackToTheFieldPopover() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let embedded = try seededTask("Embedded", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        let scope = scope([owner, embedded], owner: owner, modelContext)

        handlers.editEmbeddedTask(id: UUID(), field: .status, in: scope)
        #expect(handlers.embeddedTaskEditRequest == nil)

        handlers.editEmbeddedTask(id: embedded.id, field: .dueDate, in: scope)
        #expect(handlers.embeddedTaskEditRequest?.taskID == embedded.id)
        #expect(handlers.embeddedTaskEditRequest?.field == .dueDate)
    }

    @Test func theHoverIDIsTheHostsPrefixAndTheTaskID() {
        let id = UUID()
        #expect(TaskNotesEmbedHandlers(hoverIDPrefix: "focus-note-embed-task-").embeddedTaskHoverID(id)
            == "focus-note-embed-task-\(id.uuidString)")
    }

    // MARK: - Creating an embed

    /// A card created from a task's notes lands in that task's list and section, and is live in the
    /// editor before the host's query has caught up with it.
    @Test func aCardCreatedFromTaskNotesLandsInTheOwnersListAndSectionAndIsLiveAtOnce() throws {
        let (container, modelContext) = try context()
        let area = Area(name: "Launch")
        area.sectionNames = [TaskSectionDefaults.defaultName, "Later"]
        modelContext.insert(area)
        let owner = AppTask(title: "Owner")
        owner.area = area
        owner.sectionName = "Later"
        modelContext.insert(owner)
        try modelContext.save()

        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        // The host's query has not caught up: it holds only the owner.
        let scope = scope([owner], owner: owner, modelContext)

        let suggestion = try #require(
            handlers.createEmbeddedTask(title: "Book the room", in: scope),
            "creating an embed handed back no task reference"
        )
        #expect(suggestion.kind == .task)
        let created = try #require(
            try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == suggestion.targetID }
        )
        #expect(created.title == "Book the room")
        #expect(created.area?.id == area.id)
        #expect(created.sectionName == "Later")
        #expect(handlers.embeddedTask(id: created.id, in: scope)?.id == created.id)

        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.title == "Book the room" }
        #expect(stored?.area?.id == area.id, "the store does not hold the embed the note now points at")
    }

    @Test func aCardCreatedFromInboxTaskNotesLandsInTheInbox() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")

        let suggestion = try #require(
            handlers.createEmbeddedTask(title: "Loose end", in: scope([owner], owner: owner, modelContext))
        )
        let created = try #require(
            try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == suggestion.targetID }
        )
        #expect(created.area == nil)
        #expect(created.project == nil)
    }

    // MARK: - Editing a card: committed, or named as refused

    @Test func aTickedCardIsCommittedAndClearsAnEarlierRefusal() throws {
        let (container, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let embedded = try seededTask("Embedded", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        handlers.embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice

        handlers.toggleEmbeddedTask(id: embedded.id, in: scope([owner, embedded], owner: owner, modelContext))

        #expect(embedded.isDone)
        #expect(handlers.embeddedTaskFailureNotice == nil)
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == embedded.id }
        #expect(stored?.isDone == true, "the store does not hold the tick the card shows")
    }

    @Test func aRefusedCardTickIsNamedAndLeavesTheTaskOpen() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let embedded = try seededTask("Embedded", in: modelContext)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-") { _ in throw CommitRefused() }

        handlers.toggleEmbeddedTask(id: embedded.id, in: scope([owner, embedded], owner: owner, modelContext))

        #expect(!embedded.isDone)
        #expect(handlers.embeddedTaskFailureNotice == CadenceTaskFieldEditCommit.saveFailureNotice)
    }

    @Test func aRefusedSubtaskTickOrRenameIsNamedAndUndone() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let embedded = AppTask(title: "Embedded")
        let subtask = Subtask(title: "Step")
        subtask.parentTask = embedded
        embedded.subtasks = [subtask]
        modelContext.insert(embedded)
        modelContext.insert(subtask)
        try modelContext.save()
        let scope = scope([owner, embedded], owner: owner, modelContext)

        let refusing = TaskNotesEmbedHandlers(hoverIDPrefix: "test-") { _ in throw CommitRefused() }
        refusing.toggleEmbeddedSubtask(taskID: embedded.id, subtaskID: subtask.id, in: scope)
        #expect(!subtask.isDone)
        #expect(refusing.embeddedTaskFailureNotice == CadenceTaskFieldEditCommit.saveFailureNotice)

        refusing.embeddedTaskFailureNotice = nil
        refusing.renameEmbeddedTask(id: embedded.id, title: "Renamed", in: scope)
        #expect(embedded.title == "Embedded")
        #expect(refusing.embeddedTaskFailureNotice == CadenceTaskFieldEditCommit.saveFailureNotice)

        // The same two edits through the default commit land and clear the notice.
        let committing = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        committing.embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
        committing.toggleEmbeddedSubtask(taskID: embedded.id, subtaskID: subtask.id, in: scope)
        #expect(subtask.isDone)
        #expect(committing.embeddedTaskFailureNotice == nil)
        committing.embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
        committing.renameEmbeddedTask(id: embedded.id, title: "Renamed", in: scope)
        #expect(embedded.title == "Renamed")
        #expect(committing.embeddedTaskFailureNotice == nil)
    }
}
#endif
