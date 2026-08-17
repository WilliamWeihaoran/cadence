#if os(iOS)
import SwiftData
import SwiftUI

/// All Tasks: the query, the two stored preferences, and `iOSTaskCollectionPage`.
///
/// There is no `horizontalSizeClass` branch left in here. This view used to pick between
/// `iOSCompactAllTasksView` and a `List`-based `allTasksPanel` defined below it — one screen with
/// two scroll containers, two separator treatments and two sets of row insets. Both are gone; see
/// `iOSTaskCollectionPage` for which container won and what the `List` was providing.
struct iOSAllTasksView: View {
    /// Off when the Tasks tab hosts this as its All segment — see `iPadTodayView.showsCompactHeader`
    /// for the reasoning. Still on when All Tasks is reached as a pushed screen.
    var showsCompactHeader = true
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.allTasks.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.allTasks.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder
    }

    private var sortModeBinding: Binding<CadenceTaskSortMode> {
        Binding(
            get: { sortMode },
            set: { sortModeRaw = $0.rawValue }
        )
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
        iOSTaskCollectionPage(
            collection: .allTasks,
            showsHeader: showsCompactHeader,
            activeTasks: activeTasks,
            completedTasks: completedTasks,
            sortMode: sortModeBinding,
            showCompleted: $showCompleted
        )
        // No seed. All Tasks is every list at once, so there is no list for it to prefer.
        .iOSFloatingCreateTaskButton()
        .iOSHidesCompactNavigationBar()
    }
}
#endif
