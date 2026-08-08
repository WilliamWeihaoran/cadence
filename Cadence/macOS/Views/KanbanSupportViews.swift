#if os(macOS)
import SwiftUI
import SwiftData

struct TaskListsKanbanView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending

    /// Kanban mode has no grouping picker — the All Tasks board is always one column per list.
    var body: some View {
        taskListColumnsBoard
    }

    private var taskListColumnsBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(listColumns) { column in
                    TaskListKanbanColumn(
                        title: column.title,
                        color: column.color,
                        tasks: column.tasks,
                        universeTasks: activeTasks,
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

    private var activeTasks: [AppTask] {
        KanbanBoardSupport.activeTasks(from: allTasks)
    }

    private var listColumns: [KanbanListColumnModel] {
        KanbanBoardSupport.listColumns(
            areas: areas,
            projects: projects,
            activeTasks: activeTasks,
            sortField: sortField,
            sortDirection: sortDirection
        )
    }
}
#endif
