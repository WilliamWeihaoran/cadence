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

    static func sidebarDetail(for task: AppTask, todayKey: String, fallback: String) -> String {
        CadenceFocusSupport.sidebarDetail(for: task, todayKey: todayKey, fallback: fallback)
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
