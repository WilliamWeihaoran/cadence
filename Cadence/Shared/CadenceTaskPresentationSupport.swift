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

    /// Canonical minutes → duration label for the whole app: "45m", "2h", "1h 24m".
    /// Never renders a decimal hour — the hour and minute components are shown separately,
    /// and a zero component is omitted.
    ///
    /// The gap between the hour and minute components is a NON-BREAKING SPACE (U+00A0) on
    /// purpose. These labels are drawn inside hard-clipped fixed-size chrome (timeline blocks
    /// can be ~50pt wide when three tasks overlap); an ordinary space is a line-break
    /// opportunity, so "1h 30m" would wrap and the clipped second line would leave the badge
    /// reading "1h" for a 90-minute task — wrong information, not just truncation.
    static func estimateLabel(minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h\u{00A0}\(remainder)m"
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
