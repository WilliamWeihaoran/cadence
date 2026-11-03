#if os(iOS)
import SwiftData
import SwiftUI

/// Inbox: the query, the stored Sort / Order / Group / show-completed preferences, and
/// `iOSTaskCollectionPage`.
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
    /// **The Mac's three keys, not a second set** ([[T-8731]]). This was one
    /// `ios.inbox.sortMode`; the owner's 2026-10-31 decision under [[T-8201]] brought the Mac's
    /// Sort + Order + Group model here, and the ticket's last named consequence was that the two
    /// platforms stored the choice under different keys, "so the choice cannot follow the owner
    /// between devices". The retired key is projected onto these once at launch by
    /// `CadenceTaskPresentationPreferences`; the defaults below are the Mac Inbox's, which is the
    /// surface this page now matches.
    ///
    /// `@AppStorage` over a `RawRepresentable` rather than the `String` + subscript projection the
    /// sort chip used (T-3156, T-3158): that projection existed so the binding handed down was a
    /// comparable key path rather than a `Binding(get:set:)` closure pair, and `$sortField` on an
    /// `@AppStorage` of the enum itself is a comparable location too — the same property wrapper
    /// `TasksPageView` passes to its three badges.
    @AppStorage(CadencePreferenceKeys.inboxSortField) private var sortField: TaskSortField = .custom
    @AppStorage(CadencePreferenceKeys.inboxSortDirection) private var sortDirection: TaskSortDirection = .ascending
    @AppStorage(CadencePreferenceKeys.inboxGroupingMode) private var groupingMode: TaskGroupingMode = .none
    @AppStorage(CadencePreferenceKeys.iosInboxShowCompleted) private var showCompleted = false

    private var inboxTasks: [AppTask] {
        CadenceTaskQuerySupport.activeInboxTasks(
            from: allTasks,
            sortField: sortField,
            sortDirection: sortDirection
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
            sortField: $sortField,
            sortDirection: $sortDirection,
            // [[T-10461]]: a stored By List reads as None; the Inbox's menu no longer offers it.
            groupingMode: $groupingMode.inboxResolved,
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
