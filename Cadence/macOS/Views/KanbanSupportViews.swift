#if os(macOS)
import SwiftUI
import SwiftData

struct TaskListsKanbanView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending
    var groupingMode: TaskGroupingMode = .byList

    var body: some View {
        if groupingMode == .byList {
            taskListColumnsBoard
        } else {
            legacyGroupedBoards
        }
    }

    private var taskListColumnsBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(listColumns) { column in
                    TaskListKanbanColumn(
                        title: column.title,
                        icon: column.icon,
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

    private var legacyGroupedBoards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                switch groupingMode {
                case .none:
                    TaskListBoardSection(
                        title: "Tasks",
                        icon: "square.stack.3d.up",
                        color: Theme.dim,
                        taskCount: activeTasks.taskSorted(by: sortField, direction: sortDirection).count
                    ) {
                        let sorted = activeTasks.taskSorted(by: sortField, direction: sortDirection)
                        ListSectionsKanbanView(
                            tasks: sorted,
                            universeTasks: activeTasks,
                            explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                            sortField: sortField,
                            sortDirection: sortDirection,
                            sectionTaskProvider: { _ in sorted }
                        )
                    }
                case .byList:
                    EmptyView()
                case .byPriority:
                    ForEach(Array(TaskPriority.allCases.reversed()), id: \.self) { priority in
                        let bucket = activeTasks.filter { $0.priority == priority }.taskSorted(by: sortField, direction: sortDirection)
                        if !bucket.isEmpty {
                            TaskListBoardSection(
                                title: priority.label,
                                icon: "flag.fill",
                                color: Theme.priorityColor(priority),
                                taskCount: bucket.count
                            ) {
                                ListSectionsKanbanView(
                                    tasks: bucket,
                                    universeTasks: activeTasks,
                                    explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                                    onTaskDroppedIntoColumn: { task, _ in
                                        task.priority = priority
                                    }
                                )
                            }
                        }
                    }
                case .byDate:
                    ForEach(dateBuckets) { bucket in
                        if !bucket.tasks.isEmpty {
                            TaskListBoardSection(
                                title: bucket.title,
                                icon: bucket.icon,
                                color: bucket.color,
                                taskCount: bucket.tasks.count
                            ) {
                                ListSectionsKanbanView(
                                    tasks: bucket.tasks,
                                    universeTasks: activeTasks,
                                    explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                                    onTaskDroppedIntoColumn: { task, _ in
                                        KanbanBoardSupport.applyDateBucketDrop(task: task, bucketTitle: bucket.title, todayKey: todayKey)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .clipped()
    }

    private var activeTasks: [AppTask] {
        KanbanBoardSupport.activeTasks(from: allTasks)
    }

    private var todayKey: String {
        DateFormatters.todayKey()
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

    private var dateBuckets: [KanbanDateBucket] {
        KanbanBoardSupport.dateBuckets(
            activeTasks: activeTasks,
            todayKey: todayKey,
            sortField: sortField,
            sortDirection: sortDirection
        )
    }
}
#endif
