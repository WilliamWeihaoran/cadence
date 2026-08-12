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
        if totalMinutes > 0 {
            task.actualMinutes += totalMinutes
            if let project = task.project {
                project.loggedMinutes += totalMinutes
            } else if let area = task.area {
                area.loggedMinutes += totalMinutes
            }
        }

        if complete {
            TaskWorkflowService.markDone(task, in: modelContext)
        }

        focusManager.reset()
    }

    static func logBundleSession(
        hours: Int,
        minutes: Int,
        tasks: [AppTask],
        focusManager: FocusManager
    ) {
        distributeBundleMinutes(hours * 60 + minutes, across: tasks)
        focusManager.reset()
    }

    static func distributeBundleMinutes(_ totalMinutes: Int, across tasks: [AppTask]) {
        guard totalMinutes > 0, !tasks.isEmpty else { return }
        let weights = tasks.map { max($0.estimatedMinutes, 5) }
        let totalWeight = max(weights.reduce(0, +), 1)
        var remaining = totalMinutes

        for (index, task) in tasks.enumerated() {
            let minutes: Int
            if index == tasks.count - 1 {
                minutes = max(0, remaining)
            } else {
                minutes = min(
                    remaining,
                    max(0, Int((Double(totalMinutes) * Double(weights[index]) / Double(totalWeight)).rounded()))
                )
                remaining -= minutes
            }
            guard minutes > 0 else { continue }
            task.actualMinutes += minutes
            if let project = task.project {
                project.loggedMinutes += minutes
            } else if let area = task.area {
                area.loggedMinutes += minutes
            }
        }
    }

}
#endif
