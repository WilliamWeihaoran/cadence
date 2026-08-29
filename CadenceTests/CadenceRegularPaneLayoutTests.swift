import Testing
import CoreGraphics
import Foundation
@testable import Cadence

/// A pane is the window less the shell sidebar — 188pt when it is out, 0 when the user folds it.
/// On the target iPad that is 646 / 1022 with the sidebar out (834 and 1210 of window) and 834 /
/// 1210 with it folded; a 2/3 Split View adds 737 and 795. 632 is the 820pt threshold, the
/// narrowest pane the labelled column can leave.
struct CadenceRegularSplitLayoutTests {
    private func listPane(_ paneWidth: CGFloat) -> CGFloat {
        CadenceRegularSplitLayout.listPaneWidth(forPaneWidth: paneWidth)
    }

    @Test
    func theChooserIsNeverWiderThanTheDetailBesideIt() {
        for paneWidth in [CGFloat(632), 646, 737, 834, 1022, 1210] {
            let list = listPane(paneWidth)
            let detail = paneWidth - CadenceRegularSplitLayout.paneDividerWidth - list
            #expect(list <= detail, "chooser \(list) beat detail \(detail) at pane \(paneWidth)")
        }
    }

    @Test
    func aRoomyPaneStopsSplittingItselfInHalf() {
        // The bug: `iOSFeatureListPane` declared a minimum and an ideal but no maximum, so an
        // `HStack` gave the Goals chooser half the pane to draw one-line rows.
        #expect(listPane(834) == 834 * CadenceRegularSplitLayout.listPaneFraction)
        #expect(listPane(834) < 417)
    }

    /// Reachable, unlike the caps this file's siblings shed: 380 binds from 950pt of pane up, and
    /// the target iPad is 1022 in landscape with the sidebar out.
    @Test
    func theChooserNeverExceedsItsMaximumHoweverWideThePaneGets() {
        #expect(listPane(1022) == CadenceRegularSplitLayout.listPaneMaxWidth)
        #expect(listPane(1210) == CadenceRegularSplitLayout.listPaneMaxWidth)
    }

    @Test
    func theNarrowestRegularPaneGivesTheMajorityToTheDetail() {
        // 646 * 0.40 = 258, raised to the 300 floor, which is still under half of 646.
        #expect(listPane(646) == CadenceRegularSplitLayout.listPaneMinWidth)
        #expect(646 - 1 - listPane(646) > listPane(646))
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

    // MARK: - T-252: two panes is worse than one, below 750

    /// 750pt, and derived rather than typed: `listPaneMinWidth / listPaneFraction` is the width at
    /// which the chooser's floor and the share it asks for stop agreeing. Asserted both ways round
    /// so a change to either part has to be deliberate.
    @Test
    func theTwoPaneFloorIsTheWidthAtWhichTheChoosersFloorStopsBeingItsShare() {
        #expect(CadenceRegularSplitLayout.twoPaneMinimumWidth == 750)
        #expect(
            750 * CadenceRegularSplitLayout.listPaneFraction
                == CadenceRegularSplitLayout.listPaneMinWidth
        )
        #expect(CadenceRegularSplitLayout.supportsTwoPanes(paneWidth: 750))
        #expect(!CadenceRegularSplitLayout.supportsTwoPanes(paneWidth: 749))
    }

    /// The ticket's device, and the point of the change: at 646 of pane — an 11" iPad Pro in
    /// portrait with the shell sidebar out, the primary target in its default configuration — the
    /// split used to hand a 300pt chooser to a 345pt detail on the same screen where Today is one
    /// column and Calendar has dropped its inspector. Three registered rules now answer alike.
    @Test
    func theTargetIPadsPortraitPaneIsOneColumnLikeTodayAndCalendar() {
        #expect(!CadenceRegularSplitLayout.supportsTwoPanes(paneWidth: 646))
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 646) == .compact)
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 646))
    }

    /// And it still splits everywhere the proportion is affordable, so the fallback is a floor
    /// rather than a retreat: the sidebar folded in portrait (834), landscape with it out (1022)
    /// and landscape folded (1210).
    @Test
    func everyPaneThatCanAffordTheProportionStillSplits() {
        for paneWidth in [CGFloat(834), 1022, 1210] {
            #expect(
                CadenceRegularSplitLayout.supportsTwoPanes(paneWidth: paneWidth),
                "pane \(paneWidth) stopped splitting"
            )
            #expect(listPane(paneWidth) >= CadenceRegularSplitLayout.listPaneMinWidth)
        }
    }

    /// Above the gate the half-pane clamp never binds — the chooser gets the width it asked for,
    /// bounded only by its own floor and maximum. That is what "the floor stopped being the share"
    /// means, stated as a property over the whole range rather than at three sampled widths, and it
    /// is the half `listPaneWidth` alone could not promise.
    @Test
    func aboveTheGateTheChooserAlwaysGetsTheWidthItAsksFor() {
        var paneWidth = CadenceRegularSplitLayout.twoPaneMinimumWidth
        while paneWidth <= 1400 {
            let wish = min(
                max(paneWidth * CadenceRegularSplitLayout.listPaneFraction,
                    CadenceRegularSplitLayout.listPaneMinWidth),
                CadenceRegularSplitLayout.listPaneMaxWidth
            )
            #expect(
                listPane(paneWidth) == wish,
                "the half-pane clamp bound at pane \(paneWidth): \(listPane(paneWidth)) not \(wish)"
            )
            paneWidth += 1
        }
        // And below it, it does — otherwise the assertion above is about nothing.
        #expect(listPane(600) < min(
            max(600 * CadenceRegularSplitLayout.listPaneFraction,
                CadenceRegularSplitLayout.listPaneMinWidth),
            CadenceRegularSplitLayout.listPaneMaxWidth
        ))
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
    func aPortraitPaneGivesTheWholeThingToTheCalendar() {
        // 646pt, a full-screen portrait iPad with the sidebar out: the old
        // `min(max(width * 0.30, 340), 430)` returned 340 — over half the pane — and left the week
        // grid running seven 112pt columns behind a scroller showing two of them.
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 646))
    }

    /// The first pane past the 681pt split floor keeps the inspector at exactly the width it had
    /// before the gate was generalised. On the target iPad that is a folded portrait window (834).
    @Test
    func aPaneJustPastTheFloorKeepsExactlyTheInspectorItAlreadyHad() {
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 834))
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 834) == 340)
    }

    @Test
    func theInspectorIsNeverWiderThanTheCalendarBesideIt() {
        for paneWidth in [CGFloat(681), 737, 795, 834, 1022, 1210] {
            let inspector = CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: paneWidth)
            let calendar = paneWidth - CadenceCalendarPaneLayout.paneDividerWidth - inspector
            #expect(inspector <= calendar, "inspector \(inspector) beat calendar \(calendar) at pane \(paneWidth)")
        }
    }

    /// Replaces an assertion that pinned a 430pt ceiling at a 2000pt pane. That cap needed 1434pt
    /// to bind and the widest pane a target device produces is 1210 — an 11" Pro in landscape with
    /// the shell sidebar folded — so the fraction, floored at `inspectorMinWidth`, is what decides
    /// the inspector at every width that exists. If a ceiling comes back, this fails.
    @Test
    func theInspectorIsItsFractionAtEveryReachablePaneWidth() {
        for paneWidth in [CGFloat(834), 1022, 1210] {
            #expect(
                CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: paneWidth)
                    == max(
                        paneWidth * CadenceCalendarPaneLayout.inspectorFraction,
                        CadenceCalendarPaneLayout.inspectorMinWidth
                    ),
                "inspector was clamped at pane \(paneWidth)"
            )
        }
    }
}

/// Which Calendar presentations draw the day inspector at all.
///
/// The Board used to, and it was the one surface that could least afford it: horizontally scrolling
/// day columns, each headed with its own date and each listing that day's items, with a 340pt column
/// beside them repeating one of those days. On an 11" Pro in landscape that is a column and a half
/// of the days the board exists to show, spent restating one of the days still on screen.
struct CadenceCalendarDayInspectorGateTests {
    /// Every pane the target iPad reaches — both orientations, sidebar out and folded, plus a 2/3
    /// Split View — with the degenerate case and the two gate boundaries (681, 1183) either side.
    private static let paneWidths: [CGFloat] = [0, 646, 681, 737, 795, 834, 1022, 1182, 1183, 1210]

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
    /// columns are already paid for, at 1183pt of pane. With the shell sidebar out, neither
    /// orientation of the target iPad reaches that (646 and 1022). Folding it in landscape does:
    /// 1210, where the week keeps seven full-size columns *and* gets an inspector, which is exactly
    /// what the gate promises rather than an accident.
    @Test
    func weekSplitsOnlyOnceSevenFullSizeColumnsArePaidFor() {
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 646))
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1022))
        #expect(!CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1182))
        #expect(CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1183))
        #expect(CadenceCalendarPaneLayout.showsDayInspector(isCompact: false, presentation: .timeline, viewMode: .week, paneWidth: 1210))
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
    /// Every pane the app actually runs a week in, on the devices it targets. 646 and 1022 are the
    /// target iPad full screen with the shell sidebar out; 834 and 1210 are the same two with it
    /// folded; 737 is a 2/3 Split View. The phone is covered separately below — it has one column
    /// and scrolls.
    private static let realPaneWidths: [CGFloat] = [646, 737, 834, 1022, 1210]

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
    /// nothing. The binding case is the narrowest pane, 646pt of portrait, at 84pt a column.
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
    /// for an inspector — 834pt divided seven ways after the inspector's 340 is 62, which clears
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
        // Full screen with the shell sidebar out, neither orientation of the target iPad pays for
        // both, so Week fills the pane.
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 646, calendarMinimumWidth: Self.claim))
        #expect(!CadenceCalendarPaneLayout.showsInspector(paneWidth: 1022, calendarMinimumWidth: Self.claim))
        // Folding the sidebar in landscape does pay for both: 1210pt. The week keeps more than its
        // full-size claim and the inspector takes its fraction, which is the gate working rather
        // than an accident of a wide window.
        #expect(CadenceCalendarPaneLayout.showsInspector(paneWidth: 1210, calendarMinimumWidth: Self.claim))
        #expect(gridWidth(paneWidth: 1210) >= Self.claim)
        // And at the boundary the remainder, not the fraction, is what the inspector gets — 355
        // of 1183 would have left the grid under its own claim.
        #expect(CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: 1183, calendarMinimumWidth: Self.claim) == 340)
        #expect(gridWidth(paneWidth: 1183) == Self.claim)
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

/// T-251. The macOS Calendar Board's pane is `window − sidebar`: a 960pt window floor against a
/// 220–390pt sidebar gives **570 … 740**, and 960 with the sidebar hidden outright. Those are the
/// widths the ticket measured 74.0 / 200.0 / 244.0 / 464.0 day-column widths at, against a 306pt
/// column.
struct CadenceCalendarBoardLayoutTests {
    /// Every pane the app's own minimum window can produce, plus the two roomy ones.
    private static let reachablePanes: [CGFloat] = [570, 696, 740, 960, 1248, 1512]

    // MARK: - The guarantee

    @Test
    func everyReachablePaneKeepsOneWholeDayColumnOnScreen() {
        for paneWidth in Self.reachablePanes {
            let columns = CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: paneWidth)
            #expect(
                columns >= CadenceCalendarBoardLayout.oneDayColumnMinimumWidth,
                "day columns got \(columns) at a \(paneWidth) pane, under the \(CadenceCalendarBoardLayout.oneDayColumnMinimumWidth) floor"
            )
        }
    }

    /// The before/after the ticket is about, stated as values rather than as a direction, so a
    /// later change that quietly re-narrows the columns fails here.
    @Test
    func theNarrowPanesGetTheirColumnsBack() {
        // 570 and 696 used to be 74 and 200 — both under one 306pt column.
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 570) == 450)
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 696) == 576)
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 740) == 620)
        // Above the gate nothing moves: 960 and 1248 are `paneWidth − 496` exactly as before.
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 960) == 464)
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 1248) == 752)
    }

    // MARK: - The gate

    @Test
    func theGateIsTwoExpandedRailsAndOneWholeDayColumn() {
        #expect(CadenceCalendarBoardLayout.oneDayColumnMinimumWidth == 350)
        #expect(CadenceCalendarBoardLayout.expandedRailsMinimumWidth == 846)
        #expect(CadenceCalendarBoardLayout.railForm(paneWidth: 846) == .expanded)
        #expect(CadenceCalendarBoardLayout.railForm(paneWidth: 845.9) == .collapsed)
    }

    /// The MacBook that has always been fine stays byte-identical, which is the half of the change
    /// that must not be visible.
    @Test
    func aRoomyMacIsUntouched() {
        for paneWidth in [CGFloat(960), 1248, 1512] {
            #expect(CadenceCalendarBoardLayout.railForm(paneWidth: paneWidth) == .expanded)
            #expect(
                CadenceCalendarBoardLayout.railWidth(
                    form: CadenceCalendarBoardLayout.railForm(paneWidth: paneWidth)
                ) == CadenceCalendarBoardLayout.expandedRailWidth
            )
        }
    }

    /// `CadenceSettingsTemplatesCardLayout`'s call: an unmeasured frame answers with the fallback,
    /// because a frame of the wide form is the 74pt day column this type exists to prevent.
    @Test
    func anUnmeasuredPaneAnswersWithTheStrip() {
        for paneWidth in [CGFloat(0), -1, 1] {
            #expect(CadenceCalendarBoardLayout.railForm(paneWidth: paneWidth) == .collapsed)
        }
        #expect(CadenceCalendarBoardLayout.dayColumnsWidth(paneWidth: 0) == 0)
    }

    // MARK: - The floors are borrowed, not typed

    /// The collapsed strip's floor **is** the control minimum this file already states, by
    /// reference. A strip is hit under a card already in motion, so the floor applies to it at
    /// least as strongly as to a button.
    @Test
    func theStripBorrowsTheControlMinimumRatherThanRestatingIt() {
        #expect(
            CadenceCalendarBoardLayout.collapsedRailWidth
                == CadenceCalendarWeekGridLayout.minimumTouchTarget
                    + CadenceCalendarBoardLayout.railHorizontalPadding * 2
        )
        #expect(CadenceCalendarBoardLayout.collapsedRailWidth == 60)
    }

    /// A rail is never wider collapsed than expanded, and a strip always costs strictly less — the
    /// property that makes collapsing worth doing at all.
    @Test
    func aStripIsStrictlyCheaperThanAColumn() {
        #expect(
            CadenceCalendarBoardLayout.railWidth(form: .collapsed)
                < CadenceCalendarBoardLayout.railWidth(form: .expanded)
        )
    }

    // MARK: - What collapsing must not cost

    /// The rails may be reduced but never dropped, and this is the measurement behind that: the
    /// Board's day columns are floored at today, so past-dated work has no column, and the day
    /// bucketing keys strictly on the do date, so do-dateless work has none either. Both
    /// populations exist only on a rail.
    @Test
    func neitherRailsWorkHasADayColumnToFallBackOn() {
        let todayKey = "2026-08-24"
        let overdue = AppTask(title: "late")
        overdue.scheduledDate = "2026-08-01"
        let unscheduled = AppTask(title: "someday")
        unscheduled.dueDate = "2026-09-01"

        #expect(CalendarBoardPlannerSupport.rail(for: overdue, todayKey: todayKey) == .overdue)
        #expect(CalendarBoardPlannerSupport.rail(for: unscheduled, todayKey: todayKey) == .unscheduled)

        // The macOS board's own bucketing: neither task lands in any day column.
        let byDate = CalendarBoardPlannerSupport.tasksByBoardDate(from: [overdue, unscheduled])
        #expect(byDate["2026-09-01"] == nil, "a do-dateless task must not appear under its due day")
        #expect(byDate.values.flatMap { $0 }.contains { $0.id == unscheduled.id } == false)
        // Overdue does key a day — one the board no longer renders, which is why the rail is the
        // only route to it.
        #expect(byDate["2026-08-01"]?.count == 1)
        let windowStart = CalendarBoardPlannerSupport.plannerWindowStart(
            for: DateFormatters.date(from: "2026-08-01") ?? Date(),
            notBefore: DateFormatters.date(from: todayKey) ?? Date()
        )
        #expect(DateFormatters.dateKey(from: windowStart) == todayKey)
    }

    // MARK: - The surface asks, and asks once

    /// A layout type nothing calls is a passing test suite over a broken page. Pinned the way
    /// `CadenceDesktopSplitLayoutTests.eachSplitIsGatedOnTheWidthItWasHanded` pins its three: the
    /// board reads its width from a `GeometryReader` and asks the house file exactly once.
    @Test
    func theBoardIsGatedOnTheWidthItWasHanded() throws {
        let path = "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        let code = try boardLayoutStrippingComments(boardLayoutSource(path))

        #expect(boardLayoutOccurrences(of: "CadenceCalendarBoardLayout.railForm(paneWidth:", in: code) == 1)
        #expect(boardLayoutOccurrences(of: "GeometryReader", in: code) == 1)
        // And the surface declares no width rule of its own — it passes the *answer* down.
        // `CadencePaneWidthRuleHomesTests` enforces this globally; this says it about the one file
        // the ticket is on, so a regression names the board rather than a count.
        #expect(boardLayoutOccurrences(of: "paneWidth: CGFloat", in: code) == 0)
    }

    /// The four board metrics moved to the house file so the floor could be a sum of them. If one
    /// gets re-typed back into the macOS view layer the sum stops following it, which is the exact
    /// failure `everyRegisteredFloorIsStillSpelledAsASumRatherThanTyped` exists for one level up.
    @Test
    func theBoardsGeometryIsSpelledOnceAndReadBack() throws {
        for path in [
            "Cadence/macOS/Views/KanbanBoardSupport.swift",
            "Cadence/macOS/Views/CalendarBoardRailSupportViews.swift",
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift",
        ] {
            let code = try boardLayoutStrippingComments(boardLayoutSource(path))
            for gone in [
                "calendarBoardDayColumnWidth",
                "calendarBoardRailWidth",
                "calendarBoardColumnSpacing",
                "calendarBoardHorizontalPadding",
            ] {
                #expect(
                    boardLayoutOccurrences(of: gone, in: code) == 0,
                    "\(path) still spells \(gone); it is CadenceCalendarBoardLayout's now"
                )
            }
        }
        // The rail reads both its widths from the one place, and the strip is a reduction of the
        // same column rather than a second view: one `.frame(width:)`, one drop modifier.
        let rail = try boardLayoutStrippingComments(
            boardLayoutSource("Cadence/macOS/Views/CalendarBoardRailSupportViews.swift")
        )
        #expect(boardLayoutOccurrences(of: "CadenceCalendarBoardLayout.railWidth(form:", in: rail) == 1)
        #expect(boardLayoutOccurrences(of: ".modifier(CalendarBoardRailDropModifier(", in: rail) == 1)
    }

    // MARK: - Non-vacuity

    /// Every source assertion above is a count over a file read from disk, and a read that silently
    /// returns nothing makes the zero-expectations pass.
    @Test
    func theSourceScanActuallyReadsTheBoardFiles() throws {
        for path in [
            "Cadence/macOS/Views/KanbanBoardSupport.swift",
            "Cadence/macOS/Views/CalendarBoardRailSupportViews.swift",
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift",
        ] {
            let code = try boardLayoutStrippingComments(boardLayoutSource(path))
            #expect(code.count > 400, "\(path) read as \(code.count) characters")
            #expect(boardLayoutOccurrences(of: "struct", in: code) >= 1, "\(path)")
        }
    }

    /// Proof the stripper runs, from a case in the tree rather than a synthetic one: the
    /// tombstone left in `KanbanBoardSupport.swift` names the constants it no longer declares, so
    /// raw source sees them and stripped source does not.
    @Test
    func theCommentStrippingIsActuallyStrippingInCalendarBoardLayout() throws {
        let path = "Cadence/macOS/Views/KanbanBoardSupport.swift"
        let raw = try boardLayoutSource(path)
        let stripped = try boardLayoutStrippingComments(raw)
        #expect(boardLayoutOccurrences(of: "CadenceCalendarBoardLayout", in: raw) >= 1)
        #expect(boardLayoutOccurrences(of: "CadenceCalendarBoardLayout", in: stripped) == 0)
    }

    /// The Timeline's "unscheduled tasks" are a different population entirely — a task with a day
    /// and no start minute — so it is not a second route to the Unscheduled rail's contents and
    /// cannot be cited as one.
    @Test
    func theTimelinesUnscheduledChipsAreNotTheUnscheduledRail() {
        let railTask = AppTask(title: "no day at all")
        let timelineChip = AppTask(title: "today, no slot")
        timelineChip.scheduledDate = "2026-08-24"
        timelineChip.scheduledStartMin = -1

        let byDate = CadenceScheduleSupport.unscheduledTasksByDate([railTask, timelineChip])
        #expect(byDate.values.flatMap { $0 }.contains { $0.id == railTask.id } == false)
        #expect(byDate["2026-08-24"]?.count == 1)
    }
}

// MARK: - Source-reading helpers

/// Prefixed rather than shared, exactly as `CadencePaneWidthRuleHomesTests` and
/// `CadenceDesktopSplitLayoutTests` keep theirs private to their own files.
private func boardLayoutRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func boardLayoutSource(_ relativePath: String) throws -> String {
    try String(contentsOf: boardLayoutRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func boardLayoutStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

private func boardLayoutOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}
