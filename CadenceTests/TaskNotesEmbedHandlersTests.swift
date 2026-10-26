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

    // MARK: - [[T-6721]]: the two note-owned editors' host policy

    /// `NotePanel`'s core notes file a new card into the Inbox, default section.
    @Test func theCoreNotesFileIntoTheInbox() throws {
        let (_, modelContext) = try context()
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-")
        let coreNotes = TaskNotesEmbedScope(referenceTasks: [], embedTarget: .coreNotes, modelContext: modelContext)

        let suggestion = try #require(handlers.createEmbeddedTask(title: "Call the venue", in: coreNotes))
        let created = try #require(
            try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == suggestion.targetID }
        )
        #expect(created.area == nil)
        #expect(created.project == nil)
        #expect(created.sectionName == TaskSectionDefaults.defaultName)
    }

    // MARK: - [[T-6781]]: every host's task links read the creation cache

    /// **A `[[task]]` link to a task created from the same note a moment ago opens in every macOS
    /// note editor**, not only `NotePanel` — the host's query (`referenceTasks: []` here) has not
    /// caught up yet. Once the task is deleted from the store the same link opens nothing: the cache
    /// is re-checked against the store ([[T-349]]), which is why reading it everywhere is safe.
    @Test func everyHostsTaskLinkOpensAJustCreatedTaskAndNotADeletedOne() throws {
        let (_, modelContext) = try context()
        let owner = try seededTask("Owner", in: modelContext)
        let listNote = Note(kind: .list, title: "Plans")
        modelContext.insert(listNote)
        try modelContext.save()

        let targets: [(String, TaskNotesEmbedTarget)] = [
            ("a task's notes", .ownerTask(owner)),
            ("NotePanel's core notes", .coreNotes),
            ("a NoteEditorPane note", .noteEditor(listNote, area: nil, project: nil))
        ]
        for (host, target) in targets {
            let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
            let scope = TaskNotesEmbedScope(referenceTasks: [], embedTarget: target, modelContext: modelContext)
            let suggestion = try #require(handlers.createEmbeddedTask(title: "Fresh \(host)", in: scope), "\(host)")
            let id = suggestion.targetID

            handlers.openTaskReference(id: id, title: "", in: scope)
            #expect(handlers.linkedTaskForPopover?.id == id, "\(host)'s link missed a just-created task")

            handlers.linkedTaskForPopover = nil
            let created = try #require(try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == id })
            modelContext.delete(created)
            try modelContext.save()
            handlers.openTaskReference(id: id, title: "", in: scope)
            #expect(handlers.linkedTaskForPopover == nil, "\(host)'s link opened a deleted task")
        }
    }

    /// `NoteEditorPane`: a list note files into the list its host passes, else its own; a project
    /// list's card lands in that project; any other kind of note's card lands in the Inbox.
    @Test func aNoteEditorFilesAListNotesCardIntoItsListAndAnyOtherNotesIntoTheInbox() throws {
        let (_, modelContext) = try context()
        let hostArea = Area(name: "Host area")
        let noteArea = Area(name: "Note area")
        let project = Project(name: "Launch")
        project.sectionNames = [TaskSectionDefaults.defaultName, "Later"]
        let areaList = Note(kind: .list, title: "Area list")
        areaList.area = noteArea
        let projectList = Note(kind: .list, title: "Project list")
        projectList.project = project
        let meeting = Note(kind: .meeting, title: "Standup")
        meeting.area = noteArea
        for model: any PersistentModel in [hostArea, noteArea, project, areaList, projectList, meeting] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-")

        func created(_ title: String, _ target: TaskNotesEmbedTarget) throws -> AppTask {
            let scope = TaskNotesEmbedScope(referenceTasks: [], embedTarget: target, modelContext: modelContext)
            let suggestion = try #require(handlers.createEmbeddedTask(title: title, in: scope), "\(title)")
            return try #require(try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == suggestion.targetID })
        }

        let hosted = try created("Hosted", .noteEditor(areaList, area: hostArea, project: nil))
        #expect(hosted.area?.id == hostArea.id, "the host's area did not win over the note's")
        let own = try created("Own", .noteEditor(areaList, area: nil, project: nil))
        #expect(own.area?.id == noteArea.id)
        let inProject = try created("In project", .noteEditor(projectList, area: nil, project: nil))
        #expect(inProject.project?.id == project.id)
        #expect(inProject.area == nil)
        #expect(inProject.sectionName == TaskSectionDefaults.defaultName)
        let loose = try created("Loose", .noteEditor(meeting, area: hostArea, project: project))
        #expect(loose.area == nil)
        #expect(loose.project == nil)
    }

    /// `NoteEditorPane` bumps the note's `updatedAt` inside the creation's own commit, and puts it
    /// back when that commit is refused — so a refused card leaves neither a task nor an edited note.
    @Test func aNoteEditorsCardBumpsTheNoteInTheSameCommitAndARefusalPutsItBack() throws {
        let (container, modelContext) = try context()
        let note = Note(kind: .list, title: "Plans")
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        note.updatedAt = earlier
        modelContext.insert(note)
        try modelContext.save()
        let scope = TaskNotesEmbedScope(
            referenceTasks: [],
            embedTarget: .noteEditor(note, area: nil, project: nil),
            modelContext: modelContext
        )

        let refusing = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-") { _ in throw CommitRefused() }
        #expect(refusing.createEmbeddedTask(title: "Refused", in: scope) == nil)
        #expect(note.updatedAt == earlier, "a refused card left the note marked as edited")
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).allSatisfy { $0.title != "Refused" })

        let committing = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-")
        #expect(committing.createEmbeddedTask(title: "Taken", in: scope) != nil)
        #expect(note.updatedAt > earlier)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Note>()).first { $0.id == note.id }
        #expect(stored.map { $0.updatedAt > earlier } == true, "the note's bump did not ride in the creation's commit")

        // A task's notes touch no note.
        let owner = try seededTask("Owner", in: modelContext)
        #expect(TaskNotesEmbedTarget.ownerTask(owner).touchedNote == nil)
    }

    /// **Source shape — the one part a test cannot drive without a window.** Each note-owned host
    /// builds its scope in a view, so which policy it picks is read from source: `NotePanel` takes
    /// the core-notes target, `NoteEditorPane` its note's. The behaviour each choice means is pinned
    /// above.
    @Test func eachNoteOwnedHostPassesItsOwnPolicy() throws {
        for (path, target) in [
            ("Cadence/macOS/Views/NotePanel.swift", "embedTarget: .coreNotes,"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "embedTarget: .noteEditor(note, area: area, project: project),")
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let scope = try #require(
                CadenceSourceScan.declarationBody("private var embedScope: TaskNotesEmbedScope", in: code),
                "\(path) builds no embed scope"
            )
            #expect(scope.contains(target), "\(path) files new cards somewhere else")
            #expect(code.contains(".taskNotesEmbedPopovers(embeds, scope: embedScope)"), "\(path)")
            #expect(
                CadenceSourceScan.matchCount(#"func (createEmbeddedTask|toggleEmbeddedTask|openTaskReference)\("#, in: code) == 0,
                "\(path) grew its own copy of a shared handler back"
            )
        }
    }
}
#endif
