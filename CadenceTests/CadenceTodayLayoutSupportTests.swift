import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Two panes had no floor at all: `layout(...)` gated only the (since deleted) three-pane case and
/// returned `.twoPane` for every regular-width device, however little room there was.
@MainActor
struct CadenceTodayTwoPaneFloorTests {
    /// A pane is the window less the shell sidebar — 188pt (`iOSSidebarMetrics.expandedWidth`) when
    /// it is out, **0 when the user folds it**, which hands the detail the whole window. Spelled
    /// out here rather than imported because the sidebar metrics live under `Cadence/iOS/`, inside
    /// `#if os(iOS)`.
    ///
    /// The target iPad is an 11" Pro: 834pt of window in portrait, 1210 in landscape. So the four
    /// panes Today is actually handed on it are **646 / 1022** with the sidebar out and
    /// **834 / 1210** with it folded. Every width below is one of those four, or a boundary of the
    /// function itself.
    private static let sidebarWidth: CGFloat = 188
    private static func pane(window: CGFloat) -> CGFloat { window - sidebarWidth }

    private func layout(paneWidth: CGFloat) -> CadenceTodayLayout {
        CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: paneWidth)
    }

    @Test func compactWidthAlwaysWinsRegardlessOfSpace() {
        // The iPhone's own width, and then a width no device produces, to say that the guard is on
        // the size class and not on how much room happens to be behind it.
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: false, paneWidth: 393) == .compact)
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: false, paneWidth: 4_000) == .compact)
    }

    @Test
    func anElevenInchIPadInPortraitGetsOneColumnRatherThanTwoStarvedOnes() {
        // 834pt window − 188pt sidebar. Two panes here meant a 325pt task column, too narrow for
        // its own header: the date wrapped to "SUND AY, …".
        #expect(layout(paneWidth: Self.pane(window: 834)) == .compact)
    }

    @Test
    func theSameIPadInPortraitWithTheSidebarFoldedGetsTwoPanes() {
        // Folding the sidebar gives Today the whole 834pt window, past the 761 floor — so the one
        // device swaps layouts on a control the user drives, which is why the floor has to be
        // derived rather than assumed from hardware.
        #expect(layout(paneWidth: 834) == .twoPane)
    }

    @Test
    func theFloorIsDerivedFromThePanesRatherThanPicked() {
        // Not a device width: the boundary itself, which no iPad lands on and every iPad crosses.
        #expect(CadenceTodayLayoutSupport.twoPaneMinimumWidth == 761)
        #expect(layout(paneWidth: 761) == .twoPane)
        #expect(layout(paneWidth: 760) == .compact)
    }

    @Test
    func everyIPadLandscapeTargetGetsTwoPanes() {
        // The 11" Pro in landscape, sidebar out and folded — the two widest shapes the app is built
        // for. These used to be the widths that unlocked a third column.
        #expect(layout(paneWidth: Self.pane(window: 1_210)) == .twoPane)
        #expect(layout(paneWidth: 1_210) == .twoPane)
    }
}

/// The layout picker's removal, pinned.
///
/// `ios.today.layoutMode` — a `UserDefaults` key, never a SwiftData property — could hold `mac`,
/// naming a three-column layout that no longer exists. That value cannot strand anyone, because
/// there is no longer any input to `layout(...)` other than width: a stored preference has no path
/// into the decision at all. These tests are the guard on that, and on the range of the function
/// being exactly two cases.
@MainActor
struct CadenceTodayLayoutModeRemovalTests {
    @Test func noWidthOnAnyDeviceCanProduceAThirdLayout() {
        for paneWidth in stride(from: CGFloat(0), through: 4_000, by: 17) {
            for isRegularWidth in [true, false] {
                let layout = CadenceTodayLayoutSupport.layout(
                    isRegularWidth: isRegularWidth,
                    paneWidth: paneWidth
                )
                #expect(layout == .compact || layout == .twoPane)
            }
        }
    }

    @Test func aWidthWideEnoughForThreeColumnsStillLandsOnTwoPanes() {
        // 1022pt was `threePaneMinimumWidth`, and an 11" Pro in landscape with the sidebar out
        // measures 1022pt of pane exactly — so the deleted layout was reachable on the target
        // device, not theoretical. 1210 is the same iPad with the sidebar folded: the widest pane
        // anything produces, and it resolves to the same two panes.
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 1_022) == .twoPane)
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 1_210) == .twoPane)
    }

    @Test func theTwoPaneFloorStillLeavesBothPanesTheirDeclaredMinimums() {
        #expect(
            CadenceTodayLayoutSupport.twoPaneMinimumWidth ==
            CadenceTodayLayoutSupport.taskPaneMinWidth +
            CadenceTodayLayoutSupport.inspectorPaneMinWidth +
            CadenceTodayLayoutSupport.paneDividerWidth
        )
    }
}
