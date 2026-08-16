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

    /// Generalising the gate must not move it for the surface that was not asking a new question.
    /// Month still splits at 681.
    @Test
    func aCalendarThatStatesNoMinimumSplitsExactlyWhereItAlwaysDid() {
        for paneWidth in stride(from: CGFloat(300), through: 2000, by: 1) {
            #expect(
                CadenceCalendarPaneLayout.showsInspector(paneWidth: paneWidth)
                    == (paneWidth >= CadenceCalendarPaneLayout.splitMinimumWidth),
                "gate moved at pane \(paneWidth)"
            )
        }
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

/// Which Calendar presentations draw the day inspector at all.
///
/// The Board used to, and it was the one surface that could least afford it: horizontally scrolling
/// day columns, each headed with its own date and each listing that day's items, with a 340pt column
/// beside them repeating one of those days. On an 11" Pro in landscape that is a column and a half
/// of the days the board exists to show, spent restating one of the days still on screen.
struct CadenceCalendarDayInspectorGateTests {
    /// Every pane the target iPad reaches, in both orientations, and then some.
    private static let paneWidths: [CGFloat] = [0, 646, 681, 844, 1022, 1188, 1183, 1523, 2000]

    @Test
    func theBoardNeverSplits() {
        for paneWidth in Self.paneWidths {
            for viewMode in CadenceCalendarViewMode.allCases {
                #expect(
                    !CadenceCalendarPaneLayout.showsDayInspector(
                        isCompact: false,
                        presentation: .board,
                        viewMode: viewMode,
                        paneWidth: paneWidth
                    ),
                    "board split at pane \(paneWidth) in \(viewMode)"
                )
            }
        }
    }

    /// Month has two readings and two placements of its own; routing it through the pane-wide gate
    /// would be a third answer to a question `CadenceCalendarMonthLayout` already owns.
    @Test
    func monthIsAnsweredByItsOwnLayoutRatherThanThisGate() {
        for paneWidth in Self.paneWidths {
            #expect(
                !CadenceCalendarPaneLayout.showsDayInspector(
                    isCompact: false,
                    presentation: .timeline,
                    viewMode: .month,
                    paneWidth: paneWidth
                )
            )
        }
    }

    /// Week keeps the gate it was given in `545f429` — it may only split once seven full-size
    /// columns are already paid for — which no orientation of the target iPad reaches.
    @Test
    func weekSplitsOnlyBeyondEveryPaneTheTargetIPadReaches() {
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 646))
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1022))
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1182))
        #expect(CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1183))
    }

    /// A phone has one column and no room for a second.
    @Test
    func aCompactPaneNeverSplitsWhateverItMeasures() {
        for paneWidth in Self.paneWidths {
            for presentation in [CadenceCalendarPresentation.timeline, .board] {
                #expect(
                    !CadenceCalendarPaneLayout.showsDayInspector(
                        isCompact: true,
                        presentation: presentation,
                        viewMode: .week,
                        paneWidth: paneWidth
                    )
                )
            }
        }
    }

    /// The claim is per mode, and only Week states one of its own.
    @Test
    func onlyWeekClaimsWidthBeforeTheInspectorMayHaveAny() {
        #expect(
            CadenceCalendarPaneLayout.calendarMinimumWidth(for: .week)
                == CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)
        )
        #expect(CadenceCalendarPaneLayout.calendarMinimumWidth(for: .month) == CadenceCalendarPaneLayout.inspectorMinWidth)
        #expect(CadenceCalendarPaneLayout.calendarMinimumWidth(for: .twoWeeks) == CadenceCalendarPaneLayout.inspectorMinWidth)
    }
}

/// Week has to show a week.
///
/// Every one of these runs the *whole* chain a pane goes through — does the inspector fit, what is
/// left for the grid, what is left for the columns — rather than any one number in it, because the
/// bug was never in a single value. `showsInspector` was right about the inspector, `dayColumnWidth`
/// was right about a column, and between them seven columns did not fit.
struct CadenceCalendarWeekGridLayoutTests {
    /// Window width less the 188pt shell sidebar. 632 and 1022 are an 11" iPad Pro (820 and 1210 of
    /// window), 646 the 11" Pro M4 in portrait (834), 844 and 1188 a 13" (1032 and 1376).
    private static let realPaneWidths: [CGFloat] = [632, 646, 844, 1022, 1188]

    /// What Week claims before an inspector may take anything: seven full-size columns and the rail.
    private static let claim = CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)

    /// The grid width Week is actually handed at a given pane width.
    private func gridWidth(paneWidth: CGFloat) -> CGFloat {
        guard CadenceCalendarPaneLayout.showsInspector(paneWidth: paneWidth, calendarMinimumWidth: Self.claim) else {
            return paneWidth
        }
        return CadenceCalendarPaneLayout.calendarWidth(forPaneWidth: paneWidth, calendarMinimumWidth: Self.claim)
    }

    private func dayColumnWidth(paneWidth: CGFloat) -> CGFloat {
        let available = gridWidth(paneWidth: paneWidth)
            - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: true)
        return CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: available,
            dayCount: CadenceCalendarWeekGridLayout.daysInWeek,
            isRegularWidth: true
        )
    }

    /// The property that matters. Not "the columns are wide enough" and not "the threshold is N" —
    /// seven columns and the hour rail fit inside the grid, at every pane an iPad can produce.
    @Test
    func sevenDaysFitAtEveryRealPaneWidth() {
        for paneWidth in Self.realPaneWidths {
            let content = CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: true)
                + dayColumnWidth(paneWidth: paneWidth) * CGFloat(CadenceCalendarWeekGridLayout.daysInWeek)
            let grid = gridWidth(paneWidth: paneWidth)
            #expect(
                content <= grid + 0.5,
                "week needed \(content) of \(grid) at pane \(paneWidth) — the seventh day is behind a scroller"
            )
        }
    }

    /// And they stay tappable while doing it, so "it fits" is not bought by shaving the columns to
    /// nothing. The binding case is the narrowest pane, 632pt of 11" portrait, at 82pt a column.
    @Test
    func everyColumnStaysALegalTouchTargetAtEveryRealPaneWidth() {
        for paneWidth in Self.realPaneWidths {
            #expect(
                dayColumnWidth(paneWidth: paneWidth) >= CadenceCalendarWeekGridLayout.minimumDayColumnWidth,
                "column \(dayColumnWidth(paneWidth: paneWidth)) at pane \(paneWidth)"
            )
        }
    }

    /// The stronger claim the split gate buys: not merely seven columns, but seven columns wide
    /// enough for a block to say something. Compression exists for panes that are small, not to pay
    /// for an inspector — 844pt divided seven ways after the inspector's 340 is 63.6, which clears
    /// the touch floor and still renders every block as `[S…` over `3…`.
    @Test
    func noRealPaneEverBuysAnInspectorWithColumnWidth() {
        for paneWidth in Self.realPaneWidths where paneWidth >= Self.claim {
            #expect(
                dayColumnWidth(paneWidth: paneWidth)
                    >= CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true),
                "column \(dayColumnWidth(paneWidth: paneWidth)) at pane \(paneWidth)"
            )
        }
    }

    @Test
    func onlyAPaneThatCanPayForBothGetsAnInspector() {
        #expect(Self.claim == 842)
        // 842 + 340 + 1. Below this the grid takes the pane, exactly as it does on a phone.
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 1183, calendarMinimumWidth: Self.claim))
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 1182, calendarMinimumWidth: Self.claim))
        // The two target iPad panes are both below it, so Week fills them.
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 646, calendarMinimumWidth: Self.claim))
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 1022, calendarMinimumWidth: Self.claim))
        // A 13" in landscape can pay for both, and the inspector takes the remainder rather than
        // its 30% — 356.4 would have left the grid 831 and put it back under its own claim.
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 1188, calendarMinimumWidth: Self.claim))
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 1188, calendarMinimumWidth: Self.claim) == 345)
        #expect(gridWidth(paneWidth: 1188) == Self.claim)
    }

    /// A week fills the pane it is given rather than stopping at 112 and leaving a gutter — which is
    /// what `max(available / 7, 112)` did right and must keep doing.
    @Test
    func aWideGridSpendsItsWholeWidthOnTheWeek() {
        let available: CGFloat = 964 // an 11" Pro in landscape with the pane to itself, less the rail
        let column = CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: available,
            dayCount: 7,
            isRegularWidth: true
        )
        #expect(column == available / 7)
        #expect(column > CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true))
    }

    /// A phone cannot hold seven legible columns at any zoom — 393pt leaves 49 a column — so it
    /// keeps the preferred width and scrolls, which is what it already did.
    @Test
    func aPhoneStillScrollsItsWeekRatherThanShavingItToNothing() {
        let rail = CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: false)
        let column = CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: 393 - rail,
            dayCount: 7,
            isRegularWidth: false
        )
        #expect(column == CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: false))
    }

    /// Fourteen columns are a fortnight or a legible day, never both. `.twoWeeks` is off the picker
    /// and only reachable from an older persisted value, but the width it used must not change.
    @Test
    func aFortnightKeepsItsFixedColumnAndItsScroller() {
        for isRegularWidth in [true, false] {
            #expect(
                CadenceCalendarWeekGridLayout.dayColumnWidth(
                    availableWidth: 1188,
                    dayCount: 14,
                    isRegularWidth: isRegularWidth
                ) == CadenceCalendarWeekGridLayout.multiWeekDayColumnWidth
            )
        }
    }

    @Test
    func aZeroWidthGridDoesNotProduceAZeroWidthColumn() {
        #expect(
            CadenceCalendarWeekGridLayout.dayColumnWidth(availableWidth: 0, dayCount: 7, isRegularWidth: true)
                == CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true)
        )
        #expect(
            CadenceCalendarWeekGridLayout.dayColumnWidth(availableWidth: 800, dayCount: 0, isRegularWidth: true)
                == CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true)
        )
    }
}
