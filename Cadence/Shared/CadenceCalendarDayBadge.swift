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
