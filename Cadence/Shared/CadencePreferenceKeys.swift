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
}
