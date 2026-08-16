import Foundation
import Testing
@testable import Cadence

/// The header title on the mobile Notes surface, which is also the date-jump control.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so the view
/// itself cannot be tested here — the arithmetic it reads is what these pin.
struct CadenceNoteDateNavigationTests {
    /// Monday 2026-08-17 through Sunday 2026-08-23: an ISO week wholly inside August.
    private let midWeekMonday = "2026-08-17"

    @Test func dailyTitleIsTheDay() {
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: midWeekMonday) == "Aug 17")
    }

    @Test func weeklyTitleIsTheRange() {
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: midWeekMonday) == "Aug 17–23")
    }

    /// Any day in the week names the same week, not the day you happened to pick. Picking Thursday
    /// from the calendar must open the Monday-to-Sunday note, exactly as macOS's weekly picker does.
    @Test func weeklyTitleIsStableAcrossTheWeek() {
        let expected = CadenceNoteDateNavigation.title(for: .week, dayKey: midWeekMonday)
        for day in ["2026-08-17", "2026-08-19", "2026-08-23"] {
            #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: day) == expected)
        }
        // ...and the next day is a different week.
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: "2026-08-24") != expected)
    }

    /// A week straddling two months gets the spaced dash and both month names. Set tight,
    /// "Aug 31–Sep 6" reads as one date.
    @Test func weekAcrossAMonthBoundarySpellsBothMonths() {
        // Mon 2026-08-31 … Sun 2026-09-06.
        #expect(CadenceNoteDateNavigation.weekRangeLabel(forDayKey: "2026-09-02") == "Aug 31 – Sep 6")
    }

    /// The two undated tabs return `nil` rather than a string, so the host supplies its own
    /// constant word. Returning "Notes" here would put the fallback in the wrong layer.
    @Test func undatedTabsHaveNoDateTitle() {
        #expect(CadenceNoteDateNavigation.title(for: .notepad, dayKey: midWeekMonday) == nil)
        #expect(CadenceNoteDateNavigation.title(for: .events, dayKey: midWeekMonday) == nil)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.notepad) == false)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.events) == false)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.today))
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.week))
    }

    /// A malformed key shows itself rather than silently becoming today. Substituting today would
    /// let the user write into a day the header is not naming.
    @Test func malformedKeyIsShownRatherThanSubstituted() {
        #expect(CadenceNoteDateNavigation.dayLabel(forDayKey: "not-a-date") == "not-a-date")
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: "") == "")
    }

    @Test func currentPeriodDrivesTheAwayTreatment() {
        let today = DateFormatters.todayKey()
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .today, dayKey: today, today: today))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .today, dayKey: "2026-08-17", today: "2026-08-18") == false)
        // Same week, different day: the weekly note has not moved, so the header must not claim it has.
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .week, dayKey: "2026-08-17", today: "2026-08-19"))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .week, dayKey: "2026-08-17", today: "2026-08-24") == false)
    }

    /// Notepad and Event Notes are never "away", or the popover would offer a way back to a today
    /// they do not have.
    @Test func undatedTabsAreAlwaysCurrent() {
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .notepad, dayKey: "2020-01-01", today: "2026-08-17"))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .events, dayKey: "2020-01-01", today: "2026-08-17"))
    }

    /// The week key the panel loads is derived from the day key, so the title and the note on
    /// screen cannot disagree about which week is showing.
    @Test func weekKeyMatchesTheDateFormattersSpelling() {
        for day in ["2026-08-17", "2026-01-01", "2025-12-31"] {
            let date = DateFormatters.date(from: day)
            #expect(date != nil)
            #expect(CadenceNoteDateNavigation.weekKey(forDayKey: day) == DateFormatters.weekKey(from: date!))
        }
    }
}
