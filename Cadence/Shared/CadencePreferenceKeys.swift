import Foundation

/// The `@AppStorage` keys shared by more than one surface, and their defaults.
///
/// Each of these was previously typed as a bare string literal in two or three unrelated files,
/// with the default value repeated alongside it. Both halves of that are hazards: a typo in one
/// site silently creates a *second, empty* preference rather than failing, and a duplicated
/// default lets a settings screen and the screen it configures disagree about what "unset" means.
///
/// Keys that only one file reads are deliberately not here — a constant for a single call site
/// adds indirection without removing a way to be wrong.
enum CadencePreferenceKeys {
    /// Comma-separated `SidebarStaticDestination` raw values the user has hidden.
    /// Read by the sidebar, the Settings sidebar section, and global search (which must not offer
    /// a destination the sidebar is hiding).
    static let sidebarHiddenTabs = "sidebarHiddenTabs"

    /// Comma-separated `SidebarStaticDestination` raw values in the user's chosen order.
    static let sidebarTabOrder = "sidebarTabOrder"

    /// Per-destination colour overrides, encoded by `SidebarStaticDestination`.
    static let sidebarTabColors = "sidebarTabColors"

    /// Which tab a list detail page opens on. The default lives here rather than at each call
    /// site because `ListDetailPage.resolved(_:)` also has to map a persisted "Planning" value —
    /// a tab that no longer exists — back onto it.
    static let listDetailDefaultPage = "listDetailDefaultPage"

    /// Empty string, the shared "nothing stored yet" default for the three sidebar keys above.
    static let emptySidebarPreference = ""

    // MARK: - Task-surface presentation (T-1307)
    //
    // Every one of these gained a second reader the day the look became synced:
    // `CadenceLookPreferenceStore.mirrors(on:)` names them to carry their values into and out of
    // the `LookPreference` record, and the surface below each one still reads it through
    // `@AppStorage`. Two readers is exactly the condition this file exists for — and the sweep
    // agrees: `CadenceSharedConstantReuseSweepTests` failed on the first version of the mirror
    // table, which re-typed all fourteen literals.
    //
    // **The raw strings cannot change.** They are on disk on the owner's three devices, and a
    // renamed key does not migrate — it silently resets that preference to its default.

    /// macOS All Tasks: `TaskSortField`, `TaskSortDirection` and `TaskGroupingMode` raw values.
    static let allTasksSortField = "allTasksSortField"
    static let allTasksSortDirection = "allTasksSortDirection"
    static let allTasksGroupingMode = "allTasksGroupingMode"

    /// macOS Inbox. Separate from All Tasks' keys on purpose: Inbox is a hand-ordered capture list
    /// where `.custom` is the point, and All Tasks is date-first.
    static let inboxSortField = "inboxSortField"
    static let inboxSortDirection = "inboxSortDirection"
    static let inboxGroupingMode = "inboxGroupingMode"

    /// macOS Today, holding a `CadenceTaskSortMode` raw value rather than a `TaskSortField` —
    /// T-606 folded the Order chip into the named modes there. `TasksPanel` reads it through
    /// `sortModeDefaultsKey`, which is this constant.
    static let todaySortMode = "todaySortMode"

    /// iOS's four task surfaces. Each stores one `CadenceTaskSortMode` and one show-completed
    /// `Bool`; iOS has never had a direction control or a grouping one.
    static let iosTodaySortMode = "ios.today.sortMode"
    static let iosTodayShowCompleted = "ios.today.showCompleted"
    static let iosAllTasksSortMode = "ios.allTasks.sortMode"
    static let iosAllTasksShowCompleted = "ios.allTasks.showCompleted"
    static let iosInboxSortMode = "ios.inbox.sortMode"
    static let iosInboxShowCompleted = "ios.inbox.showCompleted"
    static let iosListDetailSortMode = "ios.listDetail.sortMode"
    static let iosListDetailShowCompleted = "ios.listDetail.showCompleted"
}
