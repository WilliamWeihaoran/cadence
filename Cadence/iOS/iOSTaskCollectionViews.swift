#if os(iOS)
import SwiftData
import SwiftUI

struct iOSAllTasksView: View {
    /// Off when the Tasks tab hosts this as its All segment — see `iPadTodayView.showsCompactHeader`
    /// for the reasoning. Still on when All Tasks is reached as a pushed screen.
    var showsCompactHeader = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.allTasks.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.allTasks.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: allTasks,
            sortMode: sortMode
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: allTasks)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                iOSCompactAllTasksView(
                    showsHeader: showsCompactHeader,
                    activeTasks: activeTasks,
                    completedTasks: completedTasks,
                    sortMode: Binding(
                        get: { sortMode },
                        set: { sortModeRaw = $0.rawValue }
                    ),
                    showCompleted: $showCompleted
                )
            } else {
                allTasksPanel
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        // No seed. All Tasks is every list at once, so there is no list for it to prefer.
        .iOSFloatingCreateTaskButton()
        .iOSHidesCompactNavigationBar()
    }

    private var allTasksPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same page as `iOSCompactAllTasksView`, so the same `.page` header — eyebrow, checklist
            // tile, 30/26pt title, blue count. It was `iOSPanelHeader` here and
            // `iOSCompactPageHeader` there: one screen, two headers.
            iOSPageHeader(
                eyebrow: "Tasks",
                title: "All Tasks",
                systemImage: "checklist",
                color: Theme.blue,
                count: activeTasks.count
            )

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
                    title: CadenceEmptyStateCopy.allTasksTitle,
                    subtitle: CadenceEmptyStateCopy.allTasksSubtitle
                )
            } else {
                List {
                    if !activeTasks.isEmpty {
                        Section {
                            ForEach(activeTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            // `.completion`, not `.list` — All Tasks is every list at once, so this
                            // heading shares nothing a new task could inherit and does not accept
                            // a dropped `+`. The identically titled group on Inbox does, because
                            // there every row is in the Inbox by construction.
                            iOSTaskGroupHeader(
                                title: "Active",
                                color: Theme.blue,
                                count: activeTasks.count,
                                dropIdentity: .completion
                            )
                        }
                    }

                    if showCompleted && !completedTasks.isEmpty {
                        Section {
                            ForEach(CadenceTaskSurfaceOptions.completedRows(from: completedTasks)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskGroupHeader(
                                title: "Completed",
                                color: Theme.green,
                                count: CadenceTaskSurfaceOptions.completedRows(from: completedTasks).count,
                                dropIdentity: .completion
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif
