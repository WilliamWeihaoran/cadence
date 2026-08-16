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
}
