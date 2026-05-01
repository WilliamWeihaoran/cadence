#if os(macOS)
import Foundation
import SwiftData

enum FocusSessionSupport {
    static func clockDisplay(elapsedSeconds: Int) -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func durationLabel(for task: AppTask) -> String? {
        let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        return label == "-/-" ? nil : label
    }

    static func readyTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { lhs, rhs in
                let lhsScore = focusScore(for: lhs, todayKey: todayKey)
                let rhsScore = focusScore(for: rhs, todayKey: todayKey)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func sidebarDetail(for task: AppTask, todayKey: String, fallback: String) -> String {
        if task.scheduledDate == todayKey { return "Scheduled today" }
        if task.dueDate == todayKey { return "Due today" }
        if !task.containerName.isEmpty { return task.containerName }
        return fallback
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

    private static func focusScore(for task: AppTask, todayKey: String) -> Int {
        var score = 0
        if task.scheduledDate == todayKey { score += 4 }
        if task.dueDate == todayKey { score += 3 }
        if !task.dueDate.isEmpty && task.dueDate < todayKey { score += 5 }
        switch task.priority {
        case .high: score += 3
        case .medium: score += 2
        case .low: score += 1
        case .none: break
        }
        if task.actualMinutes == 0 { score += 1 }
        return score
    }
}
#endif
