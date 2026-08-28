import Foundation
import SwiftUI

// MARK: - Timed grid: zoom

/// How tall an hour is on a timed grid, and what a pinch may do to it.
///
/// The number this replaces was an `Int` 1/2/3 fed through `base + (zoom − 1) × 16`, against a base
/// of 58 (compact) or 64 (regular). So the control labelled "3x" produced 90pt against a 58pt
/// base — about 1.55×. The label was not describing the thing it was attached to, and a continuous
/// pinch makes that kind of discrepancy obvious in a way three discrete steps did not: a user
/// pinching to the stop expects the hour to be three times the hour they started from.
///
/// So `zoom` is now a plain multiplier of the base and nothing else: 1 is the height the grid has
/// always opened at, 3 is three of it (58→174 compact, 64→192 regular). A stored `1`, `2` or `3`
/// from the old control still reads as a legal multiplier, which is why the key did not need to
/// change — see `CalendarTimelineGridTests.zoomStoredByTheOldIntegerControlStillReads`.
enum CadenceCalendarZoom {
    static let minimum: Double = 1
    static let maximum: Double = 3
    static let defaultZoom: Double = 1

    /// The `@AppStorage` key. Named here rather than at the two call sites so the migration note
    /// above sits with the key it is about.
    static let storageKey = "ios.calendar.zoomLevel"

    /// The densities Settings offers, and the labels it offers them under.
    ///
    /// Stated here rather than in the Settings section because the *values* belong to the zoom
    /// rather than to the picker, and because of how T-392 happened: Settings re-spelled the key
    /// as a literal and declared it `Int`, so a pinch that stored `1.5` read back there as `1`,
    /// showed the wrong density, and overwrote the continuous zoom with a coarse integer the
    /// moment the user touched the row. One key, one type, one list of presets.
    struct DensityPreset: Identifiable, Hashable {
        let zoom: Double
        let title: String

        var id: Double { zoom }
    }

    static let densityPresets: [DensityPreset] = [
        DensityPreset(zoom: 1, title: "Compact"),
        DensityPreset(zoom: 2, title: "Comfort"),
        DensityPreset(zoom: 3, title: "Spacious")
    ]

    /// What a zoom between two presets is called.
    ///
    /// **The picker does not snap.** A pinch is the primary control here and it writes a
    /// continuous multiplier; rounding that to the nearest density the moment Settings opens
    /// would throw away a zoom the user set deliberately, and naming it after a preset the grid
    /// is not actually at is the same lie the `Int` binding told. So a fractional zoom is
    /// preserved and reported as Custom, with no density row checked, until the user picks one —
    /// and picking one writes that preset's multiplier through this same key.
    static let customDensityTitle = "Custom"

    /// The preset a stored zoom *is*, or `nil` when it sits between two of them.
    static func densityPreset(matching zoom: Double) -> DensityPreset? {
        let clamped = clamp(zoom)
        return densityPresets.first { abs($0.zoom - clamped) < 0.0001 }
    }

    static func densityTitle(for zoom: Double) -> String {
        densityPreset(matching: zoom)?.title ?? customDensityTitle
    }

    static func clamp(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return defaultZoom }
        return min(max(zoom, minimum), maximum)
    }

    /// The scale a pinch of `magnification` produces from the zoom it started at, clamped at both
    /// ends. Clamping the *result* rather than the gesture means pinching past a stop and back
    /// returns to where it was, instead of the grid drifting because the excess was accumulated.
    static func zoom(startingFrom startZoom: Double, magnification: CGFloat) -> Double {
        guard magnification.isFinite, magnification > 0 else { return clamp(startZoom) }
        return clamp(clamp(startZoom) * Double(magnification))
    }

    static func hourHeight(base: CGFloat, zoom: Double) -> CGFloat {
        base * CGFloat(clamp(zoom))
    }

    /// The vertical content offset that keeps whatever was under the fingers under the fingers.
    ///
    /// `focusY` is measured from the top of the hour canvas's *viewport*, so `currentOffset +
    /// focusY` is the content point being held; scaling that and putting it back at `focusY` is the
    /// whole rule. Clamped to the scrolled range, because the alternative is asking a scroll view
    /// to go somewhere it cannot and having it silently land somewhere else.
    static func anchoredVerticalOffset(
        currentOffset: CGFloat,
        focusY: CGFloat,
        scale: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return max(0, currentOffset) }
        let held = max(0, currentOffset) + focusY
        let raw = held * scale - focusY
        let maximumOffset = max(0, contentHeight - viewportHeight)
        return min(max(raw, 0), maximumOffset)
    }
}

// MARK: - Timed grid: the day window it scrolls through

/// The day columns a timed grid renders, and how a scroll position maps to a date.
///
/// The grid used to draw exactly `CadenceScheduleSupport.dates(containing:mode:)` — seven columns
/// for Week, fourteen for 2 Weeks — with the toolbar's chevrons rebuilding that window a week at a
/// time. Scrolling sideways reached nothing, because there was nothing either side to reach.
///
/// This is the window the Calendar Board already scrolls through
/// (`CalendarBoardPlannerSupport.plannerRenderDayCount`), reused rather than re-derived: a wide
/// lazy run of day columns with the anchor near its middle, recentred when a scroll approaches
/// either end. The only thing added is the week snap — the window starts on a week boundary, so a
/// Week grid's leading edge lands on a Sunday whenever the user has not deliberately scrolled off
/// one, and every week boundary is a multiple of seven columns in.
enum CadenceCalendarTimelineWindow {
    static let renderDayCount = CalendarBoardPlannerSupport.plannerRenderDayCount

    /// The first day column rendered: half the window behind the anchor, snapped back to the start
    /// of that week. `plannerLeadingDayCount` is 210 — thirty whole weeks — so the snap survives
    /// the subtraction and the window start is itself a week start.
    static func windowStart(for anchorDate: Date, calendar: Calendar = .current) -> Date {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: anchorDate, calendar: calendar)
        return CalendarBoardPlannerSupport.plannerWindowStart(for: weekStart, calendar: calendar)
    }

    static func date(at index: Int, windowStart: Date, calendar: Calendar = .current) -> Date {
        CalendarBoardPlannerSupport.date(at: index, bufferStart: windowStart, calendar: calendar)
    }

    static func index(for date: Date, windowStart: Date, calendar: Calendar = .current) -> Int {
        CalendarBoardPlannerSupport.dayIndex(
            for: date,
            bufferStart: windowStart,
            calendar: calendar,
            renderDays: renderDayCount
        )
    }

    /// The window to adopt when the leading column nears an end of the rendered run, or `nil` to
    /// leave it alone. Same threshold the Board uses; the no-op guard is what keeps it from
    /// re-scrolling under a finger that is still moving.
    static func recenteredWindowStart(
        leadingIndex: Int,
        leadingDate: Date,
        currentWindowStart: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard CalendarBoardPlannerSupport.shouldRecenter(
            dayIndex: leadingIndex,
            renderDays: renderDayCount
        ) else { return nil }
        let recentered = windowStart(for: leadingDate, calendar: calendar)
        guard !calendar.isDate(recentered, inSameDayAs: currentWindowStart) else { return nil }
        return recentered
    }

    // MARK: Scroll position ↔ column index

    /// The column at the leading edge, for a horizontal content offset.
    static func leadingIndex(scrollOffsetX: CGFloat, columnWidth: CGFloat) -> Int {
        guard columnWidth > 0 else { return 0 }
        let raw = Int((max(0, scrollOffsetX) / columnWidth).rounded())
        return min(max(raw, 0), max(0, renderDayCount - 1))
    }

    /// The content offset that puts `index` at the leading edge.
    static func scrollOffsetX(forIndex index: Int, columnWidth: CGFloat) -> CGFloat {
        CGFloat(min(max(index, 0), max(0, renderDayCount - 1))) * max(0, columnWidth)
    }

    /// The columns actually built, given the one at the leading edge.
    ///
    /// The grid windows its own columns rather than leaning on `LazyHStack`, because the lazy
    /// stack would sit inside a *vertical* scroll view inside the horizontal one — see the note on
    /// `iOSCalendarTimelineGrid` — and which enclosing scroll view drives a lazy stack's visible
    /// region through that nesting is not something to find out in production. Windowing on the
    /// offset this file already reads is the same result with none of the question.
    ///
    /// `margin` columns either side, so a fling has something built to land on and the scroll never
    /// shows a gap before the state catches up.
    static func renderedIndexRange(
        leadingIndex: Int,
        visibleDayCount: Int,
        margin: Int = 7
    ) -> Range<Int> {
        let visible = max(1, visibleDayCount)
        let lower = max(0, leadingIndex - max(0, margin))
        let upper = min(renderDayCount, leadingIndex + visible + max(0, margin))
        guard lower < upper else { return 0..<min(renderDayCount, visible) }
        return lower..<upper
    }

    // MARK: Event fetching

    /// Days of calendar events a timed grid holds at once.
    ///
    /// The grid renders hundreds of columns; it cannot ask EventKit about all of them. It also
    /// cannot ask about exactly what is on screen, because the leading column changes on every
    /// column the user scrolls past and each change would re-run the whole fetch mid-gesture. So
    /// the fetch window is a **week-aligned** four-week span around the leading day: it covers 2
    /// Weeks' fourteen columns with a week of margin either side, and its identity only changes
    /// when the leading column crosses into another week.
    static let eventWindowDayCount = 28

    static func eventWindowStart(leadingDate: Date, calendar: Calendar = .current) -> Date {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: leadingDate, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }

    static func eventWindowDates(leadingDate: Date, calendar: Calendar = .current) -> [Date] {
        let start = eventWindowStart(leadingDate: leadingDate, calendar: calendar)
        return (0..<eventWindowDayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}
