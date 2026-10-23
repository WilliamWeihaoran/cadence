#if os(macOS)
import SwiftUI

struct CalendarBoardDayColumn: View {
    let dayIndex: Int
    let date: Date
    let dateKey: String
    /// The page's observed day, handed down by `CalendarPageBoardView` ([[T-3140]]); read in
    /// place of the clock so the amber "today" accent moves at midnight.
    let todayKey: String
    let tasks: [AppTask]
    let events: [CalendarBoardEventDisplayItem]
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    /// What the column's ghost row does. A day column always composes in place — it supplies the
    /// day — but the decision still comes from `CalendarBoardPlannerSupport.addAction(for:)` so the
    /// board's columns and rails answer it in one place.
    let add: KanbanColumnAddBehavior?
    /// **Answers whether the store took the drop ([[T-1980]]), and `Void` is what hid the defect.**
    /// `handleDrop` below reads this to decide what `.dropDestination` is told, and while these two
    /// answered nothing it told it `true` unconditionally — over a `try? modelContext.save()` one
    /// frame up in `CalendarPageBoardView`. A refused drop was drawn on the day it was released and
    /// reverted at the next launch, the [[T-566]] shape the rail drop had until [[T-1952]].
    let onDropTaskOnDay: (AppTask) -> Bool

    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @State private var isDropTargeted = false
    @State private var isCompletedCollapsed = true
    @State private var isHovered = false
    @State private var isComposing = false

    nonisolated private var coordinateSpaceName: String { "calendarBoardDayColumn-\(dayIndex)" }

    /// Keyed by the day, not by `dayIndex`: the board slides its render window, so the same index
    /// is a different day after a recenter, and a hover registered under an index would answer
    /// Cmd+N for whichever day had drifted into that slot.
    private var columnHoverID: String { CalendarBoardDayColumn.hoverID(dateKey: dateKey) }

    static func hoverID(dateKey: String) -> String {
        "calendar-board-day-column-\(dateKey)"
    }

    private var isToday: Bool {
        dateKey == todayKey
    }

    /// Split on `isFinishedTask`, not on `isDone`. A cancelled task is finished, and `!$0.isDone`
    /// put it in the **active** half — the column of work you still intend to do. No card proves it
    /// today, because `CalendarBoardPlannerSupport`'s day bucketing keeps cancelled work off the
    /// Board upstream by policy; this split has to be right without depending on that (T-203).
    private var activeTasks: [AppTask] {
        tasks.filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
    }

    private var completedTasks: [AppTask] {
        tasks.filter { CadenceTaskQuerySupport.isFinishedTask($0) }
    }

    private var activeItems: [CalendarBoardColumnItem] {
        let eventItems = events.map { CalendarBoardColumnItem.event($0) }
        let taskItems = activeTasks.map { CalendarBoardColumnItem.task($0) }
        return (eventItems + taskItems).sorted(by: sortColumnItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // Same scroll container the kanban columns use, so "Add task" — and the composer that
            // replaces it — sits last in the column here exactly as it does there.
            KanbanColumnScroll(isColumnHovered: isHovered, add: add, isComposing: $isComposing) {
                content
                completedFooter
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        // Registering with `HoveredKanbanColumnManager` is what makes Cmd+N work here, the same way
        // it works over a kanban section column and an All Tasks list column. The day column used to
        // set only `isHovered`, so the shortcut documented as "open the inline composer in the
        // hovered column" silently did nothing on this board and the ghost row was the only way in.
        .onHover { hovering in
            isHovered = hovering
            if hovering, add.opensInlineComposer {
                hoveredKanbanColumnManager.beginHovering(id: columnHoverID) {
                    isComposing = true
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: columnHoverID)
            }
        }
        .background(laneBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.28))
                .frame(width: 1)
                .padding(.vertical, 3)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.72), style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        // Named at exactly the layer `dropDestination` decorates, so a release point and a measured
        // card frame are in the same space by construction rather than by coincidence.
        .coordinateSpace(.named(coordinateSpaceName))
        .dropDestination(for: String.self) { items, location in
            handleDrop(items, at: location)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        // Same count the header above it draws, through the same shared spelling iOS reads. It
        // used to announce a local `totalCount` of active + completed while the header showed
        // active only, so VoiceOver and the visible number disagreed (T-571/T-572).
        .accessibilityLabel(
            CadenceBoardColumnAccessibility.dayColumnLabel(date: date, itemCount: activeItems.count)
        )
    }

    /// The shared board header. The only things that differ from a kanban column or one of this
    /// board's rails are the label text (weekday + date) and — for today only — the amber rule in
    /// place of the neutral hairline, which is the single sanctioned exception to the treatment.
    private var header: some View {
        CadenceBoardColumnHeader(
            dotColor: isToday ? Theme.amber : Theme.dim,
            title: "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))",
            count: activeItems.count,
            accentRule: isToday ? Theme.amber : nil
        )
    }

    @ViewBuilder
    private var content: some View {
        ForEach(activeItems) { item in
            columnItemView(item)
        }
    }

    @ViewBuilder
    private var completedFooter: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                KanbanCompletedTasksToggle(count: completedTasks.count, isExpanded: !isCompletedCollapsed) {
                    withAnimation(.snappy(duration: 0.16)) {
                        isCompletedCollapsed.toggle()
                    }
                }

                if !isCompletedCollapsed {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(completedTasks.sorted { lhs, rhs in
                            CalendarBoardPlannerSupport.boardTaskSort(lhs, rhs)
                        }) { task in
                            KanbanCard(task: task, showsContainerChip: true, dayAlreadyStatedBySurface: dateKey, todayKey: todayKey)
                                .draggable(TaskDragPayload.string(for: task.id))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func columnItemView(_ item: CalendarBoardColumnItem) -> some View {
        switch item {
        case .event(let item):
            CalendarBoardEventCard(item: item)
        case .task(let task):
            KanbanCard(task: task, showsContainerChip: true, dayAlreadyStatedBySurface: dateKey, todayKey: todayKey)
                .draggable(TaskDragPayload.string(for: task.id))
        }
    }

    @ViewBuilder
    private var laneBackground: some View {
        if isToday || isDropTargeted {
            LinearGradient(
                colors: [
                    (isDropTargeted ? Theme.blue : Theme.amber).opacity(isDropTargeted ? 0.10 : 0.055),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.clear
        }
    }

    /// **Nothing nested in this column can claim a drag any more ([[T-3170]]).** A release used to
    /// be arbitrated: a Block card sitting in the column owned its own drop, so answering the day
    /// drop as well would re-file the task onto the day and, through `removeTaskFromBundle`, undo
    /// the bundling that had just happened. With the Block card gone there is no second claimant,
    /// so every release is the reschedule this column already reads it as — the same simplification
    /// the iOS board made in the pass before this one.
    ///
    /// `location` is kept in the signature: `.dropDestination` supplies it, and the parameter
    /// costing nothing is cheaper than a call-site change that would have to be undone if this
    /// column ever gains a nested target again.
    private func handleDrop(_ items: [String], at location: CGPoint) -> Bool {
        guard let payload = items.first,
              let taskID = TaskDragPayload.taskID(from: payload),
              let task = allTasks.first(where: { $0.id == taskID }) else { return false }
        return onDropTaskOnDay(task)
    }

    private func sortColumnItems(_ lhs: CalendarBoardColumnItem, _ rhs: CalendarBoardColumnItem) -> Bool {
        let lhsKey = lhs.sortKey
        let rhsKey = rhs.sortKey
        if lhsKey != rhsKey { return lhsKey < rhsKey }
        switch (lhs, rhs) {
        case (.task(let lhsTask), .task(let rhsTask)):
            return CalendarBoardPlannerSupport.boardTaskSort(lhsTask, rhsTask)
        case (.event(let lhsEvent), .event(let rhsEvent)):
            return lhsEvent.id < rhsEvent.id
        default:
            return lhs.id < rhs.id
        }
    }

}

private enum CalendarBoardColumnItem: Identifiable {
    case event(CalendarBoardEventDisplayItem)
    case task(AppTask)

    var id: String {
        switch self {
        case .event(let item):
            return "event-\(item.id)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    // Rank 2 for tasks, with no rank 1 above it: [[T-3170]] removed the Block card that held the
    // middle rank. These are a sort order rather than a dense index, and renumbering would make
    // this column disagree with `CalendarBoardPlannerSupport.sortKey`'s other callers for nothing.
    var sortKey: CalendarBoardSortKey {
        switch self {
        case .event(let item):
            return item.sortKey
        case .task(let task):
            return CalendarBoardPlannerSupport.sortKey(for: task, kindRank: 2)
        }
    }
}
#endif
