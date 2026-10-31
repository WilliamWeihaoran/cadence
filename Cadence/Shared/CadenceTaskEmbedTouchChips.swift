import SwiftUI

/// One metadata chip on the iOS task-embed card: its words and its hue.
nonisolated struct CadenceTaskEmbedTouchChip: Equatable {
    let title: String
    let tint: Color
}

/// The chip row the iOS task-embed card draws, in the note editor (`iOSMarkdownTaskEmbedLayoutInfo`)
/// and in Focus's read-only note (`iOSMarkdownPreview`).
///
/// [[T-9271]]: those two files each built this row privately, and both had drifted from the rule
/// the Mac card (`MarkdownTaskEmbedDrawingSupport.displayChips`) and the rest of the app follow:
///
/// - **Every open task carried a `Todo` chip**, and a snapshot still reading "inprogress" an
///   `In Progress` one. [[T-5015]] (b) — an owner decision — is that neither status draws a mark of
///   its own, and `CadenceInProgressStatusRetirement.drawsStatusChip` is where that is decided.
/// - **Low priority was green**, the colour that means done on the same card; it is blue
///   everywhere else (`Theme.priorityColor`).
///
/// One builder now, so the editor and the Focus copy of the same card cannot disagree either.
nonisolated enum CadenceTaskEmbedTouchChips {
    static let missingTitle = "Missing"

    static func chips(
        for task: MarkdownTaskEmbedRenderInfo,
        relativeTo referenceDate: Date = Date()
    ) -> [CadenceTaskEmbedTouchChip] {
        // A reference whose task is gone says so and nothing else, as the Mac card does.
        if task.isMissing {
            return [CadenceTaskEmbedTouchChip(title: missingTitle, tint: Theme.red)]
        }

        var chips: [CadenceTaskEmbedTouchChip] = []
        let status = TaskStatus(rawValue: task.statusRaw) ?? (task.isDone ? .done : .todo)
        if CadenceInProgressStatusRetirement.drawsStatusChip(status) {
            chips.append(CadenceTaskEmbedTouchChip(title: status.label, tint: Theme.statusColor(status)))
        }

        if let priority = TaskPriority(rawValue: task.priorityRaw), priority != .none {
            chips.append(CadenceTaskEmbedTouchChip(title: priority.label, tint: Theme.priorityColor(priority)))
        }
        if task.estimatedMinutes > 0 {
            chips.append(
                CadenceTaskEmbedTouchChip(
                    title: TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes),
                    tint: Theme.amber
                )
            )
        }
        if !task.scheduledDate.isEmpty {
            let date = DateFormatters.relativeDate(from: task.scheduledDate, relativeTo: referenceDate)
            let time = task.scheduledStartMin >= 0 ? " \(TimeFormatters.timeString(from: task.scheduledStartMin))" : ""
            chips.append(CadenceTaskEmbedTouchChip(title: "Do \(date)\(time)", tint: Theme.blue))
        }
        if !task.dueDate.isEmpty {
            let date = DateFormatters.relativeDate(from: task.dueDate, relativeTo: referenceDate)
            chips.append(CadenceTaskEmbedTouchChip(title: "Due \(date)", tint: Theme.red))
        }
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(CadenceTaskEmbedTouchChip(title: task.containerName, tint: Theme.muted))
        }
        return chips
    }
}
