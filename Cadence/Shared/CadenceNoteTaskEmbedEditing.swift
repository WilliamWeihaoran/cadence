import Foundation
import SwiftData

/// The two edits a task card embedded in a note offers inline: ticking one of its subtasks, and
/// renaming the task by typing over its title.
///
/// **Why this is one unit (T-648).** Four editors host those cards — `NotePanel`,
/// `ListNotesSupportViews`, `NoteEditorPane` and `iOSMarkdownEditingSurface` — and all four wrote
/// the same three lines: mutate the task, `try? modelContext.save()`, then hand back a fresh
/// `MarkdownTaskEmbedRenderInfo`. That last step is what repaints the card inside the note, so a
/// refused commit left the card showing a tick or a title the store does not hold, with nothing
/// else on screen to disagree. It is [[T-366]] — the defect `TaskEmbedFieldEditorPopover` was fixed
/// for — in four more places, and the report was in a spelling the rule's vocabulary did not have:
/// three of the four hand the render info *sideways* through `refreshEmbeddedTask` rather than
/// returning it ([[T-657]]).
///
/// Both functions answer `false` with the task exactly as it was found, so a caller that repaints
/// on `false` is the bug again.
///
/// **`CadenceTaskFieldEditCommit` is not the unit here, and the reason has shrunk to one field.**
/// Its snapshot (`CadenceTaskFieldSnapshot`) used to carry neither `title` nor a subtask's
/// `isDone`, so restoring a refused rename through it would have put the priority back and left the
/// title — a worse state than either outcome the user could have expected. `title` is snapshotted
/// as of [[T-701]], so `rename`'s undo is `CadenceTaskFieldSnapshot` directly rather than a
/// hand-written near-copy of it ([[T-765]]) — restoring the raw `priorityRaw` this way is also
/// stricter than the hand-rolled version was: it round-trips an unrecognised value exactly instead
/// of coercing it through `task.priority` and writing `.none` back. `isDone` lives on `Subtask`,
/// which that snapshot is not about at all, so `toggleSubtask` still owns its own undo.
enum CadenceNoteTaskEmbedEditing {

    /// Ticks or unticks one subtask of an embedded card.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    static func toggleSubtask(
        _ subtask: Subtask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let restored = subtask.isDone
        subtask.isDone.toggle()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                subtask.isDone = restored
            }
        } catch {
            return false
        }
        return true
    }

    /// Renames an embedded card's task, applying the `!`-style priority shortcut the inline title
    /// field accepts. Both fields are restored together when the commit is refused: the shortcut
    /// moves the priority as a side effect of the title, so undoing one without the other would
    /// leave the card holding half of an edit nobody made. The restore is `CadenceTaskFieldSnapshot`
    /// rather than the two locals this used to save by hand ([[T-765]]).
    ///
    /// - Parameter commit: See `toggleSubtask(_:in:commit:)`.
    static func rename(
        _ task: AppTask,
        to title: String,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let snapshot = CadenceTaskFieldSnapshot(task)

        var priority = task.priority
        task.title = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        task.priority = priority

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                snapshot.restore(to: task)
            }
        } catch {
            return false
        }
        return true
    }
}
