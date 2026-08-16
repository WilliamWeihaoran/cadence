import Testing
import CoreGraphics
@testable import Cadence

/// The iPad shell's own split. Window widths: 744 (mini portrait), 820 (11" Air portrait),
/// 834 (11" Pro portrait), 1032 (13" portrait), 1210/1376 (landscape).
struct CadenceRootShellLayoutTests {
    private static let windowWidths: [CGFloat] = [744, 820, 834, 1024, 1032, 1180, 1210, 1376]

    /// The regression this file exists for. The shell used to hand the detail pane
    /// `maxWidth: .infinity` and let its content's own minimums decide the row's width; a detail
    /// wider than `window - sidebar` pushed the sidebar off the leading edge of the screen, which
    /// is what rendered "WORKSPACE" as "KSPACE".
    @Test
    func theTwoColumnsAlwaysAddUpToExactlyTheWindow() {
        for width in Self.windowWidths {
            let sidebar = CadenceRootShellLayout.sidebarWidth(windowWidth: width)
            let detail = CadenceRootShellLayout.detailWidth(windowWidth: width)
            #expect(sidebar + detail == width, "\(sidebar) + \(detail) != \(width)")
        }
    }

    @Test
    func theDetailPaneIsNeverNegativeHoweverNarrowTheWindowGets() {
        for width in [CGFloat(0), 40, 58, 120, 187, 188] {
            #expect(CadenceRootShellLayout.detailWidth(windowWidth: width) >= 0)
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width) <= max(0, width))
        }
    }

    @Test
    func theLabelledColumnStartsAtTheDocumentedThreshold() {
        #expect(!CadenceRootShellLayout.usesExpandedSidebar(windowWidth: 819))
        #expect(CadenceRootShellLayout.usesExpandedSidebar(windowWidth: 820))
        #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: 744) == CadenceRootShellLayout.railWidth)
        #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: 834) == CadenceRootShellLayout.expandedWidth)
    }

    /// The two portrait widths the clipping was reported at, spelled out rather than derived: an
    /// 11" iPad gives the detail 632 or 646pt, and no pane it hosts may exceed that.
    @Test
    func anElevenInchPortraitDetailPaneIsTheWindowLessTheLabelledColumn() {
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 820) == 632)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 834) == 646)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 1032) == 844)
    }

    // MARK: - Folding

    /// The guarantee this file exists for has to survive the fold, or a folded sidebar becomes a
    /// second layout path and the overflow that pushed the column off-screen has a second way back.
    @Test
    func theTwoColumnsStillAddUpToTheWindowWhenTheSidebarIsFolded() {
        for width in Self.windowWidths {
            let sidebar = CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: true)
            let detail = CadenceRootShellLayout.detailWidth(windowWidth: width, isCollapsed: true)
            #expect(sidebar + detail == width, "\(sidebar) + \(detail) != \(width)")
        }
    }

    /// Zero, not a stub. A residual strip would spend part of what the fold is for — the whole
    /// point is that the detail pane gets the window.
    @Test
    func aFoldedSidebarTakesNoWidthAtAllAndTheDetailTakesTheWholeWindow() {
        #expect(CadenceRootShellLayout.collapsedWidth == 0)

        for width in Self.windowWidths {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: true) == 0)
            #expect(CadenceRootShellLayout.detailWidth(windowWidth: width, isCollapsed: true) == width)
        }
    }

    /// Folding is decided by the flag alone. It must not depend on the width threshold, or the
    /// column would quietly unfold when the user rotated the iPad.
    @Test
    func foldingAppliesAtEveryWidthIncludingTheRail() {
        for width in [CGFloat(744), 819, 820, 1180] {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: true) == 0)
        }
    }

    /// The 188pt the 11" Pro reclaims in portrait, spelled out: 646pt of detail becomes 834.
    @Test
    func foldingHandsTheElevenInchPortraitPaneTheColumnsWidthBack() {
        let unfolded = CadenceRootShellLayout.detailWidth(windowWidth: 834)
        let folded = CadenceRootShellLayout.detailWidth(windowWidth: 834, isCollapsed: true)

        #expect(unfolded == 646)
        #expect(folded == 834)
        #expect(folded - unfolded == CadenceRootShellLayout.expandedWidth)
    }

    /// Unfolded is the default everywhere, so no existing caller changes behaviour by omitting it.
    @Test
    func theDefaultIsUnfolded() {
        for width in Self.windowWidths {
            #expect(
                CadenceRootShellLayout.sidebarWidth(windowWidth: width)
                    == CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: false)
            )
        }
    }
}
