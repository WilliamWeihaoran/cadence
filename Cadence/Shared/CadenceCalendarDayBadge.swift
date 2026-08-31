import Foundation

// MARK: - How a month grid draws a day

/// The treatment a month grid's day badge takes, as the four states it can actually be in.
///
/// The colours are `MonthCalendarPanel`'s — the panel behind every date picker in the app, on both
/// platforms: a **selected** day is a solid `Theme.blue` circle with `Theme.onColor` on it, **today**
/// is `Theme.blue` at `washOpacity` with `Theme.blue` on it, and anything else has no circle at all.
/// The iOS month grids had that pairing the wrong way round — today took the solid fill and the
/// selection took the wash — so the same two facts read as each other's opposite depending on which
/// month surface you were looking at.
///
/// This is the mapping only; the colours are applied at the call sites, because the two grids differ
/// in what "no circle" and "not this month" look like. Keeping the *decision* here is what stops a
/// third and fourth spelling of "today" appearing.
enum CadenceCalendarDayBadge: Hashable, CaseIterable {
    case plain
    case today
    case selected
    /// Today, and the selected day. Needs to be distinguishable from either alone — a grid where
    /// selecting today makes the "today" marker vanish has lost a fact rather than combined two.
    case todayAndSelected

    /// The fill of `Theme.blue` a wash uses. `MonthCalendarPanel`'s number, named once.
    static let washOpacity: Double = 0.15

    /// How far `Theme.dim` is pulled back for a day carried in from a neighbouring month — **one
    /// layer, one value, on every month grid in the app (T-568)**.
    ///
    /// The figure and its measurement are macOS's, from `CalendarMonthDayEmphasis`: composited on
    /// the carried plate (`Theme.bg`, #3d3d43 rather than #47474d) it is 1.84:1 against its own
    /// cell, while the in-month number stays `Theme.text` at 15.9:1. That is close to the floor
    /// and deliberately so — Apple's own other-month numeral is `tertiaryLabelColor`, white at
    /// 0.25, near 2.3:1 — but **0.35 gives 1.45:1, at which a 12pt numeral no longer resolves**,
    /// and 12pt is exactly what `iOSCalendarMonthDayCell` sets its day number at.
    ///
    /// It lives here rather than beside the macOS enum because iOS was where the floor was being
    /// broken and `Cadence/macOS/` is invisible from `Cadence/iOS/`. The iOS full-size cell dimmed
    /// a carried day **three times over** — 0.58 on the label, 0.18→0.08 on the badge behind it,
    /// and `.opacity(0.52)` on the whole cell — and SwiftUI multiplies, so the numeral landed at
    /// 0.30, under a floor the other platform had already measured and written down.
    ///
    /// **The band that reads at a glance is the cell's plate, not this.** A grid separates its
    /// months by moving the plate — in-month `Theme.surface`, carried `Theme.bg` — and never by
    /// fading the cell, because a cell-wide opacity also takes the today ring and the event chips
    /// down with it. This is the supporting half.
    static let outOfMonthLabelOpacity: Double = 0.50

    static func style(isToday: Bool, isSelected: Bool) -> CadenceCalendarDayBadge {
        switch (isToday, isSelected) {
        case (true, true):   return .todayAndSelected
        case (true, false):  return .today
        case (false, true):  return .selected
        case (false, false): return .plain
        }
    }

    /// The circle behind the day number.
    enum Fill: Hashable {
        /// Whatever the grid's resting cell looks like — no accent at all.
        case none
        /// `Theme.blue` at `washOpacity`.
        case wash
        /// Solid `Theme.blue`.
        case solid
    }

    /// The day number itself.
    enum Label: Hashable {
        /// The grid's ordinary day-number colour, which also carries "not this month".
        case normal
        /// `Theme.blue`, read against a wash.
        case accent
        /// `Theme.onColor`, read against a solid fill.
        case onFill
    }

    var fill: Fill {
        switch self {
        case .plain:                       return .none
        case .today:                       return .wash
        case .selected, .todayAndSelected: return .solid
        }
    }

    var label: Label {
        switch self {
        case .plain:                       return .normal
        case .today:                       return .accent
        case .selected, .todayAndSelected: return .onFill
        }
    }

    /// A ring drawn just outside the badge. The **only** thing separating "today, and selected" from
    /// "selected", since both take the solid fill.
    var showsTodayRing: Bool { self == .todayAndSelected }

    /// Whether the day number is drawn heavier than its neighbours.
    var isEmphasized: Bool { self != .plain }
}
