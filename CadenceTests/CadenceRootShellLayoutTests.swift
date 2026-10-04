import Testing
import CoreGraphics
@testable import Cadence

/// The iPad shell's own split, at the window widths the app actually runs at.
///
/// Full screen the target iPad is 834 (portrait) and 1210 (landscape). The rest are multitasking:
/// 585 is a half Split View in landscape, 782 and 795 are the 2/3 pane on the two generations that
/// produce one, and 820 is the threshold itself. This shell never sees an iPhone — that is compact
/// width and runs the tab shell — so no phone width appears here.
struct CadenceRootShellLayoutTests {
    private static let windowWidths: [CGFloat] = [585, 782, 795, 820, 834, 1210]

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
        #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: 834) == CadenceRootShellLayout.expandedWidth)
    }

    /// **Why the rail exists.** Nothing the app runs full screen reaches it: the phone is compact
    /// and runs the tab shell, and the target iPad is 834 in portrait and 1210 in landscape. What
    /// reaches it is a window that is horizontally regular *and* under 820 — a 2/3 Split View on
    /// the 11" Pro in landscape, ~782–795pt depending on generation, and any Stage Manager window
    /// dragged into the band. Delete the rail and 216pt of labelled column comes out of a 780pt
    /// window.
    @Test
    func aSplitViewPaneIsWhatTheRailIsFor() {
        for windowWidth in [CGFloat(585), 782, 795, 819] {
            #expect(
                CadenceRootShellLayout.sidebarWidth(windowWidth: windowWidth)
                    == CadenceRootShellLayout.railWidth,
                "window \(windowWidth) did not get the rail"
            )
            #expect(CadenceRootShellLayout.detailWidth(windowWidth: windowWidth) == windowWidth - 58)
        }
    }

    /// The widths the clipping was reported at, spelled out rather than derived: the target iPad
    /// gives the detail **618pt** in portrait and **994** in landscape, and no pane it hosts may
    /// exceed that. 820 is the threshold, where the column first becomes the labelled one.
    ///
    /// **These were 646 and 1022 until T-2054 widened the column to 216.** They are spelled rather
    /// than computed on purpose — a literal is what makes a column change show up as a *pane*
    /// change, which is the ripple worth seeing. Both readings still sit on the same side of every
    /// floor they face: 618 was already under `CadenceTodayLayoutSupport.twoPaneMinimumWidth`
    /// (761) at 646, and 994 is still over `inspectorWidePaneThreshold` (900).
    @Test
    func theDetailPaneIsTheWindowLessTheLabelledColumn() {
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 820) == 604)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 834) == 618)
        #expect(CadenceRootShellLayout.detailWidth(windowWidth: 1210) == 994)
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
        for width in [CGFloat(782), 819, 820, 1210] {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: true) == 0)
        }
    }

    /// The 216pt the target iPad reclaims in portrait, spelled out: 618pt of detail becomes 834.
    ///
    /// This is not only a nicety — it is the case that puts a full-screen portrait iPad *over*
    /// `CadenceTodayLayoutSupport.twoPaneMinimumWidth` (761), which 618 is under. Today's two-pane
    /// layout and its narrow inspector floor are reachable because of this fold, and widening the
    /// column to 216 (T-2054) made that more true rather than less.
    @Test
    func foldingHandsTheElevenInchPortraitPaneTheColumnsWidthBack() {
        let unfolded = CadenceRootShellLayout.detailWidth(windowWidth: 834)
        let folded = CadenceRootShellLayout.detailWidth(windowWidth: 834, isCollapsed: true)

        #expect(unfolded == 618)
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
