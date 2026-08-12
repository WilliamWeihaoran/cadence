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

    /// Minutes → duration label for task chrome — "45m", "2h", "1h 24m", `"0m"` for nothing.
    ///
    /// The shape (and the non-breaking space that keeps it from wrapping into a wrong number) is
    /// `TimeFormatters.durationLabel(minutes:emptyPlaceholder:)`; only the empty sentinel is this
    /// surface's own. `emptyPlaceholder` lets the callers that want a dash instead of `"0m"` reach
    /// the same formatter rather than writing a fifth copy of it.
    static func estimateLabel(minutes: Int, emptyPlaceholder: String = "0m") -> String {
        TimeFormatters.durationLabel(minutes: minutes, emptyPlaceholder: emptyPlaceholder)
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
