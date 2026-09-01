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
    /// `nonisolated` because the project builds with `-default-isolation=MainActor`, so without it
    /// this enum's `Hashable`/`Equatable` conformance is main-actor-isolated — and a `#expect`
    /// comparing two `Fill`s from a nonisolated test context expands into a warning. Same shape as the
    /// `TaskContainerSelection` fix: a pure value type that never touches UI state has no reason to be
    /// isolated, and the isolation is inherited by default rather than chosen.
    nonisolated enum Fill: Hashable {
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

// MARK: - What a day cell announces

/// What VoiceOver calls one day in a calendar grid.
///
/// **Every one of these cells announced a bare long date** — the same date its own day number
/// already draws — and nothing about what is *on* the day, which is the only reason to look at a
/// month grid at all ([[T-573]]). The date is the cheap half; the load is in the capsule, the dot
/// and the chips beside it.
///
/// Three functions rather than one, because the three cells draw three genuinely different things
/// and a label states what its own cell shows. That rule is [[T-572]]'s: a label that announces a
/// number the screen does not draw is the same defect as a label that announces the wrong one.
///
/// A value type outside every platform conditional, so `CadenceTests` — which builds for macOS and
/// cannot see `Cadence/iOS/` — can pin the words themselves rather than only the call sites.
nonisolated enum CadenceCalendarDayAccessibility {
    /// For a cell that draws the number: the full month grid's count capsule.
    ///
    /// `"Monday, 31 August 2026, 3 scheduled items"`.
    static func countedDayLabel(date: Date, itemCount: Int) -> String {
        guard itemCount > 0 else { return "\(dayName(date)), \(emptyPhrase)" }
        return "\(dayName(date)), \(itemCount) scheduled item\(itemCount == 1 ? "" : "s")"
    }

    /// For a cell that draws only presence: the compact agenda grid's dot, which is binary.
    ///
    /// It says "has scheduled items" rather than a number **on purpose**. The count is knowable at
    /// the call site — the parent already buckets the day to decide whether to draw the dot at all
    /// — but the cell does not show it, and inventing a figure that is nowhere on screen is the
    /// mirror of the mismatch [[T-571]] left behind.
    static func markedDayLabel(date: Date, hasItems: Bool) -> String {
        "\(dayName(date)), \(hasItems ? "has scheduled items" : emptyPhrase)"
    }

    /// For the timeline's day header, which draws **two** figures: an "N timed" chip and up to two
    /// unscheduled task chips with a "+ M more".
    ///
    /// `"Monday, 31 August 2026, 3 timed items, 2 unscheduled"`. Both numbers, because both are on
    /// screen; the unscheduled clause is dropped when there are none rather than read as "0".
    static func timelineDayLabel(date: Date, timedCount: Int, unscheduledCount: Int) -> String {
        var label = timedCount > 0
            ? "\(dayName(date)), \(timedCount) timed item\(timedCount == 1 ? "" : "s")"
            : "\(dayName(date)), \(emptyPhrase)"
        if unscheduledCount > 0 {
            label += ", \(unscheduledCount) unscheduled"
        }
        return label
    }

    /// One wording for an empty day, so the three cells cannot drift into three ways of saying
    /// nothing. `countedDayLabel(itemCount: 0)` and `markedDayLabel(hasItems: false)` are the same
    /// sentence by construction.
    static let emptyPhrase = "no scheduled items"

    private static func dayName(_ date: Date) -> String {
        DateFormatters.longDate.string(from: date)
    }
}
