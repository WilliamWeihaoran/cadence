#if os(macOS)
import SwiftUI

enum TaskHoverVisuals {
    static func accentColor(for task: AppTask) -> Color {
        if task.isCancelled { return Theme.dim }
        if task.isDone { return Theme.green }
        if task.priority != .none { return Theme.priorityColor(task.priority) }

        let containerHex = task.containerColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !containerHex.isEmpty,
           containerHex.caseInsensitiveCompare(TaskSectionDefaults.defaultColorHex) != .orderedSame {
            return Color(hex: containerHex)
        }

        return Theme.blue
    }

    static func hoverFill(
        for task: AppTask,
        isHovered: Bool,
        isOverdue: Bool,
        isOverdo: Bool,
        normalOpacity: Double = 0.08
    ) -> Color {
        guard isHovered else { return .clear }
        if task.isDone { return Theme.green.opacity(0.07) }
        if isOverdue { return Theme.red.opacity(0.2) }
        if isOverdo { return Theme.amber.opacity(0.22) }
        return accentColor(for: task).opacity(normalOpacity)
    }

    static func borderColor(for task: AppTask, isHovered: Bool, opacity: Double) -> Color {
        isHovered ? accentColor(for: task).opacity(opacity) : .clear
    }
}
#endif
