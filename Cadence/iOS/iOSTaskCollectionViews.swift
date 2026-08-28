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
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager

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
        // **T-375.** A deep link for work finished elsewhere routes to this page, and this page
        // kept the row it named behind the Completed toggle — so the tap landed on the right
        // screen with the task hidden on it. Opening the toggle is what makes the link's promise
        // ("show me this task") true, and it is the precondition for every other answer: a
        // collapsed section renders no row to select, scroll to or open.
        //
        // It **writes** the stored preference rather than overriding the read. An override would
        // make the toggle read `true` while the user's setting stayed `false`, so their next tap
        // on it would appear to do nothing. This way the disclosure is simply open, with the
        // control that closes it in view — the state is visible and the user owns it again the
        // moment they touch it.
        .onAppear(perform: revealCompletedIfLinked)
        .onChange(of: deepLinkManager.revealedCompletedTaskID) { _, _ in
            revealCompletedIfLinked()
        }
        // No seed. All Tasks is every list at once, so there is no list for it to prefer.
        .iOSFloatingCreateTaskButton()
        .iOSHidesCompactNavigationBar()
    }

    /// Membership-tested, not id-tested: `revealedCompletedTaskID` is one value on a manager every
    /// task surface can read, so a page whose universe does not contain the task leaves its
    /// logbook shut. See `CadenceDeepLinkResolutionSupport.revealsCompletedSection`.
    private func revealCompletedIfLinked() {
        guard CadenceDeepLinkResolutionSupport.revealsCompletedSection(
            revealedTaskID: deepLinkManager.revealedCompletedTaskID,
            completedTasks: completedTasks
        ) else { return }
        showCompleted = true
    }
}
#endif
