#if os(macOS)
import SwiftUI

/// One of the two rails pinned either side of the Calendar Board's day columns.
///
/// Structurally this is a day column: the same `CadenceBoardColumnHeader`, the same `KanbanColumnScroll`,
/// the same `KanbanCard`. The one deliberate difference is the plate. Day columns sit straight on
/// the board canvas (`Theme.bg`); a rail sits on `Theme.surfaceRecessed`, because a rail is an
/// *inbox* — Overdue and Unscheduled are not dates, and must not read as though they were. The
/// recess is also what tells the eye these two columns are pinned while the days scroll past them.
struct CalendarBoardRailColumn: View {
    let rail: CalendarBoardRail
    let tasks: [AppTask]
    /// `nil` on the Overdue rail — see `KanbanColumnScroll.add`. The Unscheduled rail passes
    /// `.presentSheet`: a backlog has neither a day nor a list, so there is nothing for the inline
    /// composer the day columns use to pre-fill.
    let add: KanbanColumnAddBehavior?
    let onDrop: ([String]) -> Bool

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CadenceBoardColumnHeader(dotColor: rail.dotColor, title: rail.label, count: tasks.count)

            KanbanColumnScroll(isColumnHovered: isHovered, add: add) {
                ForEach(tasks) { task in
                    KanbanCard(task: task, showsContainerChip: true)
                        .draggable(TaskDragPayload.string(for: task.id))
                }
            }
        }
        // Matches `CalendarBoardDayColumn`'s insets exactly so the rail header sits on the same
        // baseline as the day headers even though the rail is narrower.
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: calendarBoardRailWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .onHover { isHovered = $0 }
        .background(Theme.surfaceRecessed)
        .overlay(alignment: rail == .overdue ? .trailing : .leading) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius, style: .continuous)
                    .strokeBorder(
                        rail.dotColor.opacity(kanbanColumnDropStrokeOpacity),
                        style: StrokeStyle(lineWidth: 1, dash: kanbanColumnDropDash)
                    )
                    .padding(2)
            }
        }
        .animation(kanbanColumnDropAnimation, value: isDropTargeted)
        .contentShape(Rectangle())
        .modifier(CalendarBoardRailDropModifier(
            rail: rail,
            onDrop: onDrop,
            onTargetChange: { isDropTargeted = $0 }
        ))
        .accessibilityLabel("\(rail.label.capitalized), \(tasks.count) task\(tasks.count == 1 ? "" : "s")")
    }
}

/// Installs the drop destination only on rails that accept one. Overdue is a derived state —
/// dropping a task "into overdue" would mean backdating it — so it never becomes a drop target
/// rather than accepting a drop and silently no-oping.
private struct CalendarBoardRailDropModifier: ViewModifier {
    let rail: CalendarBoardRail
    let onDrop: ([String]) -> Bool
    let onTargetChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if rail.acceptsDrops {
            content
                .dropDestination(for: String.self) { items, _ in
                    onDrop(items)
                } isTargeted: { isTargeted in
                    onTargetChange(isTargeted)
                }
        } else {
            content
        }
    }
}
#endif
