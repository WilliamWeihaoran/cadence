#if os(iOS)
import SwiftData
import SwiftUI

struct iOSAllTasksView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.allTasks.sortMode") private var sortModeRaw = iOSTaskSortMode.listOrder.rawValue
    @AppStorage("ios.allTasks.showCompleted") private var showCompleted = false

    private var sortMode: iOSTaskSortMode {
        get { iOSTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: allTasks,
            sortMode: sortMode.cadenceSortMode
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: allTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Tasks", title: "All Tasks", count: activeTasks.count)

            Divider().background(Theme.borderSubtle)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: "No active tasks",
                    subtitle: "Tasks you create on iPad or Mac will collect here."
                )
            } else {
                List {
                    if !activeTasks.isEmpty {
                        Section {
                            ForEach(activeTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Active", color: Theme.blue)
                        }
                    }

                    if showCompleted && !completedTasks.isEmpty {
                        Section {
                            ForEach(completedTasks.prefix(24)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

}
#endif
