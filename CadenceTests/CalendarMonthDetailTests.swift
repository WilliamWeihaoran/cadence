import Testing
import CoreGraphics
@testable import Cadence

/// Month used to pick its own mechanism from the window: a pane under 681pt got the agenda and a
/// pane over it got the day inspector, so rotating an 11" iPad swapped one for the other and there
/// was no way to ask for the one you were not given. These pin the split that replaced that — the
/// toggle picks the content, the width picks only where it is drawn.
///
/// Pane widths are the window width less the 188pt shell sidebar:
/// 646 (11" portrait), 844 (13" portrait), 1022 (11" landscape), 1188 (13" landscape).
struct CalendarMonthDetailTests {

    // MARK: - The stored choice

    @Test
    func anUnsetPreferenceResolvesToTheAgenda() {
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "") == .agenda)
        #expect(CadenceCalendarMonthLayout.defaultDetail == .agenda)
    }

    @Test
    func aStoredChoiceIsHonouredAtEveryRegularWidth() {
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "day", isCompact: false) == .day)
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "agenda", isCompact: false) == .agenda)
    }

    /// A value written by a future build, or a corrupted defaults entry, must not leave Month with
    /// no detail at all.
    @Test
    func anUnrecognisedStoredValueFallsBackRatherThanBlanking() {
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "inspector") == .agenda)
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "Day") == .agenda)
    }

    /// The raw values are persisted, so they are independent of what the pills are labelled.
    @Test
    func theStoredSpellingIsNotTheButtonLabel() {
        #expect(CadenceCalendarMonthDetail.agenda.rawValue == "agenda")
        #expect(CadenceCalendarMonthDetail.day.rawValue == "day")
        #expect(CadenceCalendarMonthDetail.agenda.title == "Agenda")
        #expect(CadenceCalendarMonthDetail.day.title == "Day")
    }

    @Test
    func aPhoneKeepsTheAgendaWhateverAnIPadStored() {
        #expect(CadenceCalendarMonthLayout.detail(storedRawValue: "day", isCompact: true) == .agenda)
        #expect(CadenceCalendarMonthLayout.compactDetail == .agenda)
    }

    // MARK: - Where the choice is drawn

    @Test
    func placementFollowsTheWidthTheInspectorAlreadySplitsAt() {
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 1022) == .beside)
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 844) == .beside)
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 681) == .beside)
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 680) == .below)
        // 11" portrait. Beside here would leave ~43pt per weekday column, the starvation that had
        // the week grid showing two of its seven days.
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 646) == .below)
    }

    /// The first layout pass measures 0. Falling to `.below` there means a pane opens stacked and
    /// gains its side column, rather than opening split at a width that cannot hold a split.
    @Test
    func anUnmeasuredPaneStacks() {
        #expect(CadenceCalendarMonthLayout.placement(paneWidth: 0) == .below)
    }

    /// The two axes are genuinely independent: every combination of stored choice and pane width
    /// resolves, so no orientation can take a reading away.
    @Test
    func bothReadingsAreReachableAtBothWidths() {
        for paneWidth in [CGFloat(646), 1022] {
            for stored in CadenceCalendarMonthDetail.allCases {
                #expect(CadenceCalendarMonthLayout.detail(storedRawValue: stored.rawValue) == stored)
                _ = CadenceCalendarMonthLayout.placement(paneWidth: paneWidth)
            }
        }
    }

    // MARK: - Where the control appears

    @Test
    func theToggleIsMonthOnly() {
        #expect(CadenceCalendarMonthLayout.showsDetailControl(isCompact: false, presentation: .timeline, viewMode: .month))
        #expect(!CadenceCalendarMonthLayout.showsDetailControl(isCompact: false, presentation: .timeline, viewMode: .week))
        #expect(!CadenceCalendarMonthLayout.showsDetailControl(isCompact: false, presentation: .board, viewMode: .month))
    }

    @Test
    func thePhoneHasNoToggleToOffer() {
        #expect(!CadenceCalendarMonthLayout.showsDetailControl(isCompact: true, presentation: .timeline, viewMode: .month))
    }

    // MARK: - The counts strip above the grid

    /// The strip carries the selected date. Every arrangement except one restates that date in the
    /// next pane down — the agenda heads every day, and an inspector under the grid heads the
    /// selected one — so only the inspector-as-a-side-column keeps it.
    @Test
    func theCountsStripSurvivesOnlyWhereItIsNotImmediatelyRestated() {
        #expect(CadenceCalendarMonthLayout.showsDaySummaryStrip(placement: .beside, detail: .day))
        #expect(!CadenceCalendarMonthLayout.showsDaySummaryStrip(placement: .beside, detail: .agenda))
        #expect(!CadenceCalendarMonthLayout.showsDaySummaryStrip(placement: .below, detail: .day))
        #expect(!CadenceCalendarMonthLayout.showsDaySummaryStrip(placement: .below, detail: .agenda))
    }

    // MARK: - What the grid is capped against when the detail is under it

    /// The inspector opens with a 63pt header carrying the date and the add button, so the agenda's
    /// 96 would leave it a header and a sliver.
    @Test
    func theInspectorReservesMoreRoomUnderTheGridThanTheAgendaDoes() {
        #expect(
            CadenceCalendarMonthLayout.detailMinimumHeight(for: .day) >
            CadenceCalendarMonthLayout.detailMinimumHeight(for: .agenda)
        )
        #expect(
            CadenceCalendarMonthLayout.detailMinimumHeight(for: .agenda) ==
            CadenceCalendarMonthAgendaSupport.agendaMinimumHeight
        )
    }

    /// The hazard the whole `gridRowHeight` cap exists for: whichever detail is underneath, the grid
    /// must not be able to claim the pane and starve it to zero height. Six rows is the tallest a
    /// month gets.
    @Test
    func neitherDetailCanBeStarvedToNothingByTheGrid() {
        for detail in CadenceCalendarMonthDetail.allCases {
            let minimum = CadenceCalendarMonthLayout.detailMinimumHeight(for: detail)
            for availableHeight in [CGFloat(320), 420, 640, 1050] {
                let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
                    availableHeight: availableHeight,
                    rowCount: 6,
                    weekdayHeaderHeight: 22,
                    agendaMinimumHeight: minimum
                )
                let gridHeight = 22 + rowHeight * 6 + 8
                #expect(
                    availableHeight - gridHeight >= minimum - 0.001,
                    "grid took \(gridHeight) of \(availableHeight), leaving \(availableHeight - gridHeight) for \(detail)"
                )
            }
        }
    }
}
