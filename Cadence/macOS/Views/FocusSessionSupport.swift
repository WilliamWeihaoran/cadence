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

    /// **The Mac's half of the Log Session form, and only its half** ([[T-8732]]).
    ///
    /// The write itself — bank the minutes, settle a ticked completion, undo the bank on a refusal
    /// — is `CadenceFocusSupport.logSession`, which iOS's sheet calls too; T-654's one-unit rule
    /// and its reasoning live there. What stays here is what is genuinely the Mac's: `FocusManager`
    /// is this platform's session, and moving it on is not something a shared helper can do for a
    /// screen whose clock is `CadenceFocusTimerState`.
    static func logSession(
        hours: Int,
        minutes: Int,
        complete: Bool,
        task: AppTask,
        modelContext: ModelContext,
        focusManager: FocusManager,
        nextReadyTask: () -> AppTask?,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceFocusSupport.logSession(
            hours: hours,
            minutes: minutes,
            complete: complete,
            task: task,
            modelContext: modelContext,
            commit: commit
        )
        // T-5303: a completed task is not a session any more. Leaving it as `activeSession` kept
        // the page on the finished task, so the next ▶ timed it and the next log credited it.
        // Mirror iOS `iOSFocusView.logSession(hours:minutes:complete:task:)`: adopt the next ready
        // task, else end the session. Read only after the settle, so the finished task is no
        // longer ready.
        if complete, focusManager.activeTask?.id == task.id {
            focusManager.activeTask = nextReadyTask()
        }
        focusManager.reset()
    }

}
#endif
