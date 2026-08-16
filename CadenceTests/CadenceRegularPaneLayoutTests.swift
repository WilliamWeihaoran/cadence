import Testing
import CoreGraphics
@testable import Cadence

/// Pane widths are the window width less the 188pt shell sidebar:
/// 820 − 188 = 632 (11" portrait), 1032 − 188 = 844 (13" portrait),
/// 1210 − 188 = 1022 (11" landscape), 1376 − 188 = 1188 (13" landscape).
struct CadenceRegularSplitLayoutTests {
    private func listPane(_ paneWidth: CGFloat) -> CGFloat {
        CadenceRegularSplitLayout.listPaneWidth(forPaneWidth: paneWidth)
    }

    @Test
    func theChooserIsNeverWiderThanTheDetailBesideIt() {
        for paneWidth in [CGFloat(632), 844, 1022, 1188] {
            let list = listPane(paneWidth)
            let detail = paneWidth - CadenceRegularSplitLayout.paneDividerWidth - list
            #expect(list <= detail, "chooser \(list) beat detail \(detail) at pane \(paneWidth)")
        }
    }

    @Test
    func aThirteenInchPortraitPaneStopsSplittingItselfInHalf() {
        // The bug: `iOSFeatureListPane` declared a minimum and an ideal but no maximum, so an
        // `HStack` gave the Goals chooser 422 of 844 to draw one-line rows.
        #expect(listPane(844) == 844 * CadenceRegularSplitLayout.listPaneFraction)
        #expect(listPane(844) < 422)
    }

    @Test
    func theChooserNeverExceedsItsMaximumHoweverWideThePaneGets() {
        #expect(listPane(1188) == CadenceRegularSplitLayout.listPaneMaxWidth)
        #expect(listPane(4000) == CadenceRegularSplitLayout.listPaneMaxWidth)
    }

    @Test
    func anElevenInchPortraitPaneGivesTheMajorityToTheDetail() {
        // 632 * 0.38 = 240, raised to the 300 floor, which is still under half of 632.
        #expect(listPane(632) == CadenceRegularSplitLayout.listPaneMinWidth)
        #expect(632 - 1 - listPane(632) > listPane(632))
    }

    @Test
    func theFloorIsAPreferenceRatherThanAGuarantee() {
        // A pane narrower than twice the floor must not hand the floor's width to the chooser and
        // let the detail overflow — the shape of the bug that split 632 into 312 and 320.
        #expect(listPane(400) < CadenceRegularSplitLayout.listPaneMinWidth)
        // Half of 400 less the divider. Spelled out rather than recomputed: `(400 - 1) / 2` in an
        // expectation is integer arithmetic and reads as 199.
        #expect(listPane(400) == 199.5)
    }

    @Test
    func aZeroWidthPaneDoesNotProduceANegativeChooser() {
        #expect(listPane(0) == CadenceRegularSplitLayout.listPaneMinWidth)
    }
}

struct CadenceCalendarPaneLayoutTests {
    @Test
    func theSplitFloorIsDerivedFromTheInspectorRatherThanPicked() {
        #expect(CadenceCalendarPaneLayout.splitMinimumWidth == 681)
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 681))
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 680))
    }

    @Test
    func anElevenInchPortraitPaneGivesTheWholeThingToTheCalendar() {
        // 632pt: the old `min(max(width * 0.30, 340), 430)` returned 340 — 54% of the pane — and
        // left the week grid running seven 112pt columns behind a scroller showing two of them.
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 632))
    }

    @Test
    func aThirteenInchPortraitPaneKeepsExactlyTheInspectorItAlreadyHad() {
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 844))
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 844) == 340)
    }

    @Test
    func theInspectorIsNeverWiderThanTheCalendarBesideIt() {
        for paneWidth in [CGFloat(681), 844, 1022, 1188] {
            let inspector = CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: paneWidth)
            let calendar = paneWidth - CadenceCalendarPaneLayout.paneDividerWidth - inspector
            #expect(inspector <= calendar, "inspector \(inspector) beat calendar \(calendar) at pane \(paneWidth)")
        }
    }

    /// The 430pt cap is not reachable on any iPad — it needs 1433pt of pane and the widest is a 13"
    /// Pro in landscape at 1188. It still has to hold, because the fraction is what grows.
    @Test
    func theInspectorHasACeilingEvenThoughNoIPadReachesIt() {
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 1188) == 1188 * CadenceCalendarPaneLayout.inspectorFraction)
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 2000) == CadenceCalendarPaneLayout.inspectorMaxWidth)
    }
}
