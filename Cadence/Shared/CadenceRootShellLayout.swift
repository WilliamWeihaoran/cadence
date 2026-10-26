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

    // MARK: - Window controls (T-6700)

    /// How far a pane must drop its content so the iPadOS 26 window controls do not cover it.
    ///
    /// A windowed iPad app gets red/yellow/green controls drawn over its top-leading corner, and
    /// the shell ignores the container safe area, so every page header used to sit under them.
    /// The system reports that region as `GeometryProxy.containerCornerInsets.topLeading` (zero
    /// full screen). A pane whose leading edge starts inside the region's width drops by its
    /// height; a pane that starts clear of it — the detail beside a docked sidebar — keeps its
    /// top. One rule at the shell rather than padding on each screen: every page is drawn by
    /// this shell, and the corner belongs to whichever pane is at the window's leading edge.
    static func topReserve(paneLeadingX: CGFloat, topLeadingCorner: CGSize) -> CGFloat {
        guard topLeadingCorner.width > 0, topLeadingCorner.height > 0,
              paneLeadingX < topLeadingCorner.width
        else { return 0 }
        return topLeadingCorner.height
    }

    /// The sidebar is drawn at the leading edge whenever it is visible, docked or as a drawer.
    static func sidebarTopReserve(topLeadingCorner: CGSize) -> CGFloat {
        topReserve(paneLeadingX: 0, topLeadingCorner: topLeadingCorner)
    }

    /// The detail starts after the docked reservation, which is zero in drawer mode and folded.
    static func detailTopReserve(
        windowWidth: CGFloat,
        isCollapsed: Bool = false,
        topLeadingCorner: CGSize
    ) -> CGFloat {
        topReserve(
            paneLeadingX: sidebarWidth(windowWidth: windowWidth, isCollapsed: isCollapsed),
            topLeadingCorner: topLeadingCorner
        )
    }
}
