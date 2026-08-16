import CoreGraphics

/// How the iPad root shell divides its window between the sidebar column and the detail pane.
///
/// The shell is an `HStack` of a **fixed-width** sidebar and the detail beside it. An `HStack` does
/// not shrink a fixed `.frame(width:)`, and it does not shrink a child below the minimum its own
/// content declares either — it overflows. The detail pane's content routinely declares minimums
/// (`iPadTodayView`'s two panes, `iOSCalendarView`'s inspector, and — until it was deleted — the
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
enum CadenceRootShellLayout {
    /// The icon-only column, used where a labelled one would not leave the detail enough room —
    /// iPad mini portrait, Slide Over, and narrow Split View.
    static let railWidth: CGFloat = 58
    /// The labelled column.
    static let expandedWidth: CGFloat = 188
    /// Full window width (not the column's own). iPad portrait widths run from ~744pt (mini) to
    /// ~1032pt (13"); landscape is comfortably wider on every model. 820pt activates the labelled
    /// column for portrait on 10.9"+ iPads and for both orientations on 11"/13" iPads.
    static let expandedMinWindowWidth: CGFloat = 820

    static func usesExpandedSidebar(windowWidth: CGFloat) -> Bool {
        windowWidth >= expandedMinWindowWidth
    }

    /// Never wider than the window itself: a sidebar that has taken the whole screen is still
    /// preferable to one that has pushed the page off the side of it.
    static func sidebarWidth(windowWidth: CGFloat) -> CGFloat {
        let preferred = usesExpandedSidebar(windowWidth: windowWidth) ? expandedWidth : railWidth
        return min(preferred, max(0, windowWidth))
    }

    static func detailWidth(windowWidth: CGFloat) -> CGFloat {
        max(0, windowWidth - sidebarWidth(windowWidth: windowWidth))
    }
}
