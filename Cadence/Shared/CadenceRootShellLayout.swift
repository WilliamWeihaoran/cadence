import CoreGraphics

/// How the iPad root shell divides its window between the sidebar column and the detail pane.
///
/// The shell is an `HStack` of a **fixed-width** sidebar and the detail beside it. An `HStack` does
/// not shrink a fixed `.frame(width:)`, and it does not shrink a child below the minimum its own
/// content declares either — it overflows. The detail pane's content routinely declares minimums
/// (`iOSTodayView`'s two panes, `iOSCalendarView`'s inspector, and — until it was deleted — the
/// Inbox's second column at `440 + 1 + 280`). When those minimums exceed what is left after the
/// sidebar, the row lays out wider than the window, and because the shell then pinned that row into
/// a `.frame(width: proxy.size.width, ...)` with the **default `.center` alignment**, half of the
/// overflow hung off the *leading* edge, where the screen clipped it. The symptom was the sidebar
/// reading "KSPACE" and "GRESS" — nothing was clipping the sidebar; the sidebar had been positioned
/// off-screen by a pane three levels down.
///
/// The fix is the rule `CadenceTodayLayoutSupport` and `CadenceRegularSplitLayout` already follow: a
/// declared minimum is a preference, and what is actually on screen is the guarantee. The detail
/// pane is handed exactly `windowWidth - sidebarWidth` and clips its own content, so no pane it
/// hosts can move the navigation column. `detailWidth` + `sidebarWidth` is always the window.
///
/// **Registered, not orphaned.** T-182 counted four expressions of that rule and there are six; this
/// is one of the two it missed, which is the argument for keeping the list somewhere a test can
/// check. The register — every expression, and why each stays in its own surface's file — is at the
/// top of `CadenceRegularPaneLayout.swift`.
enum CadenceRootShellLayout {
    /// The icon-only column, used where a labelled one would not leave the detail enough room.
    ///
    /// **Multitasking is the only thing that reaches it, and it does reach it.** No target device
    /// produces a window under 820pt at regular width *full screen*: an iPhone is compact and runs
    /// the tab shell instead, and an 11" Pro is 834 in portrait and 1210 in landscape. It takes a
    /// window that is simultaneously horizontally-regular and narrow, which is exactly what
    /// **a 2/3 Split View on the 11" Pro in landscape is — ~782–795pt depending on generation** —
    /// and what Stage Manager produces at any size the user drags to. Delete this and that
    /// configuration gets a 188pt labelled column out of a 780pt window, or no navigation at all.
    static let railWidth: CGFloat = 58
    /// The labelled column.
    static let expandedWidth: CGFloat = 188
    /// Folded away. **Zero, not a stub.** The point of folding is that the detail pane gets the
    /// whole window — an 11" Pro in portrait hands the detail 646pt, and 188pt back is the
    /// difference between a cramped pane and a usable one. Leaving a residual strip would spend
    /// part of what the fold is for, so the expand affordance floats over the detail instead of
    /// living in a column of its own.
    static let collapsedWidth: CGFloat = 0
    /// Full window width (not the column's own). Both orientations of the target iPad clear it —
    /// 834 portrait, 1210 landscape — so the labelled column is what the app shows full screen and
    /// `railWidth` is what a split or a resized window falls back to.
    static let expandedMinWindowWidth: CGFloat = 820

    static func usesExpandedSidebar(windowWidth: CGFloat) -> Bool {
        windowWidth >= expandedMinWindowWidth
    }

    /// Never wider than the window itself: a sidebar that has taken the whole screen is still
    /// preferable to one that has pushed the page off the side of it.
    ///
    /// Collapsing is decided **here** rather than by a second layout path in the shell, so the one
    /// guarantee this file exists for — `sidebarWidth + detailWidth == windowWidth` — holds folded
    /// and unfolded alike.
    static func sidebarWidth(windowWidth: CGFloat, isCollapsed: Bool = false) -> CGFloat {
        guard !isCollapsed else { return collapsedWidth }
        let preferred = usesExpandedSidebar(windowWidth: windowWidth) ? expandedWidth : railWidth
        return min(preferred, max(0, windowWidth))
    }

    static func detailWidth(windowWidth: CGFloat, isCollapsed: Bool = false) -> CGFloat {
        max(0, windowWidth - sidebarWidth(windowWidth: windowWidth, isCollapsed: isCollapsed))
    }
}
