#if os(macOS)
import SwiftUI

/// Hover visuals shared by every task-row-like surface (task lists, kanban cards, planning cards).
///
/// Hover is deliberately **neutral**: it never derives a hue from the task's list/container color,
/// its priority, or its urgency. Hovering any task on any surface produces the same gray wash.
/// State meaning (priority on the completion circle, the container icon color, red/amber overdue
/// and over-do date text) is expressed by persistent elements, not by the hover wash.
enum TaskHoverVisuals {
    /// Neutral raised-surface fill for surfaces that are **transparent** at rest — task rows,
    /// which sit directly on the page background.
    static func hoverFill(isHovered: Bool) -> Color {
        isHovered ? Theme.surfaceElevated : .clear
    }

    /// Neutral raised-surface fill for surfaces that draw their **own** resting fill — kanban
    /// and planning cards, which are `Theme.surface` objects on a canvas. Same raise as
    /// `hoverFill`, so all three surfaces stay single-sourced.
    static func cardFill(isHovered: Bool) -> Color {
        isHovered ? Theme.surfaceElevated : Theme.surface
    }

    /// Neutral hairline used while a task row/card is hovered.
    static func borderColor(isHovered: Bool) -> Color {
        isHovered ? Theme.borderSubtle : .clear
    }
}
#endif
