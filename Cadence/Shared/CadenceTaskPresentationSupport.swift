import Foundation
import SwiftUI

struct CadenceSubtaskProgress: Hashable {
    let completed: Int
    let total: Int

    var compactLabel: String {
        "\(completed)/\(total)"
    }

    var label: String {
        total == 1 ? "\(completed)/1 subtask" : "\(completed)/\(total) subtasks"
    }
}

enum CadenceTaskPresentationSupport {
    static func plainPreviewText(from markdown: String, limit: Int? = nil) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown, limit: limit)
    }

    static func hasNotes(_ task: AppTask) -> Bool {
        !plainPreviewText(from: task.notes).isEmpty
    }

    static func subtaskProgress(for task: AppTask) -> CadenceSubtaskProgress? {
        let subtasks = task.subtasks ?? []
        guard !subtasks.isEmpty else { return nil }
        return CadenceSubtaskProgress(
            completed: subtasks.filter(\.isDone).count,
            total: subtasks.count
        )
    }

    static func estimateLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }

    static func estimateLabel(for task: AppTask) -> String {
        estimateLabel(minutes: task.estimatedMinutes)
    }

    static func scheduledDateLabel(for task: AppTask, todayKey: String = DateFormatters.todayKey()) -> String {
        if task.scheduledStartMin >= 0 {
            let time = TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)
            if task.scheduledDate == todayKey {
                return time
            }
            return "\(DateFormatters.relativeDate(from: task.scheduledDate)) at \(time)"
        }
        return DateFormatters.relativeDate(from: task.scheduledDate)
    }

    static func dueDateLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.dueDate)
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        Theme.statusColor(status)
    }
}
