import Foundation
import SwiftData

/// **[[T-18594]]: the store half of renaming a task card by typing over its title in a note.**
///
/// The inline rename commits the new title to the task and then rewrites the hidden title inside
/// the note's `[[task:UUID|Title]]` reference as an ordinary undoable text edit. Undo used to take
/// back only that hidden text: the card is drawn from the live task, so nothing on screen moved,
/// the task kept the new name everywhere, and the note's stored reference drifted back to the old
/// title. The editor now registers this object on the text view's own undo manager, inside the
/// same undo group as the reference rewrite, so one undo renames the task back with the text and
/// one redo renames it forward again -- the [[T-18174]] shape, for a rename instead of a creation.
///
/// **It reverts only its own rename, and only while it still stands.** Each step goes ahead only
/// when the live task still carries the title (and priority, which the `!` shortcut moves with the
/// title) this edit left it with; a task renamed or re-prioritised elsewhere meanwhile, deleted,
/// or unreadable is left alone, and the text reverts by itself -- what undo of text always did.
/// The write goes through `CadencePendingChangePersistence.commitEdit`, so a refused commit puts
/// the fields back rather than leaving a half-undone rename.
@MainActor
final class MarkdownEmbeddedTaskRenameUndo: MarkdownReferenceTitleSyncBaseline {
    /// The two fields an inline rename writes: the `!` priority shortcut moves the priority as a
    /// side effect of the title, so the two are reverted together.
    struct Title: Equatable {
        let title: String
        let priorityRaw: String

        init(_ task: AppTask) {
            title = task.title
            priorityRaw = task.priorityRaw
        }

        init(title: String, priorityRaw: String) {
            self.title = title
            self.priorityRaw = priorityRaw
        }
    }

    let taskID: UUID
    private var before: Title
    private var after: Title
    /// Whether the step on the stack is the redo: the last press undid this rename. Read when the
    /// step runs, so an adopted title ([[T-18963]]) is what it expects.
    private var isUndone = false
    private let modelContext: ModelContext
    private let commit: (ModelContext) throws -> Void
    private let didApply: (AppTask) -> Void

    /// - Parameters:
    ///   - task: The task the rename just committed, read after the commit.
    ///   - before: The same task's `Title` read before the rename. `nil` comes back when the
    ///     rename changed nothing, so an editor registers no step that would do nothing.
    ///   - didApply: The host's repaint after an undo or redo renamed the task -- the card's
    ///     render info and the reconcile. It must not rewrite the note's text: the undo group
    ///     already holds that half.
    init?(
        task: AppTask,
        before: Title,
        modelContext: ModelContext,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() },
        didApply: @escaping (AppTask) -> Void = { _ in }
    ) {
        let after = Title(task)
        guard after != before else { return nil }
        taskID = task.id
        self.before = before
        self.after = after
        self.modelContext = modelContext
        self.commit = commit
        self.didApply = didApply
    }

    /// Registers the inverse on `manager`. Call it inside the undo group that holds the reference
    /// rewrite, so the two are one step.
    func register(on manager: UndoManager) {
        registerStep(on: manager)
        MarkdownReferenceTitleSyncUndo.attached(to: manager).track(self)
    }

    /// [[T-18963]]: the task was renamed outside the note after this rename and the reference
    /// caught up, on a step at or above this one. That title is the one the next step expects, so
    /// undo still renames the task back instead of refusing; the priority is not the note's, and a
    /// change to it still refuses.
    func adoptOutsideRename() {
        let id = taskID
        guard let rows = try? modelContext.fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })),
              rows.count == 1, let task = rows.first else { return }
        if isUndone {
            before = Title(title: task.title, priorityRaw: before.priorityRaw)
        } else {
            after = Title(title: task.title, priorityRaw: after.priorityRaw)
        }
    }

    /// The handler holds `self` strongly on purpose: `UndoManager` does not retain its target (see
    /// `MarkdownEmbeddedTaskCreationUndo.registerWithdrawal`). The manager is held weakly.
    private func registerStep(on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak manager] _ in
            let (expected, target) = self.isUndone ? (self.before, self.after) : (self.after, self.before)
            self.isUndone.toggle()
            self.apply(expecting: expected, writing: target)
            if let manager { self.registerStep(on: manager) }
        }
    }

    /// Writes `target` when the live task still reads `expected`. Returns whether it did.
    @discardableResult
    func apply(expecting expected: Title, writing target: Title) -> Bool {
        let id = taskID
        guard let rows = try? modelContext.fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })),
              rows.count == 1, let task = rows.first,
              Title(task) == expected else { return false }
        let snapshot = CadenceTaskFieldSnapshot(task)
        task.title = target.title
        task.priorityRaw = target.priorityRaw
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                snapshot.restore(to: task)
            }
        } catch {
            return false
        }
        didApply(task)
        return true
    }
}
