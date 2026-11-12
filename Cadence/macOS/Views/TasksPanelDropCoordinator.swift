#if os(macOS)
import Foundation

struct TasksPanelDropCoordinator {
    let allTasks: [AppTask]
    let taskIDFromPayload: (String) -> UUID?
    /// Answers all three outcomes, not a `Bool` ([[T-17115]]): a row drop has to tell a key that
    /// resolved to nothing (reorder anyway) from a re-file the store refused (stop). See
    /// `handleSectionDrop` and `handleTaskDrop`.
    let assignTask: (AppTask, String) -> TasksPanelDropOutcome
    /// Answers whether the new order is in the store — see `handleTaskDrop`. It was `Void` until
    /// T-868, over a `try? modelContext.save()` that could not have told anyone anyway.
    let reorderTask: (UUID, UUID, [AppTask]) -> Bool

    /// Curried because the `Optional` is the point: a group with no `dropKey` gets `nil`, and
    /// `TasksPanelIntentSectionView` / `TasksListSectionView` take `((String) -> Bool)?` so the
    /// header simply has no drop target rather than one that refuses everything.
    ///
    /// **The task-level half of this pair is gone (T-564(b)).** `taskDropHandler(scopeTasks:dropKey:)`
    /// curried `handleTaskDrop` the same way and lost its last call site when `liveFlatSection`
    /// went; both remaining row drops — Today's in `TasksPanel.todayGroupSections` and All Tasks' /
    /// Inbox's in `TasksListView` — spell `coordinator.handleTaskDrop(payload:targetTask:scopeTasks:dropKey:)`
    /// inline, because a row hands over its own section's `scopeTasks` at the point of the drop and
    /// has no `Optional` to express. So the pair was symmetric in shape and not in use: one half was
    /// carrying an argument order and a defaulted `dropKey` that nothing supplied and no test
    /// exercised, which is the half most likely to be wrong the day somebody reaches for it.
    /// Pinned absent by `CadenceTodayUnificationTests.theDropCoordinatorKeepsOnlyTheHalfItsCallersUse`.
    func sectionDropHandler(for dropKey: String?) -> ((String) -> Bool)? {
        guard let dropKey else { return nil }
        return { payload in
            handleSectionDrop(payload: payload, dropKey: dropKey)
        }
    }

    /// **A drop that applied nothing reports `false`.** This returned `true` unconditionally, so
    /// every Today list header lit up, accepted the row and left it where it was — for as long as
    /// the compound key went unparsed, which is exactly as long as nothing could tell the two
    /// outcomes apart (T-591). A rejected drop springs the row back and says so; a silent accept
    /// says the move happened.
    func handleSectionDrop(payload: String, dropKey: String) -> Bool {
        guard let (_, droppedTask) = droppedTask(from: payload) else { return false }
        return assignTask(droppedTask, dropKey) == .applied
    }

    /// **`dropKey` has no default (T-715).** It carried `= nil`, and both call sites — Today's
    /// `TasksPanel.todayGroupSections` and All Tasks' / Inbox's `TasksListView` — pass it, so the
    /// default was a branch no caller took: the same shape T-564(b) deleted from this type one
    /// ticket earlier, and the half most likely to be wrong the day somebody reaches for it.
    /// Without it a future caller has to say `dropKey: nil` out loud, which is a claim about the
    /// group it is dropping into rather than an argument it forgot.
    ///
    /// **The `nil` *arm* stays, and is not untravelled code.** `CadenceTaskDropSupport
    /// .dropKey(forGroup:)` answers `nil` for `.todayDate(.overdue)`, `.todayDate(.pastDo)` and
    /// `.completion`, so every row drop inside Today's Overdue, Past-do and Completed groups
    /// arrives here with no key. What it must do there is reorder and nothing else — those three
    /// groups are defined by a day already gone or by being finished, and there is no assignment
    /// that would make a task a member of them.
    /// `arowDropIntoAGroupWithNoKeyReordersAndAssignsNothing` is the test the ticket asked for.
    func handleTaskDrop(
        payload: String,
        targetTask: AppTask,
        scopeTasks: [AppTask],
        dropKey: String?
    ) -> Bool {
        guard let (droppedID, droppedTask) = droppedTask(from: payload),
              droppedID != targetTask.id else { return false }
        var joined = false
        if let dropKey {
            // A key that resolved to nothing is not a refusal, unlike `handleSectionDrop`: the
            // reorder below runs either way, so a row drop whose key named nothing still moved the
            // row and is not the silent accept T-591 was about. What it answers decides the
            // reorder's scope, below.
            //
            // **A re-file the STORE refused is ([[T-17115]]).** `CadenceTaskFieldEditCommit` has
            // already put the row back in its old group, so the reorder would find it outside this
            // group's scope, write nothing and answer `true` -- a drop reported as landed while the
            // row springs home, and the page's notice, set by the refusal, cleared by that `true`.
            // The drop answers `false` and the refusal's own notice stands.
            let outcome = assignTask(droppedTask, dropKey)
            if outcome == .refused { return false }
            joined = outcome == .applied
        }
        // **A row filed into this group by the drop is one of its rows ([[T-17112]]).** `scopeTasks`
        // is the TARGET group's rows, drawn before the drop, so a row dragged in from another group
        // was not among them -- and `CadenceRowReorderSpan` reads a dragged id it cannot find as a
        // drop with nothing to write. Every cross-group row drop on All Tasks, Inbox and Today
        // re-filed the row and never placed it: By List sent it to the end of the new list (the
        // re-file's own end-of-list order), By Priority and By Date left it wherever its old number
        // fell, never in front of the row it was let go over.
        let scope = joined && !scopeTasks.contains(where: { $0.id == droppedID })
            ? scopeTasks + [droppedTask]
            : scopeTasks
        // **The answer is the reorder's own (T-868).** A row drop that renumbered and then had
        // its commit refused must not be reported as a drop that happened: the rows have already
        // been put back by the time this returns, so answering `true` would spring the row to a
        // position neither the screen nor the store holds. Same sentence as `handleSectionDrop`'s
        // `false`, one failure mode further along — and the panel draws
        // `CadenceOrderCommit.failureNotice` beside it, because a drop that silently declines is
        // indistinguishable from a drop the user aimed badly.
        return reorderTask(droppedID, targetTask.id, scope)
    }

    private func droppedTask(from payload: String) -> (UUID, AppTask)? {
        guard let droppedID = taskIDFromPayload(payload),
              let droppedTask = allTasks.first(where: { $0.id == droppedID }) else {
            return nil
        }
        return (droppedID, droppedTask)
    }
}
#endif
