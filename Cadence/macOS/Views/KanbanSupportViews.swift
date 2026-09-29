#if os(macOS)
import SwiftUI
import SwiftData

struct TaskListsKanbanView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// The Tasks page's All / Inbox switch. `.inbox` leaves the board's Inbox column and drops the
    /// rest — see `KanbanBoardSupport.listColumns`.
    var scope: CadenceTasksPageScope = .all
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending

    /// Kanban mode has no grouping picker — the board is always one column per list.
    var body: some View {
        // **The board derives its universe once per render, not once per column (T-1501).**
        // `activeTasks` was a computed property — two full passes over every task in the store —
        // and it was referenced *inside* the `ForEach` content closure, which is evaluated once
        // per column. So this board's per-render cost was never a constant: it was one derivation
        // plus one more per list, and adding a list added one. `TaskSurfaceUniversePassCensusTests`
        // counts the two positions separately, which is the only way that slope is visible at all.
        let activeTasks = KanbanBoardSupport.activeTasks(from: allTasks)
        return taskListColumnsBoard(activeTasks: activeTasks)
    }

    private func taskListColumnsBoard(activeTasks: [AppTask]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(listColumns(activeTasks: activeTasks)) { column in
                    TaskListKanbanColumn(
                        title: column.title,
                        color: column.color,
                        tasks: column.tasks,
                        universeTasks: activeTasks,
                        spanTasks: allTasks,
                        sortField: sortField,
                        sortDirection: sortDirection,
                        container: column.container,
                        onAssignTask: column.onAssignTask
                    )
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .clipped()
    }

    private func listColumns(activeTasks: [AppTask]) -> [KanbanListColumnModel] {
        KanbanBoardSupport.listColumns(
            areas: areas,
            projects: projects,
            activeTasks: activeTasks,
            sortField: sortField,
            sortDirection: sortDirection,
            scope: scope
        )
    }
}
#endif
