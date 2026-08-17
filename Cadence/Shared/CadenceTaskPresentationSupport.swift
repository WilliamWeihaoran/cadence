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

    /// How many unfinished subtasks a row lists before it stops and says how many are left.
    ///
    /// Three, measured rather than guessed. Uncapped was tried first and shipped to a screenshot:
    /// one sample row with four subtasks stood ~290pt tall and iPhone Today fell from about five
    /// visible tasks to two and a half — a checklist on one task hiding the rest of the day. The
    /// row still names what is left rather than counting it, which is what the old `0/3` chip got
    /// wrong; it just stops naming at three.
    static let rowSubtaskLimit = 3

    /// The subtasks a task row lists **beneath** itself, in `order`, capped at `rowSubtaskLimit`.
    ///
    /// Unfinished only. The iOS row used to say `0/3` in a chip, which named a number of things to
    /// do without naming any of them — so the checklist was only ever readable by opening the task.
    /// Finished subtasks stay out because they say nothing new: a row's job here is what is left.
    static func unfinishedSubtasks(for task: AppTask) -> [Subtask] {
        Array(allUnfinishedSubtasks(for: task).prefix(rowSubtaskLimit))
    }

    /// Everything `unfinishedSubtasks` would list if it did not cap — the denominator behind the
    /// overflow line, so the two cannot disagree about what "more" means.
    static func allUnfinishedSubtasks(for task: AppTask) -> [Subtask] {
        (task.subtasks ?? [])
            .filter { !$0.isDone }
            .sorted { $0.order < $1.order }
    }

    /// How many unfinished subtasks the row is **not** showing, or `nil` when it is showing them
    /// all. The row draws a "+N more" line from this; `nil` draws nothing rather than "+0 more".
    static func hiddenSubtaskCount(for task: AppTask) -> Int? {
        let hidden = allUnfinishedSubtasks(for: task).count - rowSubtaskLimit
        return hidden > 0 ? hidden : nil
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

    /// The do date as a **day**, never a time — "Today", "3 days ago", "Aug 24".
    ///
    /// `scheduledDateLabel` folds the timeline slot into the same string ("3 days ago at 9:30 AM –
    /// 10 AM"), which is right for a surface with no timeline beside it and wrong for a task row:
    /// there the slot ran to three times the width of every other chip and pushed the row's
    /// metadata onto a second line. The iOS row shows the day here; the Today timeline pane and the
    /// task inspector are where the slot itself is read.
    static func scheduledDayLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.scheduledDate)
    }

    static func dueDateLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.dueDate)
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        Theme.statusColor(status)
    }
}
