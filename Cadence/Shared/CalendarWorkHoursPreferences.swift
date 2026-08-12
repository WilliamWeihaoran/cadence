import CoreGraphics
import Foundation

/// The user's work-hours window: the band the day timeline emphasizes, and the only thing that
/// reads or writes `calendar.workHours.*.v1`.
///
/// Cross-platform. It used to sit behind `#if os(macOS)` in `macOS/Services/`, which meant an
/// iPad showed a flat, unemphasized 6–23 timeline and iOS Settings offered no way to discover or
/// change a window the user had already set on the Mac — even though the defaults keys are
/// `calendar.*`, not `macos.*`, and sync through the same store.
enum CalendarWorkHoursPreferences {
    struct WorkHoursRange: Equatable {
        let startMinute: Int
        let endMinute: Int
    }

    struct HighlightFrame: Equatable {
        let y: CGFloat
        let height: CGFloat
    }

    static let startMinuteKey = "calendar.workHours.startMinute.v1"
    static let endMinuteKey = "calendar.workHours.endMinute.v1"
    static let defaultStartMinute = 9 * 60
    static let defaultEndMinute = 17 * 60

    static let selectableStartMinutes = stride(from: 0, through: 23 * 60 + 30, by: 30).map { $0 }
    static let selectableEndMinutes = stride(from: 30, through: 24 * 60, by: 30).map { $0 }

    static func normalizedStartMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 23 * 60 + 30)
    }

    static func normalizedEndMinute(_ minute: Int, startMinute: Int) -> Int {
        let safeStart = normalizedStartMinute(startMinute)
        return min(max(minute, safeStart + 30), 24 * 60)
    }

    static func normalizedRange(startMinute: Int, endMinute: Int) -> WorkHoursRange {
        let start = normalizedStartMinute(startMinute)
        return WorkHoursRange(
            startMinute: start,
            endMinute: normalizedEndMinute(endMinute, startMinute: start)
        )
    }

    static func rangeByUpdatingStart(
        _ startMinute: Int,
        currentEndMinute: Int
    ) -> WorkHoursRange {
        normalizedRange(startMinute: startMinute, endMinute: currentEndMinute)
    }

    static func rangeByUpdatingEnd(
        _ endMinute: Int,
        currentStartMinute: Int
    ) -> WorkHoursRange {
        normalizedRange(startMinute: currentStartMinute, endMinute: endMinute)
    }

    static func visibleMinuteRange(
        startMinute: Int,
        endMinute: Int,
        timelineStartHour: Int,
        timelineEndHour: Int
    ) -> ClosedRange<Int>? {
        let timelineStart = max(0, timelineStartHour * 60)
        let timelineEnd = min(24 * 60, timelineEndHour * 60)
        let range = normalizedRange(startMinute: startMinute, endMinute: endMinute)
        let visibleStart = max(range.startMinute, timelineStart)
        let visibleEnd = min(range.endMinute, timelineEnd)

        guard visibleEnd > visibleStart else { return nil }
        return visibleStart...visibleEnd
    }

    /// The band's rect on a timeline canvas.
    ///
    /// Takes the canvas's own `TimelineMetrics` rather than `(startHour, endHour, hourHeight)`:
    /// the minute → Y conversion is `metrics.yOffset(forFractionalMinute:)`, and this used to
    /// carry its own copy of that expression. A top inset or a non-linear zoom added to
    /// `yOffset` would have moved every block while leaving the amber band where it was.
    #if os(macOS)
    static func highlightFrame(
        startMinute: Int,
        endMinute: Int,
        metrics: TimelineMetrics
    ) -> HighlightFrame? {
        highlightFrame(
            startMinute: startMinute,
            endMinute: endMinute,
            timelineStartHour: metrics.startHour,
            timelineEndHour: metrics.endHour,
            yOffset: metrics.yOffset(forFractionalMinute:)
        )
    }
    #endif

    /// The band's rect on a canvas whose minute → Y conversion the caller supplies.
    ///
    /// iOS's day view does its own linear `yOffset`; rather than give this type a second
    /// `(startHour, endHour, hourHeight)` spelling of that arithmetic — the exact duplication the
    /// `metrics:` overload was introduced to remove — the caller passes the conversion it already
    /// uses, so there is still only one of them per surface.
    static func highlightFrame(
        startMinute: Int,
        endMinute: Int,
        timelineStartHour: Int,
        timelineEndHour: Int,
        yOffset: (CGFloat) -> CGFloat
    ) -> HighlightFrame? {
        guard let visibleRange = visibleMinuteRange(
            startMinute: startMinute,
            endMinute: endMinute,
            timelineStartHour: timelineStartHour,
            timelineEndHour: timelineEndHour
        ) else {
            return nil
        }

        let y = yOffset(CGFloat(visibleRange.lowerBound))
        let height = yOffset(CGFloat(visibleRange.upperBound)) - y
        guard height > 0 else { return nil }
        return HighlightFrame(y: y, height: height)
    }

    static func shouldShowHighlight(on date: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDateInWeekend(date)
    }

    static func displayLabel(startMinute: Int, endMinute: Int) -> String {
        let range = normalizedRange(startMinute: startMinute, endMinute: endMinute)
        return TimeFormatters.timeRange(
            startMin: range.startMinute,
            endMin: range.endMinute
        )
    }
}
