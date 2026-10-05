import Testing
import CoreGraphics
@testable import Cadence

/// The iPad shell's own split, at the window widths the app actually runs at.
///
/// Full screen the target iPad is 834 (portrait) and 1210 (landscape). The rest are multitasking:
/// 585 is a half Split View in landscape, 782 and 795 are the 2/3 pane on the two generations that
/// produce one. 865 is the docked threshold; narrower regular-width windows use a drawer.
/// Compact width still runs the tab shell and is not decided by this helper.
struct CadenceRootShellLayoutTests {
    private static let windowWidths: [CGFloat] = [585, 782, 795, 820, 834, 864, 865, 1210]

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
        #expect(CadenceRootShellLayout.expandedWidth == 264)
        #expect(CadenceRootShellLayout.expandedMinWindowWidth == 865)
        #expect(CadenceRootShellLayout.expandedMinWindowWidth
                == CadenceRootShellLayout.expandedWidth + CadenceNotesListMetrics.twoColumnMinimumWidth)
        #expect(!CadenceRootShellLayout.usesExpandedSidebar(windowWidth: 864))
        #expect(CadenceRootShellLayout.usesExpandedSidebar(windowWidth: 865))
        #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: 865) == CadenceRootShellLayout.expandedWidth)
    }

    /// Portrait, Split View and Stage Manager use the same width rule. The labelled drawer
    /// overlays rather than shrinking the main page; the former 58pt rail is not reserved.
    @Test
    func narrowWindowsKeepTheWholePageBehindTheDrawer() {
        for windowWidth in [CGFloat(585), 782, 795, 834, 864] {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: windowWidth) == 0)
            #expect(CadenceRootShellLayout.detailWidth(windowWidth: windowWidth) == windowWidth)
            #expect(CadenceRootShellLayout.drawerWidth(windowWidth: windowWidth) == 264)
        }
    }

    /// Literal page widths expose the effect of changing either the column or its fit floor.
    @Test
    func theDetailPaneIsTheWindowLessTheLabelledColumn() {
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 820) == 820)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 834) == 834)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 865) == 601)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 1210) == 946)
    }

    @Test
    func theDrawerFitsEvenAnUnmeasuredOrVeryNarrowWindow() {
        #expect(CadenceRootShellLayout.drawerWidth(windowWidth: -1) == 0)
        #expect(CadenceRootShellLayout.drawerWidth(windowWidth: 0) == 0)
        #expect(CadenceRootShellLayout.drawerWidth(windowWidth: 120) == 120)
        #expect(CadenceRootShellLayout.drawerWidth(windowWidth: 264) == 264)
        #expect(CadenceRootShellLayout.drawerWidth(windowWidth: 1210) == 264)
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
    func foldingAppliesAtEveryWidthIncludingDrawerWindows() {
        for width in [CGFloat(782), 834, 865, 1210] {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: true) == 0)
        }
    }

    /// Only the docked column consumes width. Portrait already has the full page behind its drawer.
    @Test
    func foldingReclaimsTheDockedColumnButNeverShrinksPortrait() {
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 834) == 834)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 834, isCollapsed: true) == 834)
        let unfolded = CadenceRootShellLayout.detailWidth(windowWidth: 1210)
        let folded = CadenceRootShellLayout.detailWidth(windowWidth: 1210, isCollapsed: true)
        #expect(unfolded == 946)
        #expect(folded == 1210)
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
