#if os(iOS)
import SwiftData
import SwiftUI

/// Inbox: the query, the two stored preferences, and `iOSTaskCollectionPage`.
///
/// **One full-width column, at every width.** The iPad layout was once an `HStack` of the list and
/// an "Overview" pane, which spent about a third of the screen on "0 ACTIVE", "0 DONE" and an
/// "OLDEST ITEM" that read "Clear" whenever there was nothing to be oldest — every one of which was
/// already on screen. What replaced it was a `List` column that still differed from the phone's
/// `LazyVStack` in its container, its row insets and its separators; that is gone too, and the
/// `horizontalSizeClass` branch with it. See `iOSTaskCollectionPage`.
///
/// The type was called `iPadInboxView` for one release after that, and its own doc comment said the
/// name was wrong. T-283 renamed it and its file: a name that claims a device is the thing that
/// makes the next reader write a second copy for the other one.
struct iOSInboxView: View {
    /// Off when the Tasks tab hosts this as its Inbox segment — see
    /// `iOSTodayView.showsCompactHeader`. Still on when Inbox is reached as a pushed screen.
    var showsCompactHeader = true
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.inbox.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.inbox.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder
    }

    private var sortModeBinding: Binding<CadenceTaskSortMode> {
        Binding(
            get: { sortMode },
            set: { sortModeRaw = $0.rawValue }
        )
    }

    private var inboxTasks: [AppTask] {
        CadenceTaskQuerySupport.activeInboxTasks(
            from: allTasks,
            sortMode: sortMode
        )
    }

    private var completedInboxTasks: [AppTask] {
        CadenceTaskQuerySupport.completedInboxTasks(from: allTasks)
    }

    var body: some View {
        iOSTaskCollectionPage(
            collection: .inbox,
            showsHeader: showsCompactHeader,
            activeTasks: inboxTasks,
            completedTasks: completedInboxTasks,
            sortMode: sortModeBinding,
            showCompleted: $showCompleted
        )
        // No seed: the Inbox is where a task goes when it has no list yet, so seeding one would
        // contradict the surface it was captured from.
        .iOSFloatingCreateTaskButton()
        // The page heads itself with "CAPTURE / Inbox", so a nav title repeated the word one row
        // higher. See `iOSHidesCompactNavigationBar()`.
        .iOSHidesCompactNavigationBar()
    }
}
#endif
