#if os(macOS)
import Foundation
import SwiftData

enum FocusSessionSupport {
    static func clockDisplay(elapsedSeconds: Int) -> String {
        CadenceFocusSupport.clockDisplay(elapsedSeconds: elapsedSeconds)
    }

    static func durationLabel(for task: AppTask) -> String? {
        let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        return label == "-/-" ? nil : label
    }

    static func readyTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        CadenceFocusSupport.readyTasks(from: tasks, todayKey: todayKey)
    }

    /// The hour/minute pair the "Log session" popovers pre-fill from the stopwatch.
    ///
    /// Goes through `CadenceFocusSupport.minutes(fromElapsedSeconds:)` — the one place that turns
    /// elapsed seconds into logged minutes — rather than re-deriving it. Both popovers used to
    /// ceil (`(seconds + 59) / 60`), which is the rounding that helper's own doc comment describes
    /// as a bug it fixed: a 61-second session pre-filled 2 minutes while `FocusManager.commitElapsed`
    /// logged 1 for the same stopwatch reading, and a 20-second session pre-filled a whole minute
    /// of work that never happened. Logged time is a record, so the two paths have to agree.
    static func logFieldSeed(elapsedSeconds: Int) -> (hours: Int, minutes: Int) {
        let total = CadenceFocusSupport.minutes(fromElapsedSeconds: elapsedSeconds)
        return (total / 60, total % 60)
    }

    /// **Throws and takes `commit:` now (T-654).** It used to bank through
    /// `CadenceFocusLedger.bank` — a pending insert since T-621 — and, when `complete` was ticked,
    /// finish the task through `TaskWorkflowService.markDone` directly: neither ever reached a
    /// `save()`, swallowed or otherwise, so the manual "Log Session" popover's checkmark could mint
    /// a recurrence successor with nothing to commit it. Both writes are one unit now, the same
    /// shape `CadenceFocusSupport.complete` uses for the focus timer's own completion door
    /// (T-636(c)): the bank is written pending, then `complete` settles through the funnel that
    /// commits the successor too, or (when not completing) the bank commits on its own — either
    /// way exactly one commit, and the banked minutes are undone if it refuses.
    static func logSession(
        hours: Int,
        minutes: Int,
        complete: Bool,
        task: AppTask,
        modelContext: ModelContext,
        focusManager: FocusManager,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let totalMinutes = hours * 60 + minutes
        let banked = CadenceFocusSupport.BankedMinutes(task)
        CadenceFocusLedger.bank(totalMinutes, forTaskAndItsList: task, in: modelContext)
        do {
            if complete {
                try CadenceTaskMutationSupport.commitSettle(task, in: modelContext, commit: commit) {
                    TaskWorkflowService.markDone(task, in: modelContext)
                }
            } else {
                try commit(modelContext)
            }
        } catch {
            banked.restore(in: modelContext)
            throw error
        }
        focusManager.reset()
    }

    /// - Parameter commit: See `distributeBundleMinutes(_:across:in:commit:)`.
    static func logBundleSession(
        hours: Int,
        minutes: Int,
        tasks: [AppTask],
        modelContext: ModelContext,
        focusManager: FocusManager,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try distributeBundleMinutes(hours * 60 + minutes, across: tasks, in: modelContext, commit: commit)
        focusManager.reset()
    }

    /// Delegation. The arithmetic moved to `CadenceFocusSupport.distributeMinutes(_:across:)` in
    /// `Shared/` under T-242 — it touched nothing but models, and living behind `#if os(macOS)` is
    /// why an iPhone could not run a block's timer at all. The Mac's spelling stays because the
    /// popovers here read better in this file's vocabulary; it must not grow a body again.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func distributeBundleMinutes(
        _ totalMinutes: Int,
        across tasks: [AppTask],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceFocusSupport.distributeMinutes(totalMinutes, across: tasks, in: modelContext, commit: commit)
    }

}
#endif
