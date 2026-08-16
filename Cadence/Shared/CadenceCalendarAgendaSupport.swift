import CoreGraphics
import Foundation

/// The logic behind the compact **Month** view: a month grid on top, a live agenda underneath.
///
/// Month was the last calendar mode still carrying the shared chrome block `ecaf80f` removed from
/// Week and Board — the four "0 total / 0 timed / 0 tasks / 0 events" chips, the selected-day card,
/// and the oversized empty state. It was left deliberately: the grid alone lists nothing, so
/// stripping the inspector without building an agenda first would have left a month you could look
/// at but not read. This type is that agenda's half of the work — which days it lists, what each
/// day's heading says, how tall the grid may grow, and the two rules that keep tapping a grid day
/// and scrolling the agenda from driving each other in a loop.
///
/// It lives in `Shared/` rather than beside the view because `Cadence/iOS/` is inside
/// `#if os(iOS)` and invisible to the macOS-built `CadenceTests`.
enum CadenceCalendarMonthAgendaSupport {

    // MARK: - Which days the agenda lists

    /// The days the agenda lists, in order: **exactly** the days the grid draws.
    ///
    /// Not the calendar month, and not just the days that hold something. The grid and the agenda
    /// are two views of one list, so every cell has a section to jump to and every section has a
    /// cell to light up. Listing only the month proper would leave the grid's leading and trailing
    /// cells as controls that look tappable and scroll nowhere; listing only non-empty days would
    /// do the same to every empty day, which is most of them — and would leave a quiet month with
    /// too little agenda to scroll, which is the other half of the two-way sync.
    static func agendaDays(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    static func agendaDayKeys(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [String] {
        agendaDays(forMonthContaining: monthDate, calendar: calendar).map {
            DateFormatters.dateKey(from: $0, calendar: calendar)
        }
    }

    /// A day section's heading — `Sat · Aug 15`, which the shared board column header uppercases to
    /// `SAT · AUG 15`. Same shape as a Calendar Board day column's heading, because it is the same
    /// thing: the label over one day's items.
    static func dayHeaderLabel(for date: Date) -> String {
        "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))"
    }

    // MARK: - Two-way selection sync

    /// The section the agenda **opens** on.
    ///
    /// The selected day, but only where the agenda actually lists it. `.scrollPosition(id:)` drops a
    /// scroll to an id that is not in the stack, and a dropped scroll leaves the grid lit on one day
    /// and the agenda parked on another with no gesture that reconciles them — the same failure
    /// `scrollTarget` guards for a *later* selection, which the opening position had no equivalent
    /// of. A selection outside this month opens on the month's first listed day instead.
    ///
    /// `nil` only for a month with no days at all, which no calendar produces.
    static func initialScrollTarget(selectedKey: String, agendaDayKeys: [String]) -> String? {
        agendaDayKeys.contains(selectedKey) ? selectedKey : agendaDayKeys.first
    }

    /// The agenda section a **selection change** should scroll to, or `nil` to leave the agenda
    /// where it is.
    ///
    /// `nil` in the two cases that would otherwise close the loop between the grid and the agenda:
    /// the agenda already sits at that section — which is what a selection arriving *from* a scroll
    /// looks like, so re-issuing the scroll would fight the finger — and a day the agenda does not
    /// list, where the scroll would be dropped on the floor and leave the two out of step with no
    /// way back.
    static func scrollTarget(selectedKey: String, scrolledKey: String?, agendaDayKeys: [String]) -> String? {
        guard scrolledKey != selectedKey else { return nil }
        guard agendaDayKeys.contains(selectedKey) else { return nil }
        return selectedKey
    }

    /// The day a **scrolled-to section** should select, or `nil` to leave the selection alone.
    ///
    /// The mirror of `scrollTarget`: a scroll that lands back on the already-selected day — which is
    /// what the scroll *caused by* a grid tap settles into — changes nothing, so the tap does not
    /// bounce back through the selection a second time.
    static func selectionTarget(scrolledKey: String?, selectedKey: String) -> String? {
        guard let scrolledKey, scrolledKey != selectedKey else { return nil }
        return scrolledKey
    }

    // MARK: - Grid geometry

    /// How many week rows the grid draws for this month — 4, 5 or 6 depending on where the first of
    /// the month falls.
    static func weekRowCount(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> Int {
        let days = agendaDays(forMonthContaining: monthDate, calendar: calendar).count
        return max(0, days / 7)
    }

    /// The least the detail under the grid is left with, whatever the grid would like — a heading
    /// and the top of the first row under it. The detail is the half of this view that lists
    /// anything.
    ///
    /// It is one number for both readings. The day inspector used to reserve 168 because it opened
    /// with a fixed 63pt bar carrying the date and an add button; that bar is gone, so the inspector
    /// now opens on its first section heading — the same shape the agenda opens on, and the same
    /// claim. Leaving 168 behind would have had the grid buy the detail 72pt it no longer needs out
    /// of its own cell height, on the one view whose subject is a whole month of cells.
    static let agendaMinimumHeight: CGFloat = 96

    /// The height of one week row, so that **every** week of the month is on screen at once — and so
    /// that the agenda under it is on screen *at all*.
    ///
    /// The compact month used to give the grid the bottom ~40% of a pane it shared with a day
    /// inspector, at a 104pt minimum cell — three weeks fitted and the rest were below the fold, on
    /// the one view whose entire job is showing a whole month. Rows are sized to a share of the
    /// pane instead, so the row *count* is what the grid honours and the row *height* is what gives.
    ///
    /// The 44pt touch floor is a floor on the grid's **share of the pane**, not a claim against the
    /// pane itself. It used to be applied last and unconditionally, which quietly made it outrank
    /// the agenda: at six rows the grid asked for `weekdayHeader + 6 × 44 + padding` — 294pt — no
    /// matter how little there was, its `VStack` gave the fixed-height grid what it asked for, and
    /// the agenda's `ScrollView`, the flexible sibling, got whatever remained. On a pane shorter
    /// than ~390pt that remainder is nothing, and a zero-height scroll view is not an empty list:
    /// it is a pane that draws its grid and then shows no day headings, no rows, and no scroll in
    /// either direction that brings any back, because there is nowhere for them to be. So the grid
    /// is capped at `availableHeight - agendaMinimumHeight` first and the touch floor applies inside
    /// that cap. Every pane that can hold both still gets its 44pt cells; a pane that cannot hold
    /// both gives up cell height rather than giving up the agenda.
    static func gridRowHeight(
        availableHeight: CGFloat,
        rowCount: Int,
        weekdayHeaderHeight: CGFloat,
        gridBottomPadding: CGFloat = 8,
        agendaMinimumHeight: CGFloat = Self.agendaMinimumHeight,
        gridHeightFraction: CGFloat = 0.46,
        minimumRowHeight: CGFloat = 44,
        maximumRowHeight: CGFloat = 58
    ) -> CGFloat {
        guard rowCount > 0 else { return minimumRowHeight }
        let fraction = min(max(gridHeightFraction, 0), 1)
        let preferred = max(0, availableHeight * fraction - weekdayHeaderHeight) / CGFloat(rowCount)
        let ceiling = max(
            0,
            availableHeight - agendaMinimumHeight - weekdayHeaderHeight - gridBottomPadding
        ) / CGFloat(rowCount)
        let floor = min(minimumRowHeight, ceiling)
        return min(max(min(preferred, ceiling), floor), max(floor, maximumRowHeight))
    }
}

// MARK: - Which reading of the month, and where it goes

/// The two ways Month can say what is on a day, as a **choice** rather than a consequence of how
/// wide the window happens to be.
///
/// Both already existed. Which one you got was decided by `hasInspector`, i.e. by the pane clearing
/// 681pt: an 11" iPad in portrait showed the agenda and the same iPad in landscape showed the day
/// inspector, so rotating the device silently swapped the mechanism — two different answers to
/// "what is on the 14th", neither reachable from the other.
enum CadenceCalendarMonthDetail: String, CaseIterable, Hashable {
    /// Every day of the month in sequence, scrolling, two-way synced with the grid.
    case agenda
    /// The selected day on its own, in sections: blocks, Apple Calendar, timed, do date, due.
    case day

    var title: String {
        switch self {
        case .agenda: return "Agenda"
        case .day: return "Day"
        }
    }

    var systemImage: String {
        switch self {
        case .agenda: return "list.bullet"
        case .day: return "calendar.day.timeline.left"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .agenda: return "List every day of the month"
        case .day: return "Show only the selected day"
        }
    }
}

/// Month's two axes: the **toggle** picks what is shown beside or under the grid, and the pane
/// width picks which of those two it is.
///
/// Keeping them apart is the whole point. The stored preference is written from a tap and from
/// nothing else — a persisted value written from a measured one compounds across launches, which
/// `ecaf80f` had already paid for once — while placement is derived every layout pass and never
/// stored.
enum CadenceCalendarMonthLayout {
    /// Where the chosen detail sits relative to the month grid.
    ///
    /// `nonisolated` so its synthesized `Equatable` is too: this project builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which otherwise makes comparing two placements
    /// from a `nonisolated` context — a test, say — a Swift 6 error.
    nonisolated enum Placement: Hashable {
        /// A column beside the grid. What a landscape iPad already did with the day inspector.
        case beside
        /// A pane under the grid. What a phone, and a narrow iPad pane, already did with the agenda.
        case below
    }

    /// What a compact pane shows whatever is stored. The phone's Month has one shape and no toggle,
    /// so the stored value is a regular-width preference that a phone neither reads nor writes.
    static let compactDetail: CadenceCalendarMonthDetail = .agenda

    /// The agenda is the default because it is the reading that actually lists the month, and
    /// because it is what every phone shows — so a cold launch looks the same on all of them.
    static let defaultDetail: CadenceCalendarMonthDetail = .agenda

    static func detail(storedRawValue: String, isCompact: Bool = false) -> CadenceCalendarMonthDetail {
        guard !isCompact else { return compactDetail }
        return CadenceCalendarMonthDetail(rawValue: storedRawValue) ?? defaultDetail
    }

    /// Beside the grid exactly where a 340pt side column fits — 681pt of pane, the width
    /// `CadenceCalendarPaneLayout` has always split at. Below that the detail goes under the grid
    /// instead of disappearing: the inspector's 340pt floor against a 646pt pane would leave ~43pt
    /// per weekday column, which is the starvation `CadenceCalendarPaneLayout` exists to prevent.
    ///
    /// Month is now the only surface that splits at this width. Week claims the whole grid before an
    /// inspector may take anything and so splits at 1183, and the Board does not split at all.
    static func placement(paneWidth: CGFloat) -> Placement {
        CadenceCalendarPaneLayout.showsInspector(paneWidth: paneWidth) ? .beside : .below
    }

    /// Month-only, regular-width-only. Week and Board have one detail each and would gain a control
    /// with nothing to switch between; a phone has no room to place either one beside the grid.
    static func showsDetailControl(
        isCompact: Bool,
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode
    ) -> Bool {
        !isCompact && presentation == .timeline && viewMode == .month
    }

    /// Whether Month keeps the one-line counts strip under the toolbar.
    ///
    /// Only where the detail is a **column beside** the grid and it is the day inspector.
    ///
    /// The agenda heads every day with its own date, so the strip's date is a second copy of a line
    /// a few points below it. The inspector no longer states a date at all — its header bar is gone
    /// — but under the grid it is directly below the lit-up cell that says which day this is, and a
    /// full "Sunday, August 30" wedged between the two is chrome the grid has already covered.
    /// Beside the grid there is nothing between the strip and the calendar, so it stays.
    static func showsDaySummaryStrip(placement: Placement, detail: CadenceCalendarMonthDetail) -> Bool {
        placement == .beside && detail == .day
    }
}
