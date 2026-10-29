import Foundation
import SwiftData

/// **The one write a Kanban card drop makes, on both platforms ([[T-8183]]).**
///
/// `reorder` is the body of macOS's `KanbanBoardSupport.reorder`, moved here unchanged so the iOS
/// list Kanban tab could make the same write instead of a second copy of it (AGENTS.md, one app on
/// two platforms, [[T-8201]]). `KanbanBoardSupport.reorder` still owns the argument for every
/// parameter and now only wraps this in its card animation, which is a macOS constant.
///
/// **The iOS list board's drop (`drop`) is that write, with the two targets macOS's columns have.**
/// The card is refiled under the column's section and the list is renumbered `0…n` in the same
/// commit, so a refused save puts every card back. Where it lands depends on what it was dropped
/// on, exactly as on macOS:
///
/// - **On a card (`before: card`)** it goes in front of that card, in its own column or another —
///   macOS's `onDropBefore` ([[T-8271]]). A card dropped on itself writes nothing and answers
///   `false`, the same refusal macOS's `handleTaskDrop` makes (`droppedID != target.id`).
/// - **On the column (`before: nil`)** it goes to the column's end, macOS's column-body drop. A
///   drop there on the card's OWN column writes nothing and answers `false`: the iOS column is one
///   target from header to foot, so a card lifted and set down in the gap between cards would
///   otherwise jump to the bottom of a column it never left.
/// - **Only a card of this board is accepted.** The payload decode is lenient by design (a bare
///   UUID passes, see `TaskDragPayload.taskID(from:)`), and an iPad shell can drag a task in from
///   another pane; refiling that one would be a container move this write does not make.
enum CadenceKanbanCardDrop {
    /// Move `task` into `columnTasks` before `target` (or to the end), renumbering the whole list
    /// `spanTasks` holds under `listKey`, with `assign` refiling it inside the same commit. See
    /// `KanbanBoardSupport.reorder` for why each of those is what it is.
    ///
    /// - Returns: Whether the drop is in the store. `false` means every card is back where it was.
    @MainActor
    static func reorder(
        _ columnTasks: [AppTask],
        moving task: AppTask,
        before target: AppTask?,
        spanning spanTasks: [AppTask],
        ofList listKey: String,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        assigning assign: () -> Void = {}
    ) -> Bool {
        var ordered = columnTasks
        ordered.removeAll { $0.id == task.id }
        if let target, let targetIndex = ordered.firstIndex(where: { $0.id == target.id }) {
            ordered.insert(task, at: targetIndex)
        } else {
            ordered.append(task)
        }
        let sequence = CadenceRowReorderSpan.wholeSequence(
            resequencing: ordered,
            within: spanTasks,
            ofList: listKey
        )
        return CadenceTaskFieldEditCommit.commit(
            task,
            // The whole sequence, not the column: the undo has to put back every card the
            // renumber below writes, and since T-1175 that is the list rather than the column.
            alsoRestoring: sequence,
            in: modelContext,
            commit: commit
        ) {
            assign()
            for (index, item) in sequence.enumerated() {
                item.order = index
            }
        }
    }

    /// The board card a drop names, or `nil` when it names none of them.
    static func droppedCard(from items: [String], among boardTasks: [AppTask]) -> AppTask? {
        guard let payload = items.first,
              let taskID = TaskDragPayload.taskID(from: payload) else { return nil }
        return boardTasks.first { $0.id == taskID }
    }

    /// An iOS list-board drop: decode, check the card is on this board, and file it in the column
    /// `sectionName` through `reorder` — in front of `target` when it was dropped on a card, at the
    /// column's end when it was dropped on the column itself.
    ///
    /// - Parameters:
    ///   - target: the card it was dropped on, or `nil` for the column body.
    ///   - columnTasks: the destination column's cards, in any order; they are put in `order`
    ///     order here, as macOS's column does, because the display sort is not what gets written.
    ///   - boardTasks: every card the board draws — the set a payload must name one of.
    ///   - spanTasks: the list's tasks from the store, finished ones included (see
    ///     `KanbanBoardSupport.reorder`'s `spanTasks`).
    @MainActor
    static func drop(
        _ items: [String],
        intoColumn sectionName: String,
        before target: AppTask? = nil,
        columnTasks: [AppTask],
        among boardTasks: [AppTask],
        spanning spanTasks: [AppTask],
        ofList listKey: String,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard let task = droppedCard(from: items, among: boardTasks) else { return false }
        if let target {
            guard task.id != target.id else { return false }
        } else {
            guard task.resolvedSectionName.caseInsensitiveCompare(sectionName) != .orderedSame else {
                return false
            }
        }
        return reorder(
            columnTasks.sorted { $0.order < $1.order },
            moving: task,
            before: target,
            spanning: spanTasks,
            ofList: listKey,
            in: modelContext,
            commit: commit
        ) {
            task.sectionName = sectionName
        }
    }
}
