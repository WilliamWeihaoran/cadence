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

    static func logSession(
        hours: Int,
        minutes: Int,
        complete: Bool,
        task: AppTask,
        modelContext: ModelContext,
        focusManager: FocusManager
    ) {
        let totalMinutes = hours * 60 + minutes
        CadenceFocusLedger.bank(totalMinutes, forTaskAndItsList: task, in: modelContext)

        if complete {
            TaskWorkflowService.markDone(task, in: modelContext)
        }

        focusManager.reset()
    }

    static func logBundleSession(
        hours: Int,
        minutes: Int,
        tasks: [AppTask],
        modelContext: ModelContext,
        focusManager: FocusManager
    ) {
        distributeBundleMinutes(hours * 60 + minutes, across: tasks, in: modelContext)
        focusManager.reset()
    }

    /// Delegation. The arithmetic moved to `CadenceFocusSupport.distributeMinutes(_:across:)` in
    /// `Shared/` under T-242 — it touched nothing but models, and living behind `#if os(macOS)` is
    /// why an iPhone could not run a block's timer at all. The Mac's spelling stays because the
    /// popovers here read better in this file's vocabulary; it must not grow a body again.
    static func distributeBundleMinutes(_ totalMinutes: Int, across tasks: [AppTask], in modelContext: ModelContext) {
        CadenceFocusSupport.distributeMinutes(totalMinutes, across: tasks, in: modelContext)
    }

}
#endif
