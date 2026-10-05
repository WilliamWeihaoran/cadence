import CoreGraphics

/// The iPad shell reserves a docked column only when the remaining page can stay usable.
/// In narrower windows navigation is a modal drawer, so the page keeps the whole window.
/// The detail is still hard-sized and clipped: a descendant's preferred minimum may not move
/// the navigation off-screen (T-182). Overlay width is never subtracted from the page.
enum CadenceRootShellLayout {
    static let expandedWidth: CGFloat = 264
    static let collapsedWidth: CGFloat = 0

    /// 264 + 601 = 865 today. Derive the floor from the same Notes minimum the page reads,
    /// rather than keeping two constants that can drift when either column changes.
    static var expandedMinWindowWidth: CGFloat {
        expandedWidth + CadenceNotesListMetrics.twoColumnMinimumWidth
    }

    static func usesExpandedSidebar(windowWidth: CGFloat) -> Bool {
        windowWidth >= expandedMinWindowWidth
    }

    /// Only a docked, unfolded sidebar takes space from the detail pane. The old narrow-window
    /// icon rail is replaced by a labelled drawer, not enlarged beside an already cramped page.
    static func sidebarWidth(windowWidth: CGFloat, isCollapsed: Bool = false) -> CGFloat {
        guard !isCollapsed, usesExpandedSidebar(windowWidth: windowWidth) else {
            return collapsedWidth
        }
        return min(expandedWidth, max(0, windowWidth))
    }

    static func detailWidth(windowWidth: CGFloat, isCollapsed: Bool = false) -> CGFloat {
        max(0, windowWidth - sidebarWidth(windowWidth: windowWidth, isCollapsed: isCollapsed))
    }

    static func drawerWidth(windowWidth: CGFloat) -> CGFloat {
        min(expandedWidth, max(0, windowWidth))
    }
}
