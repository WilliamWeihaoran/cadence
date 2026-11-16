import Foundation
import SwiftData

/// **[[T-18174]]: the store half of the edit that turns a `( ) Title` line into a task card.**
///
/// Return on that line (and the Mac's `( ) ` trigger) commits a real `AppTask` and then swaps the
/// line for `[[task:UUID|Title]]` as an ordinary undoable text edit. Undo used to put the line back
/// and leave the task in the store, so Return again made a second one. The editor now registers
/// this object on the text view's own undo manager, inside the same undo group as the replacement
/// (`register(on:)`), so one undo takes back both halves and one redo puts both back.
///
/// **Why an inverse on the editor's manager, not anything on the model context.** [[T-367]] took
/// whole-context undo out of the app because it reverts whatever the context recorded last; this
/// is the opposite shape — one inverse for one write this edit made, riding the text history that
/// already owns the edit. It deletes through the app's one delete core and re-creates through
/// `TaskCreationService`, so nothing bypasses the commit spine.
///
/// **It removes only what it minted, and only while it is untouched.** The id is the one this edit
/// created — never a task that already existed — and the withdrawal is refused when the task no
/// longer reads as it did when it was made (`Fingerprint`): renamed, ticked, dated, given a
/// subtask or tag, moved, or deleted meanwhile. A refused withdrawal leaves the task where it is;
/// the text still reverts, which is what undo of text has always done.
///
/// **Redo re-creates it under the same id**, so the reference the redone text puts back resolves
/// to a card again rather than dangling.
///
/// Not covered: a copy of the reference pasted into *another* note before the undo. The store has
/// no reliable answer to "does any other text still name it" at that moment — the host note's own
/// stored body still holds the reference until the editor's change is published — so this keys on
/// the task's own state only.
/// What a host hands an editor for a new embed: the text to write, and the inverse to register in
/// the same undo group. `Reference` is the Mac's `MarkdownReferenceSuggestion` or iOS's markdown
/// string. `undo` is nil only when the host could not build one; the editor then writes the text
/// alone, as before [[T-18174]].
struct MarkdownEmbeddedTaskCreation<Reference> {
    let reference: Reference
    let undo: MarkdownEmbeddedTaskCreationUndo?
}

@MainActor
final class MarkdownEmbeddedTaskCreationUndo {
    /// What a user can change on a task, read when it was minted. A withdrawal goes ahead only
    /// while the live task still reads the same.
    struct Fingerprint: Equatable {
        let title: String
        let notes: String
        let statusRaw: String
        let priorityRaw: String
        let dueDate: String
        let scheduledDate: String
        let scheduledStartMin: Int
        let estimatedMinutes: Int
        let actualMinutes: Int
        let sectionName: String
        let recurrenceRaw: String
        let completedAt: Date?
        let area: PersistentIdentifier?
        let project: PersistentIdentifier?
        let goal: PersistentIdentifier?
        let context: PersistentIdentifier?
        let bundle: PersistentIdentifier?
        let subtaskCount: Int
        let tagCount: Int
        let focusSessionCount: Int

        init(_ task: AppTask) {
            title = task.title
            notes = task.notes
            statusRaw = task.statusRaw
            priorityRaw = task.priorityRaw
            dueDate = task.dueDate
            scheduledDate = task.scheduledDate
            scheduledStartMin = task.scheduledStartMin
            estimatedMinutes = task.estimatedMinutes
            actualMinutes = task.actualMinutes
            sectionName = task.sectionName
            recurrenceRaw = task.recurrenceRaw
            completedAt = task.completedAt
            area = task.area?.persistentModelID
            project = task.project?.persistentModelID
            goal = task.goal?.persistentModelID
            context = task.context?.persistentModelID
            bundle = task.bundle?.persistentModelID
            subtaskCount = task.subtasks?.count ?? 0
            tagCount = task.tags?.count ?? 0
            focusSessionCount = task.focusSessions?.count ?? 0
        }
    }

    let taskID: UUID
    private var fingerprint: Fingerprint
    private let draft: TaskCreationDraft
    private let areas: [Area]
    private let projects: [Project]
    private let modelContext: ModelContext
    private let commit: (ModelContext) throws -> Void
    private let deleteTasks: (Set<UUID>) -> Bool
    private let didWithdraw: (UUID) -> Void
    private let didRestore: (AppTask) -> Void

    /// Whether the last undo actually removed the task, so a redo re-creates only what it took.
    private(set) var isWithdrawn = false

    /// - Parameters:
    ///   - task: The task this edit just committed, from `draft`.
    ///   - draft, areas, projects: What it was created from, so a redo files it the same way.
    ///   - deleteTasks: The platform's delete entry point. The Mac passes `ModelContext.deleteTasks`
    ///     for its AppKit teardown hooks; the default is the shared core both platforms reach.
    ///   - didWithdraw, didRestore: The host's creation-cache bookkeeping.
    init(
        task: AppTask,
        draft: TaskCreationDraft,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() },
        deleteTasks: ((Set<UUID>) -> Bool)? = nil,
        didWithdraw: @escaping (UUID) -> Void = { _ in },
        didRestore: @escaping (AppTask) -> Void = { _ in }
    ) {
        taskID = task.id
        fingerprint = Fingerprint(task)
        self.draft = draft
        self.areas = areas
        self.projects = projects
        self.modelContext = modelContext
        self.commit = commit
        self.deleteTasks = deleteTasks ?? { ids in
            CadenceTaskMutationSupport.deleteTasks(withIDs: ids, modelContext: modelContext, commit: commit)
        }
        self.didWithdraw = didWithdraw
        self.didRestore = didRestore
    }

    /// Registers the inverse on `manager`. Call it inside the undo group that holds the text
    /// replacement, so the two are one step.
    func register(on manager: UndoManager) {
        registerWithdrawal(on: manager)
    }

    /// The handler holds `self` strongly on purpose: `UndoManager` does NOT retain the target it
    /// is given, and nothing else keeps this object alive once the editor has registered it --
    /// measured, a target-only registration crashed inside the undo stack on the first undo. The
    /// manager is held weakly, so the manager -> handler -> manager loop is never closed.
    private func registerWithdrawal(on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak manager] _ in
            self.withdraw()
            if let manager { self.registerRestoration(on: manager) }
        }
    }

    private func registerRestoration(on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak manager] _ in
            self.restore()
            if let manager { self.registerWithdrawal(on: manager) }
        }
    }

    /// Every row carrying the id, or nil when the store could not be read -- which both callers
    /// treat as "do nothing", never as "absent".
    private func rowsWithID() -> [AppTask]? {
        let id = taskID
        return try? modelContext.fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id }))
    }

    /// Deletes the minted task when it is still exactly as minted. Returns whether it did.
    @discardableResult
    func withdraw() -> Bool {
        isWithdrawn = false
        guard let rows = rowsWithID(), rows.count == 1, let task = rows.first,
              Fingerprint(task) == fingerprint else { return false }
        guard deleteTasks([taskID]) else { return false }
        isWithdrawn = true
        didWithdraw(taskID)
        return true
    }

    /// Re-creates the task the last undo withdrew, under the same id. Does nothing when that undo
    /// was refused, or when a task with this id exists again.
    @discardableResult
    func restore() -> Bool {
        guard isWithdrawn else { return false }
        isWithdrawn = false
        guard rowsWithID()?.isEmpty == true,
              let insertion = TaskCreationService(areas: areas, projects: projects)
                .insertion(from: draft, into: modelContext) else { return false }
        insertion.task.id = taskID
        do {
            try CadencePendingChangePersistence.commitInsert(
                of: insertion.inserted,
                in: modelContext,
                commit: commit
            )
        } catch {
            return false
        }
        fingerprint = Fingerprint(insertion.task)
        didRestore(insertion.task)
        return true
    }
}
