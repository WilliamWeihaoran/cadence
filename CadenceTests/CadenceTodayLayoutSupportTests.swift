import CoreGraphics
import Foundation
import Testing
@testable import Cadence

struct CadenceTodayLayoutSupportTests {
    /// Window widths in points, less the 188pt shell sidebar (`iOSSidebarMetrics.expandedWidth`),
    /// which is what `iPadTodayView`'s `GeometryReader` actually measures. Spelled out here rather
    /// than imported because the sidebar metrics live under `Cadence/iOS/`, inside `#if os(iOS)`.
    private static let sidebarWidth: CGFloat = 188
    private static func pane(window: CGFloat) -> CGFloat { window - sidebarWidth }

    @Test func threePaneFloorIsTheWidthAtWhichTheThreeColumnsFirstFit() {
        // Derived, not chosen: notes floor + task floor + schedule floor + two dividers.
        #expect(CadenceTodayLayoutSupport.threePaneMinimumWidth == 1_022)
        #expect(CadenceTodayLayoutSupport.supportsThreePane(paneWidth: 1_022))
        #expect(!CadenceTodayLayoutSupport.supportsThreePane(paneWidth: 1_021))
    }

    @Test func theOldThresholdWasUnreachableOnEveryIPadAndTheNewOneIsNot() {
        // The regression this replaced: `width >= 1_500`. The widest iPad ever shipped is the 13"
        // Pro at 1376pt of *window*, so no device could satisfy it even before the sidebar was
        // subtracted — `iPadTodayLayoutMode.mac` was selectable in two places and inert everywhere.
        let widestPane = Self.pane(window: 1_376)
        #expect(widestPane < 1_500)
        #expect(CadenceTodayLayoutSupport.supportsThreePane(paneWidth: widestPane))

        // 11" and 13" iPad Pro landscape reach the new floor; 12.9" Pro does too.
        #expect(CadenceTodayLayoutSupport.supportsThreePane(paneWidth: Self.pane(window: 1_366)))
        #expect(CadenceTodayLayoutSupport.supportsThreePane(paneWidth: Self.pane(window: 1_210)))

        // Narrower hardware and every portrait orientation genuinely cannot fit three columns, so
        // the picker disables Mac there rather than accepting a tap that changes nothing.
        #expect(!CadenceTodayLayoutSupport.supportsThreePane(paneWidth: Self.pane(window: 1_180)))
        #expect(!CadenceTodayLayoutSupport.supportsThreePane(paneWidth: Self.pane(window: 1_133)))
        #expect(!CadenceTodayLayoutSupport.supportsThreePane(paneWidth: Self.pane(window: 1_032)))
    }

    @Test func compactWidthAlwaysWinsRegardlessOfPreferenceOrSpace() {
        #expect(CadenceTodayLayoutSupport.layout(
            prefersThreePane: true,
            isRegularWidth: false,
            paneWidth: 4_000
        ) == .compact)
    }

    @Test func aStoredMacPreferenceFallsBackToTwoPanesWithoutBeingDiscarded() {
        // The preference outlives the width: rotate a 13" Pro to portrait and Today drops to two
        // panes; rotate back and the same stored value produces three again. Nothing rewrites
        // `ios.today.layoutMode`, so no migration is needed and no device is ever left pointing at
        // a mode that does not exist.
        let portrait = Self.pane(window: 1_032)
        let landscape = Self.pane(window: 1_376)

        #expect(CadenceTodayLayoutSupport.layout(
            prefersThreePane: true,
            isRegularWidth: true,
            paneWidth: portrait
        ) == .twoPane)

        #expect(CadenceTodayLayoutSupport.layout(
            prefersThreePane: true,
            isRegularWidth: true,
            paneWidth: landscape
        ) == .threePane)
    }

    @Test func focusPreferenceStaysTwoPaneEvenWhenThereIsRoomForThree() {
        #expect(CadenceTodayLayoutSupport.layout(
            prefersThreePane: false,
            isRegularWidth: true,
            paneWidth: 4_000
        ) == .twoPane)
    }
}

/// Two panes had no floor at all: `layout(...)` gated only the three-pane case and returned
/// `.twoPane` for every regular-width device, however little room there was.
struct CadenceTodayTwoPaneFloorTests {
    private func layout(paneWidth: CGFloat, prefersThreePane: Bool = false) -> CadenceTodayLayout {
        CadenceTodayLayoutSupport.layout(
            prefersThreePane: prefersThreePane,
            isRegularWidth: true,
            paneWidth: paneWidth
        )
    }

    @Test
    func anElevenInchIPadInPortraitGetsOneColumnRatherThanTwoStarvedOnes() {
        // 820pt window − 188pt sidebar. Two panes here meant a 312pt task column, too narrow for
        // its own header: the date wrapped to "SUND AY, …" and the layout picker read "Fo…".
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
    func theTwoPaneFloorNeverExceedsTheThreePaneFloor() {
        // A width that fits three panes must necessarily fit two.
        #expect(CadenceTodayLayoutSupport.twoPaneMinimumWidth <= CadenceTodayLayoutSupport.threePaneMinimumWidth)
        #expect(layout(paneWidth: 1_188, prefersThreePane: true) == .threePane)
        #expect(layout(paneWidth: 1_188, prefersThreePane: false) == .twoPane)
    }

    @Test
    func aStoredThreePanePreferenceStillFallsBackSensiblyOnANarrowDevice() {
        // The preference is never discarded, but it cannot conjure space: a narrow pane that
        // prefers three should land on one column, not on a two-pane layout it also cannot fit.
        #expect(layout(paneWidth: 632, prefersThreePane: true) == .compact)
    }
}
