import Testing
import CoreGraphics
import Foundation
@testable import Cadence

/// The iPad shell's own split, at the window widths the app actually runs at.
///
/// Full screen the target iPad is 834 (portrait) and 1210 (landscape). The rest are multitasking:
/// 585 is a half Split View in landscape, 782 and 795 are the 2/3 pane on the two generations that
/// produce one. 865 is the docked threshold; narrower regular-width windows use a drawer.
/// Compact width still runs the tab shell and its split is not decided by this helper; only its
/// window-controls reserve is (T-6711).
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

    // MARK: - Window controls (T-6700)

    /// A stand-in for the iPadOS 26 window-controls region. The rule is a relation to whatever
    /// the system reports, so no test here pins the system's own figure.
    private static let controls = CGSize(width: 80, height: 30)

    /// What the shell asks for the detail: the reserve at the docked reservation's trailing edge.
    private static func detailReserve(_ width: CGFloat, folded: Bool, corner: CGSize) -> CGFloat {
        CadenceRootShellLayout.topReserve(
            paneLeadingX: CadenceRootShellLayout.sidebarWidth(windowWidth: width, isCollapsed: folded),
            topLeadingCorner: corner)
    }

    /// The defect: in a window narrow enough for the drawer, or with the sidebar folded, the page
    /// starts at the window's leading edge, so its header sat under the controls.
    @Test
    func aPageAtTheLeadingEdgeDropsBelowTheWindowControls() {
        for width in Self.windowWidths {
            for folded in [false, true] where CadenceRootShellLayout.sidebarWidth(
                windowWidth: width, isCollapsed: folded) == 0 {
                #expect(Self.detailReserve(width, folded: folded, corner: Self.controls)
                        == Self.controls.height, "width \(width) folded \(folded)")
            }
        }
    }

    /// The sidebar is always the leading pane while it is shown, so it owns the corner instead.
    @Test
    func theSidebarDropsBelowTheWindowControls() {
        #expect(CadenceRootShellLayout.sidebarTopReserve(topLeadingCorner: Self.controls)
                == Self.controls.height)
    }

    /// Beside a docked sidebar the page starts clear of the controls and must not lose height.
    @Test
    func aPageBesideTheDockedSidebarKeepsItsTop() {
        for width in Self.windowWidths where CadenceRootShellLayout.usesExpandedSidebar(windowWidth: width) {
            #expect(CadenceRootShellLayout.sidebarWidth(windowWidth: width) > Self.controls.width)
            #expect(Self.detailReserve(width, folded: false, corner: Self.controls) == 0)
        }
    }

    /// Full screen the system reports no corner, and nothing moves.
    @Test
    func fullScreenReservesNothing() {
        for width in Self.windowWidths {
            for folded in [false, true] {
                #expect(Self.detailReserve(width, folded: folded, corner: .zero) == 0)
            }
        }
        #expect(CadenceRootShellLayout.sidebarTopReserve(topLeadingCorner: .zero) == 0)
    }

    /// The shell must actually read the system's region and apply both reserves, or the rule
    /// above is a function nothing calls.
    @Test
    func theIPadShellAppliesTheReserveFromTheSystemsCornerRegion() throws {
        let code = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootSidebar.swift"))
        let root = try cadenceFunctionBody("struct iPadMacStyleRootShell<Content: View>: View", in: code)
        #expect(root.contains("let topLeadingCorner = proxy.containerCornerInsets.topLeading"))
        #expect(root.contains("CadenceRootShellLayout.sidebarTopReserve(topLeadingCorner: topLeadingCorner)"))
        #expect(root.range(of: #"let detailTopReserve = CadenceRootShellLayout\.topReserve\(\s*paneLeadingX: sidebarWidth,\s*topLeadingCorner: topLeadingCorner\s*\)"#,
                           options: .regularExpression) != nil)
        #expect(root.range(of: #"\.padding\(\.top, sidebarTopReserve\)\s*\.frame\(width: drawerWidth"#,
                           options: .regularExpression) != nil)
        #expect(root.range(of: #"detail\(\)\s*\.padding\(\.top, detailTopReserve\)\s*\.frame\(width: detailWidth"#,
                           options: .regularExpression) != nil)
    }

    // MARK: - Window controls, compact shell (T-6711)

    /// A windowed iPad narrow enough for compact width runs the tab shell, whose page always
    /// starts at the leading edge: it drops by the region's height, like a drawer-mode detail.
    @Test
    func theCompactShellOnAnIPadDropsBelowTheWindowControls() {
        #expect(CadenceRootShellLayout.compactTopReserve(topLeadingCorner: Self.controls, isPad: true)
                == Self.controls.height)
        #expect(CadenceRootShellLayout.compactTopReserve(topLeadingCorner: Self.controls, isPad: true)
                == Self.detailReserve(585, folded: true, corner: Self.controls))
    }

    /// A phone has no window controls; whatever corner it reports is the display's rounding, which
    /// its safe area already clears. Full screen on an iPad reports nothing and nothing moves.
    @Test
    func theCompactShellReservesNothingOnAPhoneOrFullScreen() {
        #expect(CadenceRootShellLayout.compactTopReserve(topLeadingCorner: Self.controls, isPad: false) == 0)
        #expect(CadenceRootShellLayout.compactTopReserve(topLeadingCorner: .zero, isPad: true) == 0)
        #expect(CadenceRootShellLayout.compactTopReserve(topLeadingCorner: .zero, isPad: false) == 0)
    }

    /// The compact shell must read the system's region on an iPad and pad the tab content, which
    /// is what holds every compact page's header, or the rule above is a function nothing calls.
    @Test
    func theCompactShellAppliesTheReserveFromTheSystemsCornerRegion() throws {
        let code = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let shell = try cadenceFunctionBody("struct iOSCompactRootShell: View", in: code)
        #expect(shell.range(of: #"let topReserve = CadenceRootShellLayout\.compactTopReserve\(\s*topLeadingCorner: proxy\.containerCornerInsets\.topLeading,\s*isPad: UIDevice\.current\.userInterfaceIdiom == \.pad\s*\)"#,
                            options: .regularExpression) != nil)
        #expect(shell.range(of: #"stack\(for: tab\)[\s\S]*?\}\s*\}\s*\}\s*\.padding\(\.top, topReserve\)\s*\.frame\(width: proxy\.size\.width"#,
                            options: .regularExpression) != nil)
    }
}
