import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Two panes had no floor at all: `layout(...)` gated only the (since deleted) three-pane case and
/// returned `.twoPane` for every regular-width device, however little room there was.
struct CadenceTodayTwoPaneFloorTests {
    /// Window widths in points, less the 188pt shell sidebar (`iOSSidebarMetrics.expandedWidth`),
    /// which is what `iPadTodayView`'s `GeometryReader` actually measures. Spelled out here rather
    /// than imported because the sidebar metrics live under `Cadence/iOS/`, inside `#if os(iOS)`.
    private static let sidebarWidth: CGFloat = 188
    private static func pane(window: CGFloat) -> CGFloat { window - sidebarWidth }

    private func layout(paneWidth: CGFloat) -> CadenceTodayLayout {
        CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: paneWidth)
    }

    @Test func compactWidthAlwaysWinsRegardlessOfSpace() {
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: false, paneWidth: 4_000) == .compact)
    }

    @Test
    func anElevenInchIPadInPortraitGetsOneColumnRatherThanTwoStarvedOnes() {
        // 820pt window − 188pt sidebar. Two panes here meant a 312pt task column, too narrow for
        // its own header: the date wrapped to "SUND AY, …".
        #expect(layout(paneWidth: 632) == .compact)
    }

    @Test
    func aThirteenInchIPadInPortraitStillGetsTwoPanes() {
        // 1032 − 188 = 844, comfortably past the 761 floor.
        #expect(layout(paneWidth: 844) == .twoPane)
    }

    @Test
    func theFloorIsDerivedFromThePanesRatherThanPicked() {
        #expect(CadenceTodayLayoutSupport.twoPaneMinimumWidth == 761)
        #expect(layout(paneWidth: 761) == .twoPane)
        #expect(layout(paneWidth: 760) == .compact)
    }

    @Test
    func everyIPadLandscapeTargetGetsTwoPanes() {
        // 11" and 13" Pro in landscape, the widest shapes the app is built for. These used to be
        // the widths that unlocked a third column.
        #expect(layout(paneWidth: Self.pane(window: 1_210)) == .twoPane)
        #expect(layout(paneWidth: Self.pane(window: 1_376)) == .twoPane)
    }
}

/// The layout picker's removal, pinned.
///
/// `ios.today.layoutMode` — a `UserDefaults` key, never a SwiftData property — could hold `mac`,
/// naming a three-column layout that no longer exists. That value cannot strand anyone, because
/// there is no longer any input to `layout(...)` other than width: a stored preference has no path
/// into the decision at all. These tests are the guard on that, and on the range of the function
/// being exactly two cases.
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
        // 1022pt was `threePaneMinimumWidth`; an 11" Pro in landscape measures 1022pt of pane
        // exactly. Both it and anything wider now resolve to the same two-pane layout as a 13".
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 1_022) == .twoPane)
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 1_188) == .twoPane)
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
