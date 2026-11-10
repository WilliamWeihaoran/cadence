#if os(iOS)
import SwiftData
import SwiftUI

/// All Tasks: the query, the stored Sort / Order / Group / show-completed preferences, and
/// `iOSTaskCollectionPage`.
///
/// There is no `horizontalSizeClass` branch left in here. This view used to pick between
/// `iOSCompactAllTasksView` and a `List`-based `allTasksPanel` defined below it — one screen with
/// two scroll containers, two separator treatments and two sets of row insets. Both are gone; see
/// `iOSTaskCollectionPage` for which container won and what the `List` was providing.
///
/// No header of its own and no flag for one (T-11214) — see `iOSInboxView`, which has the same
/// single host.
struct iOSAllTasksView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// **The Mac's three keys, not a second set** ([[T-8731]]) — see `iOSInboxView`, which carries
    /// the argument and the migration. The defaults are macOS All Tasks': date-first, ascending,
    /// grouped by date, which is the page this one now matches.
    ///
    /// These replace the `String` + `sortModeFallingBackTo` projection that was here. That
    /// projection existed for one measured reason (T-3156): a `Binding(get:set:)` is a binding
    /// SwiftUI cannot compare, so `iOSTaskCollectionPage` was re-run with `_sortMode changed` four
    /// times per New task sheet round trip while this view itself ran 0 times, and 0 times once
    /// the binding became a comparable key path. `$sortField` on an `@AppStorage` of the enum is
    /// a comparable location for the same reason, so the property that fixed it is preserved
    /// rather than reverted — it is the same `@AppStorage` projection `TasksPageView` hands its
    /// three badges on the Mac.
    @AppStorage(CadencePreferenceKeys.allTasksSortField) private var sortField: TaskSortField = .date
    @AppStorage(CadencePreferenceKeys.allTasksSortDirection) private var sortDirection: TaskSortDirection = .ascending
    @AppStorage(CadencePreferenceKeys.allTasksGroupingMode) private var groupingMode: TaskGroupingMode = .byDate
    @AppStorage(CadencePreferenceKeys.iosAllTasksShowCompleted) private var showCompleted = false
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager

    /// **The Mac's scope, not the whole store** ([[T-15101]]): a task inside a completed or
    /// archived list draws no row here, which is what the header badge and Settings' Active tasks
    /// tile already counted.
    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: CadenceTaskQuerySupport.allTasksScope(from: allTasks),
            sortField: sortField,
            sortDirection: sortDirection
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: CadenceTaskQuerySupport.allTasksScope(from: allTasks))
    }

    var body: some View {
        iOSTaskCollectionPage(
            collection: .allTasks,
            activeTasks: activeTasks,
            completedTasks: completedTasks,
            sortField: $sortField,
            sortDirection: $sortDirection,
            groupingMode: $groupingMode,
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
